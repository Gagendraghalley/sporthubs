// SportsHub's assistant, for anyone (no account needed): questions about
// SportsHub, answered by Cloudflare Workers AI from a guide written into
// reply.ts, or "find gyms (in a dzongkhag)", which the app lists itself:
//
//   { question, history?: [{ question, reply }] }
//     -> { kind, answer?, page?, venue_type?, dzongkhag?, left }
//
// Anyone can call it, so the database counts each question first
// (ai_take_public_question, with the service role): 15 a Bhutan day from
// one address, 150 a day from everyone (about half the free allowance),
// which leaves the rest to the gyms' own Ask AI. Addresses are kept only as a keyed
// hash, for 30 days.
//
// Secrets: see _shared/workers_ai.ts.
// Deploy: supabase functions deploy ask-sportshub (verify_jwt off: visitors)
import { createClient } from 'npm:@supabase/supabase-js@2';

import { AskError, askWorkersAi, cors, reply, workersAi } from '../_shared/workers_ai.ts';
import { cleanHistory, cleanQuestion, messages, sanitize, SCHEMA } from './reply.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Use POST' }, 405);

  const ai = workersAi();
  if (!ai) {
    return reply({ error: "SportsHub's assistant isn't set up yet. The suggestions still work.", code: 'not_set_up' }, 503);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply({ error: 'Send JSON' }, 400);
  }
  const question = cleanQuestion(body.question);
  if (!question) return reply({ error: 'Type a question.' }, 400);

  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey, { auth: { persistSession: false } });
  const { data: left, error: takeError } = await admin.rpc('ai_take_public_question', {
    client: await visitorKey(req, serviceKey),
  });
  if (takeError) return reply({ error: takeError.message }, 429);

  try {
    const raw = await askWorkersAi(ai, messages(question, cleanHistory(body.history)), SCHEMA);
    return reply({ ...sanitize(raw), left }, 200);
  } catch (e) {
    if (e instanceof AskError) return reply({ error: e.message, left }, 502);
    console.error('ask-sportshub failed', e);
    return reply({ error: "The AI couldn't answer just now. Please try again, or tap a suggestion.", left }, 502);
  }
});

/** Who is asking, without keeping who: their address, hashed with a secret
 *  (so the hashes can't be turned back into addresses). */
async function visitorKey(req: Request, secret: string): Promise<string> {
  const address = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() ||
    req.headers.get('cf-connecting-ip') || 'unknown';
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`ask-sportshub:${address}`));
  return Array.from(new Uint8Array(mac), (b) => b.toString(16).padStart(2, '0')).join('');
}
