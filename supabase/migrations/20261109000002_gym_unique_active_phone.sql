-- A phone number identifies one registered member per gym while that
-- member has a paid package that has not expired. The advisory lock makes
-- the check safe when two staff members register at the same time.

create or replace function public.gym_register_member(venue_id uuid, details jsonb, plan_id uuid default null,
                                                      months int default null, amount int default 0,
                                                      method text default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_register_member.venue_id;
  m public.gym_members;
  v_existing_name text;
  v_existing_code text;
  v_existing_until date;
  v_membership jsonb;
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'gym.register') then
    raise exception 'Only the gym''s staff who register members can do this.';
  end if;

  m := public.gym_member_from_details(details);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_venue::text || ':' || m.phone, 0)
  );

  select c.full_name, c.member_code, c.expires_on
    into v_existing_name, v_existing_code, v_existing_until
  from (
    select g.full_name, g.code as member_code, max(s.end_date) as expires_on
    from public.gym_members g
    join public.gym_subscriptions s on s.gym_member_id = g.id
    where g.venue_id = p_venue and g.phone = m.phone
      and s.status = 'active' and s.end_date >= public.bhutan_today()
    group by g.id, g.full_name, g.code
    union all
    select coalesce(nullif(trim(p.full_name), ''), 'Member'), null::text, max(s.end_date)
    from public.profiles p
    join public.gym_subscriptions s on s.member_id = p.id
    where s.venue_id = p_venue and p.phone = m.phone
      and s.status = 'active' and s.end_date >= public.bhutan_today()
    group by p.id, p.full_name
  ) c
  order by c.expires_on desc
  limit 1;
  if v_existing_until is not null then
    raise exception 'This phone number belongs to % (%) until %. Register it again after the package expires.',
      v_existing_name, coalesce(v_existing_code, 'account member'), to_char(v_existing_until, 'FMDD Mon YYYY');
  end if;

  m.id := gen_random_uuid();
  m.venue_id := p_venue;
  m.code := public.gym_new_member_code();
  m.qr_token := public.gym_new_qr_token();
  m.created_by := (select auth.uid());
  m.created_at := now();
  m.updated_at := now();
  insert into public.gym_members select m.*;

  if gym_register_member.plan_id is not null then
    v_membership := public.gym_add_membership(m, gym_register_member.plan_id, gym_register_member.months, m.joined_on,
                                              coalesce(gym_register_member.amount, 0), gym_register_member.method,
                                              gym_register_member.reference);
  end if;

  return jsonb_build_object('gym_member_id', m.id, 'code', m.code, 'qr_token', m.qr_token, 'membership', v_membership);
end;
$$;

create or replace function public.gym_update_member(gym_member_id uuid, details jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  m public.gym_members;
  v_existing_name text;
  v_existing_code text;
  v_existing_until date;
begin
  select * into v_member from public.gym_members g where g.id = gym_update_member.gym_member_id for update;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.has_venue_permission(v_member.venue_id, 'gym.register') then
    raise exception 'Only the gym''s staff who register members can change their details.';
  end if;

  m := public.gym_member_from_details(details);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_member.venue_id::text || ':' || m.phone, 0)
  );
  select c.full_name, c.member_code, c.expires_on
    into v_existing_name, v_existing_code, v_existing_until
  from (
    select g.full_name, g.code as member_code, max(s.end_date) as expires_on
    from public.gym_members g
    join public.gym_subscriptions s on s.gym_member_id = g.id
    where g.venue_id = v_member.venue_id and g.phone = m.phone and g.id <> v_member.id
      and s.status = 'active' and s.end_date >= public.bhutan_today()
    group by g.id, g.full_name, g.code
    union all
    select coalesce(nullif(trim(p.full_name), ''), 'Member'), null::text, max(s.end_date)
    from public.profiles p
    join public.gym_subscriptions s on s.member_id = p.id
    where s.venue_id = v_member.venue_id and p.phone = m.phone
      and s.status = 'active' and s.end_date >= public.bhutan_today()
    group by p.id, p.full_name
  ) c
  order by c.expires_on desc
  limit 1;
  if v_existing_until is not null then
    raise exception 'This phone number belongs to % (%) until %. It cannot be assigned to another member before then.',
      v_existing_name, coalesce(v_existing_code, 'account member'), to_char(v_existing_until, 'FMDD Mon YYYY');
  end if;

  update public.gym_members g set
    full_name = m.full_name, phone = m.phone, email = m.email, date_of_birth = m.date_of_birth,
    blood_group = m.blood_group, occupation = m.occupation, dzongkhag_id = m.dzongkhag_id, gewog_id = m.gewog_id,
    village_id = m.village_id, emergency_contact_name = m.emergency_contact_name,
    emergency_contact_phone = m.emergency_contact_phone, medical_notes = m.medical_notes, joined_on = m.joined_on
  where g.id = v_member.id;
end;
$$;

-- If older data contains reused numbers, check in the member with the
-- current package first, then the next unexpired package, then the newest
-- historical record.
create or replace function public.gym_check_in_by_phone(venue_id uuid, phone text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_check_in_by_phone.venue_id;
  p_phone text := regexp_replace(coalesce(gym_check_in_by_phone.phone, ''), '[\s()-]', '', 'g');
  v_registered public.gym_members;
  v_member uuid;
begin
  if not public.has_venue_permission(p_venue, 'gym.check_in') then
    raise exception 'Only the gym''s staff can check members in.';
  end if;

  if p_phone ~ '^[0-9]{8}$' then
    p_phone := '+975' || p_phone;
  elsif p_phone ~ '^[0-9]{8,15}$' then
    p_phone := '+' || p_phone;
  end if;
  if p_phone !~ '^\+[0-9]{8,15}$' then
    raise exception 'Enter a valid phone number, e.g. 17123456.';
  end if;

  select g.* into v_registered
  from public.gym_members g
  where g.venue_id = p_venue and g.phone = p_phone
  order by
    case
      when exists (
        select 1 from public.gym_subscriptions s
        where s.gym_member_id = g.id and s.status = 'active'
          and s.start_date <= public.bhutan_today() and s.end_date >= public.bhutan_today()
      ) then 0
      when exists (
        select 1 from public.gym_subscriptions s
        where s.gym_member_id = g.id and s.status = 'active'
          and s.end_date >= public.bhutan_today()
      ) then 1
      else 2
    end,
    g.created_at desc
  limit 1;
  if found then
    return public.gym_check_in_registered(p_venue, v_registered.id);
  end if;

  select p.id into v_member
  from public.profiles p
  where p.phone = p_phone
    and exists (
      select 1 from public.gym_subscriptions s
      where s.venue_id = p_venue and s.member_id = p.id
    )
  order by p.id
  limit 1;
  if v_member is null then
    raise exception 'No member with that phone number is registered at this gym.';
  end if;
  return public.gym_check_in(p_venue, v_member);
end;
$$;

revoke execute on function public.gym_check_in_by_phone(uuid, text) from public, anon, authenticated;
grant execute on function public.gym_check_in_by_phone(uuid, text) to authenticated;
