-- Test accounts: one for every role, to try SportsHub as each kind of user.
--
-- They sign in with their email and a password (Sign in, then the password
-- box), so no email has to arrive.
--
-- How: Supabase -> SQL Editor -> New query, paste this whole file, put a
-- password of your own on the PASSWORD line below (8 or more characters;
-- every test account gets it), and Run. The table at the end lists the
-- accounts. Don't save the password in this file.
--
-- Safe to run again: it makes nothing twice, and puts the passwords and
-- roles back (and turns a test account back on if it was turned off).
--
-- What it makes, at "SportsHub Test Gym" (made here, verified):
--   superadmin@example.com  Super admin: can do everything
--   admin@example.com       Administrator: users, roles, master data, venues, modules
--   owner@example.com       Owner of the test gym
--   manager@example.com     Manager
--   frontdesk@example.com   Front desk: registers members, takes payments, checks in
--   trainer@example.com     Trainer: sees members, checks them in
--   member@example.com      A member with an account: 3 months of Monthly at the test gym
-- and <role key>@example.com for each role made under Admin -> Roles and
-- permissions (gym_cleaner: gym.cleaner@example.com). example.com is kept for
-- examples, so no real person has one of these addresses: every
-- @example.com account is a test account.
--
-- While gym membership is off (Admin -> Modules), only the super admin and
-- the administrator see the gym's pages. Turn it on to try the gym's roles.
--
-- These are real accounts on the project this runs on, a super admin among
-- them. Remove them before launch: supabase/test_users_remove.sql.

do $$
declare
    v_password constant text := 'SportsHub2026';  -- <- your password here
  v_gym constant uuid := '7e570000-0000-4000-8000-000000000001';
  v_hash text;
  v_account record;
  v_email text;
  v_user uuid;
  v_start date;
  v_end date;
begin
  if v_password = 'PASSWORD' or char_length(v_password) < 8 then
    raise exception 'Put a password of your own (8 or more characters) on the PASSWORD line first.';
  end if;
  -- How Supabase Auth keeps passwords (bcrypt).
  v_hash := extensions.crypt(v_password, extensions.gen_salt('bf'));

  insert into public.venues (id, type, name, description, dzongkhag, town, address, phone, payment_info,
                             verification_status, verified_at)
  values (v_gym, 'gym', 'SportsHub Test Gym', 'For trying SportsHub out. Not a real gym.',
          'Thimphu', 'Thimphu', 'Test address', '+97517000000', 'Cash at the front desk.',
          'verified', now())
  on conflict (id) do nothing;

  insert into public.gym_plans (venue_id, name, description, duration_days, price, sort_order)
  select v_gym, p.name, p.description, 30, p.price, p.sort_order
  from (values
    ('Monthly', 'All equipment', 1500, 1),
    ('Monthly with a trainer', 'All equipment and a personal trainer', 2500, 2)
  ) as p (name, description, price, sort_order)
  where not exists (select 1 from public.gym_plans pl where pl.venue_id = v_gym);

  for v_account in
    select a.name, a.full_name, a.kind, a.role_key
    from (values
      ('superadmin', 'Test Super Admin',   'super',    null),
      ('admin',      'Test Administrator', 'platform', 'platform_admin'),
      ('owner',      'Test Gym Owner',     'venue',    'owner'),
      ('manager',    'Test Gym Manager',   'venue',    'manager'),
      ('frontdesk',  'Test Front Desk',    'venue',    'staff'),
      ('trainer',    'Test Trainer',       'venue',    'trainer'),
      ('member',     'Test Member',        'member',   null)
    ) as a (name, full_name, kind, role_key)
    union all
    -- Roles made under Admin -> Roles and permissions.
    select replace(r.key, '_', '.'), left('Test ' || r.name, 100), r.scope, r.key
    from public.roles r
    where r.is_active and r.key not in ('platform_admin', 'owner', 'manager', 'staff', 'trainer')
  loop
    v_email := v_account.name || '@example.com';

    -- The account: made, or its password put back.
    select u.id into v_user from auth.users u where lower(u.email) = v_email;
    if v_user is null then
      v_user := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                              raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                              confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated', v_email, v_hash, now(),
              '{"provider": "email", "providers": ["email"]}', jsonb_build_object('full_name', v_account.full_name),
              now(), now(), '', '', '', '');
    else
      update auth.users u
      set encrypted_password = v_hash, email_confirmed_at = coalesce(u.email_confirmed_at, now()),
          banned_until = null, updated_at = now()
      where u.id = v_user;
    end if;
    insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
    select v_user::text, v_user, jsonb_build_object('sub', v_user::text, 'email', v_email, 'email_verified', true),
           'email', now(), now()
    where not exists (select 1 from auth.identities i where i.user_id = v_user and i.provider = 'email');

    -- The profile (the sign-up trigger made it), on, with only this role.
    insert into public.profiles (id, full_name, email)
    values (v_user, v_account.full_name, v_email)
    on conflict (id) do nothing;
    update public.profiles p
    set full_name = v_account.full_name, is_active = true,
        role = case when v_account.kind = 'super' then 'admin' else 'user' end
    where p.id = v_user;
    delete from public.user_roles ur where ur.user_id = v_user;
    delete from public.venue_staff s where s.user_id = v_user and s.venue_id = v_gym;

    if v_account.kind = 'platform' then
      insert into public.user_roles (user_id, role_id)
      select v_user, r.id from public.roles r where r.key = v_account.role_key;
    elsif v_account.kind = 'venue' then
      insert into public.venue_staff (venue_id, user_id, role) values (v_gym, v_user, v_account.role_key);
    elsif v_account.kind = 'member' and not exists (
      select 1 from public.gym_subscriptions s
      where s.member_id = v_user and s.venue_id = v_gym and s.status = 'active'
        and s.end_date >= public.bhutan_today()) then
      -- 3 months from today, as the desk would sell it.
      v_start := public.bhutan_today();
      v_end := (v_start + make_interval(months => 3))::date;
      insert into public.gym_subscriptions (venue_id, member_id, plan_id, plan_name, duration_days, price, status,
                                            start_date, end_date, activated_at)
      select v_gym, v_user, pl.id, pl.name, v_end - v_start + 1, pl.price * 3, 'active', v_start, v_end, now()
      from public.gym_plans pl
      where pl.venue_id = v_gym
      order by pl.sort_order
      limit 1;
    end if;
  end loop;
end;
$$;

-- The test accounts and what each can do.
select p.email,
       p.full_name as name,
       case
         when p.role = 'admin' then 'Super admin'
         else coalesce(
           (select string_agg(r.name, ', ') from public.user_roles ur join public.roles r on r.id = ur.role_id
            where ur.user_id = p.id),
           (select r.name || ' at SportsHub Test Gym' from public.venue_staff s join public.roles r on r.key = s.role
            where s.user_id = p.id and s.venue_id = '7e570000-0000-4000-8000-000000000001'),
           (select 'Member at SportsHub Test Gym until ' || to_char(max(s.end_date), 'DD Mon YYYY')
            from public.gym_subscriptions s
            where s.member_id = p.id and s.venue_id = '7e570000-0000-4000-8000-000000000001' and s.status = 'active'
            having count(*) > 0),
           'No role')
       end as role
from public.profiles p
where p.email like '%@example.com'
order by p.role = 'admin' desc, p.created_at, p.email;
