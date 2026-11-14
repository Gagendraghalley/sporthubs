// Cloudflare Workers AI, in JSON mode: where ask-ai (a gym's staff) and
// ask-sportshub (anyone) send questions. Its free daily allowance is shared
// by both, and by every gym on SportsHub.
//
// Secrets: CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_AI_TOKEN (an API token with
// Workers AI permissions); CLOUDFLARE_AI_MODEL optionally, for another model
// with JSON mode.

export const DEFAULT_MODEL = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';

export type Message = { role: 'system' | 'user' | 'assistant'; content: string };
export type WorkersAi = { account: string; token: string; model: string };

/** A problem to tell the person about, in their words. */
export class AskError extends Error {}

/** The account and token, or null when Ask AI isn't set up. */
export function workersAi(): WorkersAi | null {
  const account = Deno.env.get('CLOUDFLARE_ACCOUNT_ID');
  const token = Deno.env.get('CLOUDFLARE_AI_TOKEN');
  if (!account || !token) return null;
  return { account, token, model: Deno.env.get('CLOUDFLARE_AI_MODEL') || DEFAULT_MODEL };
}

/** The model's answer to [messages], held to [schema]: an object or JSON
 *  text; null when it couldn't fit its answer to the schema. Throws
 *  [AskError] with words to show for what the person should know. */
export async function askWorkersAi(ai: WorkersAi, messages: Message[], schema: unknown): Promise<unknown> {
  let res: Response;
  try {
    res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${ai.account}/ai/run/${ai.model}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${ai.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        messages,
        response_format: { type: 'json_schema', json_schema: schema },
        max_tokens: 300,
        temperature: 0,
      }),
      signal: AbortSignal.timeout(25_000),
    });
  } catch (e) {
    if (e instanceof DOMException && e.name === 'TimeoutError') {
      throw new AskError('The AI took too long to answer. Please try again.');
    }
    throw e;
  }

  const json = await res.json().catch(() => null) as
    | {
      success?: boolean;
      result?: { response?: unknown; usage?: unknown };
      errors?: { code?: number; message?: string; error_chain?: { code?: number; message?: string }[] }[];
    }
    | null;
  const errors = json?.errors ?? [];
  const problem = errors.flatMap((e) => [e.message, ...(e.error_chain ?? []).map((c) => c.message)])
    .filter(Boolean).join('; ');
  if (!res.ok || json?.success === false) {
    // The whole answer, codes and all: Supabase → Edge Functions → Logs.
    console.error('Workers AI said', res.status, JSON.stringify(errors));
    // It couldn't fit its answer to the shape: as if off-topic.
    if (/json mode/i.test(problem)) return null;
    if (res.status === 429 || /neuron|allocation|quota/i.test(problem)) {
      throw new AskError("Today's free AI questions are used up. They come back at 6 am; the suggestions still work.");
    }
    // An account ID that isn't one, a token Cloudflare won't take (or in the
    // wrong form), a model it doesn't have: these come back as 400s too.
    if (
      res.status === 401 || res.status === 403 ||
      /object identifier|could not route|authenticat|authoriz|request headers|no such model/i.test(problem)
    ) {
      throw new AskError(
        "Ask AI isn't set up properly: Cloudflare didn't accept its account ID, token or model. " +
          "The SportsHub team can see why in the function's logs.",
      );
    }
    throw new AskError("The AI couldn't answer just now. Please try again, or tap a suggestion.");
  }
  if (json?.result?.usage) console.log('Workers AI usage', JSON.stringify(json.result.usage));
  return json?.result?.response ?? null;
}

/** Turns the model's reply into an object: JSON text (perhaps in a code
 *  fence) is read; anything else that isn't an object is null. */
export function asObject(raw: unknown): Record<string, unknown> | null {
  let value = raw;
  if (typeof value === 'string') {
    const text = value.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
    try {
      value = JSON.parse(text);
    } catch {
      return null;
    }
  }
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

/** [value] as one line of at most [max] characters, or null when empty. */
export function cleanText(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null;
  const text = value.replace(/\s+/g, ' ').trim();
  return text.length === 0 ? null : text.slice(0, max);
}

export const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function reply(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
