-- =====================================================================
-- Gym membership: a package expires on the same date, months later.
--
-- The client's example: joining on 8 November 2026 for 3 months expires on
-- 8 February 2027, and they can still come in that day. A renewal starts
-- on that expiry date, so the dates don't drift: 8 Feb, 8 May, 8 Aug.
-- (Before, a package ended the day before, 7 February, and a renewal
-- started the day after its end.)
--
-- A package runs 1 to 24 months, the registration form's longest. 36
-- months over a leap day went past gym_subscriptions.duration_days' limit
-- of 1095 days.
--
-- Packages already sold keep their dates. Account members' memberships
-- (gym_activate_subscription, by the plan's days) are unchanged.
-- =====================================================================


-- A membership of [plan] for [months] months from [start] for [member],
-- paid [amount] (recorded in payments unless 0). Its last day is the same
-- date [months] months later. Ended already (an old member entered late)
-- if that was before today.
create or replace function public.gym_add_membership(member public.gym_members, plan_id uuid, months int, start date,
                                                     amount int, method text, reference text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_member public.gym_members := gym_add_membership.member;
  p_months int := gym_add_membership.months;
  p_start date := gym_add_membership.start;
  p_amount int := gym_add_membership.amount;
  p_method text := gym_add_membership.method;
  p_reference text := nullif(trim(gym_add_membership.reference), '');
  v_plan public.gym_plans;
  v_end date;
  v_status text;
  v_sub uuid;
  v_payment uuid;
begin
  if not public.has_venue_permission(p_member.venue_id, 'gym.payments') then
    raise exception 'Your role here can register members but not sell them a package.';
  end if;
  select * into v_plan from public.gym_plans pl where pl.id = gym_add_membership.plan_id and pl.venue_id = p_member.venue_id;
  if not found or not v_plan.is_active then
    raise exception 'Choose one of the gym''s packages.';
  end if;
  if p_months is null or p_months not between 1 and 24 then
    raise exception 'Choose how many months (1 to 24).';
  end if;
  if p_amount is null or p_amount < 0 or p_amount > 1000000 then
    raise exception 'Enter the amount received.';
  end if;
  if p_amount > 0 and (p_method is null or p_method not in ('mbob', 'cash', 'bank', 'other')) then
    raise exception 'Choose how they paid.';
  end if;
  v_end := (p_start + make_interval(months => p_months))::date;
  v_status := case when v_end < public.bhutan_today() then 'expired' else 'active' end;

  insert into public.gym_subscriptions (venue_id, gym_member_id, plan_id, plan_name, duration_days, price, status,
                                        start_date, end_date, activated_at, activated_by)
  values (p_member.venue_id, p_member.id, v_plan.id, v_plan.name, v_end - p_start + 1, p_amount, v_status,
          p_start, v_end, now(), (select auth.uid()))
  returning gym_subscriptions.id into v_sub;

  if p_amount > 0 then
    insert into public.payments (venue_id, module_key, reference_id, amount, method, reference, recorded_by, payer_name)
    values (p_member.venue_id, 'gym_membership', v_sub, p_amount, p_method, p_reference, (select auth.uid()),
            p_member.full_name)
    returning payments.id into v_payment;
    update public.gym_subscriptions s set payment_id = v_payment where s.id = v_sub;
  end if;

  return jsonb_build_object('subscription_id', v_sub, 'start_date', p_start, 'end_date', v_end, 'status', v_status,
                            'payment_id', v_payment);
end;
$$;

-- Sells a registered member another package: from the day their current
-- one expires (both cover that day), or today if it has ended.
create or replace function public.gym_renew_member(gym_member_id uuid, plan_id uuid, months int, amount int,
                                                   method text default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  v_last_end date;
  v_today date := public.bhutan_today();
begin
  select * into v_member from public.gym_members g where g.id = gym_renew_member.gym_member_id;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  -- Serialises renewals of the same member.
  perform 1 from public.gym_members g where g.id = v_member.id for update;
  select max(s.end_date) into v_last_end from public.gym_subscriptions s
  where s.gym_member_id = v_member.id and s.status = 'active';
  return public.gym_add_membership(v_member, gym_renew_member.plan_id, gym_renew_member.months,
                                   greatest(v_today, coalesce(v_last_end, v_today)), gym_renew_member.amount,
                                   gym_renew_member.method, gym_renew_member.reference);
end;
$$;

-- A gym's numbers. Ending soon: a membership ending in the next 7 days with
-- no paid one ending after it (a renewal now starts on its last day).
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
    'active', (select count(distinct coalesce(s.member_id, s.gym_member_id)) from public.gym_subscriptions s
               where s.venue_id = p_venue and s.status = 'active' and s.start_date <= v_today and s.end_date >= v_today),
    'expiring_soon', (select count(distinct coalesce(s.member_id, s.gym_member_id)) from public.gym_subscriptions s
                      where s.venue_id = p_venue and s.status = 'active'
                        and s.start_date <= v_today and s.end_date between v_today and v_today + 6
                        and not exists (select 1 from public.gym_subscriptions r
                                        where r.venue_id = s.venue_id
                                          and coalesce(r.member_id, r.gym_member_id) = coalesce(s.member_id, s.gym_member_id)
                                          and r.status = 'active' and r.end_date > s.end_date)),
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

-- create or replace keeps each function's grants; said again so this file
-- stands on its own.
revoke execute on function public.gym_add_membership(public.gym_members, uuid, int, date, int, text, text),
  public.gym_renew_member(uuid, uuid, int, int, text, text), public.gym_dashboard(uuid)
  from public, anon, authenticated;
grant execute on function public.gym_renew_member(uuid, uuid, int, int, text, text), public.gym_dashboard(uuid)
  to authenticated;
