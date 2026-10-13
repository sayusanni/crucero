-- Desk actions for operations, finance, and GST, plus the message queue the backend desk reads.

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references public.bookings (id),
  channel text not null check (channel in ('sms', 'whatsapp', 'email')),
  recipient text not null,
  template text not null,
  status text not null default 'queued' check (status in ('queued', 'sent')),
  created_at timestamptz not null default now()
);

alter table public.notifications enable row level security;

drop policy if exists "backend reads notifications" on public.notifications;
create policy "backend reads notifications" on public.notifications
  for select to authenticated
  using (private.has_area('backend'));

grant select on public.notifications to authenticated;

drop policy if exists "desk reads vehicles" on public.vehicles;
create policy "desk reads vehicles" on public.vehicles
  for select to authenticated
  using (
    private.has_area('operations')
    or private.has_area('gst')
    or private.has_area('reports')
  );

drop policy if exists "update own document files" on storage.objects;
create policy "update own document files" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'customer-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'customer-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create or replace function private.queue_booking_notice()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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

insert into public.notifications (booking_id, channel, recipient, template)
select b.id, ch.channel, coalesce(nullif(p.email, ''), p.full_name, 'customer'),
  case b.status
    when 'captured' then 'booking_confirmed'
    when 'out' then 'vehicle_picked_up'
    else 'vehicle_returned'
  end
from public.bookings b
join public.profiles p on p.id = b.customer_id
cross join (values ('sms'), ('whatsapp')) as ch(channel)
where b.status in ('captured', 'out', 'returned')
  and not exists (
    select 1 from public.notifications n
    where n.booking_id = b.id and n.channel = ch.channel and n.template = case b.status
      when 'captured' then 'booking_confirmed'
      when 'out' then 'vehicle_picked_up'
      else 'vehicle_returned'
    end
  );

drop trigger if exists bookings_queue_notice on public.bookings;
create trigger bookings_queue_notice
  after insert or update of status on public.bookings
  for each row
  execute function private.queue_booking_notice();

create or replace function private.set_vehicle_status(p_vehicle uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
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

create or replace function private.release_deposit(p_booking uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
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

create or replace function private.add_tax_rule(
  p_name text,
  p_sac text,
  p_rate numeric,
  p_from date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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

create or replace function public.set_vehicle_status(p_vehicle uuid, p_status text)
returns void language sql security invoker set search_path = public, private
as $$ select private.set_vehicle_status(p_vehicle, p_status); $$;

create or replace function public.release_deposit(p_booking uuid)
returns void language sql security invoker set search_path = public, private
as $$ select private.release_deposit(p_booking); $$;

create or replace function public.add_tax_rule(p_name text, p_sac text, p_rate numeric, p_from date)
returns uuid language sql security invoker set search_path = public, private
as $$ select private.add_tax_rule(p_name, p_sac, p_rate, p_from); $$;

revoke all on function public.set_vehicle_status(uuid, text) from public;
revoke all on function public.release_deposit(uuid) from public;
revoke all on function public.add_tax_rule(text, text, numeric, date) from public;

grant execute on function public.set_vehicle_status(uuid, text) to authenticated;
grant execute on function public.release_deposit(uuid) to authenticated;
grant execute on function public.add_tax_rule(text, text, numeric, date) to authenticated;

grant execute on function private.set_vehicle_status(uuid, text) to authenticated;
grant execute on function private.release_deposit(uuid) to authenticated;
grant execute on function private.add_tax_rule(text, text, numeric, date) to authenticated;

drop policy if exists "gst reads bookings" on public.bookings;
create policy "gst reads bookings" on public.bookings
  for select to authenticated
  using (private.has_area('gst'));
