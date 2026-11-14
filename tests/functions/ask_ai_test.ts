// What the ask-ai Edge Function lets through from the model and the browser.
//
//   deno test tests/functions/
import {
  cleanHistory,
  messages,
  OTHER_ANSWER,
  sanitize,
  SYSTEM_PROMPT,
} from '../../supabase/functions/ask-ai/reply.ts';

function same(actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`got ${a}\nexpected ${e}`);
}

Deno.test('a report, with its period', () => {
  same(sanitize({ kind: 'report', report: 'busiest_hours', period: 'quarter' }),
    { kind: 'report', report: 'busiest_hours', period: 'quarter' });
});

Deno.test('JSON text, even in a code fence, is read', () => {
  same(sanitize('```json\n{"kind":"report","report":"revenue","period":"year"}\n```'),
    { kind: 'report', report: 'revenue', period: 'year' });
});

Deno.test('an unknown period becomes the last 30 days', () => {
  same(sanitize({ kind: 'report', report: 'new_members', period: 'decade' }),
    { kind: 'report', report: 'new_members', period: 'month' });
});

Deno.test('days are whole and within bounds, with defaults', () => {
  same(sanitize({ kind: 'report', report: 'inactive_members', days: 1000 }).days, 180);
  same(sanitize({ kind: 'report', report: 'inactive_members', days: '10.4' }).days, 10);
  same(sanitize({ kind: 'report', report: 'inactive_members' }).days, 14);
  same(sanitize({ kind: 'report', report: 'ending_soon', days: -3 }).days, 1);
  same(sanitize({ kind: 'report', report: 'ending_soon' }).days, 7);
  same(sanitize({ kind: 'report', report: 'top_members', days: 5 }).days, undefined);
});

Deno.test('finding a member needs a name', () => {
  same(sanitize({ kind: 'report', report: 'find_member', name: '  Pema   Wangmo ' }),
    { kind: 'report', report: 'find_member', period: 'month', name: 'Pema Wangmo' });
  same(sanitize({ kind: 'report', report: 'find_member', name: ' ' }).kind, 'other');
});

Deno.test('a report the app does not have is not passed on', () => {
  same(sanitize({ kind: 'report', report: 'delete_members' }), { kind: 'other', answer: OTHER_ANSWER });
  same(sanitize({ kind: 'report', report: 'nope', page: 'members' }), { kind: 'help', page: 'members' });
});

Deno.test('help: a known page and a short answer', () => {
  same(sanitize({ kind: 'help', page: 'members', answer: 'Open the member and tap Renew.' }),
    { kind: 'help', page: 'members', answer: 'Open the member and tap Renew.' });
  same(sanitize({ kind: 'help', page: 'admin_secrets', answer: 'Go there.' }), { kind: 'help', answer: 'Go there.' });
  same(sanitize({ kind: 'help', answer: 'x'.repeat(900) }).answer?.length, 500);
  same(sanitize({ kind: 'help' }), { kind: 'other', answer: OTHER_ANSWER });
});

Deno.test('anything else is a friendly "other"', () => {
  same(sanitize('not json'), { kind: 'other', answer: OTHER_ANSWER });
  same(sanitize(null), { kind: 'other', answer: OTHER_ANSWER });
  same(sanitize([1, 2]), { kind: 'other', answer: OTHER_ANSWER });
  same(sanitize({ kind: 'other', answer: 'I can help with your gym.' }), { kind: 'other', answer: 'I can help with your gym.' });
});

Deno.test("the browser's history is checked, kept short, and loses its answers", () => {
  const history = cleanHistory([
    { question: 'zero', reply: { kind: 'report', report: 'revenue' } },
    { question: 'one', reply: { kind: 'report', report: 'revenue' } },
    { question: 'two', reply: { kind: 'help', page: 'members', answer: 'Long text' } },
    { question: '', reply: { kind: 'report', report: 'revenue' } },
    { question: 'three', reply: { kind: 'report', report: 'top_members', period: 'week' } },
    'junk',
  ]);
  same(history, [
    { question: 'one', reply: { kind: 'report', report: 'revenue', period: 'month' } },
    { question: 'two', reply: { kind: 'help', page: 'members' } },
    { question: 'three', reply: { kind: 'report', report: 'top_members', period: 'week' } },
  ]);
  same(cleanHistory('nope'), []);
});

Deno.test('the model gets the instructions, the last turns, then the question', () => {
  const sent = messages('and last year?', [{ question: 'revenue', reply: { kind: 'report', report: 'revenue', period: 'month' } }]);
  same(sent.map((m) => m.role), ['system', 'user', 'assistant', 'user']);
  same(sent[0].content, SYSTEM_PROMPT);
  same(sent[2].content, '{"kind":"report","report":"revenue","period":"month"}');
  same(sent[3].content, 'and last year?');
});
