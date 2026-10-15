--
-- PostgreSQL database dump
--

\restrict yQtUW6QC2ndFRsffZe9dSQ4LjXztbDJ3L8qLCwR51g9ni8WmgczdmDivfdL7yQ1

-- Dumped from database version 17.11
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: private; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA private;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: add_tax_rule(text, text, numeric, date); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.add_tax_rule(p_name text, p_sac text, p_rate numeric, p_from date) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  new_id uuid;
begin
  if not private.has_area('gst') then
    raise exception 'Only the GST desk can version a tax rule';
  end if;
  if p_rate < 0 or length(trim(p_sac)) < 4 or p_from is null then
    raise exception 'A tax rule needs a SAC, a rate, and a start date';
  end if;

  update public.tax_rules
    set effective_to = p_from - 1
    where is_active
      and effective_to is null
      and effective_from < p_from;

  insert into public.tax_rules (name, sac, rate_percent, effective_from)
  values (trim(p_name), trim(p_sac), p_rate, p_from)
  returning id into new_id;

  return new_id;
end;
$$;


--
-- Name: allot_vehicle_price(uuid, uuid, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.allot_vehicle_price(p_vehicle uuid, p_rate_card uuid, p_package numeric, p_included_km numeric, p_excess numeric, p_deposit numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: allot_vehicle_price(uuid, uuid, text, numeric, numeric, numeric); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.allot_vehicle_price(p_vehicle uuid, p_rate_card uuid, p_unit text, p_unit_rate numeric, p_daily_rate numeric, p_deposit numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: authorize_booking(uuid, text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.authorize_booking(p_booking uuid, p_method text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare b public.bookings%rowtype;
begin
  select * into b from public.bookings where id = p_booking and customer_id = auth.uid();
  if not found then raise exception 'Booking not found'; end if;
  if b.status <> 'draft' then raise exception 'This booking cannot be authorized'; end if;
  if not exists (select 1 from public.documents where booking_id = p_booking and kind = 'dl_front')
     or not exists (select 1 from public.documents where booking_id = p_booking and kind = 'id_last4') then
    raise exception 'Upload the licence and ID reference before payment';
  end if;
  insert into public.payments (booking_id, purpose, method, amount, status)
  values (p_booking, 'authorization', p_method, b.authorize_amount, 'authorized');
  update public.bookings set status = 'authorized' where id = p_booking;
end; $$;


--
-- Name: auto_confirm_user(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.auto_confirm_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'auth'
    AS $$
begin
  new.email_confirmed_at := coalesce(new.email_confirmed_at, now());
  return new;
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: vehicles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vehicles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    branch_id uuid NOT NULL,
    kind text NOT NULL,
    name text NOT NULL,
    model text NOT NULL,
    category text NOT NULL,
    engine_cc integer,
    ev_range_km integer,
    hourly_price numeric(12,2) NOT NULL,
    daily_price numeric(12,2) NOT NULL,
    deposit numeric(12,2) NOT NULL,
    features text[] DEFAULT '{}'::text[] NOT NULL,
    image_url text NOT NULL,
    registration text NOT NULL,
    status text DEFAULT 'available'::text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    rate_card_id uuid,
    price_unit text DEFAULT 'hour'::text NOT NULL,
    unit_rate numeric(12,2) NOT NULL,
    package_price numeric(12,2),
    included_km numeric(10,2),
    excess_per_km numeric(12,2),
    CONSTRAINT vehicles_daily_price_check CHECK ((daily_price >= (0)::numeric)),
    CONSTRAINT vehicles_deposit_check CHECK ((deposit >= (0)::numeric)),
    CONSTRAINT vehicles_hourly_price_check CHECK ((hourly_price >= (0)::numeric)),
    CONSTRAINT vehicles_kind_check CHECK ((kind = ANY (ARRAY['bike'::text, 'car'::text]))),
    CONSTRAINT vehicles_price_unit_check CHECK ((price_unit = ANY (ARRAY['hour'::text, 'minute'::text, 'km'::text, 'package'::text]))),
    CONSTRAINT vehicles_status_check CHECK ((status = ANY (ARRAY['available'::text, 'maintenance'::text])))
);


--
-- Name: available_vehicles(uuid, timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.available_vehicles(p_branch uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_kind text) RETURNS SETOF public.vehicles
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select v.* from public.vehicles v
  where v.is_active and v.status = 'available'
    and (p_branch is null or v.branch_id = p_branch)
    and (p_kind is null or p_kind = '' or v.kind = p_kind)
    and private.vehicle_is_free(v.id, p_start, p_end)
  order by v.kind, v.hourly_price;
$$;


--
-- Name: capture_booking(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.capture_booking(p_booking uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: claim_first_admin(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.claim_first_admin() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if auth.uid() is null then
    return false;
  end if;
  if exists (select 1 from public.profiles where role = 'admin') then
    return exists (
      select 1 from public.profiles where id = auth.uid() and role = 'admin'
    );
  end if;
  update public.profiles set role = 'admin' where id = auth.uid();
  return true;
end;
$$;


--
-- Name: confirm_pickup(uuid, integer); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.confirm_pickup(p_booking uuid, p_odometer integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare b public.bookings%rowtype;
begin
  select * into b from public.bookings where id = p_booking;
  if not found or not private.staff_can(b.branch_id) then raise exception 'Not allowed to confirm this pickup'; end if;
  if b.status <> 'captured' then raise exception 'Pickup waits until payment is captured'; end if;
  update public.bookings set status = 'out', odometer_out = p_odometer where id = p_booking;
end; $$;


--
-- Name: confirm_return(uuid, integer, timestamp with time zone); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.confirm_return(p_booking uuid, p_odometer integer, p_returned_at timestamp with time zone) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: create_rental_booking(uuid, timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.create_rental_booking(p_vehicle uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_coupon text) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select private.create_rental_booking(p_vehicle, p_start, p_end, p_coupon, null);
$$;


--
-- Name: create_rental_booking(uuid, timestamp with time zone, timestamp with time zone, text, numeric); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.create_rental_booking(p_vehicle uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_coupon text, p_km numeric) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    'customer'
  );
  return new;
end;
$$;


--
-- Name: has_area(text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.has_area(p_area text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.profile_areas
    where profile_id = auth.uid() and area = p_area
  );
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;


--
-- Name: package_multiplier(numeric); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.package_multiplier(p_hours numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    when p_hours <= 24 then 1::numeric
    else floor(p_hours / 24) + round(p_hours - floor(p_hours / 24) * 24, 2) / 24
  end;
$$;


--
-- Name: post_balanced(uuid, text, numeric, text, jsonb); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.post_balanced(p_booking uuid, p_type text, p_amount numeric, p_memo text, p_lines jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare ev uuid; entry uuid; line jsonb; debit_sum numeric := 0; credit_sum numeric := 0;
begin
  insert into public.financial_events (booking_id, event_type, amount) values (p_booking, p_type, p_amount) returning id into ev;
  insert into public.journal_entries (event_id, memo) values (ev, p_memo) returning id into entry;
  for line in select * from jsonb_array_elements(p_lines) loop
    insert into public.journal_lines (entry_id, account_code, debit, credit) values (
      entry, line->>'account', coalesce((line->>'debit')::numeric, 0), coalesce((line->>'credit')::numeric, 0)
    );
    debit_sum := debit_sum + coalesce((line->>'debit')::numeric, 0);
    credit_sum := credit_sum + coalesce((line->>'credit')::numeric, 0);
  end loop;
  if debit_sum <> credit_sum then raise exception 'Journal does not balance (% vs %)', debit_sum, credit_sum; end if;
end; $$;


--
-- Name: protect_profile_role(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.protect_profile_role() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'private'
    AS $$
begin
  if new.role is distinct from old.role then
    if not exists (select 1 from public.profiles where role = 'admin' and id <> new.id) then
      return new;
    end if;
    if auth.uid() is null or private.is_admin() then
      return new;
    end if;
    new.role := old.role;
  end if;
  return new;
end;
$$;


--
-- Name: queue_booking_notice(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.queue_booking_notice() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  who text;
  tpl text;
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;
  if new.status not in ('captured', 'out', 'returned') then
    return new;
  end if;

  select coalesce(nullif(email, ''), nullif(phone, ''), full_name, 'customer')
    into who
  from public.profiles
  where id = new.customer_id;

  tpl := case new.status
    when 'captured' then 'booking_confirmed'
    when 'out' then 'vehicle_picked_up'
    else 'vehicle_returned'
  end;

  insert into public.notifications (booking_id, channel, recipient, template)
  values
    (new.id, 'sms', who, tpl),
    (new.id, 'whatsapp', who, tpl);

  return new;
end;
$$;


--
-- Name: quote_rental(uuid, timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.quote_rental(p_vehicle uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_coupon text) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select private.quote_rental(p_vehicle, p_start, p_end, p_coupon, null);
$$;


--
-- Name: quote_rental(uuid, timestamp with time zone, timestamp with time zone, text, numeric); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.quote_rental(p_vehicle uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_coupon text, p_km numeric) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: release_deposit(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.release_deposit(p_booking uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  b public.bookings%rowtype;
begin
  if not private.has_area('finance') then
    raise exception 'Only the finance desk can release a deposit';
  end if;
  select * into b from public.bookings where id = p_booking;
  if not found or b.status <> 'returned' then
    raise exception 'Release a deposit only after the vehicle is returned';
  end if;
  if b.deposit_amount <= 0 then
    raise exception 'This booking has no deposit';
  end if;
  if exists (
    select 1 from public.financial_events
    where booking_id = p_booking and event_type = 'deposit_released'
  ) then
    raise exception 'This deposit is already released';
  end if;

  perform private.post_balanced(
    p_booking,
    'deposit_released',
    b.deposit_amount,
    'Deposit returned to the customer. It was never revenue.',
    jsonb_build_array(
      jsonb_build_object('account', '2100', 'debit', b.deposit_amount, 'credit', 0),
      jsonb_build_object('account', '1000', 'debit', 0, 'credit', b.deposit_amount)
    )
  );
end;
$$;


--
-- Name: reserve_booking_seats(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.reserve_booking_seats() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  seats integer;
  cap integer;
begin
  if tg_op = 'INSERT' and new.status <> 'cancelled' then
    update public.cruises
      set booked_seats = booked_seats + new.passengers
      where id = new.cruise_id
      returning booked_seats, capacity into seats, cap;
    if seats > cap then
      raise exception 'Not enough seats remaining on this cruise';
    end if;
  elsif tg_op = 'UPDATE' and old.status <> 'cancelled' and new.status = 'cancelled' then
    update public.cruises
      set booked_seats = greatest(booked_seats - old.passengers, 0)
      where id = new.cruise_id;
  end if;
  return new;
end;
$$;


--
-- Name: save_rate_card(uuid, text, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.save_rate_card(p_id uuid, p_name text, p_package numeric, p_included_km numeric, p_excess numeric, p_deposit numeric) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: save_rate_card(uuid, text, text, numeric, numeric, numeric); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.save_rate_card(p_id uuid, p_name text, p_unit text, p_unit_rate numeric, p_daily_rate numeric, p_deposit numeric) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: set_vehicle_status(uuid, text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.set_vehicle_status(p_vehicle uuid, p_status text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v public.vehicles%rowtype;
begin
  if p_status not in ('available', 'maintenance') then
    raise exception 'Status must be available or maintenance';
  end if;
  select * into v from public.vehicles where id = p_vehicle;
  if not found or not private.staff_can(v.branch_id) then
    raise exception 'Not allowed to change this vehicle';
  end if;
  update public.vehicles set status = p_status where id = p_vehicle;
end;
$$;


--
-- Name: sign_agreement(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.sign_agreement(p_booking uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare b public.bookings%rowtype; body text;
begin
  select * into b from public.bookings where id = p_booking and customer_id = auth.uid();
  if not found or b.status <> 'authorized' then raise exception 'Sign the agreement only after payment is authorized'; end if;
  body := 'Crucero rental agreement for booking ' || b.id::text || '. Rental ' || b.rental_total::text || ' (tax ' || b.tax_amount::text || ' at ' || b.tax_rate::text || '%). Deposit ' || b.deposit_amount::text || ' is a liability, not revenue. Damage, late return, and cancellation follow the branch desk rules.';
  insert into public.agreements (booking_id, body, status, signed_at) values (p_booking, body, 'signed', now())
  on conflict (booking_id) do update set status = 'signed', signed_at = now(), body = excluded.body;
  update public.bookings set status = 'signed' where id = p_booking;
end; $$;


--
-- Name: staff_can(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.staff_can(p_branch uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and (
      role = 'admin' or (role in ('manager','sales','mechanic','collection') and branch_id = p_branch)
    )
  );
$$;


--
-- Name: sync_profile_areas(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.sync_profile_areas() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.role = 'customer' then
    insert into public.profile_areas (profile_id, area) values (new.id, 'platform')
    on conflict do nothing;
  elsif new.role = 'admin' then
    insert into public.profile_areas (profile_id, area)
    select new.id, a from unnest(array['operations','finance','gst','reports','backend']) as a
    on conflict do nothing;
  elsif new.role in ('manager','sales','mechanic','collection') then
    insert into public.profile_areas (profile_id, area) values (new.id, 'operations')
    on conflict do nothing;
  end if;
  return new;
end;
$$;


--
-- Name: vehicle_is_free(uuid, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.vehicle_is_free(p_vehicle uuid, p_start timestamp with time zone, p_end timestamp with time zone) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select not exists (
    select 1 from public.bookings b
    where b.vehicle_id = p_vehicle and b.status <> 'cancelled'
      and tstzrange(b.start_at, b.end_at) && tstzrange(p_start, p_end)
  );
$$;


--
-- Name: add_tax_rule(text, text, numeric, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_tax_rule(p_name text, p_sac text, p_rate numeric, p_from date) RETURNS uuid
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$ select private.add_tax_rule(p_name, p_sac, p_rate, p_from); $$;


--
-- Name: allot_package(uuid, uuid, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.allot_package(p_vehicle uuid, p_rate_card uuid, p_package numeric, p_included_km numeric, p_excess numeric, p_deposit numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$ select private.allot_vehicle_price(p_vehicle, p_rate_card, p_package, p_included_km, p_excess, p_deposit); $$;


--
-- Name: allot_vehicle_price(uuid, uuid, text, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.allot_vehicle_price(p_vehicle uuid, p_rate_card uuid, p_unit text, p_unit_rate numeric, p_daily_rate numeric, p_deposit numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$ select private.allot_vehicle_price(p_vehicle, p_rate_card, p_unit, p_unit_rate, p_daily_rate, p_deposit); $$;


--
-- Name: authorize_booking(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.authorize_booking(p_booking uuid, p_method text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$
  select private.authorize_booking(p_booking, p_method); $$;


--
-- Name: available_vehicles(uuid, timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.available_vehicles(p_branch uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_kind text) RETURNS SETOF public.vehicles
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$
  select * from private.available_vehicles(p_branch, p_start, p_end, p_kind); $$;


--
-- Name: capture_booking(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.capture_booking(p_booking uuid) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$
  select private.capture_booking(p_booking); $$;


--
-- Name: claim_first_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.claim_first_admin() RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
  select private.claim_first_admin();
$$;


--
-- Name: confirm_pickup(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_pickup(p_booking uuid, p_odometer integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$
  select private.confirm_pickup(p_booking, p_odometer); $$;


--
-- Name: confirm_return(uuid, integer, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_return(p_booking uuid, p_odometer integer, p_returned_at timestamp with time zone) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$
  select private.confirm_return(p_booking, p_odometer, p_returned_at); $$;


--
-- Name: create_rental_booking(uuid, timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_rental_booking(p_vehicle uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_coupon text) RETURNS uuid
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$
  select private.create_rental_booking(p_vehicle, p_start, p_end, p_coupon); $$;


--
-- Name: create_rental_booking(uuid, timestamp with time zone, timestamp with time zone, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_rental_booking(p_vehicle uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_coupon text, p_km numeric) RETURNS uuid
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$ select private.create_rental_booking(p_vehicle, p_start, p_end, p_coupon, p_km); $$;


--
-- Name: quote_rental(uuid, timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.quote_rental(p_vehicle uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_coupon text) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$
  select private.quote_rental(p_vehicle, p_start, p_end, p_coupon); $$;


--
-- Name: quote_rental(uuid, timestamp with time zone, timestamp with time zone, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.quote_rental(p_vehicle uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_coupon text, p_km numeric) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$ select private.quote_rental(p_vehicle, p_start, p_end, p_coupon, p_km); $$;


--
-- Name: release_deposit(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.release_deposit(p_booking uuid) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$ select private.release_deposit(p_booking); $$;


--
-- Name: save_package(uuid, text, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_package(p_id uuid, p_name text, p_package numeric, p_included_km numeric, p_excess numeric, p_deposit numeric) RETURNS uuid
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$ select private.save_rate_card(p_id, p_name, p_package, p_included_km, p_excess, p_deposit); $$;


--
-- Name: save_rate_card(uuid, text, text, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_rate_card(p_id uuid, p_name text, p_unit text, p_unit_rate numeric, p_daily_rate numeric, p_deposit numeric) RETURNS uuid
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$ select private.save_rate_card(p_id, p_name, p_unit, p_unit_rate, p_daily_rate, p_deposit); $$;


--
-- Name: set_vehicle_status(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_vehicle_status(p_vehicle uuid, p_status text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$ select private.set_vehicle_status(p_vehicle, p_status); $$;


--
-- Name: sign_agreement(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sign_agreement(p_booking uuid) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'private'
    AS $$
  select private.sign_agreement(p_booking); $$;


--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    code text NOT NULL,
    name text NOT NULL,
    kind text NOT NULL,
    CONSTRAINT accounts_kind_check CHECK ((kind = ANY (ARRAY['asset'::text, 'liability'::text, 'income'::text, 'expense'::text])))
);


--
-- Name: agreements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agreements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid NOT NULL,
    body text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    signed_at timestamp with time zone,
    CONSTRAINT agreements_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'signed'::text])))
);


--
-- Name: bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone NOT NULL,
    duration_hours numeric(10,2) NOT NULL,
    billed_days integer NOT NULL,
    remainder_hours numeric(10,2) NOT NULL,
    hourly_price numeric(12,2) NOT NULL,
    daily_price numeric(12,2) NOT NULL,
    base_amount numeric(12,2) NOT NULL,
    coupon_code text,
    discount_amount numeric(12,2) DEFAULT 0 NOT NULL,
    taxable_amount numeric(12,2) NOT NULL,
    tax_rule_id uuid NOT NULL,
    tax_rate numeric(5,2) NOT NULL,
    tax_amount numeric(12,2) NOT NULL,
    deposit_amount numeric(12,2) NOT NULL,
    rental_total numeric(12,2) NOT NULL,
    authorize_amount numeric(12,2) NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    odometer_out integer,
    odometer_in integer,
    actual_return_at timestamp with time zone,
    late_fee numeric(12,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    price_unit text DEFAULT 'hour'::text NOT NULL,
    unit_rate numeric(12,2),
    planned_km numeric(10,2),
    actual_km numeric(10,2),
    estimated_rental numeric(12,2),
    package_price numeric(12,2),
    included_km numeric(10,2),
    excess_per_km numeric(12,2),
    km_allowance numeric(10,2),
    excess_km numeric(10,2),
    excess_amount numeric(12,2),
    CONSTRAINT bookings_check CHECK ((end_at > start_at)),
    CONSTRAINT bookings_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'authorized'::text, 'signed'::text, 'captured'::text, 'out'::text, 'returned'::text, 'cancelled'::text])))
);


--
-- Name: branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    city text NOT NULL,
    address text NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: coupons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coupons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    kind text NOT NULL,
    value numeric(12,2) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    expires_at timestamp with time zone,
    CONSTRAINT coupons_kind_check CHECK ((kind = ANY (ARRAY['percent'::text, 'flat'::text]))),
    CONSTRAINT coupons_value_check CHECK ((value > (0)::numeric))
);


--
-- Name: documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    booking_id uuid,
    kind text NOT NULL,
    storage_path text,
    last4 text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT documents_kind_check CHECK ((kind = ANY (ARRAY['dl_front'::text, 'dl_back'::text, 'id_last4'::text]))),
    CONSTRAINT documents_last4_check CHECK (((last4 IS NULL) OR (last4 ~ '^[0-9A-Za-z]{4}$'::text)))
);


--
-- Name: financial_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.financial_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid,
    event_type text NOT NULL,
    amount numeric(12,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: journal_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    memo text NOT NULL,
    posted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: journal_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    entry_id uuid NOT NULL,
    account_code text NOT NULL,
    debit numeric(12,2) DEFAULT 0 NOT NULL,
    credit numeric(12,2) DEFAULT 0 NOT NULL,
    CONSTRAINT journal_lines_check CHECK (((debit = (0)::numeric) OR (credit = (0)::numeric))),
    CONSTRAINT journal_lines_credit_check CHECK ((credit >= (0)::numeric)),
    CONSTRAINT journal_lines_debit_check CHECK ((debit >= (0)::numeric))
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid,
    channel text NOT NULL,
    recipient text NOT NULL,
    template text NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT notifications_channel_check CHECK ((channel = ANY (ARRAY['sms'::text, 'whatsapp'::text, 'email'::text]))),
    CONSTRAINT notifications_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'sent'::text])))
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid NOT NULL,
    purpose text NOT NULL,
    method text NOT NULL,
    amount numeric(12,2) NOT NULL,
    status text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payments_purpose_check CHECK ((purpose = ANY (ARRAY['authorization'::text, 'capture'::text]))),
    CONSTRAINT payments_status_check CHECK ((status = ANY (ARRAY['authorized'::text, 'captured'::text, 'failed'::text])))
);


--
-- Name: profile_areas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profile_areas (
    profile_id uuid NOT NULL,
    area text NOT NULL,
    CONSTRAINT profile_areas_area_check CHECK ((area = ANY (ARRAY['platform'::text, 'operations'::text, 'finance'::text, 'gst'::text, 'reports'::text, 'backend'::text])))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    full_name text DEFAULT ''::text NOT NULL,
    email text,
    phone text,
    role text DEFAULT 'customer'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    branch_id uuid,
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['customer'::text, 'admin'::text, 'manager'::text, 'sales'::text, 'mechanic'::text, 'collection'::text])))
);


--
-- Name: rate_cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_cards (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    unit text NOT NULL,
    unit_rate numeric(12,2) NOT NULL,
    daily_rate numeric(12,2),
    deposit numeric(12,2) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    included_km numeric(10,2),
    excess_per_km numeric(12,2),
    CONSTRAINT rate_cards_daily_rate_check CHECK (((daily_rate IS NULL) OR (daily_rate >= (0)::numeric))),
    CONSTRAINT rate_cards_deposit_check CHECK ((deposit >= (0)::numeric)),
    CONSTRAINT rate_cards_unit_check CHECK ((unit = ANY (ARRAY['hour'::text, 'minute'::text, 'km'::text, 'package'::text]))),
    CONSTRAINT rate_cards_unit_rate_check CHECK ((unit_rate >= (0)::numeric))
);


--
-- Name: tax_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tax_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    sac text NOT NULL,
    rate_percent numeric(5,2) NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    is_active boolean DEFAULT true NOT NULL,
    CONSTRAINT tax_rules_rate_percent_check CHECK ((rate_percent >= (0)::numeric))
);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (code);


--
-- Name: agreements agreements_booking_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agreements
    ADD CONSTRAINT agreements_booking_id_key UNIQUE (booking_id);


--
-- Name: agreements agreements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agreements
    ADD CONSTRAINT agreements_pkey PRIMARY KEY (id);


--
-- Name: bookings bookings_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_no_overlap EXCLUDE USING gist (vehicle_id WITH =, tstzrange(start_at, end_at) WITH &&) WHERE ((status <> 'cancelled'::text));


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (id);


--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);


--
-- Name: coupons coupons_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_code_key UNIQUE (code);


--
-- Name: coupons coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_pkey PRIMARY KEY (id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: financial_events financial_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_events
    ADD CONSTRAINT financial_events_pkey PRIMARY KEY (id);


--
-- Name: journal_entries journal_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_pkey PRIMARY KEY (id);


--
-- Name: journal_lines journal_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT journal_lines_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: profile_areas profile_areas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profile_areas
    ADD CONSTRAINT profile_areas_pkey PRIMARY KEY (profile_id, area);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: rate_cards rate_cards_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_cards
    ADD CONSTRAINT rate_cards_name_key UNIQUE (name);


--
-- Name: rate_cards rate_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_cards
    ADD CONSTRAINT rate_cards_pkey PRIMARY KEY (id);


--
-- Name: tax_rules tax_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_rules
    ADD CONSTRAINT tax_rules_pkey PRIMARY KEY (id);


--
-- Name: vehicles vehicles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_pkey PRIMARY KEY (id);


--
-- Name: bookings_branch_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_branch_status_idx ON public.bookings USING btree (branch_id, status);


--
-- Name: bookings_customer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_customer_idx ON public.bookings USING btree (customer_id, created_at DESC);


--
-- Name: bookings_vehicle_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_vehicle_time_idx ON public.bookings USING btree (vehicle_id, start_at, end_at);


--
-- Name: journal_lines_account_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX journal_lines_account_idx ON public.journal_lines USING btree (account_code);


--
-- Name: vehicles_branch_kind_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vehicles_branch_kind_idx ON public.vehicles USING btree (branch_id, kind) WHERE is_active;


--
-- Name: bookings bookings_queue_notice; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bookings_queue_notice AFTER INSERT OR UPDATE OF status ON public.bookings FOR EACH ROW EXECUTE FUNCTION private.queue_booking_notice();


--
-- Name: profiles protect_profile_role; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_profile_role BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION private.protect_profile_role();


--
-- Name: profiles sync_profile_areas; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_profile_areas AFTER INSERT OR UPDATE OF role ON public.profiles FOR EACH ROW EXECUTE FUNCTION private.sync_profile_areas();


--
-- Name: agreements agreements_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agreements
    ADD CONSTRAINT agreements_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id);


--
-- Name: bookings bookings_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id);


--
-- Name: bookings bookings_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.profiles(id);


--
-- Name: bookings bookings_tax_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_tax_rule_id_fkey FOREIGN KEY (tax_rule_id) REFERENCES public.tax_rules(id);


--
-- Name: bookings bookings_vehicle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);


--
-- Name: documents documents_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id);


--
-- Name: documents documents_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.profiles(id);


--
-- Name: financial_events financial_events_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_events
    ADD CONSTRAINT financial_events_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id);


--
-- Name: journal_entries journal_entries_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.financial_events(id);


--
-- Name: journal_lines journal_lines_account_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT journal_lines_account_code_fkey FOREIGN KEY (account_code) REFERENCES public.accounts(code);


--
-- Name: journal_lines journal_lines_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT journal_lines_entry_id_fkey FOREIGN KEY (entry_id) REFERENCES public.journal_entries(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id);


--
-- Name: payments payments_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id);


--
-- Name: profile_areas profile_areas_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profile_areas
    ADD CONSTRAINT profile_areas_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id);


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: vehicles vehicles_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id);


--
-- Name: vehicles vehicles_rate_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_rate_card_id_fkey FOREIGN KEY (rate_card_id) REFERENCES public.rate_cards(id);


--
-- Name: accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles admin update any profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "admin update any profile" ON public.profiles FOR UPDATE TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());


--
-- Name: agreements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.agreements ENABLE ROW LEVEL SECURITY;

--
-- Name: agreements backend reads agreements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "backend reads agreements" ON public.agreements FOR SELECT TO authenticated USING (private.has_area('backend'::text));


--
-- Name: documents backend reads documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "backend reads documents" ON public.documents FOR SELECT TO authenticated USING (private.has_area('backend'::text));


--
-- Name: notifications backend reads notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "backend reads notifications" ON public.notifications FOR SELECT TO authenticated USING (private.has_area('backend'::text));


--
-- Name: bookings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

--
-- Name: branches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;

--
-- Name: coupons; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

--
-- Name: vehicles desk reads vehicles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "desk reads vehicles" ON public.vehicles FOR SELECT TO authenticated USING ((private.has_area('operations'::text) OR private.has_area('gst'::text) OR private.has_area('reports'::text)));


--
-- Name: documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

--
-- Name: accounts finance reads accounts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "finance reads accounts" ON public.accounts FOR SELECT TO authenticated USING ((private.has_area('finance'::text) OR private.has_area('gst'::text) OR private.has_area('reports'::text)));


--
-- Name: financial_events finance reads events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "finance reads events" ON public.financial_events FOR SELECT TO authenticated USING ((private.has_area('finance'::text) OR private.has_area('gst'::text) OR private.has_area('reports'::text)));


--
-- Name: journal_entries finance reads journal entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "finance reads journal entries" ON public.journal_entries FOR SELECT TO authenticated USING ((private.has_area('finance'::text) OR private.has_area('gst'::text) OR private.has_area('reports'::text)));


--
-- Name: journal_lines finance reads journal lines; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "finance reads journal lines" ON public.journal_lines FOR SELECT TO authenticated USING ((private.has_area('finance'::text) OR private.has_area('gst'::text) OR private.has_area('reports'::text)));


--
-- Name: payments finance reads payments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "finance reads payments" ON public.payments FOR SELECT TO authenticated USING ((private.has_area('finance'::text) OR private.has_area('reports'::text) OR private.has_area('operations'::text)));


--
-- Name: financial_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.financial_events ENABLE ROW LEVEL SECURITY;

--
-- Name: bookings gst reads bookings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "gst reads bookings" ON public.bookings FOR SELECT TO authenticated USING (private.has_area('gst'::text));


--
-- Name: documents insert own documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "insert own documents" ON public.documents FOR INSERT TO authenticated WITH CHECK ((customer_id = auth.uid()));


--
-- Name: journal_entries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: journal_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.journal_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_cards operations reads rate cards; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "operations reads rate cards" ON public.rate_cards FOR SELECT TO authenticated USING (private.has_area('operations'::text));


--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: profile_areas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profile_areas ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_cards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_cards ENABLE ROW LEVEL SECURITY;

--
-- Name: accounts read accounts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read accounts" ON public.accounts FOR SELECT TO authenticated USING (private.is_admin());


--
-- Name: branches read branches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read branches" ON public.branches FOR SELECT TO authenticated, anon USING ((is_active OR private.is_admin()));


--
-- Name: coupons read coupons; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read coupons" ON public.coupons FOR SELECT TO authenticated USING ((is_active OR private.is_admin()));


--
-- Name: financial_events read finance events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read finance events" ON public.financial_events FOR SELECT TO authenticated USING (private.is_admin());


--
-- Name: journal_lines read journal lines; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read journal lines" ON public.journal_lines FOR SELECT TO authenticated USING (private.is_admin());


--
-- Name: journal_entries read journals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read journals" ON public.journal_entries FOR SELECT TO authenticated USING (private.is_admin());


--
-- Name: agreements read own agreements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read own agreements" ON public.agreements FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.bookings b
  WHERE ((b.id = agreements.booking_id) AND ((b.customer_id = auth.uid()) OR private.staff_can(b.branch_id))))));


--
-- Name: profile_areas read own area access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read own area access" ON public.profile_areas FOR SELECT TO authenticated USING (((profile_id = auth.uid()) OR private.is_admin()));


--
-- Name: documents read own documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read own documents" ON public.documents FOR SELECT TO authenticated USING (((customer_id = auth.uid()) OR private.is_admin()));


--
-- Name: profiles read own or admin profiles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read own or admin profiles" ON public.profiles FOR SELECT TO authenticated USING (((id = auth.uid()) OR private.is_admin()));


--
-- Name: bookings read own or staff bookings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read own or staff bookings" ON public.bookings FOR SELECT TO authenticated USING (((customer_id = auth.uid()) OR private.staff_can(branch_id)));


--
-- Name: payments read own payments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read own payments" ON public.payments FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.bookings b
  WHERE ((b.id = payments.booking_id) AND ((b.customer_id = auth.uid()) OR private.staff_can(b.branch_id))))));


--
-- Name: tax_rules read tax rules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read tax rules" ON public.tax_rules FOR SELECT TO authenticated, anon USING (true);


--
-- Name: vehicles read vehicles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read vehicles" ON public.vehicles FOR SELECT TO authenticated, anon USING ((is_active OR private.is_admin()));


--
-- Name: bookings reports read bookings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "reports read bookings" ON public.bookings FOR SELECT TO authenticated USING ((private.has_area('reports'::text) OR private.has_area('finance'::text)));


--
-- Name: tax_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tax_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles update own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "update own profile" ON public.profiles FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));


--
-- Name: vehicles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict yQtUW6QC2ndFRsffZe9dSQ4LjXztbDJ3L8qLCwR51g9ni8WmgczdmDivfdL7yQ1

