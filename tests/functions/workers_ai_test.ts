// How the Edge Functions read Cloudflare Workers AI's answers, and what
// they tell people when it says no. fetch is stood in for: nothing is sent.
//
//   deno test tests/functions/
import { AskError, askWorkersAi } from '../../supabase/functions/_shared/workers_ai.ts';

const ai = { account: 'acc', token: 'tok', model: '@cf/meta/llama-3.3-70b-instruct-fp8-fast' };
const realFetch = globalThis.fetch;

/** Workers AI answering [status] with [body], for the length of [run]. */
async function answering(status: number, body: unknown, run: () => Promise<void>) {
  const sent: Request[] = [];
  globalThis.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
    sent.push(new Request(input, init));
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };
  const log = console.error;
  console.error = () => {};
  try {
    await run();
  } finally {
    globalThis.fetch = realFetch;
    console.error = log;
  }
  return sent;
}

async function problem(status: number, body: unknown): Promise<string> {
  let message = 'no error';
  await answering(status, body, async () => {
    try {
      await askWorkersAi(ai, [{ role: 'user', content: 'hi' }], {});
    } catch (e) {
      message = e instanceof AskError ? e.message : `not an AskError: ${e}`;
    }
  });
  return message;
}

function contains(text: string, part: string) {
  if (!text.includes(part)) throw new Error(`"${text}" doesn't say "${part}"`);
}

Deno.test('an answer comes back as the model gave it, to the right place', async () => {
  let got: unknown;
  const sent = await answering(200, { success: true, result: { response: { kind: 'other' } } }, async () => {
    got = await askWorkersAi(ai, [{ role: 'user', content: 'hi' }], { type: 'object' });
  });
  if (JSON.stringify(got) !== '{"kind":"other"}') throw new Error(`got ${JSON.stringify(got)}`);
  if (sent[0].url !== 'https://api.cloudflare.com/client/v4/accounts/acc/ai/run/@cf/meta/llama-3.3-70b-instruct-fp8-fast') {
    throw new Error(sent[0].url);
  }
  if (sent[0].headers.get('authorization') !== 'Bearer tok') throw new Error('no token');
});

Deno.test('a wrong account ID says Ask AI is not set up properly', async () => {
  contains(await problem(400, {
    success: false,
    errors: [{ code: 7003, message: 'Could not route to /client/v4/accounts/x/ai/run, perhaps your object identifier is invalid?' }],
  }), "isn't set up properly");
});

Deno.test('a token in the wrong form says so too', async () => {
  contains(await problem(400, {
    success: false,
    errors: [{ code: 6003, message: 'Invalid request headers', error_chain: [{ code: 6111, message: 'Invalid format for Authorization header' }] }],
  }), "isn't set up properly");
  contains(await problem(403, { success: false, errors: [{ code: 10000, message: 'Authentication error' }] }), "isn't set up properly");
});

Deno.test("a model Cloudflare doesn't have", async () => {
  contains(await problem(400, { success: false, errors: [{ code: 5007, message: 'No such model @cf/x or task' }] }),
    "isn't set up properly");
});

Deno.test('the free allowance used up', async () => {
  contains(await problem(429, { success: false, errors: [{ message: 'Too many requests' }] }), 'used up');
});

Deno.test("JSON mode that couldn't be met is no answer, not an error", async () => {
  let got: unknown = 'unset';
  await answering(400, { success: false, errors: [{ message: "JSON Mode couldn't be met" }] }, async () => {
    got = await askWorkersAi(ai, [{ role: 'user', content: 'hi' }], {});
  });
  if (got !== null) throw new Error(`got ${JSON.stringify(got)}`);
});

Deno.test('anything else: try again', async () => {
  contains(await problem(500, { success: false, errors: [{ message: 'Internal error' }] }), "couldn't answer just now");
});
