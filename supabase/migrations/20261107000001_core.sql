-- =====================================================================
-- SportsHub core: what every module shares.
--   profiles (one account for the website and the apps), app_modules,
--   venue_types, venues, venue_staff, reviews, payments, notifications,
--   the helper functions the security rules use, and the functions the
--   app calls.
--
-- Security:
--   * Row Level Security on every table; anon and authenticated get only
--     what is granted below.
--   * Users can't change their own platform role (only the SQL editor can).
--   * Venue roles (owner / manager / staff) are per venue (venue_staff).
--   * Money and statuses change only through the functions here and in the
--     modules' migrations (security definer, roles checked inside).
--   * Unverified venues are hidden from everyone but their staff and admins.
--
-- Functions that take the app's parameters use '#variable_conflict
-- use_column' and copy their parameters into p_ variables, so a parameter
-- named like a column (venue_id) is never mistaken for it.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

-- A short code for each member, typed at a gym's front desk instead of
-- scanning ('4K7P9Q'): no 0/O or 1/I to mix up.
create or replace function public.new_member_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  candidate text;
begin
  loop
    candidate := '';
    for i in 1..6 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.profiles p where p.member_code = candidate);
  end loop;
  return candidate;
end;
$$;

create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null default '' check (char_length(full_name) <= 100),
  email       text check (char_length(email) <= 320),
  phone       text check (phone ~ '^\+[0-9]{8,15}$'),
  dzongkhag   text check (char_length(dzongkhag) <= 40),
  -- 'admin': the SportsHub team, who verify venues and turn modules on and
  -- off. Set only in the SQL editor (README, 'Make yourself an admin').
  role        text not null default 'user' check (role in ('user', 'admin')),
  member_code text not null unique default public.new_member_code(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists profiles_email_idx on public.profiles (lower(email));

-- Each module's switch. The app shows enabled modules only (admins see the
-- others too, to try them), and the router closes a disabled one's pages.
create table if not exists public.app_modules (
  key        text primary key check (key ~ '^[a-z][a-z0-9_]{1,40}$'),
  name       text not null,
  is_enabled boolean not null default false,
  sort_order int not null default 100,
  updated_at timestamptz not null default now()
);

-- The kinds of venue, each run by one module: 'gym' (gym_membership).
create table if not exists public.venue_types (
  key        text primary key check (key ~ '^[a-z][a-z0-9_]{1,40}$'),
  module_key text not null references public.app_modules (key) on delete cascade,
  name       text not null
);

create table if not exists public.venues (
  id                  uuid primary key default gen_random_uuid(),
  type                text not null references public.venue_types (key),
  name                text not null check (char_length(trim(name)) between 2 and 100),
  description         text check (char_length(description) <= 2000),
  dzongkhag           text not null check (dzongkhag in (
                        'Bumthang', 'Chhukha', 'Dagana', 'Gasa', 'Haa', 'Lhuentse', 'Mongar', 'Paro',
                        'Pemagatshel', 'Punakha', 'Samdrup Jongkhar', 'Samtse', 'Sarpang', 'Thimphu',
                        'Trashigang', 'Trashiyangtse', 'Trongsa', 'Tsirang', 'Wangdue Phodrang', 'Zhemgang')),
  town                text check (char_length(town) <= 80),
  address             text check (char_length(address) <= 200),
  phone               text check (phone ~ '^\+[0-9]{8,15}$'),
  whatsapp            text check (whatsapp ~ '^\+[0-9]{8,15}$'),
  latitude            double precision check (latitude between -90 and 90),
  longitude           double precision check (longitude between -180 and 180),
  photos              text[] not null default '{}' check (cardinality(photos) <= 10),
  payment_info        text check (char_length(payment_info) <= 500), -- e.g. the mBoB account
  cancellation_policy text check (char_length(cancellation_policy) <= 1000),
  -- New venues wait for the SportsHub team (review_venue).
  verification_status text not null default 'pending'
                      check (verification_status in ('pending', 'verified', 'rejected')),
  verification_note   text check (char_length(verification_note) <= 500),
  is_verified         boolean generated always as (verification_status = 'verified') stored,
  verified_at         timestamptz,
  verified_by         uuid references public.profiles (id) on delete set null,
  -- Kept by the reviews trigger (section 5).
  rating_average      numeric(3, 2),
  rating_count        int not null default 0,
  created_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint venues_location check ((latitude is null) = (longitude is null))
);
create index if not exists venues_type_idx on public.venues (type, verification_status, dzongkhag);

-- Who runs each venue. One person can own a gym and be a member elsewhere.
create table if not exists public.venue_staff (
  venue_id   uuid not null references public.venues (id) on delete cascade,
  user_id    uuid not null constraint venue_staff_user_id_fkey references public.profiles (id) on delete cascade,
  role       text not null check (role in ('owner', 'manager', 'staff')),
  added_by   uuid constraint venue_staff_added_by_fkey references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (venue_id, user_id)
);
create index if not exists venue_staff_user_idx on public.venue_staff (user_id);

-- One review per person per venue; only people who have paid there.
create table if not exists public.reviews (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references public.venues (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  reviewer_name text not null default '',
  rating        int not null check (rating between 1 and 5),
  comment       text check (char_length(comment) <= 1000),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint reviews_one_per_user unique (venue_id, user_id)
);

-- Every payment at a venue, in any module (gym fees today; ground booking
-- deposits once ground booking moves in). Written only by the modules'
-- functions. Kept when an account is deleted, without the person.
create table if not exists public.payments (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid constraint payments_user_id_fkey references public.profiles (id) on delete set null,
  venue_id     uuid not null references public.venues (id) on delete restrict,
  module_key   text not null references public.app_modules (key),
  reference_id uuid, -- the module's row it pays for (e.g. gym_subscriptions.id)
  amount       int not null check (amount between 1 and 10000000), -- Ngultrum
  method       text not null check (method in ('mbob', 'cash', 'bank', 'other')),
  reference    text check (char_length(reference) <= 100), -- e.g. the mBoB journal number
  status       text not null default 'completed' check (status in ('completed', 'refunded')),
  recorded_by  uuid constraint payments_recorded_by_fkey references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists payments_venue_idx on public.payments (venue_id, created_at desc);
create index if not exists payments_user_idx on public.payments (user_id);

-- In-app notifications, live through Supabase Realtime.
create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  module_key text references public.app_modules (key) on delete set null,
  title      text not null check (char_length(title) <= 200),
  body       text check (char_length(body) <= 1000),
  link       text check (link ~ '^/'), -- the app page it's about
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);


-- ---------------------------------------------------------------------
-- 2. Keeping things in step
-- ---------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
drop trigger if exists venues_updated_at on public.venues;
create trigger venues_updated_at before update on public.venues
  for each row execute function public.set_updated_at();
drop trigger if exists reviews_updated_at on public.reviews;
create trigger reviews_updated_at before update on public.reviews
  for each row execute function public.set_updated_at();
drop trigger if exists app_modules_updated_at on public.app_modules;
create trigger app_modules_updated_at before update on public.app_modules
  for each row execute function public.set_updated_at();

-- A profile for every new account, with the name and phone from sign-up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := nullif(trim(new.raw_user_meta_data ->> 'phone'), '');
begin
  insert into public.profiles (id, full_name, email, phone)
  values (
    new.id,
    left(coalesce(trim(new.raw_user_meta_data ->> 'full_name'), ''), 100),
    lower(new.email),
    case when v_phone ~ '^\+[0-9]{8,15}$' then v_phone end
  )
  on conflict on constraint profiles_pkey do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Staff are added by email, so the profile keeps the login's email.
create or replace function public.handle_user_email_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles p set email = lower(new.email) where p.id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed after update of email on auth.users
  for each row when (old.email is distinct from new.email)
  execute function public.handle_user_email_changed();


-- ---------------------------------------------------------------------
-- 3. Helpers for the security rules and functions
-- ---------------------------------------------------------------------
-- 'security definer' so they read venue_staff and profiles without running
-- into those tables' own rules.

-- The SportsHub team.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin');
$$;

-- The caller's role at [venue]: 'owner', 'manager', 'staff' or null.
create or replace function public.venue_role(venue uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select s.role from public.venue_staff s where s.venue_id = venue and s.user_id = (select auth.uid());
$$;

-- Anyone who works there: owner, manager or staff.
create or replace function public.is_venue_staff(venue uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.venue_role(venue) is not null;
$$;

-- Owners and managers: details, plans, prices, income.
create or replace function public.is_venue_manager(venue uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.venue_role(venue) in ('owner', 'manager'), false);
$$;

create or replace function public.is_venue_owner(venue uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.venue_role(venue) = 'owner', false);
$$;

-- The caller has paid at [venue] (in any module), so may review it.
create or replace function public.has_used_venue(venue uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.payments p
    where p.venue_id = venue and p.user_id = (select auth.uid()) and p.status = 'completed'
  );
$$;

-- Bhutan's date today: memberships start and end on Bhutan dates.
create or replace function public.bhutan_today()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Asia/Thimphu')::date;
$$;

-- Notifications, written only by these. Nobody is told about what they did
-- themselves.
create or replace function public.notify(p_user uuid, p_module text, p_title text, p_body text default null,
                                         p_link text default null)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, module_key, title, body, link)
  select p_user, p_module, p_title, p_body, p_link
  where p_user is not null and p_user is distinct from (select auth.uid());
$$;

create or replace function public.notify_venue_staff(p_venue uuid, p_module text, p_title text, p_body text default null,
                                                     p_link text default null,
                                                     p_roles text[] default array['owner', 'manager', 'staff'])
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, module_key, title, body, link)
  select s.user_id, p_module, p_title, p_body, p_link
  from public.venue_staff s
  where s.venue_id = p_venue and s.role = any (p_roles) and s.user_id is distinct from (select auth.uid());
$$;

create or replace function public.notify_admins(p_title text, p_body text default null, p_link text default null)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, title, body, link)
  select p.id, p_title, p_body, p_link
  from public.profiles p
  where p.role = 'admin' and p.id is distinct from (select auth.uid());
$$;


-- ---------------------------------------------------------------------
-- 4. Who can do what (Row Level Security)
-- ---------------------------------------------------------------------
-- Supabase grants everything to anon and authenticated by default: start
-- from nothing and give back only what the app reads. All writes go
-- through the functions in section 5, except the few columns granted.

alter table public.profiles      enable row level security;
alter table public.app_modules   enable row level security;
alter table public.venue_types   enable row level security;
alter table public.venues        enable row level security;
alter table public.venue_staff   enable row level security;
alter table public.reviews       enable row level security;
alter table public.payments      enable row level security;
alter table public.notifications enable row level security;

revoke all on public.profiles, public.app_modules, public.venue_types, public.venues, public.venue_staff,
  public.reviews, public.payments, public.notifications from anon, authenticated;

grant select on public.app_modules, public.venue_types, public.venues, public.reviews to anon, authenticated;
grant select on public.profiles, public.venue_staff, public.payments, public.notifications to authenticated;
-- Users change only their name, phone and dzongkhag; never their role.
grant update (full_name, phone, dzongkhag) on public.profiles to authenticated;
-- ...and mark their notifications read.
grant update (read_at) on public.notifications to authenticated;

-- profiles
drop policy if exists "profiles: own, and admins" on public.profiles;
create policy "profiles: own, and admins" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "profiles: colleagues at a venue" on public.profiles;
create policy "profiles: colleagues at a venue" on public.profiles for select to authenticated
  using (exists (
    select 1 from public.venue_staff them
    where them.user_id = profiles.id and public.is_venue_staff(them.venue_id)
  ));
drop policy if exists "profiles: update own" on public.profiles;
create policy "profiles: update own" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- app_modules and venue_types: everyone reads them.
drop policy if exists "app_modules: everyone" on public.app_modules;
create policy "app_modules: everyone" on public.app_modules for select to anon, authenticated using (true);
drop policy if exists "venue_types: everyone" on public.venue_types;
create policy "venue_types: everyone" on public.venue_types for select to anon, authenticated using (true);

-- venues: verified ones for everyone; any status for their staff and admins.
drop policy if exists "venues: verified, for visitors" on public.venues;
create policy "venues: verified, for visitors" on public.venues for select to anon
  using (verification_status = 'verified');
drop policy if exists "venues: verified, own and admins" on public.venues;
create policy "venues: verified, own and admins" on public.venues for select to authenticated
  using (verification_status = 'verified' or public.is_venue_staff(id) or (select public.is_admin()));

-- venue_staff: your own places, your colleagues, and admins.
drop policy if exists "venue_staff: own, colleagues and admins" on public.venue_staff;
create policy "venue_staff: own, colleagues and admins" on public.venue_staff for select to authenticated
  using (user_id = (select auth.uid()) or public.is_venue_staff(venue_id) or (select public.is_admin()));

-- reviews: public (only verified venues can be reviewed).
drop policy if exists "reviews: everyone" on public.reviews;
create policy "reviews: everyone" on public.reviews for select to anon, authenticated using (true);

-- payments: the payer, the venue's owner and managers, and admins.
drop policy if exists "payments: payer, venue managers and admins" on public.payments;
create policy "payments: payer, venue managers and admins" on public.payments for select to authenticated
  using (user_id = (select auth.uid()) or public.is_venue_manager(venue_id) or (select public.is_admin()));

-- notifications: your own.
drop policy if exists "notifications: own" on public.notifications;
create policy "notifications: own" on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "notifications: mark own read" on public.notifications;
create policy "notifications: mark own read" on public.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- New notifications reach the bell straight away.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
     ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;


-- ---------------------------------------------------------------------
-- 5. Functions the app calls
-- ---------------------------------------------------------------------

-- A new venue of [details.type], waiting for verification. The caller is
-- its owner. Returns its id.
create or replace function public.register_venue(details jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_details jsonb := register_venue.details;
  v_user uuid := (select auth.uid());
  v_type text := p_details ->> 'type';
  v_id uuid;
  v_name text;
begin
  if v_user is null then
    raise exception 'Please sign in first.';
  end if;
  if not exists (
    select 1 from public.venue_types t join public.app_modules m on m.key = t.module_key
    where t.key = v_type and (m.is_enabled or public.is_admin())
  ) then
    raise exception 'Venues of this kind can''t be registered yet.';
  end if;
  if (select count(*) from public.venue_staff s join public.venues v on v.id = s.venue_id
      where s.user_id = v_user and s.role = 'owner' and v.verification_status = 'pending') >= 3 then
    raise exception 'You already have 3 venues waiting for verification. Wait for the SportsHub team first.';
  end if;

  insert into public.venues (type, name, description, dzongkhag, town, address, phone, whatsapp, payment_info,
                             cancellation_policy, created_by)
  values (
    v_type,
    trim(p_details ->> 'name'),
    nullif(trim(p_details ->> 'description'), ''),
    p_details ->> 'dzongkhag',
    nullif(trim(p_details ->> 'town'), ''),
    nullif(trim(p_details ->> 'address'), ''),
    nullif(trim(p_details ->> 'phone'), ''),
    nullif(trim(p_details ->> 'whatsapp'), ''),
    nullif(trim(p_details ->> 'payment_info'), ''),
    nullif(trim(p_details ->> 'cancellation_policy'), ''),
    v_user
  )
  returning venues.id, venues.name into v_id, v_name;

  insert into public.venue_staff (venue_id, user_id, role, added_by) values (v_id, v_user, 'owner', v_user);

  perform public.notify_admins('New venue to verify', v_name || ' (' || v_type || ') was sent for verification.',
                               '/admin/venues');
  return v_id;
end;
$$;

-- Changes to a venue: its owner or managers, or admins. Only the fields in
-- [details] change; the type never does. A venue that was sent back goes
-- to the SportsHub team again.
create or replace function public.update_venue(venue_id uuid, details jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := update_venue.venue_id;
  p_details jsonb := update_venue.details;
  v_venue public.venues;
  v_photos text[];
  v_resubmit boolean;
begin
  if not (public.is_venue_manager(p_venue) or public.is_admin()) then
    raise exception 'Only the venue''s owner and managers can change it.';
  end if;
  select * into v_venue from public.venues v where v.id = p_venue for update;
  if not found then
    raise exception 'This venue no longer exists.';
  end if;
  -- Sent back, and its details (not just photos) changed: check it again.
  v_resubmit := v_venue.verification_status = 'rejected'
                and exists (select 1 from jsonb_object_keys(p_details) k where k <> 'photos');

  if p_details ? 'photos' then
    v_photos := array(select jsonb_array_elements_text(p_details -> 'photos'));
    if exists (select 1 from unnest(v_photos) u where u !~ '^https://') then
      raise exception 'Photos must be uploaded to SportsHub.';
    end if;
  end if;

  update public.venues v set
    name                = case when p_details ? 'name' then trim(p_details ->> 'name') else v.name end,
    description         = case when p_details ? 'description' then nullif(trim(p_details ->> 'description'), '') else v.description end,
    dzongkhag           = case when p_details ? 'dzongkhag' then p_details ->> 'dzongkhag' else v.dzongkhag end,
    town                = case when p_details ? 'town' then nullif(trim(p_details ->> 'town'), '') else v.town end,
    address             = case when p_details ? 'address' then nullif(trim(p_details ->> 'address'), '') else v.address end,
    phone               = case when p_details ? 'phone' then nullif(trim(p_details ->> 'phone'), '') else v.phone end,
    whatsapp            = case when p_details ? 'whatsapp' then nullif(trim(p_details ->> 'whatsapp'), '') else v.whatsapp end,
    latitude            = case when p_details ? 'latitude' then (p_details ->> 'latitude')::double precision else v.latitude end,
    longitude           = case when p_details ? 'longitude' then (p_details ->> 'longitude')::double precision else v.longitude end,
    photos              = case when p_details ? 'photos' then v_photos else v.photos end,
    payment_info        = case when p_details ? 'payment_info' then nullif(trim(p_details ->> 'payment_info'), '') else v.payment_info end,
    cancellation_policy = case when p_details ? 'cancellation_policy' then nullif(trim(p_details ->> 'cancellation_policy'), '') else v.cancellation_policy end,
    verification_status = case when v_resubmit then 'pending' else v.verification_status end
  where v.id = p_venue;

  if v_resubmit then
    perform public.notify_admins('Venue sent again', v_venue.name || ' was changed and sent for verification again.',
                                 '/admin/venues');
  end if;
end;
$$;

-- Admins verify a venue (it goes live) or send it back with [note].
create or replace function public.review_venue(venue_id uuid, approve boolean, note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := review_venue.venue_id;
  p_approve boolean := review_venue.approve;
  p_note text := nullif(trim(review_venue.note), '');
  v_name text;
begin
  if not public.is_admin() then
    raise exception 'Only the SportsHub team can verify venues.';
  end if;
  if not p_approve and p_note is null then
    raise exception 'Say why it is sent back, so the owner can fix it.';
  end if;
  update public.venues v set
    verification_status = case when p_approve then 'verified' else 'rejected' end,
    verification_note   = case when p_approve then null else p_note end,
    verified_at         = case when p_approve then now() else null end,
    verified_by         = case when p_approve then (select auth.uid()) else null end
  where v.id = p_venue
  returning v.name into v_name;
  if v_name is null then
    raise exception 'This venue no longer exists.';
  end if;
  perform public.notify_venue_staff(
    p_venue, null,
    case when p_approve then v_name || ' is live on SportsHub' else v_name || ' needs changes' end,
    case when p_approve then 'Members can now find it and join.' else p_note end,
    '/manage/' || p_venue, array['owner', 'manager']);
end;
$$;

-- The owner adds someone with a SportsHub account, by email, as manager or
-- staff (or changes their role).
create or replace function public.add_venue_staff(venue_id uuid, email text, staff_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := add_venue_staff.venue_id;
  p_email text := lower(trim(add_venue_staff.email));
  p_role text := add_venue_staff.staff_role;
  v_user uuid;
  v_name text;
begin
  if not (public.is_venue_owner(p_venue) or public.is_admin()) then
    raise exception 'Only the venue''s owner can add staff.';
  end if;
  if p_role not in ('manager', 'staff') then
    raise exception 'Staff are managers or staff.';
  end if;
  select p.id into v_user from public.profiles p where lower(p.email) = p_email;
  if v_user is null then
    raise exception 'No SportsHub account uses %. Ask them to sign up first.', p_email;
  end if;
  if exists (select 1 from public.venue_staff s where s.venue_id = p_venue and s.user_id = v_user and s.role = 'owner') then
    raise exception 'They own this venue already.';
  end if;
  insert into public.venue_staff (venue_id, user_id, role, added_by)
  values (p_venue, v_user, p_role, (select auth.uid()))
  on conflict on constraint venue_staff_pkey do update set role = excluded.role;

  select v.name into v_name from public.venues v where v.id = p_venue;
  perform public.notify(v_user, null, 'You were added to ' || v_name,
                        'You are ' || p_role || ' there. Find it under Your venues.', '/manage/' || p_venue);
end;
$$;

create or replace function public.remove_venue_staff(venue_id uuid, staff_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := remove_venue_staff.venue_id;
  p_user uuid := remove_venue_staff.staff_user_id;
begin
  if not (public.is_venue_owner(p_venue) or public.is_admin()) then
    raise exception 'Only the venue''s owner can remove staff.';
  end if;
  if exists (select 1 from public.venue_staff s where s.venue_id = p_venue and s.user_id = p_user and s.role = 'owner') then
    raise exception 'The owner can''t be removed. Ask the SportsHub team to hand the venue over.';
  end if;
  delete from public.venue_staff s where s.venue_id = p_venue and s.user_id = p_user;
end;
$$;

-- A review (or a change to the caller's): only people who have paid at the
-- venue, and not its own staff.
create or replace function public.save_review(venue_id uuid, rating int, comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := save_review.venue_id;
  p_rating int := save_review.rating;
  p_comment text := nullif(trim(save_review.comment), '');
  v_user uuid := (select auth.uid());
  v_name text;
begin
  if v_user is null then
    raise exception 'Please sign in first.';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Give 1 to 5 stars.';
  end if;
  if not exists (select 1 from public.venues v where v.id = p_venue and v.verification_status = 'verified') then
    raise exception 'This venue isn''t on SportsHub.';
  end if;
  if public.is_venue_staff(p_venue) then
    raise exception 'You can''t review a venue you run.';
  end if;
  if not public.has_used_venue(p_venue) then
    raise exception 'Only members who have used this venue can review it.';
  end if;
  select coalesce(nullif(trim(p.full_name), ''), 'Member') into v_name from public.profiles p where p.id = v_user;
  insert into public.reviews (venue_id, user_id, reviewer_name, rating, comment)
  values (p_venue, v_user, v_name, p_rating, p_comment)
  on conflict on constraint reviews_one_per_user do update
    set rating = excluded.rating, comment = excluded.comment, reviewer_name = excluded.reviewer_name;
  perform public.notify_venue_staff(p_venue, null, 'New review: ' || p_rating || ' stars', p_comment,
                                    '/manage/' || p_venue, array['owner', 'manager']);
end;
$$;

create or replace function public.delete_my_review(venue_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.reviews r where r.venue_id = delete_my_review.venue_id and r.user_id = (select auth.uid());
$$;

-- Keeps venues.rating_average and rating_count.
create or replace function public.refresh_venue_rating()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue uuid := coalesce(new.venue_id, old.venue_id);
begin
  update public.venues v set
    rating_average = (select round(avg(r.rating)::numeric, 2) from public.reviews r where r.venue_id = v_venue),
    rating_count   = (select count(*) from public.reviews r where r.venue_id = v_venue)
  where v.id = v_venue;
  return null;
end;
$$;

drop trigger if exists reviews_refresh_rating on public.reviews;
create trigger reviews_refresh_rating after insert or update or delete on public.reviews
  for each row execute function public.refresh_venue_rating();

-- Admins turn a module on or off.
create or replace function public.set_module_enabled(module_key text, enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not public.is_admin() then
    raise exception 'Only the SportsHub team can turn modules on and off.';
  end if;
  update public.app_modules m set is_enabled = set_module_enabled.enabled where m.key = set_module_enabled.module_key;
  if not found then
    raise exception 'There is no module %.', set_module_enabled.module_key;
  end if;
end;
$$;

create or replace function public.mark_all_notifications_read()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.notifications n set read_at = now() where n.user_id = (select auth.uid()) and n.read_at is null;
$$;


-- ---------------------------------------------------------------------
-- 6. Who can call which function
-- ---------------------------------------------------------------------
-- Functions are callable by everyone unless revoked: revoke all, then give
-- the signed-in app what it calls. Helpers the rules use stay callable by
-- signed-in users (they only ever answer about the caller).

revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.is_admin(), public.venue_role(uuid), public.is_venue_staff(uuid),
  public.is_venue_manager(uuid), public.is_venue_owner(uuid), public.has_used_venue(uuid), public.bhutan_today()
  to authenticated;

grant execute on function public.register_venue(jsonb), public.update_venue(uuid, jsonb),
  public.review_venue(uuid, boolean, text), public.add_venue_staff(uuid, text, text),
  public.remove_venue_staff(uuid, uuid), public.save_review(uuid, int, text), public.delete_my_review(uuid),
  public.set_module_enabled(text, boolean), public.mark_all_notifications_read()
  to authenticated;


-- ---------------------------------------------------------------------
-- 7. Storage: venue photos (public)
-- ---------------------------------------------------------------------
-- Files go in a folder named after the venue's id; only its owner,
-- managers and admins upload or remove them. Anyone can view them.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('venue-photos', 'venue-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create or replace function public.can_edit_venue_folder(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_folder text := (storage.foldername(object_name))[1];
begin
  if v_folder !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return public.is_venue_manager(v_folder::uuid) or public.is_admin();
end;
$$;
revoke execute on function public.can_edit_venue_folder(text) from public, anon;
grant execute on function public.can_edit_venue_folder(text) to authenticated;

drop policy if exists "venue-photos: venue managers upload" on storage.objects;
create policy "venue-photos: venue managers upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'venue-photos' and public.can_edit_venue_folder(name));
drop policy if exists "venue-photos: venue managers replace" on storage.objects;
create policy "venue-photos: venue managers replace" on storage.objects for update to authenticated
  using (bucket_id = 'venue-photos' and public.can_edit_venue_folder(name))
  with check (bucket_id = 'venue-photos' and public.can_edit_venue_folder(name));
drop policy if exists "venue-photos: venue managers remove" on storage.objects;
create policy "venue-photos: venue managers remove" on storage.objects for delete to authenticated
  using (bucket_id = 'venue-photos' and public.can_edit_venue_folder(name));
