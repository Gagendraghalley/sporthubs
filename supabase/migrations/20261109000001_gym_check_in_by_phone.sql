-- Let the front desk check a member in when they have their phone number
-- instead of their card or member code.
create or replace function public.gym_check_in_by_phone(venue_id uuid, phone text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_check_in_by_phone.venue_id;
  p_phone text := regexp_replace(coalesce(gym_check_in_by_phone.phone, ''), '[\s()-]', '', 'g');
  v_registered public.gym_members;
  v_member uuid;
begin
  if not public.has_venue_permission(p_venue, 'gym.check_in') then
    raise exception 'Only the gym''s staff can check members in.';
  end if;

  if p_phone ~ '^[0-9]{8}$' then
    p_phone := '+975' || p_phone;
  elsif p_phone ~ '^[0-9]{8,15}$' then
    p_phone := '+' || p_phone;
  end if;
  if p_phone !~ '^\+[0-9]{8,15}$' then
    raise exception 'Enter a valid phone number, e.g. 17123456.';
  end if;

  select * into v_registered
  from public.gym_members g
  where g.venue_id = p_venue and g.phone = p_phone;
  if found then
    return public.gym_check_in_registered(p_venue, v_registered.id);
  end if;

  select p.id into v_member
  from public.profiles p
  where p.phone = p_phone
    and exists (
      select 1 from public.gym_subscriptions s
      where s.venue_id = p_venue and s.member_id = p.id
    )
  order by p.id
  limit 1;
  if v_member is null then
    raise exception 'No member with that phone number is registered at this gym.';
  end if;
  return public.gym_check_in(p_venue, v_member);
end;
$$;

revoke execute on function public.gym_check_in_by_phone(uuid, text) from public, anon, authenticated;
grant execute on function public.gym_check_in_by_phone(uuid, text) to authenticated;
