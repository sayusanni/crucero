-- Shared default rates. Allotting a vehicle copies a default onto that bike or car.

create table if not exists public.rate_cards (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  unit text not null check (unit in ('hour', 'minute', 'km')),
  unit_rate numeric(12,2) not null check (unit_rate >= 0),
  daily_rate numeric(12,2) check (daily_rate is null or daily_rate >= 0),
  deposit numeric(12,2) not null check (deposit >= 0),
  is_active boolean not null default true
);

alter table public.rate_cards enable row level security;

drop policy if exists "operations reads rate cards" on public.rate_cards;
create policy "operations reads rate cards" on public.rate_cards
  for select to authenticated
  using (private.has_area('operations'));

grant select on public.rate_cards to authenticated;

alter table public.vehicles
  add column if not exists rate_card_id uuid references public.rate_cards (id),
  add column if not exists price_unit text not null default 'hour' check (price_unit in ('hour', 'minute', 'km')),
  add column if not exists unit_rate numeric(12,2);

update public.vehicles
  set unit_rate = hourly_price
  where unit_rate is null;

alter table public.vehicles alter column unit_rate set not null;

alter table public.bookings
  add column if not exists price_unit text not null default 'hour',
  add column if not exists unit_rate numeric(12,2),
  add column if not exists planned_km numeric(10,2);

update public.bookings
  set unit_rate = hourly_price
  where unit_rate is null;

insert into public.rate_cards (name, unit, unit_rate, daily_rate, deposit)
values
  ('Default 1', 'hour', 70, 800, 1500),
  ('Default 2', 'hour', 120, 1400, 3000),
  ('Default 3', 'hour', 250, 2200, 5000),
  ('Default 4', 'minute', 2, null, 1000),
  ('Default 5', 'km', 12, null, 2000)
on conflict (name) do nothing;

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
  minutes numeric := 0;
  days integer := 0;
  rem numeric := 0;
  base numeric;
  discount numeric := 0;
  taxable numeric;
  rate numeric;
  rule_id uuid;
  tax numeric;
  c public.coupons%rowtype;
  unit text;
  unit_rate numeric;
begin
  if p_end <= p_start then
    raise exception 'End must be after start';
  end if;

  select * into v from public.vehicles
  where id = p_vehicle and is_active and status = 'available';
  if not found then
    raise exception 'Vehicle is not available';
  end if;

  unit := coalesce(v.price_unit, 'hour');
  unit_rate := coalesce(v.unit_rate, v.hourly_price);
  hours := round((extract(epoch from (p_end - p_start)) / 3600.0)::numeric, 2);

  if unit = 'minute' then
    minutes := ceil(extract(epoch from (p_end - p_start)) / 60.0);
    base := round(minutes * unit_rate, 2);
  elsif unit = 'km' then
    if p_km is null or p_km <= 0 then
      raise exception 'Enter the kilometres for this vehicle';
    end if;
    base := round(p_km * unit_rate, 2);
  else
    if hours <= 24 then
      rem := hours;
      base := round(hours * unit_rate, 2);
    else
      days := floor(hours / 24)::integer;
      rem := round(hours - days * 24, 2);
      base := round(days * v.daily_price + rem * unit_rate, 2);
    end if;
  end if;

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

  return jsonb_build_object(
    'duration_hours', hours,
    'billed_days', days,
    'remainder_hours', rem,
    'billed_minutes', minutes,
    'planned_km', case when unit = 'km' then p_km else null end,
    'price_unit', unit,
    'unit_rate', unit_rate,
    'hourly_price', case when unit = 'hour' then unit_rate else v.hourly_price end,
    'daily_price', v.daily_price,
    'base_amount', base,
    'coupon_code', nullif(btrim(coalesce(p_coupon, '')), ''),
    'discount_amount', discount,
    'taxable_amount', taxable,
    'tax_rule_id', rule_id,
    'tax_rate', rate,
    'tax_amount', tax,
    'deposit_amount', v.deposit,
    'rental_total', taxable + tax,
    'authorize_amount', taxable + tax + v.deposit
  );
end;
$$;

create or replace function private.quote_rental(
  p_vehicle uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_coupon text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select private.quote_rental(p_vehicle, p_start, p_end, p_coupon, null);
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
    price_unit, unit_rate, planned_km
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
    q->>'price_unit',
    (q->>'unit_rate')::numeric,
    nullif(q->>'planned_km', '')::numeric
  )
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function private.create_rental_booking(
  p_vehicle uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_coupon text
)
returns uuid
language sql
security definer
set search_path = public
as $$
  select private.create_rental_booking(p_vehicle, p_start, p_end, p_coupon, null);
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
  late_hours numeric;
  late_minutes numeric;
  fee numeric;
begin
  select * into b from public.bookings where id = p_booking;
  if not found or not private.staff_can(b.branch_id) then
    raise exception 'Not allowed to confirm this return';
  end if;
  if b.status <> 'out' then
    raise exception 'This vehicle is not out';
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
  p_unit text,
  p_unit_rate numeric,
  p_daily_rate numeric,
  p_deposit numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  daily numeric;
begin
  if not private.has_area('operations') then
    raise exception 'Only operations can define default rates';
  end if;
  if p_unit not in ('hour', 'minute', 'km') then
    raise exception 'A default is per hour, per minute, or per km';
  end if;
  if p_unit_rate < 0 or p_deposit < 0 or length(trim(p_name)) = 0 then
    raise exception 'Name, rate, and deposit are required';
  end if;
  daily := case when p_unit = 'hour' then p_daily_rate else null end;
  if p_unit = 'hour' and (daily is null or daily < 0) then
    raise exception 'An hourly default needs a daily rate';
  end if;

  if p_id is null then
    insert into public.rate_cards (name, unit, unit_rate, daily_rate, deposit)
    values (trim(p_name), p_unit, p_unit_rate, daily, p_deposit)
    returning id into new_id;
  else
    update public.rate_cards
      set name = trim(p_name),
          unit = p_unit,
          unit_rate = p_unit_rate,
          daily_rate = daily,
          deposit = p_deposit
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
  p_unit text,
  p_unit_rate numeric,
  p_daily_rate numeric,
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
begin
  select * into v from public.vehicles where id = p_vehicle;
  if not found or not private.staff_can(v.branch_id) then
    raise exception 'Not allowed to price this vehicle';
  end if;

  if p_rate_card is not null then
    select * into c from public.rate_cards where id = p_rate_card and is_active;
    if not found then
      raise exception 'That default rate is not active';
    end if;
    update public.vehicles
      set rate_card_id = c.id,
          price_unit = c.unit,
          unit_rate = c.unit_rate,
          hourly_price = case when c.unit = 'hour' then c.unit_rate else hourly_price end,
          daily_price = case when c.unit = 'hour' then c.daily_rate else daily_price end,
          deposit = c.deposit
      where id = p_vehicle;
    return;
  end if;

  if p_unit not in ('hour', 'minute', 'km') or p_unit_rate < 0 or p_deposit < 0 then
    raise exception 'Set the unit, the rate, and the deposit';
  end if;
  if p_unit = 'hour' and (p_daily_rate is null or p_daily_rate < 0) then
    raise exception 'An hourly price needs a daily rate';
  end if;

  update public.vehicles
    set rate_card_id = null,
        price_unit = p_unit,
        unit_rate = p_unit_rate,
        hourly_price = case when p_unit = 'hour' then p_unit_rate else hourly_price end,
        daily_price = case when p_unit = 'hour' then p_daily_rate else daily_price end,
        deposit = p_deposit
    where id = p_vehicle;
end;
$$;

create or replace function public.quote_rental(p_vehicle uuid, p_start timestamptz, p_end timestamptz, p_coupon text, p_km numeric)
returns jsonb language sql security invoker set search_path = public, private
as $$ select private.quote_rental(p_vehicle, p_start, p_end, p_coupon, p_km); $$;

create or replace function public.create_rental_booking(p_vehicle uuid, p_start timestamptz, p_end timestamptz, p_coupon text, p_km numeric)
returns uuid language sql security invoker set search_path = public, private
as $$ select private.create_rental_booking(p_vehicle, p_start, p_end, p_coupon, p_km); $$;

create or replace function public.save_rate_card(p_id uuid, p_name text, p_unit text, p_unit_rate numeric, p_daily_rate numeric, p_deposit numeric)
returns uuid language sql security invoker set search_path = public, private
as $$ select private.save_rate_card(p_id, p_name, p_unit, p_unit_rate, p_daily_rate, p_deposit); $$;

create or replace function public.allot_vehicle_price(p_vehicle uuid, p_rate_card uuid, p_unit text, p_unit_rate numeric, p_daily_rate numeric, p_deposit numeric)
returns void language sql security invoker set search_path = public, private
as $$ select private.allot_vehicle_price(p_vehicle, p_rate_card, p_unit, p_unit_rate, p_daily_rate, p_deposit); $$;

revoke all on function public.quote_rental(uuid, timestamptz, timestamptz, text, numeric) from public;
revoke all on function public.create_rental_booking(uuid, timestamptz, timestamptz, text, numeric) from public;
revoke all on function public.save_rate_card(uuid, text, text, numeric, numeric, numeric) from public;
revoke all on function public.allot_vehicle_price(uuid, uuid, text, numeric, numeric, numeric) from public;

grant execute on function public.quote_rental(uuid, timestamptz, timestamptz, text, numeric) to anon, authenticated;
grant execute on function public.create_rental_booking(uuid, timestamptz, timestamptz, text, numeric) to authenticated;
grant execute on function public.save_rate_card(uuid, text, text, numeric, numeric, numeric) to authenticated;
grant execute on function public.allot_vehicle_price(uuid, uuid, text, numeric, numeric, numeric) to authenticated;

grant execute on function private.quote_rental(uuid, timestamptz, timestamptz, text, numeric) to anon, authenticated;
grant execute on function private.create_rental_booking(uuid, timestamptz, timestamptz, text, numeric) to authenticated;
grant execute on function private.save_rate_card(uuid, text, text, numeric, numeric, numeric) to authenticated;
grant execute on function private.allot_vehicle_price(uuid, uuid, text, numeric, numeric, numeric) to authenticated;
