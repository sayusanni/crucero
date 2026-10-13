-- Crucero rental OS: bikes and cars, versioned GST, price snapshots, journals.
-- Replaces the earlier cruise-booking tables.

create extension if not exists btree_gist;

drop table if exists public.bookings cascade;
drop table if exists public.cruises cascade;

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  city text not null,
  address text not null,
  is_active boolean not null default true
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id),
  kind text not null check (kind in ('bike', 'car')),
  name text not null,
  model text not null,
  category text not null,
  engine_cc integer,
  ev_range_km integer,
  hourly_price numeric(12,2) not null check (hourly_price >= 0),
  daily_price numeric(12,2) not null check (daily_price >= 0),
  deposit numeric(12,2) not null check (deposit >= 0),
  features text[] not null default '{}',
  image_url text not null,
  registration text not null,
  status text not null default 'available' check (status in ('available', 'maintenance')),
  is_active boolean not null default true
);

create index vehicles_branch_kind_idx on public.vehicles (branch_id, kind) where is_active;

create table public.tax_rules (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sac text not null,
  rate_percent numeric(5,2) not null check (rate_percent >= 0),
  effective_from date not null,
  effective_to date,
  is_active boolean not null default true
);

create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  kind text not null check (kind in ('percent', 'flat')),
  value numeric(12,2) not null check (value > 0),
  is_active boolean not null default true,
  expires_at timestamptz
);

create table public.accounts (
  code text primary key,
  name text not null,
  kind text not null check (kind in ('asset', 'liability', 'income', 'expense'))
);

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add column if not exists branch_id uuid references public.branches (id);
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('customer', 'admin', 'manager', 'sales', 'mechanic', 'collection'));

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id),
  vehicle_id uuid not null references public.vehicles (id),
  branch_id uuid not null references public.branches (id),
  start_at timestamptz not null,
  end_at timestamptz not null,
  duration_hours numeric(10,2) not null,
  billed_days integer not null,
  remainder_hours numeric(10,2) not null,
  hourly_price numeric(12,2) not null,
  daily_price numeric(12,2) not null,
  base_amount numeric(12,2) not null,
  coupon_code text,
  discount_amount numeric(12,2) not null default 0,
  taxable_amount numeric(12,2) not null,
  tax_rule_id uuid not null references public.tax_rules (id),
  tax_rate numeric(5,2) not null,
  tax_amount numeric(12,2) not null,
  deposit_amount numeric(12,2) not null,
  rental_total numeric(12,2) not null,
  authorize_amount numeric(12,2) not null,
  status text not null default 'draft' check (
    status in ('draft', 'authorized', 'signed', 'captured', 'out', 'returned', 'cancelled')
  ),
  odometer_out integer,
  odometer_in integer,
  actual_return_at timestamptz,
  late_fee numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  check (end_at > start_at)
);

create index bookings_customer_idx on public.bookings (customer_id, created_at desc);
create index bookings_branch_status_idx on public.bookings (branch_id, status);
create index bookings_vehicle_time_idx on public.bookings (vehicle_id, start_at, end_at);

alter table public.bookings
  add constraint bookings_no_overlap
  exclude using gist (
    vehicle_id with =,
    tstzrange(start_at, end_at) with &&
  )
  where (status <> 'cancelled');

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id),
  booking_id uuid references public.bookings (id),
  kind text not null check (kind in ('dl_front', 'dl_back', 'id_last4')),
  storage_path text,
  last4 text check (last4 is null or last4 ~ '^[0-9A-Za-z]{4}$'),
  created_at timestamptz not null default now()
);

create table public.agreements (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings (id),
  body text not null,
  status text not null default 'pending' check (status in ('pending', 'signed')),
  signed_at timestamptz
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id),
  purpose text not null check (purpose in ('authorization', 'capture')),
  method text not null,
  amount numeric(12,2) not null,
  status text not null check (status in ('authorized', 'captured', 'failed')),
  created_at timestamptz not null default now()
);

create table public.financial_events (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references public.bookings (id),
  event_type text not null,
  amount numeric(12,2) not null,
  created_at timestamptz not null default now()
);

create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.financial_events (id),
  memo text not null,
  posted_at timestamptz not null default now()
);

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.journal_entries (id) on delete cascade,
  account_code text not null references public.accounts (code),
  debit numeric(12,2) not null default 0 check (debit >= 0),
  credit numeric(12,2) not null default 0 check (credit >= 0),
  check (debit = 0 or credit = 0)
);

create index journal_lines_account_idx on public.journal_lines (account_code);

insert into storage.buckets (id, name, public)
values ('customer-documents', 'customer-documents', false)
on conflict (id) do nothing;

-- Engines -------------------------------------------------------------------

create or replace function private.quote_rental(
  p_vehicle uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_coupon text
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
  days integer;
  rem numeric;
  base numeric;
  discount numeric := 0;
  taxable numeric;
  rate numeric;
  rule_id uuid;
  tax numeric;
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

  hours := round((extract(epoch from (p_end - p_start)) / 3600.0)::numeric, 2);
  if hours <= 24 then
    days := 0;
    rem := hours;
    base := round(hours * v.hourly_price, 2);
  else
    days := floor(hours / 24)::integer;
    rem := round(hours - days * 24, 2);
    base := round(days * v.daily_price + rem * v.hourly_price, 2);
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
    'hourly_price', v.hourly_price,
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

create or replace function private.vehicle_is_free(
  p_vehicle uuid,
  p_start timestamptz,
  p_end timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.bookings b
    where b.vehicle_id = p_vehicle
      and b.status <> 'cancelled'
      and tstzrange(b.start_at, b.end_at) && tstzrange(p_start, p_end)
  );
$$;

create or replace function private.available_vehicles(
  p_branch uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_kind text
)
returns setof public.vehicles
language sql
stable
security definer
set search_path = public
as $$
  select v.*
  from public.vehicles v
  where v.is_active
    and v.status = 'available'
    and (p_branch is null or v.branch_id = p_branch)
    and (p_kind is null or p_kind = '' or v.kind = p_kind)
    and private.vehicle_is_free(v.id, p_start, p_end)
  order by v.kind, v.hourly_price;
$$;

create or replace function private.create_rental_booking(
  p_vehicle uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_coupon text
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
  q := private.quote_rental(p_vehicle, p_start, p_end, p_coupon);

  insert into public.bookings (
    customer_id, vehicle_id, branch_id, start_at, end_at,
    duration_hours, billed_days, remainder_hours,
    hourly_price, daily_price, base_amount, coupon_code, discount_amount,
    taxable_amount, tax_rule_id, tax_rate, tax_amount,
    deposit_amount, rental_total, authorize_amount, status
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
    'draft'
  )
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function private.post_balanced(
  p_booking uuid,
  p_type text,
  p_amount numeric,
  p_memo text,
  p_lines jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ev uuid;
  entry uuid;
  line jsonb;
  debit_sum numeric := 0;
  credit_sum numeric := 0;
begin
  insert into public.financial_events (booking_id, event_type, amount)
  values (p_booking, p_type, p_amount)
  returning id into ev;

  insert into public.journal_entries (event_id, memo)
  values (ev, p_memo)
  returning id into entry;

  for line in select * from jsonb_array_elements(p_lines)
  loop
    insert into public.journal_lines (entry_id, account_code, debit, credit)
    values (
      entry,
      line->>'account',
      coalesce((line->>'debit')::numeric, 0),
      coalesce((line->>'credit')::numeric, 0)
    );
    debit_sum := debit_sum + coalesce((line->>'debit')::numeric, 0);
    credit_sum := credit_sum + coalesce((line->>'credit')::numeric, 0);
  end loop;

  if debit_sum <> credit_sum then
    raise exception 'Journal does not balance (% vs %)', debit_sum, credit_sum;
  end if;
end;
$$;

create or replace function private.authorize_booking(p_booking uuid, p_method text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
begin
  select * into b from public.bookings where id = p_booking and customer_id = auth.uid();
  if not found then
    raise exception 'Booking not found';
  end if;
  if b.status <> 'draft' then
    raise exception 'This booking cannot be authorized';
  end if;
  if not exists (
    select 1 from public.documents
    where booking_id = p_booking and kind = 'dl_front'
  ) or not exists (
    select 1 from public.documents
    where booking_id = p_booking and kind = 'id_last4'
  ) then
    raise exception 'Upload the licence and ID reference before payment';
  end if;

  insert into public.payments (booking_id, purpose, method, amount, status)
  values (p_booking, 'authorization', p_method, b.authorize_amount, 'authorized');

  update public.bookings set status = 'authorized' where id = p_booking;
end;
$$;

create or replace function private.sign_agreement(p_booking uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  body text;
begin
  select * into b from public.bookings where id = p_booking and customer_id = auth.uid();
  if not found or b.status <> 'authorized' then
    raise exception 'Sign the agreement only after payment is authorized';
  end if;

  body := 'Crucero rental agreement for booking ' || b.id::text
    || '. Rental ' || b.rental_total::text
    || ' (tax ' || b.tax_amount::text || ' at ' || b.tax_rate::text || '%).'
    || ' Deposit ' || b.deposit_amount::text || ' is a liability, not revenue.'
    || ' Damage, late return, and cancellation follow the branch desk rules.';

  insert into public.agreements (booking_id, body, status, signed_at)
  values (p_booking, body, 'signed', now())
  on conflict (booking_id) do update
    set status = 'signed', signed_at = now(), body = excluded.body;

  update public.bookings set status = 'signed' where id = p_booking;
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
    'Rental revenue and GST. Deposit is not included.',
    jsonb_build_array(
      jsonb_build_object('account', '1000', 'debit', b.rental_total, 'credit', 0),
      jsonb_build_object('account', '4000', 'debit', 0, 'credit', b.taxable_amount),
      jsonb_build_object('account', '2200', 'debit', 0, 'credit', b.tax_amount)
    )
  );

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

  update public.bookings set status = 'captured' where id = p_booking;
end;
$$;

create or replace function private.staff_can(p_branch uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and (
        role = 'admin'
        or (role in ('manager', 'sales', 'mechanic', 'collection') and branch_id = p_branch)
      )
  );
$$;

create or replace function private.confirm_pickup(p_booking uuid, p_odometer integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
begin
  select * into b from public.bookings where id = p_booking;
  if not found or not private.staff_can(b.branch_id) then
    raise exception 'Not allowed to confirm this pickup';
  end if;
  if b.status <> 'captured' then
    raise exception 'Pickup waits until payment is captured';
  end if;
  update public.bookings
    set status = 'out', odometer_out = p_odometer
    where id = p_booking;
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
  late_hours numeric;
  fee numeric;
begin
  select * into b from public.bookings where id = p_booking;
  if not found or not private.staff_can(b.branch_id) then
    raise exception 'Not allowed to confirm this return';
  end if;
  if b.status <> 'out' then
    raise exception 'This vehicle is not out';
  end if;

  late_hours := greatest(round((extract(epoch from (p_returned_at - b.end_at)) / 3600.0)::numeric, 2), 0);
  fee := round(late_hours * b.hourly_price, 2);

  if fee > 0 then
    perform private.post_balanced(
      p_booking,
      'late_fee',
      fee,
      'Late return charged from the price snapshot hourly rate.',
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

-- Public RPC wrappers (invoker). Logic stays in private. -----------------

create or replace function public.quote_rental(p_vehicle uuid, p_start timestamptz, p_end timestamptz, p_coupon text)
returns jsonb language sql security invoker set search_path = public, private
as $$ select private.quote_rental(p_vehicle, p_start, p_end, p_coupon); $$;

create or replace function public.available_vehicles(p_branch uuid, p_start timestamptz, p_end timestamptz, p_kind text)
returns setof public.vehicles language sql security invoker set search_path = public, private
as $$ select * from private.available_vehicles(p_branch, p_start, p_end, p_kind); $$;

create or replace function public.create_rental_booking(p_vehicle uuid, p_start timestamptz, p_end timestamptz, p_coupon text)
returns uuid language sql security invoker set search_path = public, private
as $$ select private.create_rental_booking(p_vehicle, p_start, p_end, p_coupon); $$;

create or replace function public.authorize_booking(p_booking uuid, p_method text)
returns void language sql security invoker set search_path = public, private
as $$ select private.authorize_booking(p_booking, p_method); $$;

create or replace function public.sign_agreement(p_booking uuid)
returns void language sql security invoker set search_path = public, private
as $$ select private.sign_agreement(p_booking); $$;

create or replace function public.capture_booking(p_booking uuid)
returns void language sql security invoker set search_path = public, private
as $$ select private.capture_booking(p_booking); $$;

create or replace function public.confirm_pickup(p_booking uuid, p_odometer integer)
returns void language sql security invoker set search_path = public, private
as $$ select private.confirm_pickup(p_booking, p_odometer); $$;

create or replace function public.confirm_return(p_booking uuid, p_odometer integer, p_returned_at timestamptz)
returns void language sql security invoker set search_path = public, private
as $$ select private.confirm_return(p_booking, p_odometer, p_returned_at); $$;

revoke all on function public.quote_rental(uuid, timestamptz, timestamptz, text) from public;
revoke all on function public.available_vehicles(uuid, timestamptz, timestamptz, text) from public;
revoke all on function public.create_rental_booking(uuid, timestamptz, timestamptz, text) from public;
revoke all on function public.authorize_booking(uuid, text) from public;
revoke all on function public.sign_agreement(uuid) from public;
revoke all on function public.capture_booking(uuid) from public;
revoke all on function public.confirm_pickup(uuid, integer) from public;
revoke all on function public.confirm_return(uuid, integer, timestamptz) from public;

grant execute on function public.quote_rental(uuid, timestamptz, timestamptz, text) to anon, authenticated;
grant execute on function public.available_vehicles(uuid, timestamptz, timestamptz, text) to anon, authenticated;
grant execute on function public.create_rental_booking(uuid, timestamptz, timestamptz, text) to authenticated;
grant execute on function public.authorize_booking(uuid, text) to authenticated;
grant execute on function public.sign_agreement(uuid) to authenticated;
grant execute on function public.capture_booking(uuid) to authenticated;
grant execute on function public.confirm_pickup(uuid, integer) to authenticated;
grant execute on function public.confirm_return(uuid, integer, timestamptz) to authenticated;

grant execute on function private.quote_rental(uuid, timestamptz, timestamptz, text) to anon, authenticated;
grant execute on function private.available_vehicles(uuid, timestamptz, timestamptz, text) to anon, authenticated;
grant execute on function private.create_rental_booking(uuid, timestamptz, timestamptz, text) to authenticated;
grant execute on function private.vehicle_is_free(uuid, timestamptz, timestamptz) to anon, authenticated;
grant execute on function private.authorize_booking(uuid, text) to authenticated;
grant execute on function private.sign_agreement(uuid) to authenticated;
grant execute on function private.capture_booking(uuid) to authenticated;
grant execute on function private.confirm_pickup(uuid, integer) to authenticated;
grant execute on function private.confirm_return(uuid, integer, timestamptz) to authenticated;
grant execute on function private.staff_can(uuid) to authenticated;

-- RLS ----------------------------------------------------------------------

alter table public.branches enable row level security;
alter table public.vehicles enable row level security;
alter table public.tax_rules enable row level security;
alter table public.coupons enable row level security;
alter table public.accounts enable row level security;
alter table public.bookings enable row level security;
alter table public.documents enable row level security;
alter table public.agreements enable row level security;
alter table public.payments enable row level security;
alter table public.financial_events enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;

create policy "read branches" on public.branches for select to anon, authenticated using (is_active or private.is_admin());
create policy "read vehicles" on public.vehicles for select to anon, authenticated using (is_active or private.is_admin());
create policy "read tax rules" on public.tax_rules for select to anon, authenticated using (true);
create policy "read coupons" on public.coupons for select to authenticated using (is_active or private.is_admin());
create policy "read accounts" on public.accounts for select to authenticated using (private.is_admin());

create policy "read own or staff bookings" on public.bookings for select to authenticated
  using (customer_id = auth.uid() or private.staff_can(branch_id));

create policy "read own documents" on public.documents for select to authenticated
  using (customer_id = auth.uid() or private.is_admin());
create policy "insert own documents" on public.documents for insert to authenticated
  with check (customer_id = auth.uid());

create policy "read own agreements" on public.agreements for select to authenticated
  using (
    exists (
      select 1 from public.bookings b
      where b.id = booking_id and (b.customer_id = auth.uid() or private.staff_can(b.branch_id))
    )
  );

create policy "read own payments" on public.payments for select to authenticated
  using (
    exists (
      select 1 from public.bookings b
      where b.id = booking_id and (b.customer_id = auth.uid() or private.staff_can(b.branch_id))
    )
  );

create policy "read finance events" on public.financial_events for select to authenticated
  using (private.is_admin());
create policy "read journals" on public.journal_entries for select to authenticated
  using (private.is_admin());
create policy "read journal lines" on public.journal_lines for select to authenticated
  using (private.is_admin());

create policy "own document files" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'customer-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "read own document files" on storage.objects for select to authenticated
  using (
    bucket_id = 'customer-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

grant select on public.branches, public.vehicles, public.tax_rules to anon, authenticated;
grant select on public.coupons, public.accounts, public.bookings, public.documents,
  public.agreements, public.payments, public.financial_events, public.journal_entries, public.journal_lines
  to authenticated;
grant insert on public.documents to authenticated;

-- Seed ---------------------------------------------------------------------

insert into public.accounts (code, name, kind) values
  ('1000', 'Cash', 'asset'),
  ('2100', 'Customer deposits', 'liability'),
  ('2200', 'GST payable', 'liability'),
  ('4000', 'Rental revenue', 'income'),
  ('4100', 'Late fees', 'income');

insert into public.tax_rules (name, sac, rate_percent, effective_from)
values ('GST on vehicle rental', '997329', 18, '2026-04-01');

insert into public.coupons (code, kind, value)
values ('WEEKEND10', 'percent', 10);

insert into public.branches (id, name, city, address) values
  ('11111111-1111-1111-1111-111111111111', 'Jubilee Hills', 'Hyderabad', 'Road 36, Jubilee Hills'),
  ('22222222-2222-2222-2222-222222222222', 'Gachibowli', 'Hyderabad', 'Financial District road, Gachibowli'),
  ('33333333-3333-3333-3333-333333333333', 'Secunderabad', 'Hyderabad', 'SP Road, Secunderabad');

insert into public.vehicles (
  branch_id, kind, name, model, category, engine_cc, ev_range_km,
  hourly_price, daily_price, deposit, features, image_url, registration
) values
  ('11111111-1111-1111-1111-111111111111', 'bike', 'Classic 350', 'Royal Enfield', 'Cruiser', 350, null, 120, 1400, 3000,
    array['ABS','Disc brake'], 'https://images.unsplash.com/photo-1558981403-c5f9899a28bc?auto=format&fit=crop&w=1400&q=80', 'TS09AB3501'),
  ('11111111-1111-1111-1111-111111111111', 'bike', 'Activa', 'Honda', 'Scooter', 110, null, 60, 700, 1000,
    array['Storage box','Easy seat'], 'https://images.unsplash.com/photo-1558980664-1db506751c6c?auto=format&fit=crop&w=1400&q=80', 'TS09SC1102'),
  ('22222222-2222-2222-2222-222222222222', 'bike', 'Ather 450', 'Ather', 'EV scooter', null, 120, 90, 1100, 2000,
    array['Fast charge','App lock'], 'https://images.unsplash.com/photo-1558981806-ec527fa84c39?auto=format&fit=crop&w=1400&q=80', 'TS07EV4501'),
  ('22222222-2222-2222-2222-222222222222', 'car', 'Swift', 'Maruti', 'Hatchback', 1197, null, 250, 2200, 5000,
    array['AC','Bluetooth'], 'https://images.unsplash.com/photo-1541899481282-d53bffe3c35d?auto=format&fit=crop&w=1400&q=80', 'TS07SW1197'),
  ('33333333-3333-3333-3333-333333333333', 'car', 'Creta', 'Hyundai', 'SUV', 1497, null, 400, 3600, 8000,
    array['Automatic','Cruise control'], 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?auto=format&fit=crop&w=1400&q=80', 'TS10CR1497'),
  ('33333333-3333-3333-3333-333333333333', 'bike', 'Pulsar 150', 'Bajaj', 'Commuter', 150, null, 70, 800, 1500,
    array['Kick and electric start'], 'https://images.unsplash.com/photo-1449426468159-d96dbf08f19f?auto=format&fit=crop&w=1400&q=80', 'TS10PL1501');
