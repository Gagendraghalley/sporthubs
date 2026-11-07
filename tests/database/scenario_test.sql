-- End-to-end check of the SportsHub migrations: admin A, gym owner O,
-- front-desk staff S, members M and M2, outsider X.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

-- Test helpers (run as whoever is current, so rules apply).
create schema t;
grant usage on schema t to anon, authenticated;
create function t.fails(statement text, fragment text) returns void language plpgsql as $$
begin
  execute statement;
  raise exception 'EXPECTED FAILURE did not happen: %', statement;
exception when others then
  if sqlerrm like 'EXPECTED FAILURE%' then raise; end if;
  if position(lower(fragment) in lower(sqlerrm)) = 0 then
    raise exception 'Wrong error for %: got "%", wanted "%"', statement, sqlerrm, fragment;
  end if;
end $$;
create function t.eq(actual anyelement, expected anyelement, label text) returns void language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL %: got %, expected %', label, actual, expected;
  end if;
  raise notice 'ok  %', label;
end $$;
grant execute on all functions in schema t to anon, authenticated;
create function t.as_user(u uuid) returns void language sql as $$ select set_config('request.jwt.claim.sub', u::text, false) $$;
grant execute on function t.as_user(uuid) to anon, authenticated;

-- Accounts (as Supabase Auth would make them).
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'Admin@SportsHub.bt', '{"full_name":"Ada Admin"}'),
  ('00000000-0000-0000-0000-00000000000b', 'owner@gym.bt', '{"full_name":"Olu Owner","phone":"+97517000001"}'),
  ('00000000-0000-0000-0000-00000000000c', 'staff@gym.bt', '{"full_name":"Sam Staff"}'),
  ('00000000-0000-0000-0000-00000000000d', 'member@x.bt', '{"full_name":"Meto Member","phone":"bad"}'),
  ('00000000-0000-0000-0000-00000000000e', 'member2@x.bt', '{"full_name":"Mo Two"}'),
  ('00000000-0000-0000-0000-00000000000f', 'outsider@x.bt', '{"full_name":"Xi Out"}');
update public.profiles set role = 'admin' where email = 'admin@sportshub.bt';

select t.eq((select count(*) from public.profiles)::int, 6, 'a profile for each account');
select t.eq((select email from public.profiles where id = '00000000-0000-0000-0000-00000000000a'), 'admin@sportshub.bt', 'email kept, lower case');
select t.eq((select phone from public.profiles where id = '00000000-0000-0000-0000-00000000000d'), null::text, 'a bad phone from sign-up is dropped');
select t.eq((select count(distinct member_code) from public.profiles)::int, 6, 'member codes are unique');
select t.eq((select bool_and(member_code ~ '^[A-HJ-NP-Z2-9]{6}$') from public.profiles), true, 'member codes are 6 clear characters');

-- ---- Profiles: own row, own columns only ------------------------------
set role authenticated;
select t.as_user('00000000-0000-0000-0000-00000000000d');
select t.eq((select count(*) from public.profiles)::int, 1, 'a member sees only their own profile');
select t.fails($$update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000000d'$$, 'permission denied');
select t.fails($$update public.profiles set member_code = 'AAAAAA' where id = '00000000-0000-0000-0000-00000000000d'$$, 'permission denied');
update public.profiles set full_name = 'Meto Member', phone = '+97577000002' where id = '00000000-0000-0000-0000-00000000000d';
select t.eq((select phone from public.profiles where id = '00000000-0000-0000-0000-00000000000d'), '+97577000002', 'a member updates their phone');
select t.fails($$insert into public.payments (venue_id, module_key, amount, method) values (gen_random_uuid(), 'gym_membership', 1, 'cash')$$, 'permission denied');
select t.fails($$select public.notify('00000000-0000-0000-0000-00000000000d', null, 'hi')$$, 'permission denied');

-- ---- Registering a gym: closed until the module is on -------------------
select t.as_user('00000000-0000-0000-0000-00000000000b');
select t.fails($$select public.register_venue('{"type":"gym","name":"Peak Fitness","dzongkhag":"Thimphu","phone":"+97517000001"}')$$, 'can''t be registered yet');
select t.fails($$select public.set_module_enabled('gym_membership', true)$$, 'Only the SportsHub team');
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.set_module_enabled('gym_membership', true);
select t.as_user('00000000-0000-0000-0000-00000000000b');
select t.fails($$select public.register_venue('{"type":"gym","name":"Peak Fitness","dzongkhag":"Atlantis","phone":"+97517000001"}')$$, 'venues_dzongkhag_check');
select public.register_venue('{"type":"gym","name":"Peak Fitness","dzongkhag":"Thimphu","town":"Changzamtog","phone":"+97517000001","payment_info":"mBoB 200123456"}') as venue_id \gset
select t.eq((select role from public.venue_staff where venue_id = :'venue_id' and user_id = '00000000-0000-0000-0000-00000000000b'), 'owner', 'the registrant owns the venue');
select t.eq((select verification_status from public.venues where id = :'venue_id'), 'pending', 'a new venue waits for verification');

-- Hidden until verified.
reset role; set role anon;
select t.eq((select count(*) from public.venues)::int, 0, 'visitors do not see unverified venues');
reset role; set role authenticated;
select t.as_user('00000000-0000-0000-0000-00000000000d');
select t.eq((select count(*) from public.venues)::int, 0, 'members do not see unverified venues');
select t.as_user('00000000-0000-0000-0000-00000000000b');
select t.eq((select count(*) from public.venues)::int, 1, 'the owner sees their pending venue');

-- ---- Plans and staff ---------------------------------------------------
select public.gym_save_plan(:'venue_id', null, 'Monthly', 'All equipment', 30, 1500, true) as plan_id \gset
select public.gym_save_plan(:'venue_id', null, 'Old plan', null, 7, 400, false) as hidden_plan_id \gset
select public.add_venue_staff(:'venue_id', 'STAFF@gym.bt', 'staff');
select t.fails(format($$select public.add_venue_staff(%L, 'nobody@x.bt', 'staff')$$, :'venue_id'), 'No SportsHub account');
select t.fails(format($$select public.add_venue_staff(%L, 'member@x.bt', 'owner')$$, :'venue_id'), 'managers or staff');
select t.fails(format($$select public.remove_venue_staff(%L, '00000000-0000-0000-0000-00000000000b')$$, :'venue_id'), 'owner can''t be removed');
select t.as_user('00000000-0000-0000-0000-00000000000c');
select t.fails(format($$select public.gym_save_plan(%L, null, 'Cheap', null, 30, 1, true)$$, :'venue_id'), 'owner and managers');
select t.fails(format($$select public.add_venue_staff(%L, 'member2@x.bt', 'staff')$$, :'venue_id'), 'Only the venue''s owner');
select t.fails(format($$select public.update_venue(%L, '{"name":"Mine now"}')$$, :'venue_id'), 'owner and managers');
select t.eq((select count(*) from public.profiles)::int, 2, 'staff see themselves and their colleague (the owner)');
select t.eq((select count(*) from public.gym_plans)::int, 2, 'staff see every plan of their gym');
select t.eq((select count(*) from public.notifications where title like 'You were added%')::int, 1, 'staff are told they were added');

-- ---- Members can't join before verification -----------------------------
select t.as_user('00000000-0000-0000-0000-00000000000d');
select t.fails(format($$select public.gym_request_subscription(%L)$$, :'plan_id'), 'isn''t taking members');
select t.as_user('00000000-0000-0000-0000-00000000000a');
select t.eq((select count(*) from public.notifications where title = 'New venue to verify')::int, 1, 'admins hear about new venues');
select t.fails(format($$select public.review_venue(%L, false, '  ')$$, :'venue_id'), 'Say why');
select public.review_venue(:'venue_id', true);
select t.as_user('00000000-0000-0000-0000-00000000000b');
select t.eq((select count(*) from public.notifications where title like '%is live on SportsHub')::int, 1, 'the owner hears it is live');

reset role; set role anon;
select t.eq((select count(*) from public.venues)::int, 1, 'visitors see the verified gym');
select t.eq((select count(*) from public.gym_plans)::int, 1, 'visitors see only plans on sale');
select t.fails('select count(*) from public.gym_subscriptions', 'permission denied');
reset role; set role authenticated;

-- ---- Joining ---------------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-00000000000d');
select t.fails(format($$select public.gym_request_subscription(%L)$$, :'hidden_plan_id'), 'no longer offered');
select public.gym_request_subscription(:'plan_id') as sub1 \gset
select t.fails(format($$select public.gym_request_subscription(%L)$$, :'plan_id'), 'already have a request waiting');
select t.eq((select count(*) from public.gym_subscriptions)::int, 1, 'the member sees their request');
select t.fails(format($$update public.gym_subscriptions set status = 'active' where id = %L$$, :'sub1'), 'permission denied');
select t.fails(format($$select public.gym_activate_subscription(%L, 1500, 'cash')$$, :'sub1'), 'Only the gym''s staff');

select t.as_user('00000000-0000-0000-0000-00000000000f');
select t.eq((select count(*) from public.gym_subscriptions)::int, 0, 'outsiders see no memberships');
select t.eq((select count(*) from public.profiles where id = '00000000-0000-0000-0000-00000000000d')::int, 0, 'outsiders cannot read members');

select t.as_user('00000000-0000-0000-0000-00000000000c');
select t.eq((select count(*) from public.notifications where title = 'New membership request')::int, 1, 'staff hear about the request');
select t.eq((select count(*) from public.gym_subscriptions)::int, 1, 'staff see their gym''s requests');
select t.eq((select full_name from public.profiles where id = '00000000-0000-0000-0000-00000000000d'), 'Meto Member', 'staff can read their members'' names');
select t.fails(format($$select public.gym_check_in(%L, '00000000-0000-0000-0000-00000000000d')$$, :'venue_id'), 'waiting: confirm their payment first');
select t.fails(format($$select public.gym_activate_subscription(%L, 1500, 'crypto')$$, :'sub1'), 'Choose how they paid');

-- ---- Confirming the payment ---------------------------------------------
select public.gym_activate_subscription(:'sub1', 1500, 'mbob', 'JRN123') as activated \gset
select t.eq((select status from public.gym_subscriptions where id = :'sub1'), 'active', 'confirmed: active');
select t.eq((select start_date from public.gym_subscriptions where id = :'sub1'), public.bhutan_today(), 'starts today');
select t.eq((select end_date from public.gym_subscriptions where id = :'sub1'), public.bhutan_today() + 29, '30 days, both ends included');
select t.fails(format($$select public.gym_activate_subscription(%L, 1500, 'cash')$$, :'sub1'), 'isn''t waiting any more');
select t.eq((select count(*) from public.payments)::int, 0, 'front-desk staff do not see payments');

select t.as_user('00000000-0000-0000-0000-00000000000b');
select t.eq((select count(*) from public.payments)::int, 1, 'the owner sees the payment');
select t.eq((select amount from public.payments), 1500, 'with its amount');
select t.eq((select reference from public.payments), 'JRN123', 'and the mBoB journal number');

select t.as_user('00000000-0000-0000-0000-00000000000d');
select t.eq((select count(*) from public.payments)::int, 1, 'the member sees their payment');
select t.eq((select count(*) from public.notifications where title like 'Your membership at Peak Fitness is active')::int, 1, 'the member hears it is active');

-- ---- Checking in --------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-00000000000c');
select public.gym_check_in(:'venue_id', '00000000-0000-0000-0000-00000000000d') as checkin1 \gset
select t.eq((:'checkin1'::jsonb ->> 'days_left')::int, 30, 'check-in: 30 days left');
select t.eq((:'checkin1'::jsonb ->> 'earlier_today')::int, 0, 'first check-in today');
select (select member_code from public.profiles where id = '00000000-0000-0000-0000-00000000000d') as code \gset
select t.eq((public.gym_check_in_by_code(:'venue_id', lower(:'code')) ->> 'earlier_today')::int, 1, 'by code (any case): second check-in today');
select t.fails(format($$select public.gym_check_in(%L, '00000000-0000-0000-0000-00000000000e')$$, :'venue_id'), 'has no membership at this gym');
select t.fails(format($$select public.gym_check_in_by_code(%L, 'ZZZZZZ')$$, :'venue_id'), 'No member has the code');
select t.as_user('00000000-0000-0000-0000-00000000000f');
select t.fails(format($$select public.gym_check_in(%L, '00000000-0000-0000-0000-00000000000d')$$, :'venue_id'), 'Only the gym''s staff');
select t.as_user('00000000-0000-0000-0000-00000000000d');
select t.eq((select count(*) from public.gym_check_ins)::int, 2, 'the member sees their check-ins');

-- ---- Renewing: starts the day after the current one ends -------------------
select public.gym_request_subscription(:'plan_id') as sub2 \gset
select t.as_user('00000000-0000-0000-0000-00000000000c');
select public.gym_activate_subscription(:'sub2', 1500, 'cash', null);
select t.eq((select start_date from public.gym_subscriptions where id = :'sub2'), public.bhutan_today() + 30, 'a renewal starts after the current membership');
select t.eq((select end_date from public.gym_subscriptions where id = :'sub2'), public.bhutan_today() + 59, 'and runs its full length');
select t.as_user('00000000-0000-0000-0000-00000000000d');
select t.eq((select count(*) from public.notifications where title like 'Your renewal at Peak Fitness is confirmed')::int, 1, 'the member hears the renewal is confirmed');

-- ---- Cancelling ---------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-00000000000e');
select public.gym_request_subscription(:'plan_id') as sub3 \gset
select t.as_user('00000000-0000-0000-0000-00000000000d');
select t.fails(format($$select public.gym_cancel_subscription(%L)$$, :'sub3'), 'can''t cancel');
select t.fails(format($$select public.gym_cancel_subscription(%L)$$, :'sub1'), 'still waiting');
select t.as_user('00000000-0000-0000-0000-00000000000e');
select public.gym_cancel_subscription(:'sub3');
select t.eq((select status from public.gym_subscriptions where id = :'sub3'), 'cancelled', 'a member cancels their own request');

-- ---- Reviews: only people who paid there --------------------------------
select t.fails(format($$select public.save_review(%L, 5, 'Great')$$, :'venue_id'), 'Only members who have used');
select t.as_user('00000000-0000-0000-0000-00000000000c');
select t.fails(format($$select public.save_review(%L, 5, 'Best gym')$$, :'venue_id'), 'venue you run');
select t.as_user('00000000-0000-0000-0000-00000000000d');
select public.save_review(:'venue_id', 4, 'Good equipment');
select public.save_review(:'venue_id', 5, 'Even better now');
select t.eq((select count(*) from public.reviews)::int, 1, 'one review per member');
select t.eq((select rating_average from public.venues where id = :'venue_id'), 5.00::numeric(3,2), 'the venue''s rating follows');
select t.eq((select reviewer_name from public.reviews), 'Meto Member', 'with the reviewer''s name');

-- ---- Dashboard ----------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-00000000000c');
select t.eq((public.gym_dashboard(:'venue_id') ->> 'active')::int, 1, 'dashboard: 1 active member');
select t.eq(public.gym_dashboard(:'venue_id') ->> 'income_this_month', null, 'dashboard: staff do not see income');
select t.eq((public.gym_dashboard(:'venue_id') ->> 'check_ins_today')::int, 2, 'dashboard: check-ins today');
select t.as_user('00000000-0000-0000-0000-00000000000b');
select t.eq((public.gym_dashboard(:'venue_id') ->> 'income_this_month')::int, 3000, 'dashboard: the owner sees income');
select t.as_user('00000000-0000-0000-0000-00000000000f');
select t.fails(format($$select public.gym_dashboard(%L)$$, :'venue_id'), 'Only the gym''s staff');

-- ---- Venue details and photos ---------------------------------------------
select t.as_user('00000000-0000-0000-0000-00000000000b');
select public.update_venue(:'venue_id', '{"photos":["https://example.supabase.co/storage/v1/object/public/venue-photos/a.jpg"]}');
select t.eq((select cardinality(photos) from public.venues where id = :'venue_id'), 1, 'the owner sets photos');
select t.fails(format($$select public.update_venue(%L, '{"photos":["javascript:alert(1)"]}')$$, :'venue_id'), 'uploaded to SportsHub');
insert into storage.objects (bucket_id, name) values ('venue-photos', :'venue_id' || '/a.jpg');
select t.as_user('00000000-0000-0000-0000-00000000000c');
select t.fails(format($$insert into storage.objects (bucket_id, name) values ('venue-photos', %L)$$, :'venue_id' || '/b.jpg'), 'row-level security');
select t.as_user('00000000-0000-0000-0000-00000000000b');
select t.fails($$insert into storage.objects (bucket_id, name) values ('venue-photos', 'not-a-venue/b.jpg')$$, 'row-level security');

-- Sent back, then fixed: it waits again.
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'venue_id', false, 'Add the address');
select t.as_user('00000000-0000-0000-0000-00000000000b');
select public.update_venue(:'venue_id', '{"photos":[]}');
select t.eq((select verification_status from public.venues where id = :'venue_id'), 'rejected', 'changing only photos does not resend it');
select public.update_venue(:'venue_id', '{"address":"Near the clock tower"}');
select t.eq((select verification_status from public.venues where id = :'venue_id'), 'pending', 'fixing its details sends it again');
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'venue_id', true);

-- ---- Every day ------------------------------------------------------------
reset role;
-- The first membership ended yesterday; another member's ends in 3 days.
update public.gym_subscriptions set start_date = public.bhutan_today() - 30, end_date = public.bhutan_today() - 1 where id = :'sub1';
update public.gym_subscriptions set start_date = public.bhutan_today() + 1, end_date = public.bhutan_today() + 30 where id = :'sub2';
insert into public.gym_subscriptions (venue_id, member_id, plan_name, duration_days, price, status, start_date, end_date)
values (:'venue_id', '00000000-0000-0000-0000-00000000000e', 'Monthly', 30, 1500, 'active', public.bhutan_today() - 26, public.bhutan_today() + 3);
insert into public.gym_subscriptions (venue_id, member_id, plan_name, duration_days, price, status, requested_at)
values (:'venue_id', '00000000-0000-0000-0000-00000000000f', 'Monthly', 30, 1500, 'pending', now() - interval '31 days');
select public.gym_daily_maintenance() as daily \gset
select t.eq(:'daily'::jsonb, '{"expired": 1, "reminded": 1, "cancelled": 1}'::jsonb, 'daily: 1 expired, 1 reminded, 1 old request closed');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-00000000000d' and title like '%has ended')::int, 0, 'no "ended" notice when they have renewed');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-00000000000e' and title = 'Your membership ends in 3 days')::int, 1, 'reminder 3 days before the end');
select t.eq(public.gym_daily_maintenance(), '{"expired": 0, "reminded": 0, "cancelled": 0}'::jsonb, 'daily: running again changes nothing');

-- ---- Notifications are private ------------------------------------------
set role authenticated;
select t.as_user('00000000-0000-0000-0000-00000000000e');
select t.eq((select count(*) from public.notifications where user_id <> '00000000-0000-0000-0000-00000000000e')::int, 0, 'nobody reads others'' notifications');
select public.mark_all_notifications_read();
select t.eq((select count(*) from public.notifications where read_at is null)::int, 0, 'mark all read');
select t.fails($$update public.notifications set title = 'x'$$, 'permission denied');

-- ---- Account deletion keeps the gym's money records -------------------------
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000000d';
select t.eq((select count(*) from public.payments where user_id is null)::int, 2, 'payments stay, without the deleted member');
select t.eq((select count(*) from public.gym_subscriptions where member_id = '00000000-0000-0000-0000-00000000000d')::int, 0, 'their memberships go');

\echo ALL SCENARIO CHECKS PASSED
