-- Test data for a LOCAL database only (supabase db reset runs it). Never
-- run it on the live project.
--
-- Turns gym membership on and adds one verified demo gym with plans, so
-- the gym pages have something to show. To run it as its owner, sign up
-- in the app, then in the SQL editor:
--   insert into public.venue_staff (venue_id, user_id, role)
--   select '11111111-1111-1111-1111-111111111111', id, 'owner' from public.profiles where email = 'you@example.com';

update public.app_modules set is_enabled = true where key = 'gym_membership';

insert into public.venues (id, type, name, description, dzongkhag, town, address, phone, payment_info,
                           cancellation_policy, verification_status, verified_at)
values (
  '11111111-1111-1111-1111-111111111111', 'gym', 'Demo Fitness Centre',
  'Free weights, machines and a cardio floor. Open 6 am to 9 pm, Monday to Saturday.',
  'Thimphu', 'Changzamtog', 'Above the demo bakery', '+97517000000',
  'mBoB account 200000000 (Demo Fitness), or cash at the front desk.',
  'Memberships are not refunded once they have started.',
  'verified', now()
)
on conflict (id) do nothing;

insert into public.gym_plans (venue_id, name, description, duration_days, price, sort_order)
select '11111111-1111-1111-1111-111111111111', name, description, days, price, sort_order
from (values
  ('Day pass', 'One visit', 1, 150, 1),
  ('Monthly', 'All equipment', 30, 1500, 2),
  ('3 months', 'All equipment', 90, 4000, 3),
  ('Yearly', 'All equipment and one free personal training session', 365, 14000, 4)
) as p(name, description, days, price, sort_order)
where not exists (select 1 from public.gym_plans where venue_id = '11111111-1111-1111-1111-111111111111');
