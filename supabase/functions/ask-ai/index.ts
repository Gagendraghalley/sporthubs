// Ask AI for a gym's staff: they ask in their own words; Cloudflare Workers
// AI (its free daily allowance) turns the question into one of the app's
// reports, or a short how-to answer:
//
//   { venue_id, question, history?: [{ question, reply }] }
//     -> { kind, report?, period?, days?, name?, page?, answer?, left }
//
// Only the question goes to Cloudflare. The app works the answer out from
// the gym's records, which this function never reads. The database counts
// each question first, as the caller (ai_take_question: that gym's staff,
// 25 a day each), so one person can't use up everyone's allowance.
//
// Secrets: see _shared/workers_ai.ts.
// Deploy: supabase functions deploy ask-ai
import { createClient } from 'npm:@supabase/supabase-js@2';

import { AskError, askWorkersAi, cors, reply, workersAi } from '../_shared/workers_ai.ts';
import { cleanHistory, cleanQuestion, messages, sanitize, SCHEMA } from './reply.ts';

const uuid = (value: unknown): string | null =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value) ? value : null;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Use POST' }, 405);

  const authorization = req.headers.get('Authorization');
  if (!authorization) return reply({ error: 'Please sign in again.' }, 401);

  const ai = workersAi();
  if (!ai) return reply({ error: "Ask AI isn't set up yet. The suggestions still work.", code: 'not_set_up' }, 503);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply({ error: 'Send JSON' }, 400);
  }
  const venueId = uuid(body.venue_id);
  const question = cleanQuestion(body.question);
  if (!venueId) return reply({ error: 'Which gym?' }, 400);
  if (!question) return reply({ error: 'Type a question.' }, 400);

  const asCaller = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: who, error: whoError } = await asCaller.auth.getUser();
  if (whoError || !who.user) return reply({ error: 'Please sign in again.' }, 401);

  // Staff of this gym, within today's allowance: the database decides.
  const { data: left, error: takeError } = await asCaller.rpc('ai_take_question', { venue_id: venueId });
  if (takeError) return reply({ error: takeError.message }, 403);

  try {
    const raw = await askWorkersAi(ai, messages(question, cleanHistory(body.history)), SCHEMA);
    return reply({ ...sanitize(raw), left }, 200);
  } catch (e) {
    if (e instanceof AskError) return reply({ error: e.message, left }, 502);
    console.error('ask-ai failed', e);
    return reply({ error: "The AI couldn't answer just now. Please try again, or tap a suggestion.", left }, 502);
  }
});
