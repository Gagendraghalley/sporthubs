-- Removes what supabase/test_users.sql made: the test accounts
-- (every *@example.com account) and SportsHub Test Gym, with its packages, members,
-- check-ins and payments, and its organisation once no other venue is in it.
-- Supabase -> SQL Editor, paste, Run.

begin;
create temporary table test_gym_organisation on commit drop as
  select organisation_id from public.venues where id = '7e570000-0000-4000-8000-000000000001';
-- Payments keep their venue (they're the gym's books), so they go first.
delete from public.payments where venue_id = '7e570000-0000-4000-8000-000000000001';
delete from public.venues where id = '7e570000-0000-4000-8000-000000000001';
-- With its own roles and its changes to SportsHub's.
delete from public.organisations o
using test_gym_organisation t
where o.id = t.organisation_id and not exists (select 1 from public.venues v where v.organisation_id = o.id);
-- With their profiles, roles and memberships.
delete from auth.users where email like '%@example.com';
commit;
