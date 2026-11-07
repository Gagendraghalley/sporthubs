-- =====================================================================
-- Module 1: ground booking.
-- Grounds and tournaments still run on the ground booking website, with
-- its own database; SportsHub links to it, so this module has no tables
-- here yet. When ground booking moves into SportsHub (one domain), its
-- tables go in a new migration (prefixed ground_, linked to venues), its
-- venue types into venue_types, and its deposits into payments.
-- =====================================================================

insert into public.app_modules (key, name, is_enabled, sort_order)
values ('ground_booking', 'Ground booking', true, 10)
on conflict (key) do nothing;
