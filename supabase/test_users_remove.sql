-- Removes what supabase/test_users.sql made: the test accounts
-- (every *@example.com account) and SportsHub Test Gym, with its packages, members,
-- check-ins and payments. Supabase -> SQL Editor, paste, Run.

begin;
-- Payments keep their venue (they're the gym's books), so they go first.
delete from public.payments where venue_id = '7e570000-0000-4000-8000-000000000001';
delete from public.venues where id = '7e570000-0000-4000-8000-000000000001';
-- With their profiles, roles and memberships.
delete from auth.users where email like '%@example.com';
commit;
