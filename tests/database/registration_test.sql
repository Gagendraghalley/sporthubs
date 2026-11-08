-- Members registered at the front desk: runs after access_test.sql (it uses
-- the t.* helpers). Gym owner O4 with front desk F, trainer T4 and a
-- registrar R (registers, can't take payments); outsider X4; super admin A
-- from scenario_test.sql.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000301', 'owner4@gym.bt', '{"full_name":"Olo Owner"}'),
  ('00000000-0000-0000-0000-000000000302', 'desk@gym.bt', '{"full_name":"Fo Desk"}'),
  ('00000000-0000-0000-0000-000000000303', 'trainer4@gym.bt', '{"full_name":"Tee Trainer"}'),
  ('00000000-0000-0000-0000-000000000304', 'registrar@gym.bt', '{"full_name":"Rey Registrar"}'),
  ('00000000-0000-0000-0000-000000000305', 'outsider4@x.bt', '{"full_name":"Xo Out"}');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-000000000301');
select public.register_venue('{"type":"gym","name":"Paro Power Gym","dzongkhag":"Paro","phone":"+97517000301"}') as gym \gset
select public.register_venue('{"type":"gym","name":"Other Gym","dzongkhag":"Paro","phone":"+97517000309"}') as other_gym \gset
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'gym', true);
select public.review_venue(:'other_gym', true);
select public.save_role(null, 'venue', 'Registrar', null, true, array['gym.register', 'gym.members']) as registrar \gset
select t.as_user('00000000-0000-0000-0000-000000000301');
select public.gym_save_plan(:'gym', null, 'Gym', null, 30, 1500, true) as plan \gset
select public.gym_save_plan(:'gym', null, 'Old', null, 30, 900, false) as old_plan \gset
select public.add_venue_staff(:'gym', 'desk@gym.bt', 'staff');
select public.add_venue_staff(:'gym', 'trainer4@gym.bt', 'trainer');
select public.add_venue_staff(:'gym', 'registrar@gym.bt', 'registrar');

-- ---- Registering ------------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000302');
select public.gym_register_member(:'gym', jsonb_build_object(
  'full_name', '  Karma   Wangmo ', 'phone', '17 12-34 56', 'email', 'Karma@Example.BT', 'date_of_birth', '1995-04-12',
  'blood_group', 'b+', 'occupation', 'Teacher', 'village_id', 1, 'emergency_contact_name', 'Pema',
  'emergency_contact_phone', '77123456', 'medical_notes', 'Asthma: keeps an inhaler', 'joined_on', public.bhutan_today()),
  :'plan', 3, 4500, 'cash', null) as reg \gset
select (:'reg'::jsonb ->> 'gym_member_id') as karma \gset
select (:'reg'::jsonb ->> 'qr_token') as karma_token \gset
select (:'reg'::jsonb ->> 'code') as karma_code \gset
select t.eq(:'karma_code' ~ '^[A-HJ-NP-Z2-9]{6}$', true, 'a member code like account members''');
select t.eq(:'karma_token' ~ '^[0-9a-f]{32}$', true, 'a 32-character QR token');
select t.eq((select full_name || '|' || phone || '|' || email || '|' || blood_group || '|' || emergency_contact_phone
             from public.gym_members where id = :'karma'),
            'Karma Wangmo|+97517123456|karma@example.bt|B+|+97577123456', 'details are tidied');
select t.eq((select (gewog_id, dzongkhag_id)::text from public.gym_members where id = :'karma'), '(1,1)',
            'the gewog and dzongkhag come from the village');
select t.eq((select end_date from public.gym_subscriptions where gym_member_id = :'karma'),
            (public.bhutan_today() + interval '3 months')::date, 'expires three months from joining, the same date');
-- The client's example, tried (as the front desk) and undone.
reset role;
begin;
select t.eq((public.gym_add_membership(m, :'plan', 3, date '2026-11-08', 0, null, null) ->> 'end_date')::date,
            date '2027-02-08', '...8 Nov 2026 for 3 months expires on 8 Feb 2027 (the client''s example)')
from public.gym_members m where m.id = :'karma';
rollback;
set role authenticated;
select t.eq((select (status, member_id is null, price)::text from public.gym_subscriptions where gym_member_id = :'karma'),
            '(active,t,4500)', 'an active membership of the registered member, at the price paid');
select t.eq((select count(*) from public.payments where venue_id = :'gym')::int, 0, 'front desk sees no income');

select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Karma Wangmo","phone":"17123456"}')$$, :'gym'),
               'already registered here');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Bad Phone","phone":"123"}')$$, :'gym'), 'phone number');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Bad Mail","phone":"17000001","email":"x@"}')$$, :'gym'),
               'email');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Unborn","phone":"17000002","date_of_birth":"2999-01-01"}')$$, :'gym'),
               'date of birth');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"No Group","phone":"17000003","blood_group":"C+"}')$$, :'gym'),
               'blood group');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Lost","phone":"17000004","village_id":999999}')$$, :'gym'),
               'village');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Old Plan","phone":"17000005"}', %L, 1, 900, 'cash')$$,
                      :'gym', :'old_plan'), 'one of the gym''s packages');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Too Long","phone":"17000006"}', %L, 25, 0)$$,
                      :'gym', :'plan'), '1 to 24');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"No Method","phone":"17000007"}', %L, 1, 1500)$$,
                      :'gym', :'plan'), 'how they paid');
select t.fails($$insert into public.gym_members (venue_id, code, qr_token, full_name, phone, joined_on)
                 values (gen_random_uuid(), 'AAAAAA', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'X', '+97517000000', current_date)$$,
               'permission denied');

-- An old member entered late: their package already ran out.
select (public.gym_register_member(:'gym', jsonb_build_object('full_name', 'Dorji Old', 'phone', '17000010',
          'joined_on', public.bhutan_today() - 100), :'plan', 1, 0) ->> 'gym_member_id') as dorji \gset
select t.eq((select status from public.gym_subscriptions where gym_member_id = :'dorji'), 'expired',
            'a package that ran out before today is entered as ended');

-- ---- Who registers, who sees ------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000304');
select (public.gym_register_member(:'gym', '{"full_name":"Sonam No Package","phone":"17000011"}') ->> 'gym_member_id') as sonam \gset
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Sold By Registrar","phone":"17000012"}', %L, 1, 1500, 'cash')$$,
                      :'gym', :'plan'), 'not sell them a package');
select t.fails(format($$select public.gym_renew_member(%L, %L, 1, 1500, 'cash')$$, :'sonam', :'plan'), 'not sell them a package');

select t.as_user('00000000-0000-0000-0000-000000000303');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"By Trainer","phone":"17000013"}')$$, :'gym'),
               'register members');
select t.eq((select count(*) from public.gym_members where venue_id = :'gym')::int, 3, 'the trainer sees the register');
select t.eq((select medical_notes from public.gym_members where id = :'karma'), 'Asthma: keeps an inhaler',
            '...medical notes included');
select t.eq(public.gym_member_photo_access(:'gym' || '/x.jpg', 'gym.members'), true, 'the trainer sees photos');
select t.eq(public.gym_member_photo_access(:'gym' || '/x.jpg', 'gym.register'), false, '...but can''t change them');
select t.fails(format($$select public.gym_update_member(%L, '{"full_name":"Renamed","phone":"17123456"}')$$, :'karma'),
               'change their details');

select t.as_user('00000000-0000-0000-0000-000000000305');
select t.eq((select count(*) from public.gym_members)::int, 0, 'outsiders see no members');
select t.eq(public.gym_member_photo_access(:'gym' || '/x.jpg', 'gym.members'), false, '...nor their photos');
select t.fails(format($$select public.gym_check_in_member(%L, %L)$$, :'gym', :'karma_token'), 'Only the gym''s staff');

reset role; set role anon;
select t.fails(format($$select public.gym_register_member(%L, '{}')$$, :'gym'), 'permission denied');
reset role; set role authenticated;

-- ---- Checking in --------------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000303');
select t.eq(public.gym_check_in_member(:'gym', upper(:'karma_token')) ->> 'member_name', 'Karma Wangmo',
            'the trainer checks a card in');
select t.eq((public.gym_check_in_member(:'gym', :'karma_token') ->> 'earlier_today')::int, 1, 'twice today: said so');
select t.eq(public.gym_check_in_by_code(:'gym', lower(:'karma_code')) ->> 'medical_notes', 'Asthma: keeps an inhaler',
            'by member code, with what the desk should know');
select t.eq((select count(*) from public.gym_check_ins where gym_member_id = :'karma')::int, 3, 'three visits recorded');
select t.fails(format($$select public.gym_check_in_member(%L, %L)$$, :'gym', :'dorji'), 'isn''t valid any more');
select t.fails(format($$select public.gym_check_in_by_code(%L, (select code from public.gym_members where id = %L))$$,
                      :'gym', :'dorji'), 'ended on');
select t.fails(format($$select public.gym_check_in_by_code(%L, (select code from public.gym_members where id = %L))$$,
                      :'gym', :'sonam'), 'no package yet');

select t.as_user('00000000-0000-0000-0000-000000000301');
select t.fails(format($$select public.gym_check_in_member(%L, %L)$$, :'other_gym', :'karma_token'), 'another gym');
select t.fails(format($$select public.gym_check_in_by_code(%L, %L)$$, :'other_gym', :'karma_code'), 'another gym');
select t.eq((public.gym_dashboard(:'gym') ->> 'active')::int, 1, 'the dashboard counts registered members');
select t.eq((public.gym_dashboard(:'gym') ->> 'check_ins_today')::int, 3, '...and their visits');

-- ---- Renewing, cards, changes ------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000302');
select public.gym_renew_member(:'dorji', :'plan', 2, 3000, 'mbob', '  JRN-77 ');
select t.eq((select start_date from public.gym_subscriptions where gym_member_id = :'dorji' and status = 'active'),
            public.bhutan_today(), 'an ended member renews from today');
select public.gym_renew_member(:'karma', :'plan', 1, 1500, 'cash');
select t.eq((select start_date || ' ' || end_date from public.gym_subscriptions
             where gym_member_id = :'karma' and start_date > public.bhutan_today()),
            (public.bhutan_today() + interval '3 months')::date || ' '
              || ((public.bhutan_today() + interval '3 months')::date + interval '1 month')::date,
            'a current member renews from the day it expires, a month on from there: the dates don''t drift');

-- Ending in a few days, then renewed: no longer ending soon.
select (public.gym_register_member(:'gym', jsonb_build_object('full_name', 'Pema Soon', 'phone', '17000014',
          'joined_on', public.bhutan_today() - 27), :'plan', 1, 0) ->> 'gym_member_id') as pema \gset
select t.eq((public.gym_dashboard(:'gym') ->> 'expiring_soon')::int, 1, 'a package ending within the week is ending soon');
select public.gym_renew_member(:'pema', :'plan', 1, 0);
select t.eq((select count(distinct start_date)::int from public.gym_subscriptions where gym_member_id = :'pema'), 2,
            '...renewed');
select t.eq((select bool_and(r.start_date = s.end_date) from public.gym_subscriptions s
             join public.gym_subscriptions r on r.gym_member_id = s.gym_member_id and r.start_date > s.start_date
             where s.gym_member_id = :'pema'), true, '...from the day the first one expires');
select t.eq((public.gym_dashboard(:'gym') ->> 'expiring_soon')::int, 0, '...and no longer ending soon');

select public.gym_reissue_member_qr(:'karma') as new_token \gset
select t.fails(format($$select public.gym_check_in_member(%L, %L)$$, :'gym', :'karma_token'), 'isn''t valid any more');
select t.eq(public.gym_check_in_member(:'gym', :'new_token') ->> 'member_code', :'karma_code', 'the new card works, same code');

select public.gym_update_member(:'karma', jsonb_build_object('full_name', 'Karma Wangmo Dorji', 'phone', '17123456',
  'gewog_id', 159, 'joined_on', public.bhutan_today()));
select t.eq((select full_name || ' ' || dzongkhag_id || ' ' || coalesce(village_id::text, '-') || ' ' || coalesce(email, '-')
             from public.gym_members where id = :'karma'),
            'Karma Wangmo Dorji 14 - -', 'the whole form is saved, the dzongkhag from the gewog');
select t.as_user('00000000-0000-0000-0000-000000000301');
select t.eq((select string_agg(payer_name || ' ' || amount || ' ' || coalesce(reference, '-'), ', ' order by created_at)
             from public.payments where venue_id = :'gym'),
            'Karma Wangmo 4500 -, Dorji Old 3000 JRN-77, Karma Wangmo 1500 -',
            'the owner sees each payment, who paid and the mBoB journal number');
select t.fails(format($$select public.gym_set_member_photo(%L, %L)$$, :'karma', :'other_gym' || '/k.jpg'), 'this gym''s folder');
select public.gym_set_member_photo(:'karma', :'gym' || '/' || :'karma' || '.jpg');
select t.eq((select photo_path from public.gym_members where id = :'karma'), :'gym' || '/' || :'karma' || '.jpg', 'the photo is set');

reset role;
do $$ begin raise notice 'ALL REGISTRATION CHECKS PASSED'; end $$;
