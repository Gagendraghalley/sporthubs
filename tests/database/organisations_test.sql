-- Organisations and their roles: runs after access_test.sql (it uses the
-- t.* helpers, super admin A2 and the trainer T at Zhemgang Gym). Chain
-- Fitness has two gyms: B owns both, D is front desk at one, C trains at
-- the other, R manages a branch. S owns a gym of their own; G is on the
-- SportsHub team for organisations only.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000400', 'boss@chain.bt', '{"full_name":"Bumthang Boss"}'),
  ('00000000-0000-0000-0000-000000000401', 'desk@chain.bt', '{"full_name":"Dechen Desk"}'),
  ('00000000-0000-0000-0000-000000000402', 'coach@chain.bt', '{"full_name":"Chimi Coach"}'),
  ('00000000-0000-0000-0000-000000000403', 'solo@gym.bt', '{"full_name":"Sangay Solo"}'),
  ('00000000-0000-0000-0000-000000000404', 'orgs@sportshub.bt', '{"full_name":"Ogyen Orgs"}'),
  ('00000000-0000-0000-0000-000000000405', 'branch@chain.bt', '{"full_name":"Rinzin Branch"}'),
  ('00000000-0000-0000-0000-000000000406', 'till@chain.bt', '{"full_name":"Tandin Till"}');

select t.eq((select count(*) from public.venues where organisation_id is null)::int, 0, 'every venue belongs to an organisation');
select t.eq((select count(distinct organisation_id) from public.venues)::int, (select count(*) from public.venues)::int,
            'each venue already here got its own');
select id as trainer from public.roles where key = 'trainer' \gset
select id as manager from public.roles where key = 'manager' \gset
select id as owner_role from public.roles where key = 'owner' \gset
select id as zhemgang from public.venues where name = 'Zhemgang Gym' \gset
set role authenticated;

-- ---- Organisations ----------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000400');
select public.register_venue('{"type":"gym","name":"Chain Gym Thimphu","dzongkhag":"Thimphu","phone":"+97517000301"}') as b1 \gset
select public.register_venue('{"type":"gym","name":"Chain Gym Paro","dzongkhag":"Paro","phone":"+97517000302"}') as b2 \gset
select t.eq((select o.name from public.organisations o join public.venues v on v.organisation_id = o.id where v.id = :'b1'),
            'Chain Gym Thimphu', 'a new venue gets its own organisation, named after it');
select t.fails($$select public.save_organisation(null, 'Mine', null)$$, 'manage organisations');

select t.as_user('00000000-0000-0000-0000-0000000001a0');
select public.save_role(null, 'platform', 'Organisations desk', null, true, array['organisations.manage']) as orgs_role \gset
select public.set_user_platform_roles('00000000-0000-0000-0000-000000000404', array[:'orgs_role']::uuid[]);

select t.as_user('00000000-0000-0000-0000-000000000404');
select t.fails($$select public.save_organisation(null, 'X', null)$$, '2 to 100');
select public.save_organisation(null, '  Chain   Fitness ', 'Two gyms') as chain \gset
select t.eq((select name from public.organisations where id = :'chain'), 'Chain Fitness', 'a new organisation, its name tidied');
select t.eq((select count(*) from public.venues where name like 'Chain Gym%')::int, 2,
            'organisation managers see every venue, verified or not');
select organisation_id as b2_own from public.venues where id = :'b2' \gset
select public.set_venue_organisation(:'b1', :'chain');
select public.set_venue_organisation(:'b2', :'chain');
select public.delete_organisation(:'b2_own');
select t.eq((select count(*) from public.organisations where id = :'b2_own')::int, 0, 'an empty organisation can be deleted');
select t.fails(format($$select public.delete_organisation(%L)$$, :'chain'), '2 venues belong to it');
select t.fails(format($$select public.save_role(null, 'venue', 'Sneaky', null, true, '{}', %L)$$, :'chain'),
               'manage this organisation''s roles');

select t.as_user('00000000-0000-0000-0000-000000000400');
select public.add_venue_staff(:'b1', 'desk@chain.bt', 'staff');
select public.add_venue_staff(:'b2', 'coach@chain.bt', 'trainer');
select public.add_venue_staff(:'b1', 'branch@chain.bt', 'manager');

-- ---- Changing a SportsHub-wide role for one organisation -------------------
select t.eq((public.organisation_roles(:'chain') ->> 'can_manage')::boolean, true,
            'an owner of every branch manages the organisation''s roles');
select t.eq((public.organisation_roles(:'chain') -> 'organisation' ->> 'name'), 'Chain Fitness', 'organisation_roles: whose');
select public.set_organisation_role(:'chain', :'trainer', true, array['gym.members', 'gym.check_in', 'gym.plans']);

select t.as_user('00000000-0000-0000-0000-000000000402');
select t.eq(public.has_venue_permission(:'b2', 'gym.plans'), true, 'an organisation''s change to a SportsHub-wide role applies at its venues');
select t.eq(public.my_venues() -> 0 -> 'permissions', '["gym.check_in", "gym.members", "gym.plans"]'::jsonb,
            'my_venues: what the role allows there');
select t.eq(public.my_venues() -> 0 -> 'organisation' ->> 'name', 'Chain Fitness', 'my_venues: and the organisation');
select t.as_user('00000000-0000-0000-0000-0000000001e0');
select t.eq(public.has_venue_permission(:'zhemgang', 'gym.plans'), false, '...other organisations keep SportsHub''s default');
select t.eq(public.has_venue_permission(:'zhemgang', 'gym.check_in'), true, '...and all of it');
select t.as_user('00000000-0000-0000-0000-000000000401');
select t.eq(public.has_venue_permission(:'b1', 'gym.payments'), true, 'roles the organisation didn''t change are SportsHub''s');

select t.as_user('00000000-0000-0000-0000-000000000400');
select t.fails(format($$select public.set_organisation_role(%L, %L, true, '{}')$$, :'chain', :'owner_role'), 'Owner role always');
select t.fails(format($$select public.set_organisation_role(%L, %L, true, array['users.manage'])$$, :'chain', :'trainer'),
               'aren''t for venue roles');
select public.set_organisation_role(:'chain', :'trainer', false, null);
select t.as_user('00000000-0000-0000-0000-000000000402');
select t.eq(public.is_venue_staff(:'b2'), false, 'a SportsHub-wide role turned off for an organisation gives nothing there');
select t.eq(jsonb_array_length(public.my_venues()), 0, '...and its venue leaves their list');
select t.as_user('00000000-0000-0000-0000-0000000001e0');
select t.eq(public.has_venue_permission(:'zhemgang', 'gym.check_in'), true, '...but works everywhere else');
select t.as_user('00000000-0000-0000-0000-000000000400');
select t.fails(format($$select public.set_venue_staff_role(%L, %L, 'trainer')$$, :'b1', '00000000-0000-0000-0000-000000000401'),
               'turned off');
select public.set_organisation_role(:'chain', :'trainer', true, null);
select t.eq((select count(*) from public.organisation_role_settings where organisation_id = :'chain')::int, 0,
            'on, with SportsHub''s default, is no change at all');
select t.as_user('00000000-0000-0000-0000-000000000402');
select t.eq(public.has_venue_permission(:'b2', 'gym.plans'), false, '...and the role is SportsHub''s again');

-- ---- An organisation's own roles ------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000400');
select t.fails(format($$select public.save_role(null, 'venue', 'manager', null, true, '{}', %L)$$, :'chain'),
               'SportsHub already has a manager role');
select t.fails(format($$select public.save_role(null, 'platform', 'Boss of all', null, true, '{}', %L)$$, :'chain'),
               'for its venues');
select public.save_role(null, 'venue', 'Till operator', 'Takes payments at the till', true, array['gym.payments'], :'chain')
  as till \gset
select public.save_role(null, 'venue', 'Greeter', null, true, array['gym.check_in'], :'chain') as greeter \gset
select t.eq((select organisation_id from public.roles where id = :'till'), :'chain'::uuid, 'an organisation''s own role');
select t.eq((public.organisation_roles(:'chain') -> 'roles' -> -1 ->> 'name'), 'Till operator',
            'organisation_roles: SportsHub''s first, then its own');
select public.add_venue_staff(:'b2', 'till@chain.bt', 'till_operator');
select t.as_user('00000000-0000-0000-0000-000000000406');
select t.eq(public.has_venue_permission(:'b2', 'gym.payments'), true, 'its own role works at its venues');
select t.eq(public.has_venue_permission(:'b2', 'gym.members'), false, '...and gives only its permissions');

select t.as_user('00000000-0000-0000-0000-000000000403');
select public.register_venue('{"type":"gym","name":"Solo Gym","dzongkhag":"Haa","phone":"+97517000303"}') as solo \gset
select t.eq((select count(*) from public.roles where id = :'till')::int, 0, 'other organisations don''t see its own roles');
select t.eq((select count(*) from public.organisations)::int, 1, '...nor it');
select t.fails(format($$select public.organisation_roles(%L)$$, :'chain'), 'organisation''s people');
select t.fails(format($$select public.set_venue_staff_role(%L, %L, 'till_operator')$$, :'solo', '00000000-0000-0000-0000-000000000401'),
               'Choose one of the venue roles');
select t.eq(public.can_give_role(:'till', :'solo'), false, 'another organisation''s role can''t be given');
select t.fails(format($$select public.save_role(%L, null, 'Hijack', null, true, array['gym.payments'])$$, :'till'),
               'manage this organisation''s roles');
select t.fails(format($$select public.set_organisation_role(%L, %L, true, array['gym.plans'])$$, :'chain', :'trainer'),
               'manage this organisation''s roles');
reset role;
select t.fails(format($$insert into public.venue_staff (venue_id, user_id, role) values (%L, %L, 'till_operator')$$,
                      :'solo', '00000000-0000-0000-0000-000000000401'), 'isn''t one of this venue''s');
select t.fails(format($$insert into public.venue_staff (venue_id, user_id, role) values (%L, %L, 'platform_admin')$$,
                      :'solo', '00000000-0000-0000-0000-000000000401'), 'isn''t one of this venue''s');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-000000000200');
select t.eq((select count(*) from public.roles where organisation_id is not null)::int, 0,
            'members see no organisation''s own roles');
select t.eq((select count(*) from public.organisations)::int, 0, '...and no organisations');

-- ---- Who changes an organisation's roles -----------------------------------
-- R manages one branch of two: 'venue.roles' there isn't enough.
select t.as_user('00000000-0000-0000-0000-000000000400');
select public.set_organisation_role(:'chain', :'manager', true,
  array['venue.edit', 'venue.income', 'venue.roles', 'gym.members', 'gym.check_in', 'gym.plans', 'gym.register']);
select t.as_user('00000000-0000-0000-0000-000000000405');
select t.eq((public.organisation_roles(:'chain') ->> 'can_manage')::boolean, false,
            'roles at one branch of two isn''t enough to change the organisation''s');
select t.fails(format($$select public.save_role(null, 'venue', 'Helper', null, true, '{}', %L)$$, :'chain'),
               'manage this organisation''s roles');

select t.as_user('00000000-0000-0000-0000-000000000400');
select public.add_venue_staff(:'b2', 'branch@chain.bt', 'manager');
select t.as_user('00000000-0000-0000-0000-000000000405');
select t.eq((public.organisation_roles(:'chain') ->> 'can_manage')::boolean, true, '...at every branch, it is');
select t.eq((public.organisation_roles(:'chain') -> 'grantable') ? 'gym.plans', true, 'they are offered what they have');
select t.eq((public.organisation_roles(:'chain') -> 'grantable') ? 'gym.payments', false, '...and not what they don''t');
select t.fails(format($$select public.save_role(null, 'venue', 'Hirer', null, true, array['venue.staff'], %L)$$, :'chain'),
               'permissions you have yourself');
select t.fails(format($$select public.save_role(%L, null, 'Till operator', null, true, array['gym.plans'])$$, :'till'),
               'permissions you have yourself'); -- would take away gym.payments, which they don't have
select t.fails(format($$select public.set_organisation_role(%L, %L, false, null)$$, :'chain',
                      (select id from public.roles where key = 'staff')), 'permissions you have yourself');
select public.save_role(:'greeter', null, 'Door greeter', 'At the door', true, array['gym.check_in', 'gym.members']);
select t.eq((select name from public.roles where id = :'greeter'), 'Door greeter', 'they change what they could give');
select public.set_organisation_role(:'chain', :'trainer', true, array['gym.members']);
select t.eq(public.can_give_role(:'trainer', :'b1'), true, 'giving a role: as the organisation has it');
select t.fails(format($$select public.delete_role(%L)$$, :'till'), '1 people have this role');
select public.delete_role(:'greeter');
select t.eq((select count(*) from public.roles where id = :'greeter')::int, 0, 'an organisation''s unused role can be deleted');

-- The team manages any organisation's roles.
select t.as_user('00000000-0000-0000-0000-0000000001a0');
select t.eq((public.organisation_roles(:'chain') ->> 'can_manage')::boolean, true, 'the team manages any organisation''s roles');
select public.save_role(:'till', null, 'Till operator', null, true, array['gym.payments', 'venue.income']);
select public.set_organisation_role(:'chain', :'trainer', true, null);

-- ---- Moving a venue --------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000404');
select t.fails(format($$select public.set_venue_organisation(%L, (select organisation_id from public.venues where id = %L))$$,
                      :'b2', :'solo'), 'own roles (Till operator)');
select public.set_venue_organisation(:'b1', (select organisation_id from public.venues where id = :'solo'));
select t.as_user('00000000-0000-0000-0000-000000000405');
-- The chain's Manager has 'venue.roles'; SportsHub's doesn't.
select t.eq(public.has_venue_permission(:'b1', 'venue.roles'), false, 'a venue that moves takes its new organisation''s roles');
select t.eq(public.has_venue_permission(:'b2', 'venue.roles'), true, '...and the venue it left keeps the old ones');

reset role;
do $$ begin raise notice 'ALL ORGANISATION CHECKS PASSED'; end $$;
