-- Master data, roles and permissions: runs after scenario_test.sql (it uses
-- its t.* helpers). Super admin A2, gym owner O2, and people who get roles:
-- U1 (SportsHub team), K (cashier), T (trainer), V (supervisor), M3 (member).
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000001a0', 'super@sportshub.bt', '{"full_name":"Sonam Super"}'),
  ('00000000-0000-0000-0000-0000000001b0', 'owner2@gym.bt', '{"full_name":"Ola Owner"}'),
  ('00000000-0000-0000-0000-0000000001c0', 'u1@sportshub.bt', '{"full_name":"Ugyen Team"}'),
  ('00000000-0000-0000-0000-0000000001d0', 'cashier@gym.bt', '{"full_name":"Karma Cashier"}'),
  ('00000000-0000-0000-0000-0000000001e0', 'trainer@gym.bt', '{"full_name":"Tashi Trainer"}'),
  ('00000000-0000-0000-0000-0000000001f0', 'supervisor@gym.bt', '{"full_name":"Vee Supervisor"}'),
  ('00000000-0000-0000-0000-000000000200', 'member3@x.bt', '{"full_name":"Meme Three"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000001a0';

-- ---- Master data -----------------------------------------------------------
select t.eq((select count(*) from public.dzongkhags)::int, 20, 'masters: 20 dzongkhags');
select t.eq((select count(*) from public.gewogs)::int, 216, 'masters: 216 gewogs and thromdes');
select t.eq((select count(*) from public.villages)::int, 4499, 'masters: 4499 villages');
select t.eq((select count(*) from public.dzongkhags where name in ('Chhukha', 'Samdrup Jongkhar'))::int, 2,
            'masters: dzongkhags spelled as the rest of SportsHub spells them');
select t.eq((select count(*) from public.dzongkhags d where d.name not in (
              'Bumthang', 'Chhukha', 'Dagana', 'Gasa', 'Haa', 'Lhuentse', 'Mongar', 'Paro', 'Pemagatshel', 'Punakha',
              'Samdrup Jongkhar', 'Samtse', 'Sarpang', 'Thimphu', 'Trashigang', 'Trashiyangtse', 'Trongsa', 'Tsirang',
              'Wangdue Phodrang', 'Zhemgang'))::int, 0, 'masters: every dzongkhag is one venues accept');
select t.eq((select g.name from public.villages v join public.gewogs g on g.id = v.gewog_id where v.name = 'Babesa'),
            'Thim Throm', 'masters: Thimphu localities belong to Thim Throm');
select t.eq((select count(*) from public.villages where lower(name) = 'unknown')::int, 0, 'masters: no Unknown placeholders');
select t.eq((select count(*) from public.gewogs g where not exists (select 1 from public.villages v where v.gewog_id = g.id))::int,
            0, 'masters: every gewog has villages');

set role anon;
select t.eq((select count(*) from public.villages)::int, 4499, 'visitors read the villages (sign-up forms)');
select t.fails($$insert into public.villages (gewog_id, name) values (1, 'Hack')$$, 'permission denied');
reset role; set role authenticated;

select t.as_user('00000000-0000-0000-0000-000000000200');
select t.fails($$select public.master_save_village(null, 1, 'Newville')$$, 'keep the master data');
select t.eq(public.my_access() -> 'permissions', '[]'::jsonb, 'a member has no team permissions');

select t.as_user('00000000-0000-0000-0000-0000000001a0');
select t.eq((public.my_access() ->> 'is_super_admin')::boolean, true, 'super admins are told so');
select t.eq(jsonb_array_length(public.my_access() -> 'permissions'),
            (select count(*) from public.permissions where scope = 'platform')::int, 'super admins have every team permission');
select public.master_save_village(null, 1, '  New   Chokhor  Village ') as new_village \gset
select t.eq((select name from public.villages where id = :new_village), 'New Chokhor Village', 'a new village, tidied');
select t.eq(:new_village > 4739, true, 'new villages continue after the imported ids');
select t.fails($$select public.master_save_village(null, 1, 'new chokhor village')$$, 'already in that gewog');
select t.fails($$select public.master_save_gewog(null, 99, 'Nowhere')$$, 'Choose the dzongkhag');
select public.master_save_village(:new_village, 1, 'New Chokhor Village', false);

select t.as_user('00000000-0000-0000-0000-000000000200');
select t.eq((select count(*) from public.villages where id = :new_village)::int, 0, 'turned-off villages are hidden from members');

-- ---- Platform roles --------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-0000000001c0');
select t.fails($$select public.save_role(null, 'platform', 'Sneaky', null, true, array['users.manage'])$$, 'manage roles');
select t.fails($$select public.set_user_platform_roles('00000000-0000-0000-0000-0000000001c0', '{}')$$, 'manage users');
select t.eq((select count(*) from public.profiles)::int, 1, 'without users.manage, only your own profile');

select t.as_user('00000000-0000-0000-0000-0000000001a0');
select t.fails($$select public.save_role(null, 'venue', 'Odd', null, true, array['users.manage'])$$, 'aren''t for this kind');
select t.fails($$select public.save_role((select id from public.roles where key = 'owner'), null, 'Boss', null, true, '{}')$$,
               'Owner role always');
select public.save_role(null, 'platform', 'Masters officer', 'Keeps the location lists', true, array['masters.manage'])
  as masters_role \gset
select public.save_role(null, 'platform', 'User desk', null, true, array['users.manage']) as users_role \gset
select t.eq((select key from public.roles where id = :'masters_role'), 'masters_officer', 'role keys come from their names');
select t.fails($$select public.save_role(null, 'platform', 'masters OFFICER', null, true, '{}')$$, 'already a role called');
select public.set_user_platform_roles('00000000-0000-0000-0000-0000000001c0', array[:'masters_role', :'users_role']::uuid[]);

select t.as_user('00000000-0000-0000-0000-0000000001c0');
select t.eq(public.my_access() -> 'permissions', '["users.manage", "masters.manage"]'::jsonb, 'roles give their permissions');
select public.master_save_village(:new_village, 1, 'New Chokhor Village', true);
select t.eq((select count(*) from public.profiles)::int > 10, true, 'user managers see every account');
select t.fails(format($$select public.set_user_platform_roles('00000000-0000-0000-0000-0000000001d0', array[%L]::uuid[])$$,
                      (select id from public.roles where key = 'platform_admin')), 'permissions you have yourself');
select public.set_user_platform_roles('00000000-0000-0000-0000-0000000001d0', array[:'masters_role']::uuid[]);
select t.eq((select count(*) from public.user_roles where user_id = '00000000-0000-0000-0000-0000000001d0')::int, 1,
            'they can give a role whose permissions they have');
select public.set_user_platform_roles('00000000-0000-0000-0000-0000000001d0', '{}');
select t.fails($$select public.set_user_super_admin('00000000-0000-0000-0000-0000000001c0', true)$$, 'Only super admins');
select t.fails($$select public.set_user_active('00000000-0000-0000-0000-0000000001a0', false)$$, 'turn a super admin off');
select t.fails($$select public.set_user_active('00000000-0000-0000-0000-0000000001c0', false)$$, 'your own account');
select t.fails(format($$update public.profiles set is_active = false where id = %L$$, '00000000-0000-0000-0000-0000000001d0'),
               'permission denied');

select t.as_user('00000000-0000-0000-0000-0000000001a0');
select public.save_role(:'masters_role', null, 'Masters officer', null, false, array['masters.manage']);
select t.as_user('00000000-0000-0000-0000-0000000001c0');
select t.eq(public.my_access() -> 'permissions', '["users.manage"]'::jsonb, 'a role turned off gives nothing');
select t.fails($$select public.master_save_village(null, 1, 'Another')$$, 'keep the master data');
select t.as_user('00000000-0000-0000-0000-0000000001a0');
select t.fails(format($$select public.delete_role(%L)$$, :'masters_role'), '1 people have this role');
select t.fails(format($$select public.delete_role(%L)$$, (select id from public.roles where key = 'trainer')), 'can''t be deleted');
select public.set_user_platform_roles('00000000-0000-0000-0000-0000000001c0', array[:'users_role']::uuid[]);
select public.delete_role(:'masters_role');
select t.eq((select count(*) from public.roles where id = :'masters_role')::int, 0, 'an unused role can be deleted');
select t.fails($$select public.set_user_super_admin('00000000-0000-0000-0000-0000000001a0', false)$$, 'can''t stop being');

-- ---- Venue roles -----------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-0000000001b0');
select public.register_venue('{"type":"gym","name":"Zhemgang Gym","dzongkhag":"Zhemgang","phone":"+97517000009"}') as gym \gset
select t.as_user('00000000-0000-0000-0000-0000000001a0');
select public.review_venue(:'gym', true);
select public.save_role(null, 'venue', 'Cashier', 'Takes payments only', true, array['gym.payments']) as cashier \gset
select public.save_role(null, 'venue', 'Supervisor', null, true, array['venue.staff', 'gym.members']) as supervisor \gset
select public.save_role(null, 'venue', 'Viewer', null, true, array['gym.members']) as viewer \gset
select t.eq((select count(*) from public.role_permissions rp join public.roles r on r.id = rp.role_id where r.key = 'owner')::int,
            (select count(*) from public.permissions where scope = 'venue')::int, 'the owner role lists every venue permission');
select t.eq((select array_agg(permission_key order by permission_key) from public.role_permissions rp
             join public.roles r on r.id = rp.role_id where r.key = 'staff'),
            array['gym.check_in', 'gym.members', 'gym.payments', 'gym.register'],
            'front desk: members, payments, check-in and registering');

select t.as_user('00000000-0000-0000-0000-0000000001b0');
select public.gym_save_plan(:'gym', null, 'Monthly', null, 30, 1000, true) as plan \gset
select public.add_venue_staff(:'gym', 'cashier@gym.bt', 'cashier');
select public.add_venue_staff(:'gym', 'trainer@gym.bt', 'trainer');
select public.add_venue_staff(:'gym', 'supervisor@gym.bt', 'supervisor');
select t.fails(format($$select public.set_venue_staff_role(%L, %L, 'owner')$$, :'gym', '00000000-0000-0000-0000-0000000001e0'),
               'make someone an owner');
select t.fails(format($$select public.set_venue_staff_role(%L, %L, 'manager')$$, :'gym', '00000000-0000-0000-0000-0000000001b0'),
               'your own role');

select t.as_user('00000000-0000-0000-0000-000000000200');
select public.gym_request_subscription(:'plan') as sub \gset

select t.as_user('00000000-0000-0000-0000-0000000001e0');
select t.fails(format($$select public.gym_activate_subscription(%L, 1000, 'cash')$$, :'sub'), 'Only the gym''s staff');
select t.eq((select count(*) from public.gym_subscriptions where venue_id = :'gym')::int, 1, 'the trainer sees members');
select t.eq((select count(*) from public.payments where venue_id = :'gym')::int, 0, 'the trainer sees no payments');

select t.as_user('00000000-0000-0000-0000-0000000001d0');
select t.eq((select count(*) from public.notifications where title = 'You were added to Zhemgang Gym')::int, 1,
            'the cashier is told');
select t.eq((select count(*) from public.gym_subscriptions where venue_id = :'gym')::int, 0, 'the cashier role has no members permission');
select public.gym_activate_subscription(:'sub', 1000, 'cash');
select t.fails(format($$select public.gym_check_in(%L, %L)$$, :'gym', '00000000-0000-0000-0000-000000000200'), 'Only the gym''s staff');
select t.fails(format($$select public.gym_save_plan(%L, null, 'Cheap', null, 30, 1, true)$$, :'gym'), 'manage plans');

select t.as_user('00000000-0000-0000-0000-0000000001e0');
select t.eq((public.gym_check_in(:'gym', '00000000-0000-0000-0000-000000000200') ->> 'member_name'), 'Meme Three',
            'the trainer checks members in');
-- Even a change that changes nothing is checked first.
select t.fails(format($$select public.set_venue_staff_role(%L, %L, 'cashier')$$, :'gym', '00000000-0000-0000-0000-0000000001d0'),
               'manage this venue''s staff');

select t.as_user('00000000-0000-0000-0000-0000000001f0');
select t.fails(format($$select public.set_venue_staff_role(%L, %L, 'trainer')$$, :'gym', '00000000-0000-0000-0000-000000000200'),
               'permissions you have yourself');
select public.set_venue_staff_role(:'gym', '00000000-0000-0000-0000-000000000200', 'viewer');
select t.fails(format($$select public.remove_venue_staff(%L, %L)$$, :'gym', '00000000-0000-0000-0000-0000000001d0'),
               'permissions you have yourself');
select public.remove_venue_staff(:'gym', '00000000-0000-0000-0000-000000000200');
select t.fails(format($$select public.remove_venue_staff(%L, %L)$$, :'gym', '00000000-0000-0000-0000-0000000001b0'),
               'owner can''t be removed');

-- Turning a role, or a person, off.
select t.as_user('00000000-0000-0000-0000-0000000001a0');
select public.save_role(:'cashier', null, 'Cashier', null, false, array['gym.payments']);
select t.as_user('00000000-0000-0000-0000-0000000001d0');
select t.eq(public.has_venue_permission(:'gym', 'gym.payments'), false, 'a role turned off gives nothing at the venue');
select t.eq(public.is_venue_staff(:'gym'), false, '...and they no longer count as staff');
select t.as_user('00000000-0000-0000-0000-0000000001c0');
select public.set_user_active('00000000-0000-0000-0000-0000000001e0', false);
select t.as_user('00000000-0000-0000-0000-0000000001e0');
select t.fails(format($$select public.gym_check_in(%L, %L)$$, :'gym', '00000000-0000-0000-0000-000000000200'), 'Only the gym''s staff');
select t.eq((public.my_access() ->> 'is_active')::boolean, false, 'a turned-off person is told');
select t.as_user('00000000-0000-0000-0000-0000000001c0');
select public.set_user_active('00000000-0000-0000-0000-0000000001e0', true);
select t.as_user('00000000-0000-0000-0000-0000000001e0');
select t.eq(public.has_venue_permission(:'gym', 'gym.check_in'), true, 'turned on again, their role is back');

-- User managers hand venues over; a venue keeps an owner.
select t.as_user('00000000-0000-0000-0000-0000000001c0');
select t.fails(format($$select public.set_venue_staff_role(%L, %L, 'manager')$$, :'gym', '00000000-0000-0000-0000-0000000001b0'),
               'needs an owner');
select public.set_venue_staff_role(:'gym', '00000000-0000-0000-0000-0000000001f0', 'owner');
select public.set_venue_staff_role(:'gym', '00000000-0000-0000-0000-0000000001b0', 'manager');
select t.eq((select string_agg(role, ',' order by role) from public.venue_staff where venue_id = :'gym'
             and user_id in ('00000000-0000-0000-0000-0000000001b0', '00000000-0000-0000-0000-0000000001f0')),
            'manager,owner', 'the venue is handed over');
select t.fails(format($$select public.delete_role(%L)$$, :'supervisor'), 'manage roles');

select t.as_user('00000000-0000-0000-0000-0000000001b0');
select t.fails(format($$select public.add_venue_staff(%L, 'member3@x.bt', 'staff')$$, :'gym'), 'manage this venue''s staff');
select t.eq((select count(*) from public.payments where venue_id = :'gym')::int, 1, 'a manager sees income');

reset role;
do $$ begin raise notice 'ALL ACCESS CHECKS PASSED'; end $$;
