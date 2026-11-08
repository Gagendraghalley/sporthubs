-- =====================================================================
-- Gym membership: permissions instead of fixed roles.
--   gym.members   see members, their memberships and check-ins
--   gym.payments  confirm payments (activating memberships), cancel requests
--   gym.check_in  check members in
--   gym.plans     plans and prices
-- (Income is the core's 'venue.income'.)
--
-- The defaults keep today's behaviour: Owner and Manager everything, Front
-- desk members, payments and check-in, and the new Trainer members and
-- check-in. Admins change them under Admin -> Roles and permissions.
--
-- The functions are as in 20261107000003_gym_membership.sql; only who may
-- call them changes.
-- =====================================================================

do $$
declare
  v_new_permissions text[];
begin
  with saved as (
    insert into public.permissions (key, scope, module_key, name, description, sort_order) values
      ('gym.members',  'venue', 'gym_membership', 'Members',          'See members, their memberships and check-ins', 110),
      ('gym.payments', 'venue', 'gym_membership', 'Payments',         'Confirm payments to start memberships, and cancel requests', 120),
      ('gym.check_in', 'venue', 'gym_membership', 'Check-in',         'Check members in by QR code or member code', 130),
      ('gym.plans',    'venue', 'gym_membership', 'Plans and prices', 'Add and change the plans members can buy', 140)
    on conflict (key) do update
      set scope = excluded.scope, module_key = excluded.module_key, name = excluded.name,
          description = excluded.description, sort_order = excluded.sort_order
    returning key, (xmax = 0) as inserted
  )
  select coalesce(array_agg(key) filter (where inserted), '{}') into v_new_permissions from saved;

  insert into public.role_permissions (role_id, permission_key)
  select r.id, d.permission_key
  from (values
    ('owner', 'gym.members'), ('owner', 'gym.payments'), ('owner', 'gym.check_in'), ('owner', 'gym.plans'),
    ('manager', 'gym.members'), ('manager', 'gym.payments'), ('manager', 'gym.check_in'), ('manager', 'gym.plans'),
    ('staff', 'gym.members'), ('staff', 'gym.payments'), ('staff', 'gym.check_in'),
    ('trainer', 'gym.members'), ('trainer', 'gym.check_in')
  ) d (role_key, permission_key)
  join public.roles r on r.key = d.role_key
  where d.permission_key = any (v_new_permissions)
  on conflict do nothing;
end;
$$;


-- ---------------------------------------------------------------------
-- Who can read what
-- ---------------------------------------------------------------------

drop policy if exists "gym_subscriptions: member, gym staff and admins" on public.gym_subscriptions;
drop policy if exists "gym_subscriptions: member, and who sees members" on public.gym_subscriptions;
create policy "gym_subscriptions: member, and who sees members" on public.gym_subscriptions for select to authenticated
  using (member_id = (select auth.uid()) or public.has_venue_permission(venue_id, 'gym.members'));

drop policy if exists "gym_check_ins: member, gym staff and admins" on public.gym_check_ins;
drop policy if exists "gym_check_ins: member, and who sees members" on public.gym_check_ins;
create policy "gym_check_ins: member, and who sees members" on public.gym_check_ins for select to authenticated
  using (member_id = (select auth.uid()) or public.has_venue_permission(venue_id, 'gym.members'));

drop policy if exists "profiles: gym staff see their members" on public.profiles;
create policy "profiles: gym staff see their members" on public.profiles for select to authenticated
  using (exists (
    select 1 from public.gym_subscriptions s
    where s.member_id = profiles.id and public.has_venue_permission(s.venue_id, 'gym.members')
  ));


-- ---------------------------------------------------------------------
-- Functions the app calls
-- ---------------------------------------------------------------------

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
  if not public.has_venue_permission(p_venue, 'gym.plans') then
    raise exception 'Only people who manage plans can change them.';
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
  if not public.has_venue_permission(v_sub.venue_id, 'gym.payments') then
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
  if not (v_sub.member_id = v_user or public.has_venue_permission(v_sub.venue_id, 'gym.payments')) then
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
  if not public.has_venue_permission(p_venue, 'gym.check_in') then
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
  if not public.has_venue_permission(gym_check_in_by_code.venue_id, 'gym.check_in') then
    raise exception 'Only the gym''s staff can check members in.';
  end if;
  select p.id into v_member from public.profiles p where p.member_code = p_code;
  if v_member is null then
    raise exception 'No member has the code %.', p_code;
  end if;
  return public.gym_check_in(gym_check_in_by_code.venue_id, v_member);
end;
$$;

-- Everyone who works at the gym sees its numbers; income only those with
-- 'venue.income'.
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
    'income_this_month', case when public.has_venue_permission(p_venue, 'venue.income') then
                           (select coalesce(sum(p.amount), 0) from public.payments p
                            where p.venue_id = p_venue and p.module_key = 'gym_membership'
                              and p.status = 'completed' and p.created_at >= v_month_start)
                         end
  );
end;
$$;

revoke execute on function public.gym_save_plan(uuid, uuid, text, text, int, int, boolean),
  public.gym_activate_subscription(uuid, int, text, text), public.gym_cancel_subscription(uuid),
  public.gym_check_in(uuid, uuid), public.gym_check_in_by_code(uuid, text), public.gym_dashboard(uuid)
  from public, anon;
grant execute on function public.gym_save_plan(uuid, uuid, text, text, int, int, boolean),
  public.gym_activate_subscription(uuid, int, text, text), public.gym_cancel_subscription(uuid),
  public.gym_check_in(uuid, uuid), public.gym_check_in_by_code(uuid, text), public.gym_dashboard(uuid)
  to authenticated;
