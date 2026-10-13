alter table public.bookings
  add column if not exists actual_km numeric(10,2),
  add column if not exists estimated_rental numeric(12,2);

create or replace function private.confirm_return(
  p_booking uuid,
  p_odometer integer,
  p_returned_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  late_hours numeric;
  late_minutes numeric;
  fee numeric := 0;
  driven numeric;
  new_base numeric;
  new_discount numeric;
  new_taxable numeric;
  new_tax numeric;
  new_rental numeric;
  delta_taxable numeric;
  delta_tax numeric;
  delta_rental numeric;
  lines jsonb;
begin
  select * into b from public.bookings where id = p_booking;
  if not found or not private.staff_can(b.branch_id) then
    raise exception 'Not allowed to confirm this return';
  end if;
  if b.status <> 'out' then
    raise exception 'This vehicle is not out';
  end if;
  if b.odometer_out is null then
    raise exception 'Record the pickup odometer before return';
  end if;
  if p_odometer < b.odometer_out then
    raise exception 'Odometer in cannot be below the pickup reading';
  end if;

  if coalesce(b.price_unit, 'hour') = 'km' then
    driven := p_odometer - b.odometer_out;
    new_base := round(driven * coalesce(b.unit_rate, 0), 2);
    new_discount := least(coalesce(b.discount_amount, 0), new_base);
    new_taxable := round(new_base - new_discount, 2);
    new_tax := round(new_taxable * b.tax_rate / 100, 2);
    new_rental := new_taxable + new_tax;
    delta_taxable := new_taxable - b.taxable_amount;
    delta_tax := new_tax - b.tax_amount;
    delta_rental := new_rental - b.rental_total;
    if delta_taxable + delta_tax <> delta_rental then
      delta_tax := delta_rental - delta_taxable;
    end if;

    if delta_rental <> 0 then
      lines := jsonb_build_array();
      if delta_rental > 0 then
        lines := lines || jsonb_build_array(jsonb_build_object('account', '1000', 'debit', delta_rental, 'credit', 0));
        if delta_taxable <> 0 then
          lines := lines || jsonb_build_array(jsonb_build_object('account', '4000', 'debit', 0, 'credit', delta_taxable));
        end if;
        if delta_tax <> 0 then
          lines := lines || jsonb_build_array(jsonb_build_object('account', '2200', 'debit', 0, 'credit', delta_tax));
        end if;
      else
        if delta_taxable <> 0 then
          lines := lines || jsonb_build_array(jsonb_build_object('account', '4000', 'debit', abs(delta_taxable), 'credit', 0));
        end if;
        if delta_tax <> 0 then
          lines := lines || jsonb_build_array(jsonb_build_object('account', '2200', 'debit', abs(delta_tax), 'credit', 0));
        end if;
        lines := lines || jsonb_build_array(jsonb_build_object('account', '1000', 'debit', 0, 'credit', abs(delta_rental)));
      end if;

      perform private.post_balanced(
        p_booking,
        'km_settled',
        abs(delta_rental),
        'Kilometres settled from the odometer at the snapshot per-km rate. Deposit is unchanged.',
        lines
      );
    end if;

    update public.bookings
      set status = 'returned',
          odometer_in = p_odometer,
          actual_return_at = p_returned_at,
          actual_km = driven,
          estimated_rental = coalesce(estimated_rental, b.rental_total),
          base_amount = new_base,
          discount_amount = new_discount,
          taxable_amount = new_taxable,
          tax_amount = new_tax,
          rental_total = new_rental,
          late_fee = 0
      where id = p_booking;
    return;
  end if;

  if coalesce(b.price_unit, 'hour') = 'minute' then
    late_minutes := greatest(ceil(extract(epoch from (p_returned_at - b.end_at)) / 60.0), 0);
    fee := round(late_minutes * coalesce(b.unit_rate, b.hourly_price), 2);
  else
    late_hours := greatest(round((extract(epoch from (p_returned_at - b.end_at)) / 3600.0)::numeric, 2), 0);
    fee := round(late_hours * b.hourly_price, 2);
  end if;

  if fee > 0 then
    perform private.post_balanced(
      p_booking,
      'late_fee',
      fee,
      'Late return charged from the price snapshot.',
      jsonb_build_array(
        jsonb_build_object('account', '1000', 'debit', fee, 'credit', 0),
        jsonb_build_object('account', '4100', 'debit', 0, 'credit', fee)
      )
    );
  end if;

  update public.bookings
    set status = 'returned',
        odometer_in = p_odometer,
        actual_return_at = p_returned_at,
        late_fee = fee
    where id = p_booking;
end;
$$;
