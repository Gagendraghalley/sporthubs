-- SportsHub's assistant for anyone, visitors included (the ask-sportshub
-- Edge Function, opened by the floating Ask AI button). Visitors have no
-- account, so their questions are counted by a hash of their address, which
-- the function makes with a secret: SportsHub never keeps the address.
--
-- 15 questions a Bhutan day from one address, and 300 a day from everyone:
-- the rest of the free Workers AI allowance stays for the gyms' Ask AI.
-- Rows are kept 30 days.

create table if not exists public.ai_public_questions (
  id bigint generated always as identity primary key,
  client_hash text not null,
  asked_at timestamptz not null default now()
);
create index if not exists ai_public_questions_asked on public.ai_public_questions (asked_at);
create index if not exists ai_public_questions_client on public.ai_public_questions (client_hash, asked_at);

-- Only ai_take_public_question reads or writes it.
alter table public.ai_public_questions enable row level security;
revoke all on public.ai_public_questions from anon, authenticated;

-- Counts a question from [client] (the hash of their address). Only the
-- Edge Function calls it, with the service role: a browser could send any
-- hash. Returns how many they have left today after this one.
create or replace function public.ai_take_public_question(client text)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_each constant int := 15;
  v_everyone constant int := 300;
  v_day_start timestamptz := public.bhutan_today()::timestamp at time zone 'Asia/Thimphu';
  v_all int;
  v_mine int;
begin
  if client is null or length(client) < 16 then
    raise exception 'Who is asking?';
  end if;

  select count(*) into v_all from public.ai_public_questions q where q.asked_at >= v_day_start;
  if v_all >= v_everyone then
    raise exception 'SportsHub''s assistant has answered all it can for today. Ask again tomorrow; the suggestions still work.';
  end if;
  select count(*) into v_mine
  from public.ai_public_questions q
  where q.client_hash = client and q.asked_at >= v_day_start;
  if v_mine >= v_each then
    raise exception 'You''ve asked % questions today. Ask again tomorrow; the suggestions still work.', v_each;
  end if;

  insert into public.ai_public_questions (client_hash) values (client);
  delete from public.ai_public_questions q where q.asked_at < now() - interval '30 days';
  return v_each - v_mine - 1;
end;
$$;

revoke execute on function public.ai_take_public_question(text) from public, anon, authenticated;
grant execute on function public.ai_take_public_question(text) to service_role;
