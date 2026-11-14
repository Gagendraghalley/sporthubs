-- Ask AI: a gym's staff ask questions in their own words. The ask-ai Edge
-- Function sends only the question to Cloudflare Workers AI, which picks
-- one of the app's reports (or answers how to use SportsHub); the app then
-- works the answer out from the gym's own records. No member data leaves.
--
-- The free Workers AI allowance is shared by every gym on SportsHub, so each
-- person may ask a set number of questions a Bhutan day. A question is
-- counted here before it is sent; the table keeps who asked, where and when
-- (not what), for 90 days.

create table if not exists public.ai_questions (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  venue_id uuid not null references public.venues (id) on delete cascade,
  asked_at timestamptz not null default now()
);
create index if not exists ai_questions_user_asked on public.ai_questions (user_id, asked_at);

-- Only ai_take_question reads or writes it.
alter table public.ai_questions enable row level security;
revoke all on public.ai_questions from anon, authenticated;

-- Counts a question the caller asks at venue [venue_id]: for anyone who works
-- there (or a super admin), up to 25 a Bhutan day. Returns how many they have
-- left today after this one.
create or replace function public.ai_take_question(venue_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := ai_take_question.venue_id;
  v_daily constant int := 25;
  v_day_start timestamptz := public.bhutan_today()::timestamp at time zone 'Asia/Thimphu';
  v_used int;
begin
  if (select auth.uid()) is null then
    raise exception 'Please sign in again.';
  end if;
  if not (public.is_venue_staff(p_venue) or public.is_admin()) then
    raise exception 'Only the gym''s staff can ask about it.';
  end if;

  select count(*) into v_used
  from public.ai_questions q
  where q.user_id = (select auth.uid()) and q.asked_at >= v_day_start;
  if v_used >= v_daily then
    raise exception 'You''ve asked % questions today. Ask again tomorrow, or tap a suggestion: they don''t count.', v_daily;
  end if;

  insert into public.ai_questions (user_id, venue_id) values ((select auth.uid()), p_venue);
  delete from public.ai_questions q
  where q.user_id = (select auth.uid()) and q.asked_at < now() - interval '90 days';
  return v_daily - v_used - 1;
end;
$$;

revoke execute on function public.ai_take_question(uuid) from public, anon, authenticated;
grant execute on function public.ai_take_question(uuid) to authenticated;
