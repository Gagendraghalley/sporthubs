-- =====================================================================
-- Gym membership: members registered at the front desk.
--
-- Most of a gym's members walk in: the front desk registers them (no
-- SportsHub account needed), snaps their photo, sells them a package for a
-- number of months, and gives them a QR card (sent on WhatsApp). They show
-- it at the counter to check in.
--
--   gym_members     the gym's register: details, photo, member code, and
--                   the QR card's secret token (reissued if a card is lost)
--   gym_subscriptions and gym_check_ins now belong to an account member
--                   (member_id, as before) or a registered one
--                   (gym_member_id): exactly one of the two
--   payments.payer_name  who paid, for payers without an account
--
-- The QR card holds only 'sportshub:gym-member:<token>'. Their details
-- (phone, birthday, medical notes) stay in the register, for the gym's
-- staff with 'gym.members'; the card's picture shows their name, code and
-- expiry.
--
-- 'gym.register' (new) registers members and changes their details;
-- selling them a package takes 'gym.payments' too.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

create table if not exists public.gym_members (
  id                      uuid primary key default gen_random_uuid(),
  venue_id                uuid not null references public.venues (id) on delete cascade,
  -- Typed at the desk instead of scanning; unique across account members'
  -- codes too, so a code is never two people.
  code                    text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  -- What the QR card holds; a new one makes the old card useless.
  qr_token                text not null unique check (qr_token ~ '^[0-9a-f]{32}$'),
  full_name               text not null check (char_length(trim(full_name)) between 2 and 100),
  phone                   text not null check (phone ~ '^\+[0-9]{8,15}$'),
  email                   text check (char_length(email) <= 320 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  date_of_birth           date check (date_of_birth >= '1900-01-01'),
  blood_group             text check (blood_group in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
  occupation              text check (char_length(occupation) <= 80),
  dzongkhag_id            smallint references public.dzongkhags (id),
  gewog_id                int references public.gewogs (id),
  village_id              int references public.villages (id),
  emergency_contact_name  text check (char_length(emergency_contact_name) <= 100),
  emergency_contact_phone text check (emergency_contact_phone ~ '^\+[0-9]{8,15}$'),
  medical_notes           text check (char_length(medical_notes) <= 1000),
  -- In the private gym-member-photos bucket: '<venue id>/<file>'.
  photo_path              text check (photo_path ~ '^[0-9a-f-]{36}/[0-9A-Za-z._-]{1,100}$'),
  joined_on               date not null,
  created_by              uuid constraint gym_members_created_by_fkey references public.profiles (id) on delete set null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create index if not exists gym_members_venue_name_idx on public.gym_members (venue_id, lower(full_name));
create index if not exists gym_members_venue_phone_idx on public.gym_members (venue_id, phone);

drop trigger if exists gym_members_updated_at on public.gym_members;
create trigger gym_members_updated_at before update on public.gym_members
  for each row execute function public.set_updated_at();

-- Memberships and check-ins: an account member or a registered one.
alter table public.gym_subscriptions alter column member_id drop not null;
alter table public.gym_subscriptions add column if not exists gym_member_id uuid;
alter table public.gym_check_ins alter column member_id drop not null;
alter table public.gym_check_ins add column if not exists gym_member_id uuid;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'gym_subscriptions_gym_member_id_fkey') then
    alter table public.gym_subscriptions add constraint gym_subscriptions_gym_member_id_fkey
      foreign key (gym_member_id) references public.gym_members (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'gym_subscriptions_one_member') then
    alter table public.gym_subscriptions add constraint gym_subscriptions_one_member
      check ((member_id is null) <> (gym_member_id is null));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'gym_check_ins_gym_member_id_fkey') then
    alter table public.gym_check_ins add constraint gym_check_ins_gym_member_id_fkey
      foreign key (gym_member_id) references public.gym_members (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'gym_check_ins_one_member') then
    alter table public.gym_check_ins add constraint gym_check_ins_one_member
      check ((member_id is null) <> (gym_member_id is null));
  end if;
end;
$$;
create index if not exists gym_subscriptions_gym_member_idx on public.gym_subscriptions (gym_member_id);
create index if not exists gym_check_ins_gym_member_idx on public.gym_check_ins (gym_member_id, checked_in_at desc);

-- Who paid, for payers without a SportsHub account (any module).
alter table public.payments add column if not exists payer_name text check (char_length(payer_name) <= 100);

-- 'gym.register', given to the roles that sell memberships at the desk.
do $$
declare
  v_new boolean;
begin
  with saved as (
    insert into public.permissions (key, scope, module_key, name, description, sort_order)
    values ('gym.register', 'venue', 'gym_membership', 'Register members',
            'Register members at the front desk, change their details and photo, reissue their cards', 105)
    on conflict (key) do update
      set name = excluded.name, description = excluded.description, sort_order = excluded.sort_order
    returning (xmax = 0) as inserted
  )
  select inserted into v_new from saved;
  if v_new then
    insert into public.role_permissions (role_id, permission_key)
    select r.id, 'gym.register' from public.roles r where r.key in ('owner', 'manager', 'staff')
    on conflict do nothing;
  end if;
end;
$$;


-- ---------------------------------------------------------------------
-- 2. Who can read what
-- ---------------------------------------------------------------------

alter table public.gym_members enable row level security;
revoke all on public.gym_members from anon, authenticated;
grant select on public.gym_members to authenticated;

drop policy if exists "gym_members: who sees members" on public.gym_members;
create policy "gym_members: who sees members" on public.gym_members for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.members'));

-- Photos: private. Seen by whoever sees the gym's members; changed by whoever
-- registers them. Files go in a folder named after the venue's id.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('gym-member-photos', 'gym-member-photos', false, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create or replace function public.gym_member_photo_access(object_name text, perm text)
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
  return public.has_venue_permission(v_folder::uuid, perm);
end;
$$;
revoke execute on function public.gym_member_photo_access(text, text) from public, anon;
grant execute on function public.gym_member_photo_access(text, text) to authenticated;

drop policy if exists "gym-member-photos: who sees members" on storage.objects;
create policy "gym-member-photos: who sees members" on storage.objects for select to authenticated
  using (bucket_id = 'gym-member-photos' and public.gym_member_photo_access(name, 'gym.members'));
drop policy if exists "gym-member-photos: who registers upload" on storage.objects;
create policy "gym-member-photos: who registers upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'gym-member-photos' and public.gym_member_photo_access(name, 'gym.register'));
drop policy if exists "gym-member-photos: who registers replace" on storage.objects;
create policy "gym-member-photos: who registers replace" on storage.objects for update to authenticated
  using (bucket_id = 'gym-member-photos' and public.gym_member_photo_access(name, 'gym.register'))
  with check (bucket_id = 'gym-member-photos' and public.gym_member_photo_access(name, 'gym.register'));
drop policy if exists "gym-member-photos: who registers remove" on storage.objects;
create policy "gym-member-photos: who registers remove" on storage.objects for delete to authenticated
  using (bucket_id = 'gym-member-photos' and public.gym_member_photo_access(name, 'gym.register'));


-- ---------------------------------------------------------------------
-- 3. Helpers (not callable by the app)
-- ---------------------------------------------------------------------

-- A member code no account member or registered member has.
create or replace function public.gym_new_member_code()
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
    exit when not exists (select 1 from public.profiles p where p.member_code = candidate)
          and not exists (select 1 from public.gym_members m where m.code = candidate);
  end loop;
  return candidate;
end;
$$;

-- A QR card's secret: 128 random bits as 32 hex characters.
create or replace function public.gym_new_qr_token()
returns text
language sql
volatile
set search_path = ''
as $$
  select replace(gen_random_uuid()::text, '-', '');
$$;

-- [details] (the registration form) as a gym_members row, checked and
-- tidied; the caller adds the ids, code, token and photo. The place is
-- filled upwards from the village (or gewog) chosen.
create or replace function public.gym_member_from_details(details jsonb)
returns public.gym_members
language plpgsql
stable
set search_path = ''
as $$
declare
  d jsonb := coalesce(details, '{}'::jsonb);
  m public.gym_members;
  v_today date := public.bhutan_today();
  v_text text;
begin
  m.full_name := regexp_replace(trim(coalesce(d ->> 'full_name', '')), '\s+', ' ', 'g');
  if char_length(m.full_name) not between 2 and 100 then
    raise exception 'Enter their name.';
  end if;
  m.phone := regexp_replace(coalesce(d ->> 'phone', ''), '[\s()-]', '', 'g');
  if m.phone ~ '^[0-9]{8}$' then
    m.phone := '+975' || m.phone;
  end if;
  if m.phone !~ '^\+[0-9]{8,15}$' then
    raise exception 'Enter their phone number, e.g. 17123456.';
  end if;
  m.email := nullif(lower(trim(coalesce(d ->> 'email', ''))), '');
  if m.email is not null and m.email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'That email doesn''t look right.';
  end if;

  begin
    m.date_of_birth := nullif(trim(coalesce(d ->> 'date_of_birth', '')), '')::date;
    m.joined_on := coalesce(nullif(trim(coalesce(d ->> 'joined_on', '')), '')::date, v_today);
  exception when others then
    raise exception 'Enter the dates as YYYY-MM-DD.';
  end;
  if m.date_of_birth is not null and (m.date_of_birth < date '1900-01-01' or m.date_of_birth > v_today) then
    raise exception 'Check their date of birth.';
  end if;
  if m.joined_on < v_today - 3650 or m.joined_on > v_today + 60 then
    raise exception 'Check the date of joining.';
  end if;

  m.blood_group := nullif(upper(trim(coalesce(d ->> 'blood_group', ''))), '');
  if m.blood_group is not null and m.blood_group not in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-') then
    raise exception 'Choose their blood group from the list.';
  end if;
  m.occupation := nullif(left(trim(coalesce(d ->> 'occupation', '')), 80), '');
  m.emergency_contact_name := nullif(left(regexp_replace(trim(coalesce(d ->> 'emergency_contact_name', '')), '\s+', ' ', 'g'), 100), '');
  v_text := regexp_replace(coalesce(d ->> 'emergency_contact_phone', ''), '[\s()-]', '', 'g');
  if v_text ~ '^[0-9]{8}$' then
    v_text := '+975' || v_text;
  end if;
  m.emergency_contact_phone := nullif(v_text, '');
  if m.emergency_contact_phone is not null and m.emergency_contact_phone !~ '^\+[0-9]{8,15}$' then
    raise exception 'Enter the emergency contact''s phone number, e.g. 17123456.';
  end if;
  m.medical_notes := nullif(trim(coalesce(d ->> 'medical_notes', '')), '');
  if char_length(m.medical_notes) > 1000 then
    raise exception 'Keep the medical notes under 1000 letters.';
  end if;

  -- The place: as far down as they chose, filled upwards.
  m.village_id := nullif(d ->> 'village_id', '')::int;
  m.gewog_id := nullif(d ->> 'gewog_id', '')::int;
  m.dzongkhag_id := nullif(d ->> 'dzongkhag_id', '')::smallint;
  if m.village_id is not null then
    select v.gewog_id into m.gewog_id from public.villages v where v.id = m.village_id;
    if not found then
      raise exception 'Choose the village from the list.';
    end if;
  end if;
  if m.gewog_id is not null then
    select g.dzongkhag_id into m.dzongkhag_id from public.gewogs g where g.id = m.gewog_id;
    if not found then
      raise exception 'Choose the gewog from the list.';
    end if;
  end if;
  if m.dzongkhag_id is not null and not exists (select 1 from public.dzongkhags z where z.id = m.dzongkhag_id) then
    raise exception 'Choose the dzongkhag from the list.';
  end if;
  return m;
end;
$$;

-- A membership of [plan] for [months] months from [start] for [member],
-- paid [amount] (recorded in payments unless 0). Ended already (an old
-- member entered late) if it ran out before today.
create or replace function public.gym_add_membership(member public.gym_members, plan_id uuid, months int, start date,
                                                     amount int, method text, reference text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_member public.gym_members := gym_add_membership.member;
  p_months int := gym_add_membership.months;
  p_start date := gym_add_membership.start;
  p_amount int := gym_add_membership.amount;
  p_method text := gym_add_membership.method;
  p_reference text := nullif(trim(gym_add_membership.reference), '');
  v_plan public.gym_plans;
  v_end date;
  v_status text;
  v_sub uuid;
  v_payment uuid;
begin
  if not public.has_venue_permission(p_member.venue_id, 'gym.payments') then
    raise exception 'Your role here can register members but not sell them a package.';
  end if;
  select * into v_plan from public.gym_plans pl where pl.id = gym_add_membership.plan_id and pl.venue_id = p_member.venue_id;
  if not found or not v_plan.is_active then
    raise exception 'Choose one of the gym''s packages.';
  end if;
  if p_months is null or p_months not between 1 and 36 then
    raise exception 'Choose how many months (1 to 36).';
  end if;
  if p_amount is null or p_amount < 0 or p_amount > 1000000 then
    raise exception 'Enter the amount received.';
  end if;
  if p_amount > 0 and (p_method is null or p_method not in ('mbob', 'cash', 'bank', 'other')) then
    raise exception 'Choose how they paid.';
  end if;
  v_end := (p_start + make_interval(months => p_months))::date - 1;
  v_status := case when v_end < public.bhutan_today() then 'expired' else 'active' end;

  insert into public.gym_subscriptions (venue_id, gym_member_id, plan_id, plan_name, duration_days, price, status,
                                        start_date, end_date, activated_at, activated_by)
  values (p_member.venue_id, p_member.id, v_plan.id, v_plan.name, v_end - p_start + 1, p_amount, v_status,
          p_start, v_end, now(), (select auth.uid()))
  returning gym_subscriptions.id into v_sub;

  if p_amount > 0 then
    insert into public.payments (venue_id, module_key, reference_id, amount, method, reference, recorded_by, payer_name)
    values (p_member.venue_id, 'gym_membership', v_sub, p_amount, p_method, p_reference, (select auth.uid()),
            p_member.full_name)
    returning payments.id into v_payment;
    update public.gym_subscriptions s set payment_id = v_payment where s.id = v_sub;
  end if;

  return jsonb_build_object('subscription_id', v_sub, 'start_date', p_start, 'end_date', v_end, 'status', v_status,
                            'payment_id', v_payment);
end;
$$;

-- Checks in [gym_member] (registered at [venue]): as gym_check_in, with
-- their photo and medical notes for the desk.
create or replace function public.gym_check_in_registered(venue uuid, gym_member uuid)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_today date := public.bhutan_today();
  v_member public.gym_members;
  v_sub public.gym_subscriptions;
  v_other public.gym_subscriptions;
  v_earlier int;
begin
  select * into v_member from public.gym_members m where m.id = gym_member and m.venue_id = venue;
  if not found then
    raise exception 'That member isn''t registered at this gym.';
  end if;
  select * into v_sub from public.gym_subscriptions s
  where s.gym_member_id = v_member.id and s.status = 'active' and s.start_date <= v_today and s.end_date >= v_today
  order by s.end_date desc
  limit 1;
  if v_sub.id is null then
    select * into v_other from public.gym_subscriptions s
    where s.gym_member_id = v_member.id and s.status in ('active', 'expired')
    order by case when s.status = 'active' then 0 else 1 end, s.end_date desc
    limit 1;
    if v_other.id is null then
      raise exception '% has no package yet. Sell them one on their page.', v_member.full_name;
    elsif v_other.status = 'active' then
      raise exception '%''s package starts on %.', v_member.full_name, to_char(v_other.start_date, 'FMDD Mon YYYY');
    else
      raise exception '%''s package ended on %. Renew it on their page.', v_member.full_name,
        to_char(v_other.end_date, 'FMDD Mon YYYY');
    end if;
  end if;

  select count(*) into v_earlier from public.gym_check_ins c
  where c.gym_member_id = v_member.id and (c.checked_in_at at time zone 'Asia/Thimphu')::date = v_today;
  insert into public.gym_check_ins (venue_id, gym_member_id, subscription_id, recorded_by)
  values (venue, v_member.id, v_sub.id, (select auth.uid()));

  return jsonb_build_object(
    'member_name', v_member.full_name,
    'member_code', v_member.code,
    'gym_member_id', v_member.id,
    'photo_path', v_member.photo_path,
    'medical_notes', v_member.medical_notes,
    'plan_name', v_sub.plan_name,
    'end_date', v_sub.end_date,
    'days_left', v_sub.end_date - v_today + 1,
    'earlier_today', v_earlier
  );
end;
$$;


-- ---------------------------------------------------------------------
-- 4. Functions the app calls
-- ---------------------------------------------------------------------

-- Registers a member at [venue_id] from the form's [details], and, with a
-- [plan_id], sells them that package for [months] months from the date of
-- joining. Returns their id, code and QR token, and the membership.
create or replace function public.gym_register_member(venue_id uuid, details jsonb, plan_id uuid default null,
                                                      months int default null, amount int default 0,
                                                      method text default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_register_member.venue_id;
  m public.gym_members;
  v_existing text;
  v_membership jsonb;
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'gym.register') then
    raise exception 'Only the gym''s staff who register members can do this.';
  end if;
  m := public.gym_member_from_details(details);
  select g.code into v_existing from public.gym_members g
  where g.venue_id = p_venue and g.phone = m.phone and lower(g.full_name) = lower(m.full_name);
  if v_existing is not null then
    raise exception '% is already registered here (member code %).', m.full_name, v_existing;
  end if;

  m.id := gen_random_uuid();
  m.venue_id := p_venue;
  m.code := public.gym_new_member_code();
  m.qr_token := public.gym_new_qr_token();
  m.created_by := (select auth.uid());
  m.created_at := now();
  m.updated_at := now();
  insert into public.gym_members select m.*;

  if gym_register_member.plan_id is not null then
    v_membership := public.gym_add_membership(m, gym_register_member.plan_id, gym_register_member.months, m.joined_on,
                                              coalesce(gym_register_member.amount, 0), gym_register_member.method,
                                              gym_register_member.reference);
  end if;

  return jsonb_build_object('gym_member_id', m.id, 'code', m.code, 'qr_token', m.qr_token, 'membership', v_membership);
end;
$$;

-- Changes a registered member's details (the whole form).
create or replace function public.gym_update_member(gym_member_id uuid, details jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  m public.gym_members;
begin
  select * into v_member from public.gym_members g where g.id = gym_update_member.gym_member_id for update;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.has_venue_permission(v_member.venue_id, 'gym.register') then
    raise exception 'Only the gym''s staff who register members can change their details.';
  end if;
  m := public.gym_member_from_details(details);
  update public.gym_members g set
    full_name = m.full_name, phone = m.phone, email = m.email, date_of_birth = m.date_of_birth,
    blood_group = m.blood_group, occupation = m.occupation, dzongkhag_id = m.dzongkhag_id, gewog_id = m.gewog_id,
    village_id = m.village_id, emergency_contact_name = m.emergency_contact_name,
    emergency_contact_phone = m.emergency_contact_phone, medical_notes = m.medical_notes, joined_on = m.joined_on
  where g.id = v_member.id;
end;
$$;

-- The photo uploaded for them, in their gym's folder (null: no photo).
create or replace function public.gym_set_member_photo(gym_member_id uuid, photo_path text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  p_path text := nullif(trim(gym_set_member_photo.photo_path), '');
begin
  select * into v_member from public.gym_members g where g.id = gym_set_member_photo.gym_member_id for update;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.has_venue_permission(v_member.venue_id, 'gym.register') then
    raise exception 'Only the gym''s staff who register members can change their photo.';
  end if;
  if p_path is not null and p_path not like v_member.venue_id::text || '/%' then
    raise exception 'The photo must be uploaded to this gym''s folder.';
  end if;
  update public.gym_members g set photo_path = p_path where g.id = v_member.id;
end;
$$;

-- A new QR card: the old one stops working. Returns the new token.
create or replace function public.gym_reissue_member_qr(gym_member_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  v_token text := public.gym_new_qr_token();
begin
  select * into v_member from public.gym_members g where g.id = gym_reissue_member_qr.gym_member_id for update;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.has_venue_permission(v_member.venue_id, 'gym.register') then
    raise exception 'Only the gym''s staff who register members can issue cards.';
  end if;
  update public.gym_members g set qr_token = v_token where g.id = v_member.id;
  return v_token;
end;
$$;

-- Sells a registered member another package: from the day after their
-- current one ends, or today if it has.
create or replace function public.gym_renew_member(gym_member_id uuid, plan_id uuid, months int, amount int,
                                                   method text default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  v_last_end date;
  v_today date := public.bhutan_today();
begin
  select * into v_member from public.gym_members g where g.id = gym_renew_member.gym_member_id;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  -- Serialises renewals of the same member.
  perform 1 from public.gym_members g where g.id = v_member.id for update;
  select max(s.end_date) into v_last_end from public.gym_subscriptions s
  where s.gym_member_id = v_member.id and s.status = 'active';
  return public.gym_add_membership(v_member, gym_renew_member.plan_id, gym_renew_member.months,
                                   greatest(v_today, coalesce(v_last_end + 1, v_today)), gym_renew_member.amount,
                                   gym_renew_member.method, gym_renew_member.reference);
end;
$$;

-- Checks in whoever's QR card this is.
create or replace function public.gym_check_in_member(venue_id uuid, qr_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_check_in_member.venue_id;
  v_member public.gym_members;
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'gym.check_in') then
    raise exception 'Only the gym''s staff can check members in.';
  end if;
  select * into v_member from public.gym_members g where g.qr_token = lower(trim(gym_check_in_member.qr_token));
  if not found then
    raise exception 'This card isn''t valid any more. Ask for their member code, or give them a new card.';
  end if;
  if v_member.venue_id <> p_venue then
    raise exception 'This card is for another gym.';
  end if;
  return public.gym_check_in_registered(p_venue, v_member.id);
end;
$$;

-- By the member code typed at the desk: this gym's registered members
-- first, then SportsHub account members.
create or replace function public.gym_check_in_by_code(venue_id uuid, code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_check_in_by_code.venue_id;
  p_code text := upper(regexp_replace(coalesce(gym_check_in_by_code.code, ''), '[\s-]', '', 'g'));
  v_registered public.gym_members;
  v_member uuid;
begin
  if not public.has_venue_permission(p_venue, 'gym.check_in') then
    raise exception 'Only the gym''s staff can check members in.';
  end if;
  select * into v_registered from public.gym_members g where g.code = p_code;
  if found then
    if v_registered.venue_id <> p_venue then
      raise exception 'Member % is registered at another gym.', p_code;
    end if;
    return public.gym_check_in_registered(p_venue, v_registered.id);
  end if;
  select p.id into v_member from public.profiles p where p.member_code = p_code;
  if v_member is null then
    raise exception 'No member has the code %.', p_code;
  end if;
  return public.gym_check_in(p_venue, v_member);
end;
$$;

-- A gym's numbers, counting registered members too.
create or replace function public.gym_dashboard(venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_dashboard.venue_id;
  v_today date := public.bhutan_today();
  -- The 1st of this month, midnight in Bhutan.
  v_month_start timestamptz := date_trunc('month', v_today::timestamp) at time zone 'Asia/Thimphu';
begin
  if not (public.is_venue_staff(p_venue) or public.is_admin()) then
    raise exception 'Only the gym''s staff can see this.';
  end if;
  return jsonb_build_object(
    'pending', (select count(*) from public.gym_subscriptions s where s.venue_id = p_venue and s.status = 'pending'),
    'active', (select count(distinct coalesce(s.member_id, s.gym_member_id)) from public.gym_subscriptions s
               where s.venue_id = p_venue and s.status = 'active' and s.start_date <= v_today and s.end_date >= v_today),
    'expiring_soon', (select count(distinct coalesce(s.member_id, s.gym_member_id)) from public.gym_subscriptions s
                      where s.venue_id = p_venue and s.status = 'active'
                        and s.start_date <= v_today and s.end_date between v_today and v_today + 6
                        and not exists (select 1 from public.gym_subscriptions r
                                        where r.venue_id = s.venue_id
                                          and coalesce(r.member_id, r.gym_member_id) = coalesce(s.member_id, s.gym_member_id)
                                          and r.status = 'active' and r.start_date > s.end_date)),
    'check_ins_today', (select count(*) from public.gym_check_ins c
                        where c.venue_id = p_venue and (c.checked_in_at at time zone 'Asia/Thimphu')::date = v_today),
    'income_this_month', case when public.has_venue_permission(p_venue, 'venue.income') then
                           (select coalesce(sum(p.amount), 0) from public.payments p
                            where p.venue_id = p_venue and p.module_key = 'gym_membership'
                              and p.status = 'completed' and p.created_at >= v_month_start)
                         end
  );
end;
$$;


-- ---------------------------------------------------------------------
-- 5. Who can call which function
-- ---------------------------------------------------------------------

revoke execute on function public.gym_new_member_code(), public.gym_new_qr_token(),
  public.gym_member_from_details(jsonb),
  public.gym_add_membership(public.gym_members, uuid, int, date, int, text, text),
  public.gym_check_in_registered(uuid, uuid),
  public.gym_register_member(uuid, jsonb, uuid, int, int, text, text), public.gym_update_member(uuid, jsonb),
  public.gym_set_member_photo(uuid, text), public.gym_reissue_member_qr(uuid),
  public.gym_renew_member(uuid, uuid, int, int, text, text), public.gym_check_in_member(uuid, text),
  public.gym_check_in_by_code(uuid, text), public.gym_dashboard(uuid)
  from public, anon, authenticated;

grant execute on function public.gym_register_member(uuid, jsonb, uuid, int, int, text, text),
  public.gym_update_member(uuid, jsonb), public.gym_set_member_photo(uuid, text), public.gym_reissue_member_qr(uuid),
  public.gym_renew_member(uuid, uuid, int, int, text, text), public.gym_check_in_member(uuid, text),
  public.gym_check_in_by_code(uuid, text), public.gym_dashboard(uuid)
  to authenticated;
