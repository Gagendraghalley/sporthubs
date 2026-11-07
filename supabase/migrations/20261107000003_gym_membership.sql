-- =====================================================================
-- Module 2: gym membership.
--   gym_plans, gym_subscriptions, gym_check_ins (all linked to a venue of
--   type 'gym'), their security rules, and the functions the app calls.
--
-- How a membership goes:
--   1. A member asks for a plan (gym_request_subscription): pending.
--   2. They pay the gym (mBoB, cash...). Its staff confirm the payment
--      (gym_activate_subscription): active, from today, or for a renewal
--      from the day after the current membership ends. The payment goes
--      into payments.
--   3. Staff check them in by QR code or member code (gym_check_in): only
--      with a membership at that gym covering today.
--   4. Every day (gym_daily_maintenance, pg_cron): memberships past their
--      end expire; members hear 3 days before the end; requests left for
--      30 days are cancelled.
--
-- The module starts turned off: admins turn it on (Admin -> Modules) once
-- it has been tried.
-- =====================================================================

insert into public.app_modules (key, name, is_enabled, sort_order)
values ('gym_membership', 'Gym membership', false, 20)
on conflict (key) do nothing;

insert into public.venue_types (key, module_key, name)
values ('gym', 'gym_membership', 'Gym')
on conflict (key) do nothing;


-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

create table if not exists public.gym_plans (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references public.venues (id) on delete cascade,
  name          text not null check (char_length(trim(name)) between 2 and 80),
  description   text check (char_length(description) <= 500),
  duration_days int not null check (duration_days between 1 and 1095),
  price         int not null check (price between 0 and 1000000), -- Ngultrum
  is_active     boolean not null default true, -- false: no longer sold
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists gym_plans_venue_idx on public.gym_plans (venue_id);

-- A request for a plan, then the membership it becomes. The plan's name,
-- length and price are copied, so later changes to the plan don't touch it.
create table if not exists public.gym_subscriptions (
  id               uuid primary key default gen_random_uuid(),
  venue_id         uuid not null references public.venues (id) on delete cascade,
  member_id        uuid not null constraint gym_subscriptions_member_id_fkey
                     references public.profiles (id) on delete cascade,
  plan_id          uuid references public.gym_plans (id) on delete set null,
  plan_name        text not null,
  duration_days    int not null check (duration_days between 1 and 1095),
  price            int not null check (price between 0 and 1000000),
  status           text not null default 'pending' check (status in ('pending', 'active', 'expired', 'cancelled')),
  start_date       date, -- Bhutan dates, both included
  end_date         date,
  requested_at     timestamptz not null default now(),
  activated_at     timestamptz,
  activated_by     uuid constraint gym_subscriptions_activated_by_fkey references public.profiles (id) on delete set null,
  cancelled_at     timestamptz,
  cancelled_by     uuid constraint gym_subscriptions_cancelled_by_fkey references public.profiles (id) on delete set null,
  payment_id       uuid references public.payments (id) on delete set null,
  reminder_sent_at timestamptz, -- 'ends in 3 days', sent once
  updated_at       timestamptz not null default now(),
  constraint gym_subscriptions_dates check ((status in ('active', 'expired')) = (start_date is not null and end_date is not null)),
  constraint gym_subscriptions_order check (end_date >= start_date)
);
-- One request waiting per member per gym.
create unique index if not exists gym_subscriptions_one_pending
  on public.gym_subscriptions (venue_id, member_id) where status = 'pending';
create index if not exists gym_subscriptions_member_idx on public.gym_subscriptions (member_id);
create index if not exists gym_subscriptions_venue_idx on public.gym_subscriptions (venue_id, status, end_date);

create table if not exists public.gym_check_ins (
  id              uuid primary key default gen_random_uuid(),
  venue_id        uuid not null references public.venues (id) on delete cascade,
  member_id       uuid not null constraint gym_check_ins_member_id_fkey references public.profiles (id) on delete cascade,
  subscription_id uuid references public.gym_subscriptions (id) on delete set null,
  checked_in_at   timestamptz not null default now(),
  recorded_by     uuid constraint gym_check_ins_recorded_by_fkey references public.profiles (id) on delete set null
);
create index if not exists gym_check_ins_venue_idx on public.gym_check_ins (venue_id, checked_in_at desc);
create index if not exists gym_check_ins_member_idx on public.gym_check_ins (member_id, checked_in_at desc);

drop trigger if exists gym_plans_updated_at on public.gym_plans;
create trigger gym_plans_updated_at before update on public.gym_plans
  for each row execute function public.set_updated_at();
drop trigger if exists gym_subscriptions_updated_at on public.gym_subscriptions;
create trigger gym_subscriptions_updated_at before update on public.gym_subscriptions
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------
-- 2. Who can do what
-- ---------------------------------------------------------------------
-- Members see only their own memberships and check-ins; a gym's staff see
-- only that gym's. Nobody writes directly: only the functions below.

alter table public.gym_plans         enable row level security;
alter table public.gym_subscriptions enable row level security;
alter table public.gym_check_ins     enable row level security;

revoke all on public.gym_plans, public.gym_subscriptions, public.gym_check_ins from anon, authenticated;
grant select on public.gym_plans to anon, authenticated;
grant select on public.gym_subscriptions, public.gym_check_ins to authenticated;

-- Plans on sale at verified gyms, for everyone; every plan for its staff.
drop policy if exists "gym_plans: on sale, for visitors" on public.gym_plans;
create policy "gym_plans: on sale, for visitors" on public.gym_plans for select to anon
  using (is_active and exists (select 1 from public.venues v where v.id = venue_id and v.verification_status = 'verified'));
drop policy if exists "gym_plans: on sale, staff and admins" on public.gym_plans;
create policy "gym_plans: on sale, staff and admins" on public.gym_plans for select to authenticated
  using (
    (is_active and exists (select 1 from public.venues v where v.id = venue_id and v.verification_status = 'verified'))
    or public.is_venue_staff(venue_id) or (select public.is_admin())
  );

drop policy if exists "gym_subscriptions: member, gym staff and admins" on public.gym_subscriptions;
create policy "gym_subscriptions: member, gym staff and admins" on public.gym_subscriptions for select to authenticated
  using (member_id = (select auth.uid()) or public.is_venue_staff(venue_id) or (select public.is_admin()));

drop policy if exists "gym_check_ins: member, gym staff and admins" on public.gym_check_ins;
create policy "gym_check_ins: member, gym staff and admins" on public.gym_check_ins for select to authenticated
  using (member_id = (select auth.uid()) or public.is_venue_staff(venue_id) or (select public.is_admin()));

-- A gym's staff see the names and phones of people with a membership (or
-- a request) there.
drop policy if exists "profiles: gym staff see their members" on public.profiles;
create policy "profiles: gym staff see their members" on public.profiles for select to authenticated
  using (exists (
    select 1 from public.gym_subscriptions s
    where s.member_id = profiles.id and public.is_venue_staff(s.venue_id)
  ));


-- ---------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------

-- Raises unless [venue] is a gym.
create or replace function public.gym_require_gym(venue uuid)
returns public.venues
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_venue public.venues;
begin
  select * into v_venue from public.venues v where v.id = venue;
  if not found or v_venue.type <> 'gym' then
    raise exception 'This gym isn''t on SportsHub.';
  end if;
  return v_venue;
end;
$$;

-- The member's paid membership at [venue] covering [day], if any.
create or replace function public.gym_current_subscription(venue uuid, member uuid, day date)
returns public.gym_subscriptions
language sql
stable
security definer
set search_path = ''
as $$
  select s.* from public.gym_subscriptions s
  where s.venue_id = venue and s.member_id = member and s.status = 'active'
    and s.start_date <= day and s.end_date >= day
  order by s.end_date desc
  limit 1;
$$;


-- ---------------------------------------------------------------------
-- 4. Functions the app calls
-- ---------------------------------------------------------------------

-- A new plan ([plan_id] null) or changes to one: the gym's owner or
-- managers (or admins). Returns the plan's id.
create or replace function public.gym_save_plan(venue_id uuid, plan_id uuid, name text, description text,
                                                duration_days int, price int, is_active boolean default true)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_save_plan.venue_id;
  p_plan uuid := gym_save_plan.plan_id;
  p_name text := trim(gym_save_plan.name);
  p_description text := nullif(trim(gym_save_plan.description), '');
  p_days int := gym_save_plan.duration_days;
  p_price int := gym_save_plan.price;
  p_active boolean := coalesce(gym_save_plan.is_active, true);
  v_id uuid;
begin
  perform public.gym_require_gym(p_venue);
  if not (public.is_venue_manager(p_venue) or public.is_admin()) then
    raise exception 'Only the gym''s owner and managers can change plans.';
  end if;
  if p_plan is null then
    insert into public.gym_plans (venue_id, name, description, duration_days, price, is_active)
    values (p_venue, p_name, p_description, p_days, p_price, p_active)
    returning gym_plans.id into v_id;
  else
    update public.gym_plans pl set
      name = p_name, description = p_description, duration_days = p_days, price = p_price, is_active = p_active
    where pl.id = p_plan and pl.venue_id = p_venue
    returning pl.id into v_id;
    if v_id is null then
      raise exception 'This plan no longer exists.';
    end if;
  end if;
  return v_id;
end;
$$;

-- The signed-in member asks for [plan_id]. Returns the request's id.
create or replace function public.gym_request_subscription(plan_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_plan uuid := gym_request_subscription.plan_id;
  v_user uuid := (select auth.uid());
  v_plan public.gym_plans;
  v_venue public.venues;
  v_member text;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Please sign in first.';
  end if;
  select * into v_plan from public.gym_plans pl where pl.id = p_plan;
  if not found or not v_plan.is_active then
    raise exception 'This plan is no longer offered.';
  end if;
  v_venue := public.gym_require_gym(v_plan.venue_id);
  if v_venue.verification_status <> 'verified' then
    raise exception 'This gym isn''t taking members on SportsHub yet.';
  end if;
  if not exists (select 1 from public.app_modules m where m.key = 'gym_membership' and m.is_enabled)
     and not public.is_admin() then
    raise exception 'Gym memberships aren''t open yet.';
  end if;
  if exists (select 1 from public.gym_subscriptions s
             where s.venue_id = v_venue.id and s.member_id = v_user and s.status = 'pending') then
    raise exception 'You already have a request waiting at this gym.';
  end if;

  insert into public.gym_subscriptions (venue_id, member_id, plan_id, plan_name, duration_days, price)
  values (v_venue.id, v_user, v_plan.id, v_plan.name, v_plan.duration_days, v_plan.price)
  returning gym_subscriptions.id into v_id;

  select coalesce(nullif(trim(p.full_name), ''), 'A member') into v_member from public.profiles p where p.id = v_user;
  perform public.notify_venue_staff(
    v_venue.id, 'gym_membership', 'New membership request',
    v_member || ' asked for ' || v_plan.name || ' (Nu. ' || v_plan.price || '). Confirm it once they have paid.',
    '/gyms/' || v_venue.id || '/manage/requests');
  return v_id;
end;
$$;

-- The gym's staff confirm the payment: the membership starts today, or for
-- a renewal the day after the member's current one ends. The payment is
-- recorded in payments (unless the plan is free).
create or replace function public.gym_activate_subscription(subscription_id uuid, amount int, method text,
                                                            reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_id uuid := gym_activate_subscription.subscription_id;
  p_amount int := gym_activate_subscription.amount;
  p_method text := gym_activate_subscription.method;
  p_reference text := nullif(trim(gym_activate_subscription.reference), '');
  v_today date := public.bhutan_today();
  v_sub public.gym_subscriptions;
  v_last_end date;
  v_start date;
  v_end date;
  v_payment uuid;
  v_gym text;
begin
  select * into v_sub from public.gym_subscriptions s where s.id = p_id for update;
  if not found then
    raise exception 'This request no longer exists.';
  end if;
  if not (public.is_venue_staff(v_sub.venue_id) or public.is_admin()) then
    raise exception 'Only the gym''s staff can confirm payments.';
  end if;
  if v_sub.status <> 'pending' then
    raise exception 'This request isn''t waiting any more (it is %).', v_sub.status;
  end if;
  if p_method is null or p_method not in ('mbob', 'cash', 'bank', 'other') then
    raise exception 'Choose how they paid.';
  end if;
  if p_amount is null or p_amount < 0 or p_amount > 1000000 then
    raise exception 'Enter the amount received.';
  end if;

  -- Serialises confirmations for the same member at the same gym.
  perform 1 from public.gym_subscriptions s
  where s.venue_id = v_sub.venue_id and s.member_id = v_sub.member_id and s.status = 'active'
  for update;
  select max(s.end_date) into v_last_end from public.gym_subscriptions s
  where s.venue_id = v_sub.venue_id and s.member_id = v_sub.member_id and s.status = 'active';
  v_start := greatest(v_today, coalesce(v_last_end + 1, v_today));
  v_end := v_start + v_sub.duration_days - 1;

  if p_amount > 0 then
    insert into public.payments (user_id, venue_id, module_key, reference_id, amount, method, reference, recorded_by)
    values (v_sub.member_id, v_sub.venue_id, 'gym_membership', v_sub.id, p_amount, p_method, p_reference,
            (select auth.uid()))
    returning payments.id into v_payment;
  end if;

  update public.gym_subscriptions s set
    status = 'active', start_date = v_start, end_date = v_end,
    activated_at = now(), activated_by = (select auth.uid()), payment_id = v_payment
  where s.id = v_sub.id;

  select v.name into v_gym from public.venues v where v.id = v_sub.venue_id;
  perform public.notify(
    v_sub.member_id, 'gym_membership',
    case when v_start > v_today then 'Your renewal at ' || v_gym || ' is confirmed'
         else 'Your membership at ' || v_gym || ' is active' end,
    v_sub.plan_name || ': ' || to_char(v_start, 'FMDD Mon YYYY') || ' to ' || to_char(v_end, 'FMDD Mon YYYY') || '.',
    '/my-gym');

  return jsonb_build_object('start_date', v_start, 'end_date', v_end, 'payment_id', v_payment);
end;
$$;

-- Calls off a request that is still waiting: the member, or the gym's staff.
create or replace function public.gym_cancel_subscription(subscription_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_id uuid := gym_cancel_subscription.subscription_id;
  v_user uuid := (select auth.uid());
  v_sub public.gym_subscriptions;
  v_gym text;
  v_member text;
begin
  select * into v_sub from public.gym_subscriptions s where s.id = p_id for update;
  if not found then
    raise exception 'This request no longer exists.';
  end if;
  if not (v_sub.member_id = v_user or public.is_venue_staff(v_sub.venue_id) or public.is_admin()) then
    raise exception 'You can''t cancel this request.';
  end if;
  if v_sub.status <> 'pending' then
    raise exception 'Only requests that are still waiting can be cancelled.';
  end if;
  update public.gym_subscriptions s set status = 'cancelled', cancelled_at = now(), cancelled_by = v_user
  where s.id = v_sub.id;

  select v.name into v_gym from public.venues v where v.id = v_sub.venue_id;
  if v_sub.member_id = v_user then
    select coalesce(nullif(trim(p.full_name), ''), 'A member') into v_member from public.profiles p where p.id = v_user;
    perform public.notify_venue_staff(v_sub.venue_id, 'gym_membership', 'Request cancelled',
                                      v_member || ' cancelled their request for ' || v_sub.plan_name || '.',
                                      '/gyms/' || v_sub.venue_id || '/manage/requests');
  else
    perform public.notify(v_sub.member_id, 'gym_membership', 'Your request at ' || v_gym || ' was cancelled',
                          'Contact the gym if you think this is a mistake.', '/gyms/' || v_sub.venue_id);
  end if;
end;
$$;

-- The gym's staff check a member in. Only with a membership at this gym
-- covering today; otherwise the error says why. Returns who it was and how
-- long they have left.
create or replace function public.gym_check_in(venue_id uuid, member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_check_in.venue_id;
  p_member uuid := gym_check_in.member_id;
  v_today date := public.bhutan_today();
  v_sub public.gym_subscriptions;
  v_profile public.profiles;
  v_other public.gym_subscriptions;
  v_earlier int;
begin
  perform public.gym_require_gym(p_venue);
  if not (public.is_venue_staff(p_venue) or public.is_admin()) then
    raise exception 'Only the gym''s staff can check members in.';
  end if;
  select * into v_profile from public.profiles p where p.id = p_member;
  if not found then
    raise exception 'That isn''t a SportsHub member.';
  end if;

  v_sub := public.gym_current_subscription(p_venue, p_member, v_today);
  if v_sub.id is null then
    -- Why not: the most telling of their memberships here.
    select * into v_other from public.gym_subscriptions s
    where s.venue_id = p_venue and s.member_id = p_member and s.status in ('active', 'pending', 'expired')
    order by case when s.status = 'active' then 0 when s.status = 'pending' then 1 else 2 end,
             s.end_date desc nulls last
    limit 1;
    if v_other.id is null then
      raise exception '% has no membership at this gym.', coalesce(nullif(trim(v_profile.full_name), ''), 'This member');
    elsif v_other.status = 'active' then
      raise exception 'Their membership starts on %.', to_char(v_other.start_date, 'FMDD Mon YYYY');
    elsif v_other.status = 'pending' then
      raise exception 'Their request for % is waiting: confirm their payment first.', v_other.plan_name;
    else
      raise exception 'Their membership ended on %.', to_char(v_other.end_date, 'FMDD Mon YYYY');
    end if;
  end if;

  select count(*) into v_earlier from public.gym_check_ins c
  where c.venue_id = p_venue and c.member_id = p_member
    and (c.checked_in_at at time zone 'Asia/Thimphu')::date = v_today;

  insert into public.gym_check_ins (venue_id, member_id, subscription_id, recorded_by)
  values (p_venue, p_member, v_sub.id, (select auth.uid()));

  return jsonb_build_object(
    'member_name', coalesce(nullif(trim(v_profile.full_name), ''), 'Member'),
    'member_code', v_profile.member_code,
    'plan_name', v_sub.plan_name,
    'end_date', v_sub.end_date,
    'days_left', v_sub.end_date - v_today + 1,
    'earlier_today', v_earlier
  );
end;
$$;

-- The same, by the member code typed at the front desk.
create or replace function public.gym_check_in_by_code(venue_id uuid, code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_code text := upper(regexp_replace(coalesce(gym_check_in_by_code.code, ''), '[\s-]', '', 'g'));
  v_member uuid;
begin
  if not (public.is_venue_staff(gym_check_in_by_code.venue_id) or public.is_admin()) then
    raise exception 'Only the gym''s staff can check members in.';
  end if;
  select p.id into v_member from public.profiles p where p.member_code = p_code;
  if v_member is null then
    raise exception 'No member has the code %.', p_code;
  end if;
  return public.gym_check_in(gym_check_in_by_code.venue_id, v_member);
end;
$$;

-- A gym's numbers for its Manage page. Income only for owners and managers.
create or replace function public.gym_dashboard(venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_dashboard.venue_id;
  v_today date := public.bhutan_today();
  -- The 1st of this month, midnight in Bhutan.
  v_month_start timestamptz := date_trunc('month', v_today::timestamp) at time zone 'Asia/Thimphu';
begin
  if not (public.is_venue_staff(p_venue) or public.is_admin()) then
    raise exception 'Only the gym''s staff can see this.';
  end if;
  return jsonb_build_object(
    'pending', (select count(*) from public.gym_subscriptions s where s.venue_id = p_venue and s.status = 'pending'),
    'active', (select count(distinct s.member_id) from public.gym_subscriptions s
               where s.venue_id = p_venue and s.status = 'active' and s.start_date <= v_today and s.end_date >= v_today),
    'expiring_soon', (select count(distinct s.member_id) from public.gym_subscriptions s
                      where s.venue_id = p_venue and s.status = 'active'
                        and s.start_date <= v_today and s.end_date between v_today and v_today + 6
                        and not exists (select 1 from public.gym_subscriptions r
                                        where r.venue_id = s.venue_id and r.member_id = s.member_id
                                          and r.status = 'active' and r.start_date > s.end_date)),
    'check_ins_today', (select count(*) from public.gym_check_ins c
                        where c.venue_id = p_venue and (c.checked_in_at at time zone 'Asia/Thimphu')::date = v_today),
    'income_this_month', case when public.is_venue_manager(p_venue) or public.is_admin() then
                           (select coalesce(sum(p.amount), 0) from public.payments p
                            where p.venue_id = p_venue and p.module_key = 'gym_membership'
                              and p.status = 'completed' and p.created_at >= v_month_start)
                         end
  );
end;
$$;


-- ---------------------------------------------------------------------
-- 5. Every day: expiries, reminders, old requests
-- ---------------------------------------------------------------------

create or replace function public.gym_daily_maintenance()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.bhutan_today();
  v_expired int := 0;
  v_reminded int := 0;
  v_cancelled int := 0;
  r record;
begin
  -- Memberships past their last day. Members hear unless they have renewed.
  for r in
    update public.gym_subscriptions s set status = 'expired'
    where s.status = 'active' and s.end_date < v_today
    returning s.id, s.venue_id, s.member_id, s.plan_name, s.end_date
  loop
    v_expired := v_expired + 1;
    if not exists (select 1 from public.gym_subscriptions n
                   where n.venue_id = r.venue_id and n.member_id = r.member_id
                     and n.status = 'active' and n.end_date >= v_today) then
      perform public.notify(r.member_id, 'gym_membership',
        'Your membership at ' || (select v.name from public.venues v where v.id = r.venue_id) || ' has ended',
        r.plan_name || ' ended on ' || to_char(r.end_date, 'FMDD Mon YYYY') || '. Renew it from the gym''s page.',
        '/gyms/' || r.venue_id);
    end if;
  end loop;

  -- 3 days before the end, once, unless they have renewed.
  for r in
    update public.gym_subscriptions s set reminder_sent_at = now()
    where s.status = 'active' and s.end_date = v_today + 3 and s.reminder_sent_at is null
      and not exists (select 1 from public.gym_subscriptions n
                      where n.venue_id = s.venue_id and n.member_id = s.member_id
                        and n.status = 'active' and n.start_date > s.end_date)
    returning s.venue_id, s.member_id, s.plan_name, s.end_date
  loop
    v_reminded := v_reminded + 1;
    perform public.notify(r.member_id, 'gym_membership',
      'Your membership ends in 3 days',
      (select v.name from public.venues v where v.id = r.venue_id) || ': ' || r.plan_name || ' ends on '
        || to_char(r.end_date, 'FMDD Mon YYYY') || '. Renew it to keep going.',
      '/gyms/' || r.venue_id);
  end loop;

  -- Requests nobody confirmed in 30 days.
  for r in
    update public.gym_subscriptions s set status = 'cancelled', cancelled_at = now()
    where s.status = 'pending' and s.requested_at < now() - interval '30 days'
    returning s.venue_id, s.member_id, s.plan_name
  loop
    v_cancelled := v_cancelled + 1;
    perform public.notify(r.member_id, 'gym_membership', 'Your request was closed',
      'Your request for ' || r.plan_name || ' waited 30 days without a payment. Ask again any time.',
      '/gyms/' || r.venue_id);
  end loop;

  return jsonb_build_object('expired', v_expired, 'reminded', v_reminded, 'cancelled', v_cancelled);
end;
$$;

-- Daily at 00:05 Bhutan time (18:05 UTC) with pg_cron, where it's
-- available (it is on Supabase).
-- If it can't be set up here, the rest still applies: turn on pg_cron
-- (Database -> Extensions) and run this block again (README).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('gym-daily-maintenance', '5 18 * * *', 'select public.gym_daily_maintenance()');
  else
    raise notice 'pg_cron is not available: run "select public.gym_daily_maintenance()" once a day.';
  end if;
exception when others then
  raise warning 'The daily gym job was not scheduled (%). See the README, "Daily job".', sqlerrm;
end;
$$;


-- ---------------------------------------------------------------------
-- 6. Who can call which function
-- ---------------------------------------------------------------------

revoke execute on function public.gym_require_gym(uuid), public.gym_current_subscription(uuid, uuid, date),
  public.gym_daily_maintenance(), public.gym_save_plan(uuid, uuid, text, text, int, int, boolean),
  public.gym_request_subscription(uuid), public.gym_activate_subscription(uuid, int, text, text),
  public.gym_cancel_subscription(uuid), public.gym_check_in(uuid, uuid), public.gym_check_in_by_code(uuid, text),
  public.gym_dashboard(uuid)
  from public, anon, authenticated;

grant execute on function public.gym_save_plan(uuid, uuid, text, text, int, int, boolean),
  public.gym_request_subscription(uuid), public.gym_activate_subscription(uuid, int, text, text),
  public.gym_cancel_subscription(uuid), public.gym_check_in(uuid, uuid), public.gym_check_in_by_code(uuid, text),
  public.gym_dashboard(uuid)
  to authenticated;
