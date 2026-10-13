-- 12-hour package pricing: included kilometres, extra-km rate, deposit left at zero.

alter table public.vehicles
  add column if not exists package_price numeric(12,2),
  add column if not exists included_km numeric(10,2),
  add column if not exists excess_per_km numeric(12,2);

alter table public.bookings
  add column if not exists package_price numeric(12,2),
  add column if not exists included_km numeric(10,2),
  add column if not exists excess_per_km numeric(12,2),
  add column if not exists km_allowance numeric(10,2),
  add column if not exists excess_km numeric(10,2),
  add column if not exists excess_amount numeric(12,2);

alter table public.rate_cards
  add column if not exists included_km numeric(10,2),
  add column if not exists excess_per_km numeric(12,2);

do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'public.vehicles'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%price_unit%'
  loop
    execute format('alter table public.vehicles drop constraint %I', r.conname);
  end loop;
  for r in
    select conname from pg_constraint
    where conrelid = 'public.rate_cards'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%hour%'
  loop
    execute format('alter table public.rate_cards drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.vehicles
  add constraint vehicles_price_unit_check
  check (price_unit in ('hour', 'minute', 'km', 'package'));

alter table public.rate_cards
  add constraint rate_cards_unit_check
  check (unit in ('hour', 'minute', 'km', 'package'));

update public.rate_cards set is_active = false where unit in ('hour', 'minute', 'km');

insert into public.rate_cards (name, unit, unit_rate, daily_rate, deposit, included_km, excess_per_km)
values
  ('Scooter', 'package', 499, null, 0, 120, 3),
  ('Commuter', 'package', 567, null, 0, 150, 3),
  ('Street', 'package', 1128, null, 0, 240, 6),
  ('Premium', 'package', 3048, null, 0, 192, 10),
  ('Car', 'package', 2200, null, 0, 240, 12),
  ('Car plus', 'package', 3600, null, 0, 240, 15)
on conflict (name) do update
  set unit = excluded.unit,
      unit_rate = excluded.unit_rate,
      deposit = 0,
      included_km = excluded.included_km,
      excess_per_km = excluded.excess_per_km,
      is_active = true;

update public.vehicles v
set price_unit = 'package',
    package_price = c.unit_rate,
    included_km = c.included_km,
    excess_per_km = c.excess_per_km,
    unit_rate = c.unit_rate,
    daily_price = c.unit_rate,
    hourly_price = round(c.unit_rate / 24, 2),
    deposit = 0,
    rate_card_id = c.id
from public.rate_cards c
where c.name = case v.name
  when 'Activa' then 'Scooter'
  when 'Ather 450' then 'Scooter'
  when 'Pulsar 150' then 'Commuter'
  when 'Classic 350' then 'Street'
  when 'Swift' then 'Car'
  when 'Creta' then 'Car plus'
end;

create or replace function private.package_multiplier(p_hours numeric)
returns numeric
language sql
immutable
as $$
  select case
    when p_hours <= 24 then 1::numeric
    else floor(p_hours / 24) + round(p_hours - floor(p_hours / 24) * 24, 2) / 24
  end;
$$;

create or replace function private.quote_rental(
  p_vehicle uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_coupon text,
  p_km numeric
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v public.vehicles%rowtype;
  hours numeric;
  multiplier numeric;
  base numeric;
  allowance numeric;
  discount numeric := 0;
  taxable numeric;
  rate numeric;
  rule_id uuid;
  tax numeric;
  cgst numeric;
  sgst numeric;
  c public.coupons%rowtype;
begin
  if p_end <= p_start then
    raise exception 'End must be after start';
  end if;

  select * into v from public.vehicles
  where id = p_vehicle and is_active and status = 'available';
  if not found then
    raise exception 'Vehicle is not available';
  end if;
  if v.package_price is null then
    raise exception 'This vehicle has no 12-hour package';
  end if;

  hours := round((extract(epoch from (p_end - p_start)) / 3600.0)::numeric, 2);
  multiplier := private.package_multiplier(hours);
  base := round(v.package_price * multiplier, 2);
  allowance := round(coalesce(v.included_km, 0) * multiplier, 2);

  if p_coupon is not null and btrim(p_coupon) <> '' then
    select * into c from public.coupons
    where lower(code) = lower(btrim(p_coupon))
      and is_active
      and (expires_at is null or expires_at > now());
    if not found then
      raise exception 'Coupon is not valid';
    end if;
    if c.kind = 'percent' then
      discount := round(base * c.value / 100, 2);
    else
      discount := least(c.value, base);
    end if;
  end if;

  taxable := round(base - discount, 2);

  select id, rate_percent into rule_id, rate
  from public.tax_rules
  where is_active
    and effective_from <= (p_start at time zone 'Asia/Kolkata')::date
    and (effective_to is null or effective_to >= (p_start at time zone 'Asia/Kolkata')::date)
  order by effective_from desc
  limit 1;
  if rule_id is null then
    raise exception 'No tax rule is in force for this rental';
  end if;

  tax := round(taxable * rate / 100, 2);
  cgst := round(tax / 2, 2);
  sgst := tax - cgst;

  return jsonb_build_object(
    'duration_hours', hours,
    'billed_days', case when hours <= 24 then 0 else floor(hours / 24)::integer end,
    'remainder_hours', case when hours <= 24 then hours else round(hours - floor(hours / 24) * 24, 2) end,
    'price_unit', 'package',
    'package_price', v.package_price,
    'included_km', v.included_km,
    'km_allowance', allowance,
    'excess_per_km', v.excess_per_km,
    'hourly_price', round(v.package_price / 24, 2),
    'daily_price', v.package_price,
    'unit_rate', v.package_price,
    'base_amount', base,
    'coupon_code', nullif(btrim(coalesce(p_coupon, '')), ''),
    'discount_amount', discount,
    'taxable_amount', taxable,
    'tax_rule_id', rule_id,
    'tax_rate', rate,
    'tax_amount', tax,
    'cgst', cgst,
    'sgst', sgst,
    'deposit_amount', coalesce(v.deposit, 0),
    'rental_total', taxable + tax,
    'authorize_amount', taxable + tax + coalesce(v.deposit, 0),
    'fuel_included', false
  );
end;
$$;

create or replace function private.create_rental_booking(
  p_vehicle uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_coupon text,
  p_km numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  q jsonb;
  v public.vehicles%rowtype;
  new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in to book';
  end if;
  if not private.vehicle_is_free(p_vehicle, p_start, p_end) then
    raise exception 'That vehicle is already booked for those hours';
  end if;

  select * into v from public.vehicles where id = p_vehicle;
  q := private.quote_rental(p_vehicle, p_start, p_end, p_coupon, p_km);

  insert into public.bookings (
    customer_id, vehicle_id, branch_id, start_at, end_at,
    duration_hours, billed_days, remainder_hours,
    hourly_price, daily_price, base_amount, coupon_code, discount_amount,
    taxable_amount, tax_rule_id, tax_rate, tax_amount,
    deposit_amount, rental_total, authorize_amount, status,
    price_unit, unit_rate, package_price, included_km, excess_per_km, km_allowance
  ) values (
    auth.uid(), p_vehicle, v.branch_id, p_start, p_end,
    (q->>'duration_hours')::numeric,
    (q->>'billed_days')::integer,
    (q->>'remainder_hours')::numeric,
    (q->>'hourly_price')::numeric,
    (q->>'daily_price')::numeric,
    (q->>'base_amount')::numeric,
    q->>'coupon_code',
    (q->>'discount_amount')::numeric,
    (q->>'taxable_amount')::numeric,
    (q->>'tax_rule_id')::uuid,
    (q->>'tax_rate')::numeric,
    (q->>'tax_amount')::numeric,
    (q->>'deposit_amount')::numeric,
    (q->>'rental_total')::numeric,
    (q->>'authorize_amount')::numeric,
    'draft',
    'package',
    (q->>'package_price')::numeric,
    (q->>'package_price')::numeric,
    (q->>'included_km')::numeric,
    (q->>'excess_per_km')::numeric,
    (q->>'km_allowance')::numeric
  )
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function private.capture_booking(p_booking uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
begin
  select * into b from public.bookings where id = p_booking and customer_id = auth.uid();
  if not found or b.status <> 'signed' then
    raise exception 'Capture happens only after eSign';
  end if;

  insert into public.payments (booking_id, purpose, method, amount, status)
  select p_booking, 'capture', method, b.rental_total, 'captured'
  from public.payments
  where booking_id = p_booking and purpose = 'authorization'
  order by created_at desc
  limit 1;

  perform private.post_balanced(
    p_booking,
    'rental_captured',
    b.rental_total,
    'Package rental and GST. Extra kilometres are settled at return.',
    jsonb_build_array(
      jsonb_build_object('account', '1000', 'debit', b.rental_total, 'credit', 0),
      jsonb_build_object('account', '4000', 'debit', 0, 'credit', b.taxable_amount),
      jsonb_build_object('account', '2200', 'debit', 0, 'credit', b.tax_amount)
    )
  );

  if coalesce(b.deposit_amount, 0) > 0 then
    perform private.post_balanced(
      p_booking,
      'deposit_received',
      b.deposit_amount,
      'Customer deposit held. Not revenue.',
      jsonb_build_array(
        jsonb_build_object('account', '1000', 'debit', b.deposit_amount, 'credit', 0),
        jsonb_build_object('account', '2100', 'debit', 0, 'credit', b.deposit_amount)
      )
    );
  end if;

  update public.bookings set status = 'captured' where id = p_booking;
end;
$$;

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
  booked_hours numeric;
  actual_hours numeric;
  use_hours numeric;
  multiplier numeric;
  driven numeric;
  allowance numeric;
  extra_km numeric;
  package_base numeric;
  kept_discount numeric;
  package_taxable numeric;
  excess_base numeric;
  new_taxable numeric;
  new_tax numeric;
  new_rental numeric;
  delta_taxable numeric;
  delta_tax numeric;
  delta_rental numeric;
  lines jsonb;
  late_hours numeric;
  late_minutes numeric;
  fee numeric := 0;
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

  if b.package_price is not null then
    booked_hours := round((extract(epoch from (b.end_at - b.start_at)) / 3600.0)::numeric, 2);
    actual_hours := round((extract(epoch from (p_returned_at - b.start_at)) / 3600.0)::numeric, 2);
    use_hours := greatest(booked_hours, actual_hours);
    multiplier := private.package_multiplier(use_hours);
    driven := p_odometer - b.odometer_out;
    allowance := round(coalesce(b.included_km, 0) * multiplier, 2);
    extra_km := greatest(driven - allowance, 0);
    package_base := round(b.package_price * multiplier, 2);
    kept_discount := least(coalesce(b.discount_amount, 0), package_base);
    package_taxable := round(package_base - kept_discount, 2);
    excess_base := round(extra_km * coalesce(b.excess_per_km, 0), 2);
    new_taxable := package_taxable + excess_base;
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
        'Extra kilometres and any late hours, at the package saved on the booking.',
        lines
      );
    end if;

    update public.bookings
      set status = 'returned',
          odometer_in = p_odometer,
          actual_return_at = p_returned_at,
          actual_km = driven,
          km_allowance = allowance,
          excess_km = extra_km,
          excess_amount = excess_base,
          estimated_rental = coalesce(estimated_rental, b.rental_total),
          base_amount = package_base,
          discount_amount = kept_discount,
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
  elsif coalesce(b.price_unit, 'hour') = 'km' then
    fee := 0;
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

create or replace function private.save_rate_card(
  p_id uuid,
  p_name text,
  p_package numeric,
  p_included_km numeric,
  p_excess numeric,
  p_deposit numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if not private.has_area('operations') then
    raise exception 'Only operations can define default rates';
  end if;
  if p_package < 0 or p_included_km < 0 or p_excess < 0 or p_deposit < 0 or length(trim(p_name)) = 0 then
    raise exception 'A package needs a price, included kilometres, and an extra-kilometre rate';
  end if;

  if p_id is null then
    insert into public.rate_cards (name, unit, unit_rate, deposit, included_km, excess_per_km)
    values (trim(p_name), 'package', p_package, p_deposit, p_included_km, p_excess)
    returning id into new_id;
  else
    update public.rate_cards
      set name = trim(p_name),
          unit = 'package',
          unit_rate = p_package,
          deposit = p_deposit,
          included_km = p_included_km,
          excess_per_km = p_excess,
          is_active = true
      where id = p_id
      returning id into new_id;
    if new_id is null then
      raise exception 'Default rate was not found';
    end if;
  end if;
  return new_id;
end;
$$;

create or replace function private.allot_vehicle_price(
  p_vehicle uuid,
  p_rate_card uuid,
  p_package numeric,
  p_included_km numeric,
  p_excess numeric,
  p_deposit numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.vehicles%rowtype;
  c public.rate_cards%rowtype;
  price numeric;
  km numeric;
  excess numeric;
  hold numeric;
begin
  select * into v from public.vehicles where id = p_vehicle;
  if not found or not private.staff_can(v.branch_id) then
    raise exception 'Not allowed to price this vehicle';
  end if;

  if p_rate_card is not null then
    select * into c from public.rate_cards where id = p_rate_card and is_active and unit = 'package';
    if not found then
      raise exception 'That default package is not active';
    end if;
    price := c.unit_rate;
    km := c.included_km;
    excess := c.excess_per_km;
    hold := c.deposit;
  else
    price := p_package;
    km := p_included_km;
    excess := p_excess;
    hold := coalesce(p_deposit, 0);
  end if;

  if price is null or price < 0 or km is null or km < 0 or excess is null or excess < 0 or hold < 0 then
    raise exception 'Set the package, included kilometres, extra-kilometre rate, and deposit';
  end if;

  update public.vehicles
    set rate_card_id = p_rate_card,
        price_unit = 'package',
        package_price = price,
        included_km = km,
        excess_per_km = excess,
        unit_rate = price,
        daily_price = price,
        hourly_price = round(price / 24, 2),
        deposit = hold
    where id = p_vehicle;
end;
$$;

create or replace function public.save_package(p_id uuid, p_name text, p_package numeric, p_included_km numeric, p_excess numeric, p_deposit numeric)
returns uuid language sql security invoker set search_path = public, private
as $$ select private.save_rate_card(p_id, p_name, p_package, p_included_km, p_excess, p_deposit); $$;

create or replace function public.allot_package(p_vehicle uuid, p_rate_card uuid, p_package numeric, p_included_km numeric, p_excess numeric, p_deposit numeric)
returns void language sql security invoker set search_path = public, private
as $$ select private.allot_vehicle_price(p_vehicle, p_rate_card, p_package, p_included_km, p_excess, p_deposit); $$;

revoke all on function public.save_package(uuid, text, numeric, numeric, numeric, numeric) from public;
revoke all on function public.allot_package(uuid, uuid, numeric, numeric, numeric, numeric) from public;
grant execute on function public.save_package(uuid, text, numeric, numeric, numeric, numeric) to authenticated;
grant execute on function public.allot_package(uuid, uuid, numeric, numeric, numeric, numeric) to authenticated;
grant execute on function private.save_rate_card(uuid, text, numeric, numeric, numeric, numeric) to authenticated;
grant execute on function private.allot_vehicle_price(uuid, uuid, numeric, numeric, numeric, numeric) to authenticated;
