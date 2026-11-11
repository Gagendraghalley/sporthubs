-- =====================================================================
-- Organisations, and roles and permissions per organisation.
--
-- 1. organisations: the business that runs one or more venues (its
--    branches). Every venue belongs to one. Each venue already here gets
--    its own, named after it, and so does every venue registered later.
--    The SportsHub team ('organisations.manage', Admin -> Organisations)
--    renames them and moves venues between them, so a business with
--    several gyms is one organisation.
--
-- 2. Venue roles are SportsHub-wide or an organisation's own:
--    * roles.organisation_id null: SportsHub-wide. Owner, Manager, Front
--      desk, Trainer and any the team adds. Every organisation has them,
--      with the same permissions, unless it changed them for itself.
--    * roles.organisation_id set: that organisation's own role, given only
--      at its venues.
--    * An organisation can change what a SportsHub-wide role allows at its
--      venues (organisation_role_settings.custom_permissions: exactly the
--      permissions in organisation_role_permissions), or turn the role off
--      there. Without a change, SportsHub's default applies, and follows
--      the team's later changes to it.
--    * Owner always has everything, everywhere.
--    The team's own roles (scope 'platform') stay SportsHub-wide.
--
-- 3. Who configures what:
--    * 'roles.manage' (the SportsHub team): SportsHub-wide roles, and any
--      organisation's roles and changes.
--    * An organisation's people: whoever has the new venue permission
--      'venue.roles' at every one of its venues (an owner of all of them
--      has it). They add or take away only permissions they have at all of
--      its venues themselves, so roles can't be used to climb.
--
-- 4. The database works out what a venue role allows; the app reads it
--    through my_venues() and organisation_roles(), not from the tables.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Organisations
-- ---------------------------------------------------------------------

create table if not exists public.organisations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(trim(name)) between 2 and 100),
  description text check (char_length(description) <= 500),
  created_by  uuid constraint organisations_created_by_fkey references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists organisations_name_idx on public.organisations (lower(name));

drop trigger if exists organisations_updated_at on public.organisations;
create trigger organisations_updated_at before update on public.organisations
  for each row execute function public.set_updated_at();

alter table public.venues add column if not exists organisation_id uuid
  constraint venues_organisation_id_fkey references public.organisations (id) on delete restrict;
create index if not exists venues_organisation_idx on public.venues (organisation_id);

-- A venue made without an organisation gets its own, named after it
-- (register_venue, and the test and seed scripts). A row for a venue that
-- is already there ('insert ... on conflict do nothing' runs this trigger
-- too) takes that venue's, so no organisation is left behind for nothing.
create or replace function public.venues_own_organisation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.organisation_id is null then
    select v.organisation_id into new.organisation_id from public.venues v where v.id = new.id;
  end if;
  if new.organisation_id is null then
    insert into public.organisations (name, created_by)
    values (left(trim(new.name), 100), new.created_by)
    returning id into new.organisation_id;
  end if;
  return new;
end;
$$;

drop trigger if exists venues_own_organisation on public.venues;
create trigger venues_own_organisation before insert on public.venues
  for each row execute function public.venues_own_organisation();

-- The venues already here: one each.
do $$
declare
  v_venue record;
  v_org uuid;
begin
  for v_venue in select v.id, v.name, v.created_by from public.venues v where v.organisation_id is null loop
    insert into public.organisations (name, created_by)
    values (left(trim(v_venue.name), 100), v_venue.created_by)
    returning id into v_org;
    update public.venues v set organisation_id = v_org where v.id = v_venue.id;
  end loop;
end;
$$;
alter table public.venues alter column organisation_id set not null;


-- ---------------------------------------------------------------------
-- 2. New permissions
-- ---------------------------------------------------------------------
-- As in 20261108000001: one seen for the first time gets its default
-- pairs; one already here keeps whatever admins chose since.

do $$
declare
  v_new_permissions text[];
begin
  with saved as (
    insert into public.permissions (key, scope, name, description, sort_order) values
      ('organisations.manage', 'platform', 'Organisations',
       'Make organisations and choose which venues belong to each', 60),
      ('venue.roles',          'venue',    'Roles',
       'Make the organisation''s own roles and choose what each role can do there', 25)
    on conflict (key) do update
      set scope = excluded.scope, name = excluded.name, description = excluded.description,
          sort_order = excluded.sort_order
    returning key, (xmax = 0) as inserted
  )
  select coalesce(array_agg(key) filter (where inserted), '{}') into v_new_permissions from saved;

  insert into public.role_permissions (role_id, permission_key)
  select r.id, d.permission_key
  from (values ('platform_admin', 'organisations.manage'), ('owner', 'venue.roles')) d (role_key, permission_key)
  join public.roles r on r.key = d.role_key
  where d.permission_key = any (v_new_permissions)
  on conflict do nothing;
end;
$$;


-- ---------------------------------------------------------------------
-- 3. Roles per organisation
-- ---------------------------------------------------------------------

alter table public.roles add column if not exists organisation_id uuid
  constraint roles_organisation_id_fkey references public.organisations (id) on delete cascade;
alter table public.roles drop constraint if exists roles_organisation_venue_only;
alter table public.roles add constraint roles_organisation_venue_only check (organisation_id is null or scope = 'venue');
create index if not exists roles_organisation_idx on public.roles (organisation_id);

-- Names: unique among SportsHub-wide roles, and within an organisation.
drop index if exists public.roles_name_key;
create unique index if not exists roles_name_key
  on public.roles (scope, coalesce(organisation_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name));

-- An organisation's change to a SportsHub-wide venue role. No row: the
-- role is as SportsHub has it.
create table if not exists public.organisation_role_settings (
  organisation_id    uuid not null references public.organisations (id) on delete cascade,
  role_id            uuid not null references public.roles (id) on delete cascade,
  -- Off: nobody at the organisation's venues gets the role's permissions.
  is_active          boolean not null default true,
  -- On: the role allows exactly the organisation's organisation_role_permissions
  -- there, not SportsHub's default.
  custom_permissions boolean not null default false,
  updated_by         uuid constraint organisation_role_settings_updated_by_fkey
                       references public.profiles (id) on delete set null,
  updated_at         timestamptz not null default now(),
  primary key (organisation_id, role_id)
);

create table if not exists public.organisation_role_permissions (
  organisation_id uuid not null,
  role_id         uuid not null,
  permission_key  text not null references public.permissions (key) on delete cascade,
  primary key (organisation_id, role_id, permission_key),
  foreign key (organisation_id, role_id)
    references public.organisation_role_settings (organisation_id, role_id) on delete cascade
);


-- ---------------------------------------------------------------------
-- 4. Helpers: what a role allows, and who may do what
-- ---------------------------------------------------------------------

-- [role_id] is on at organisation [org]'s venues: on, SportsHub-wide or the
-- organisation's own, and not turned off there.
create or replace function public.role_is_on_at(role_id uuid, org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select r.is_active
       and (r.organisation_id is null or r.organisation_id = org)
       and coalesce((select s.is_active from public.organisation_role_settings s
                     where s.organisation_id = org and s.role_id = r.id), true)
    from public.roles r
    where r.id = role_is_on_at.role_id
  ), false);
$$;

-- The permissions [role_id] gives at organisation [org]'s venues: Owner,
-- every venue permission; a SportsHub-wide role the organisation changed,
-- the organisation's choice; otherwise the role's own. (A team role: [org]
-- null, its own.)
create or replace function public.role_permission_keys(role_id uuid, org uuid)
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select x.id, x.key,
           exists (select 1 from public.organisation_role_settings s
                   where s.organisation_id = org and s.role_id = x.id and s.custom_permissions) as custom
    from public.roles x
    where x.id = role_permission_keys.role_id
  )
  select pm.key from public.permissions pm, r where r.key = 'owner' and pm.scope = 'venue'
  union
  select op.permission_key from public.organisation_role_permissions op, r
  where r.key <> 'owner' and r.custom and op.organisation_id = org and op.role_id = r.id
  union
  select rp.permission_key from public.role_permissions rp, r
  where r.key <> 'owner' and not r.custom and rp.role_id = r.id;
$$;

-- The caller's role at [venue]: a role key, or null. A role that is off
-- (everywhere, or at the venue's organisation), or a person who is, counts
-- as none. Written out rather than with role_is_on_at: the security rules
-- call it for every row.
create or replace function public.venue_role(venue uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select s.role
  from public.venue_staff s
  join public.venues v on v.id = s.venue_id
  join public.roles r on r.key = s.role and r.is_active
                     and (r.organisation_id is null or r.organisation_id = v.organisation_id)
  join public.profiles p on p.id = s.user_id and p.is_active
  left join public.organisation_role_settings o on o.organisation_id = v.organisation_id and o.role_id = r.id
  where s.venue_id = venue and s.user_id = (select auth.uid()) and coalesce(o.is_active, true);
$$;

-- The caller may do [perm] at [venue]: their role there allows it, as the
-- venue's organisation has the role (the Owner has everything), or they are
-- a super admin. The same as role_is_on_at and role_permission_keys,
-- written out for speed: the security rules call it for every row.
create or replace function public.has_venue_permission(venue uuid, perm text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1
    from public.venue_staff s
    join public.venues v on v.id = s.venue_id
    join public.roles r on r.key = s.role and r.is_active
                       and (r.organisation_id is null or r.organisation_id = v.organisation_id)
    join public.profiles p on p.id = s.user_id and p.is_active
    left join public.organisation_role_settings o on o.organisation_id = v.organisation_id and o.role_id = r.id
    where s.venue_id = venue and s.user_id = (select auth.uid())
      and coalesce(o.is_active, true)
      and (r.key = 'owner'
           or (coalesce(o.custom_permissions, false) and exists (
                 select 1 from public.organisation_role_permissions op
                 where op.organisation_id = o.organisation_id and op.role_id = r.id and op.permission_key = perm))
           or (not coalesce(o.custom_permissions, false) and exists (
                 select 1 from public.role_permissions rp where rp.role_id = r.id and rp.permission_key = perm)))
  );
$$;

-- The caller may do [perm] across organisation [org]: a super admin, or
-- someone with [perm] at every one of its venues.
create or replace function public.has_organisation_permission(org uuid, perm text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin() or (
    exists (select 1 from public.venues v where v.organisation_id = org)
    and not exists (select 1 from public.venues v
                    where v.organisation_id = org and not public.has_venue_permission(v.id, perm))
  );
$$;

-- The caller works at one of organisation [org]'s venues.
create or replace function public.is_organisation_staff(org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.venues v where v.organisation_id = org and public.is_venue_staff(v.id));
$$;

-- The caller may make and change organisation [org]'s roles: the team's
-- role managers, or whoever has 'venue.roles' at all of its venues.
create or replace function public.can_manage_organisation_roles(org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_permission('roles.manage') or public.has_organisation_permission(org, 'venue.roles');
$$;

-- The caller could give [role] (at [venue], for a venue role): super
-- admins any; others only roles whose every permission they have, as the
-- venue's organisation has the role. Another organisation's roles, never.
create or replace function public.can_give_role(role_id uuid, venue uuid default null)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_role public.roles;
  v_org uuid;
begin
  if public.is_admin() then
    return true;
  end if;
  select * into v_role from public.roles r where r.id = can_give_role.role_id;
  if not found then
    return false;
  end if;
  if v_role.key = 'owner' then
    return false; -- only super admins and user managers hand over a venue
  end if;
  if v_role.scope = 'platform' then
    return not exists (select 1 from public.role_permissions rp
                       where rp.role_id = v_role.id and not public.has_permission(rp.permission_key));
  end if;
  select v.organisation_id into v_org from public.venues v where v.id = can_give_role.venue;
  if v_org is null or (v_role.organisation_id is not null and v_role.organisation_id <> v_org) then
    return false;
  end if;
  return not exists (select 1 from public.role_permission_keys(v_role.id, v_org) k
                     where not public.has_venue_permission(can_give_role.venue, k));
end;
$$;

-- A venue's staff hold SportsHub-wide venue roles or its organisation's own.
create or replace function public.venue_staff_role_fits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.roles r join public.venues v on v.id = new.venue_id
    where r.key = new.role and r.scope = 'venue' and (r.organisation_id is null or r.organisation_id = v.organisation_id)
  ) then
    raise exception 'The % role isn''t one of this venue''s.', new.role;
  end if;
  return new;
end;
$$;

drop trigger if exists venue_staff_role_fits on public.venue_staff;
create trigger venue_staff_role_fits before insert or update of venue_id, role on public.venue_staff
  for each row execute function public.venue_staff_role_fits();


-- ---------------------------------------------------------------------
-- 5. Who can read what
-- ---------------------------------------------------------------------

alter table public.organisations                 enable row level security;
alter table public.organisation_role_settings    enable row level security;
alter table public.organisation_role_permissions enable row level security;

revoke all on public.organisations, public.organisation_role_settings, public.organisation_role_permissions
  from anon, authenticated;
grant select on public.organisations, public.organisation_role_settings, public.organisation_role_permissions
  to authenticated;

-- Organisations: the team, and the people who work at them.
drop policy if exists "organisations: the team, and their own people" on public.organisations;
create policy "organisations: the team, and their own people" on public.organisations for select to authenticated
  using ((select public.has_permission('organisations.manage')) or (select public.has_permission('roles.manage'))
         or (select public.has_permission('users.manage')) or (select public.has_permission('venues.verify'))
         or public.is_organisation_staff(id));

-- SportsHub-wide roles for everyone signed in, as before (staff pages list
-- them); an organisation's own, and its changes, for its people and the team.
drop policy if exists "roles: signed in" on public.roles;
drop policy if exists "roles: SportsHub-wide, and an organisation's own for its people" on public.roles;
create policy "roles: SportsHub-wide, and an organisation's own for its people" on public.roles
  for select to authenticated
  using (organisation_id is null or (select public.has_permission('roles.manage'))
         or (select public.has_permission('users.manage')) or public.is_organisation_staff(organisation_id));

drop policy if exists "role_permissions: signed in" on public.role_permissions;
drop policy if exists "role_permissions: whoever sees the role" on public.role_permissions;
create policy "role_permissions: whoever sees the role" on public.role_permissions for select to authenticated
  using (exists (select 1 from public.roles r where r.id = role_permissions.role_id));

drop policy if exists "organisation_role_settings: role managers and its people" on public.organisation_role_settings;
create policy "organisation_role_settings: role managers and its people" on public.organisation_role_settings
  for select to authenticated
  using ((select public.has_permission('roles.manage')) or public.is_organisation_staff(organisation_id));

drop policy if exists "organisation_role_permissions: role managers and its people" on public.organisation_role_permissions;
create policy "organisation_role_permissions: role managers and its people" on public.organisation_role_permissions
  for select to authenticated
  using ((select public.has_permission('roles.manage')) or public.is_organisation_staff(organisation_id));

-- Whoever groups venues into organisations sees every venue.
drop policy if exists "venues: organisation managers" on public.venues;
create policy "venues: organisation managers" on public.venues for select to authenticated
  using ((select public.has_permission('organisations.manage')));


-- ---------------------------------------------------------------------
-- 6. Functions the app calls: what people may do at their venues
-- ---------------------------------------------------------------------

-- The venues the caller runs: each venue (its row), their role there, the
-- role's name, what it allows as the venue's organisation has it, and the
-- organisation. None while their account is off; roles that are off are
-- left out.
create or replace function public.my_venues()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'venue', to_jsonb(v),
           'role', s.role,
           'role_name', r.name,
           'organisation', jsonb_build_object('id', o.id, 'name', o.name),
           'permissions', coalesce((select jsonb_agg(k order by k) from public.role_permission_keys(r.id, v.organisation_id) k),
                                   '[]'::jsonb)
         ) order by lower(v.name)), '[]'::jsonb)
  from public.venue_staff s
  join public.venues v on v.id = s.venue_id
  join public.organisations o on o.id = v.organisation_id
  join public.roles r on r.key = s.role
  join public.profiles p on p.id = s.user_id and p.is_active
  where s.user_id = (select auth.uid()) and public.role_is_on_at(r.id, v.organisation_id);
$$;

-- Organisation [organisation_id]'s venue roles as its venues have them:
-- SportsHub-wide ones (with its changes) and its own, each with what it
-- allows there and SportsHub's default, and how many people have it there.
-- Also whether the caller may change them, and the permissions they may
-- give. For the team and the organisation's people.
create or replace function public.organisation_roles(organisation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_org uuid := organisation_roles.organisation_id;
  v_org public.organisations;
  v_team boolean := public.has_permission('roles.manage');
begin
  select * into v_org from public.organisations o where o.id = p_org;
  if not found then
    raise exception 'This organisation no longer exists.';
  end if;
  if not (v_team or public.has_permission('users.manage') or public.has_permission('organisations.manage')
          or public.is_organisation_staff(p_org)) then
    raise exception 'Only the organisation''s people can see its roles.';
  end if;
  return jsonb_build_object(
    'organisation', jsonb_build_object('id', v_org.id, 'name', v_org.name),
    'can_manage', public.can_manage_organisation_roles(p_org),
    'grantable', coalesce((
      select jsonb_agg(pm.key order by pm.sort_order)
      from public.permissions pm
      where pm.scope = 'venue' and (v_team or public.has_organisation_permission(p_org, pm.key))
    ), '[]'::jsonb),
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id,
               'key', r.key,
               'scope', r.scope,
               'organisation_id', r.organisation_id,
               'name', r.name,
               'description', r.description,
               'is_system', r.is_system,
               'is_active', public.role_is_on_at(r.id, p_org),
               'default_active', r.is_active,
               'off_here', not coalesce(s.is_active, true),
               'custom_permissions', coalesce(s.custom_permissions, false),
               'permissions', coalesce((select jsonb_agg(k order by k) from public.role_permission_keys(r.id, p_org) k),
                                       '[]'::jsonb),
               'default_permissions', coalesce((select jsonb_agg(rp.permission_key order by rp.permission_key)
                                                from public.role_permissions rp where rp.role_id = r.id), '[]'::jsonb),
               'people', (select count(*) from public.venue_staff vs join public.venues v on v.id = vs.venue_id
                          where v.organisation_id = p_org and vs.role = r.key)
             ) order by r.organisation_id is not null, r.sort_order, lower(r.name))
      from public.roles r
      left join public.organisation_role_settings s on s.organisation_id = p_org and s.role_id = r.id
      where r.scope = 'venue' and (r.organisation_id is null or r.organisation_id = p_org)
    ), '[]'::jsonb)
  );
end;
$$;


-- ---------------------------------------------------------------------
-- 7. Functions the app calls: roles
-- ---------------------------------------------------------------------

-- A new role ([role_id] null) or changes to one, with exactly
-- [permission_keys]. [organisation_id], for a new venue role: that
-- organisation's own (null: SportsHub-wide). A role never moves between
-- organisations. Returns its id.
drop function if exists public.save_role(uuid, text, text, text, boolean, text[]);
create or replace function public.save_role(role_id uuid, scope text, name text, description text, active boolean,
                                            permission_keys text[], organisation_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_id uuid := save_role.role_id;
  p_name text := regexp_replace(trim(coalesce(save_role.name, '')), '\s+', ' ', 'g');
  p_description text := nullif(trim(save_role.description), '');
  p_active boolean := coalesce(save_role.active, true);
  p_keys text[] := array(select distinct k from unnest(coalesce(save_role.permission_keys, '{}')) k);
  v_team boolean := public.has_permission('roles.manage');
  v_role public.roles;
  v_scope text;
  v_org uuid;
  v_before text[] := '{}';
  v_check text[];
  v_key text;
  v_n int := 1;
begin
  if p_id is null then
    v_scope := save_role.scope;
    v_org := save_role.organisation_id;
    if v_scope is null or v_scope not in ('platform', 'venue') then
      raise exception 'Choose whether the role is for the SportsHub team or for venues.';
    end if;
    if v_org is not null then
      if v_scope <> 'venue' then
        raise exception 'An organisation''s own roles are for its venues.';
      end if;
      if not exists (select 1 from public.organisations o where o.id = v_org) then
        raise exception 'This organisation no longer exists.';
      end if;
    end if;
  else
    select * into v_role from public.roles r where r.id = p_id for update;
    if not found then
      raise exception 'This role no longer exists.';
    end if;
    v_scope := v_role.scope;
    v_org := v_role.organisation_id;
    v_before := array(select rp.permission_key from public.role_permissions rp where rp.role_id = p_id);
  end if;

  -- Who may: the team's role managers any role; an organisation's people
  -- only its own.
  if v_org is null then
    if not v_team then
      raise exception 'Only people who manage roles can change them.';
    end if;
  elsif not public.can_manage_organisation_roles(v_org) then
    raise exception 'Only people who manage this organisation''s roles can change them.';
  end if;
  if v_role.key = 'owner' then
    raise exception 'The Owner role always has every permission and can''t be changed.';
  end if;
  if char_length(p_name) not between 2 and 60 then
    raise exception 'Enter the role''s name (2 to 60 letters).';
  end if;
  if v_org is not null and exists (select 1 from public.roles r
                                   where r.organisation_id is null and r.scope = 'venue' and lower(r.name) = lower(p_name)) then
    raise exception 'SportsHub already has a % role: change what it allows for this organisation instead.', p_name;
  end if;
  if exists (select 1 from unnest(p_keys) k
             where not exists (select 1 from public.permissions pm where pm.key = k and pm.scope = v_scope)) then
    raise exception 'Some of those permissions aren''t for this kind of role.';
  end if;

  -- Nobody hands on what they don't have. Team roles: unless a super admin.
  -- An organisation's role, for its own people: what they add or take away,
  -- and all of it when they turn the role on or off, only from what they
  -- have at all of its venues. (Venue roles the team makes are templates:
  -- the venue staff rules apply when they are given.)
  if v_scope = 'platform' and not public.is_admin()
     and exists (select 1 from unnest(p_keys) k where not public.has_permission(k)) then
    raise exception 'You can only give a role permissions you have yourself.';
  end if;
  if v_org is not null and not v_team then
    v_check := array((select unnest(p_keys) except select unnest(v_before))
                     union (select unnest(v_before) except select unnest(p_keys)));
    if p_id is not null and v_role.is_active is distinct from p_active then
      v_check := v_check || p_keys || v_before;
    end if;
    if exists (select 1 from unnest(v_check) k where not public.has_organisation_permission(v_org, k)) then
      raise exception 'You can only give or take away permissions you have yourself, at all of the organisation''s venues.';
    end if;
  end if;

  if p_id is null then
    v_key := left(trim(both '_' from regexp_replace(lower(p_name), '[^a-z0-9]+', '_', 'g')), 36);
    if v_key !~ '^[a-z]' then
      v_key := 'role_' || v_key;
    end if;
    if char_length(v_key) < 2 then
      v_key := 'role';
    end if;
    while exists (select 1 from public.roles r where r.key = case when v_n = 1 then v_key else v_key || '_' || v_n end) loop
      v_n := v_n + 1;
    end loop;
    if v_n > 1 then
      v_key := v_key || '_' || v_n;
    end if;
    insert into public.roles (key, scope, organisation_id, name, description, is_active, created_by)
    values (v_key, v_scope, v_org, p_name, p_description, p_active, (select auth.uid()))
    returning * into v_role;
  else
    update public.roles r set name = p_name, description = p_description, is_active = p_active
    where r.id = p_id returning * into v_role;
  end if;

  delete from public.role_permissions rp where rp.role_id = v_role.id and not (rp.permission_key = any (p_keys));
  insert into public.role_permissions (role_id, permission_key)
  select v_role.id, k from unnest(p_keys) k
  on conflict do nothing;
  return v_role.id;
exception when unique_violation then
  raise exception 'There is already a role called %.', p_name;
end;
$$;

-- Removes a role nobody has. System roles stay (turn them off instead).
create or replace function public.delete_role(role_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_role public.roles;
  v_people int;
begin
  select * into v_role from public.roles r where r.id = delete_role.role_id for update;
  if not found then
    return;
  end if;
  if v_role.organisation_id is null then
    if not public.has_permission('roles.manage') then
      raise exception 'Only people who manage roles can change them.';
    end if;
  elsif not public.can_manage_organisation_roles(v_role.organisation_id) then
    raise exception 'Only people who manage this organisation''s roles can change them.';
  end if;
  if v_role.is_system then
    raise exception '% comes with SportsHub and can''t be deleted. Turn it off instead.', v_role.name;
  end if;
  select (select count(*) from public.user_roles ur where ur.role_id = v_role.id)
       + (select count(*) from public.venue_staff s where s.role = v_role.key)
  into v_people;
  if v_people > 0 then
    raise exception '% people have this role. Give them another role first, or turn it off.', v_people;
  end if;
  delete from public.roles r where r.id = v_role.id;
end;
$$;

-- What SportsHub-wide venue role [role_id] allows at organisation
-- [organisation_id]'s venues: exactly [permission_keys], or SportsHub's
-- default when null; and whether it is on there. On, with the default, is
-- no change at all (back to how SportsHub has it).
create or replace function public.set_organisation_role(organisation_id uuid, role_id uuid, active boolean,
                                                        permission_keys text[] default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_org uuid := set_organisation_role.organisation_id;
  p_active boolean := coalesce(set_organisation_role.active, true);
  p_keys text[] := case when set_organisation_role.permission_keys is null then null
                        else array(select distinct k from unnest(set_organisation_role.permission_keys) k) end;
  v_role public.roles;
  v_before text[];
  v_after text[];
  v_was_on boolean;
  v_check text[];
begin
  if not exists (select 1 from public.organisations o where o.id = p_org) then
    raise exception 'This organisation no longer exists.';
  end if;
  if not public.can_manage_organisation_roles(p_org) then
    raise exception 'Only people who manage this organisation''s roles can change them.';
  end if;
  select * into v_role from public.roles r where r.id = set_organisation_role.role_id;
  if not found or v_role.scope <> 'venue' then
    raise exception 'Choose one of the venue roles.';
  end if;
  if v_role.organisation_id is not null then
    raise exception '% is the organisation''s own role: change it directly.', v_role.name;
  end if;
  if v_role.key = 'owner' then
    raise exception 'The Owner role always has every permission and can''t be changed.';
  end if;
  if p_keys is not null and exists (
       select 1 from unnest(p_keys) k
       where not exists (select 1 from public.permissions pm where pm.key = k and pm.scope = 'venue')) then
    raise exception 'Some of those permissions aren''t for venue roles.';
  end if;

  -- As save_role: the organisation's people change only what they have.
  if not public.has_permission('roles.manage') then
    v_before := array(select public.role_permission_keys(v_role.id, p_org));
    v_after := coalesce(p_keys, array(select rp.permission_key from public.role_permissions rp where rp.role_id = v_role.id));
    v_was_on := coalesce((select s.is_active from public.organisation_role_settings s
                          where s.organisation_id = p_org and s.role_id = v_role.id), true);
    v_check := array((select unnest(v_after) except select unnest(v_before))
                     union (select unnest(v_before) except select unnest(v_after)));
    if v_was_on is distinct from p_active then
      v_check := v_check || v_before || v_after;
    end if;
    if exists (select 1 from unnest(v_check) k where not public.has_organisation_permission(p_org, k)) then
      raise exception 'You can only give or take away permissions you have yourself, at all of the organisation''s venues.';
    end if;
  end if;

  if p_keys is null and p_active then
    delete from public.organisation_role_settings s where s.organisation_id = p_org and s.role_id = v_role.id;
    return;
  end if;
  insert into public.organisation_role_settings (organisation_id, role_id, is_active, custom_permissions, updated_by)
  values (p_org, v_role.id, p_active, p_keys is not null, (select auth.uid()))
  on conflict on constraint organisation_role_settings_pkey do update
    set is_active = excluded.is_active, custom_permissions = excluded.custom_permissions,
        updated_by = excluded.updated_by, updated_at = now();
  delete from public.organisation_role_permissions op
  where op.organisation_id = p_org and op.role_id = v_role.id
    and (p_keys is null or not (op.permission_key = any (p_keys)));
  insert into public.organisation_role_permissions (organisation_id, role_id, permission_key)
  select p_org, v_role.id, k from unnest(coalesce(p_keys, '{}')) k
  on conflict do nothing;
end;
$$;

-- As in 20261108000001, but the role must be SportsHub-wide or the venue's
-- organisation's own, and on there.
create or replace function public.set_venue_staff_role(venue_id uuid, user_id uuid, role_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := set_venue_staff_role.venue_id;
  p_user uuid := set_venue_staff_role.user_id;
  p_role text := set_venue_staff_role.role_key;
  v_me uuid := (select auth.uid());
  v_role public.roles;
  v_current text;
  v_platform boolean := public.has_permission('users.manage');
  v_venue_name text;
  v_org uuid;
begin
  select v.name, v.organisation_id into v_venue_name, v_org from public.venues v where v.id = p_venue;
  if v_venue_name is null then
    raise exception 'This venue no longer exists.';
  end if;
  select * into v_role from public.roles r
  where r.key = p_role and r.scope = 'venue' and (r.organisation_id is null or r.organisation_id = v_org);
  if not found then
    raise exception 'Choose one of the venue roles.';
  end if;
  if not public.role_is_on_at(v_role.id, v_org) then
    raise exception 'The % role is turned off.', v_role.name;
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user) then
    raise exception 'This account no longer exists.';
  end if;
  select s.role into v_current from public.venue_staff s where s.venue_id = p_venue and s.user_id = p_user for update;

  -- Who may first, so nobody learns anything from a change that changes nothing.
  if v_platform then
    if v_current = 'owner' and p_role <> 'owner'
       and not exists (select 1 from public.venue_staff s
                       where s.venue_id = p_venue and s.role = 'owner' and s.user_id <> p_user) then
      raise exception 'A venue needs an owner. Make someone else the owner first.';
    end if;
  else
    if not public.has_venue_permission(p_venue, 'venue.staff') then
      raise exception 'Only people who manage this venue''s staff can do this.';
    end if;
    if p_user = v_me then
      raise exception 'You can''t change your own role.';
    end if;
    if p_role = 'owner' then
      raise exception 'Only the SportsHub team can make someone an owner.';
    end if;
    if v_current = 'owner' then
      raise exception 'They own this venue already.';
    end if;
    if not public.can_give_role(v_role.id, p_venue)
       or (v_current is not null and not public.can_give_role((select r.id from public.roles r where r.key = v_current), p_venue)) then
      raise exception 'You can only give roles whose permissions you have yourself.';
    end if;
  end if;
  if v_current is not distinct from p_role then
    return;
  end if;

  insert into public.venue_staff (venue_id, user_id, role, added_by)
  values (p_venue, p_user, p_role, v_me)
  on conflict on constraint venue_staff_pkey do update set role = excluded.role;

  perform public.notify(p_user, null,
                        case when v_current is null then 'You were added to ' || v_venue_name
                             else 'Your role at ' || v_venue_name || ' changed' end,
                        'You are ' || v_role.name || ' there. Find it under Your venues.', '/manage/' || p_venue);
end;
$$;


-- ---------------------------------------------------------------------
-- 8. Functions the app calls: organisations
-- ---------------------------------------------------------------------

-- A new organisation ([organisation_id] null) or changes to one. Returns
-- its id.
create or replace function public.save_organisation(organisation_id uuid, name text, description text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_id uuid := save_organisation.organisation_id;
  p_name text := regexp_replace(trim(coalesce(save_organisation.name, '')), '\s+', ' ', 'g');
  p_description text := nullif(trim(save_organisation.description), '');
  v_id uuid;
begin
  if not public.has_permission('organisations.manage') then
    raise exception 'Only people who manage organisations can change them.';
  end if;
  if char_length(p_name) not between 2 and 100 then
    raise exception 'Enter the organisation''s name (2 to 100 letters).';
  end if;
  if p_id is null then
    insert into public.organisations (name, description, created_by)
    values (p_name, p_description, (select auth.uid()))
    returning organisations.id into v_id;
  else
    update public.organisations o set name = p_name, description = p_description
    where o.id = p_id returning o.id into v_id;
    if v_id is null then
      raise exception 'This organisation no longer exists.';
    end if;
  end if;
  return v_id;
end;
$$;

-- Removes an organisation with no venues, and its own roles and changes.
create or replace function public.delete_organisation(organisation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_venues int;
begin
  if not public.has_permission('organisations.manage') then
    raise exception 'Only people who manage organisations can change them.';
  end if;
  select count(*) into v_venues from public.venues v where v.organisation_id = delete_organisation.organisation_id;
  if v_venues > 0 then
    raise exception '% venues belong to it. Move them to another organisation first.', v_venues;
  end if;
  delete from public.organisations o where o.id = delete_organisation.organisation_id;
end;
$$;

-- Moves venue [venue_id] to organisation [organisation_id]: from then on,
-- its roles are as that organisation has them. Its staff can't keep a role
-- that belongs to the organisation it leaves.
create or replace function public.set_venue_organisation(venue_id uuid, organisation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := set_venue_organisation.venue_id;
  p_org uuid := set_venue_organisation.organisation_id;
  v_venue public.venues;
  v_roles text;
begin
  if not public.has_permission('organisations.manage') then
    raise exception 'Only people who manage organisations can move venues.';
  end if;
  select * into v_venue from public.venues v where v.id = p_venue for update;
  if not found then
    raise exception 'This venue no longer exists.';
  end if;
  if not exists (select 1 from public.organisations o where o.id = p_org) then
    raise exception 'This organisation no longer exists.';
  end if;
  if v_venue.organisation_id = p_org then
    return;
  end if;
  select string_agg(distinct r.name, ', ') into v_roles
  from public.venue_staff s join public.roles r on r.key = s.role
  where s.venue_id = p_venue and r.organisation_id = v_venue.organisation_id;
  if v_roles is not null then
    raise exception 'Some of its staff have its organisation''s own roles (%). Give them SportsHub-wide roles first.', v_roles;
  end if;
  update public.venues v set organisation_id = p_org where v.id = p_venue;
end;
$$;


-- ---------------------------------------------------------------------
-- 9. Who can call which function
-- ---------------------------------------------------------------------

revoke execute on function public.venues_own_organisation(), public.venue_staff_role_fits(),
  public.role_is_on_at(uuid, uuid), public.role_permission_keys(uuid, uuid),
  public.has_organisation_permission(uuid, text), public.is_organisation_staff(uuid),
  public.can_manage_organisation_roles(uuid), public.my_venues(), public.organisation_roles(uuid),
  public.save_role(uuid, text, text, text, boolean, text[], uuid), public.set_organisation_role(uuid, uuid, boolean, text[]),
  public.save_organisation(uuid, text, text), public.delete_organisation(uuid),
  public.set_venue_organisation(uuid, uuid)
  from public, anon, authenticated;

-- The rules call these as the reader; they only ever answer about the caller.
grant execute on function public.has_organisation_permission(uuid, text), public.is_organisation_staff(uuid),
  public.can_manage_organisation_roles(uuid)
  to authenticated;

grant execute on function public.my_venues(), public.organisation_roles(uuid),
  public.save_role(uuid, text, text, text, boolean, text[], uuid), public.set_organisation_role(uuid, uuid, boolean, text[]),
  public.save_organisation(uuid, text, text), public.delete_organisation(uuid),
  public.set_venue_organisation(uuid, uuid)
  to authenticated;
