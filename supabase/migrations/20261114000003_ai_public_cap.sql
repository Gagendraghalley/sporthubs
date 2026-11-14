-- SportsHub's assistant for visitors: 150 questions a Bhutan day from
-- everyone together, down from 300 (20261114000002).
--
-- Measured on the live account, a question costs about 30-40 of Workers
-- AI's 10,000 free neurons a day, so 300 from visitors could have left the
-- gyms' own Ask AI almost nothing. 150 is about half the allowance; each
-- address still gets 15.

create or replace function public.ai_take_public_question(client text)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_each constant int := 15;
  v_everyone constant int := 150;
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
