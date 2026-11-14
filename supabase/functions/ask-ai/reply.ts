// What Ask AI may answer, what the model is told, and how its reply is
// checked before the app sees it. The model sees only the question (and the
// conversation's last few questions); it never sees the gym's records, so
// its reply is a choice of report, not an answer with numbers in it.
import { asObject, cleanText } from '../_shared/workers_ai.ts';

export const REPORTS = [
  'visits_over_time',
  'busiest_days',
  'busiest_hours',
  'new_members',
  'revenue',
  'revenue_by_method',
  'package_mix',
  'renewal_rate',
  'member_counts',
  'ending_soon',
  'inactive_members',
  'top_members',
  'find_member',
] as const;
export const PERIODS = ['week', 'month', 'quarter', 'year'] as const;
export const PAGES = [
  'check_in',
  'register_member',
  'members',
  'packages',
  'income',
  'reports',
  'staff',
  'roles',
  'settings',
] as const;

export type Report = typeof REPORTS[number];
export type Period = typeof PERIODS[number];
export type Page = typeof PAGES[number];

export type Reply = {
  kind: 'report' | 'help' | 'other';
  report?: Report;
  period?: Period;
  days?: number;
  name?: string;
  page?: Page;
  answer?: string;
};

export type Turn = { question: string; reply: Reply };

export const OTHER_ANSWER =
  'I answer questions about your gym (members, visits, packages and payments) and how to use SportsHub. Try one of the suggestions.';
const WHO_ANSWER = 'Who should I look for? Type their name, phone number or member code.';

export const SYSTEM_PROMPT = `You read questions from the staff of a gym that uses SportsHub (a gym management app in Bhutan) and reply with JSON only. You never see the gym's records: the app looks the answer up itself, so never write numbers or names about the gym.

Set "kind":
- "report" when the question is about the gym's members, visits, packages or money. Set "report" to one of:
  visits_over_time: check-ins day by day or week by week
  busiest_days: check-ins on each day of the week
  busiest_hours: check-ins at each hour of the day
  new_members: members who joined
  revenue: money received over time
  revenue_by_method: money received by payment method (mBoB, cash, bank transfer)
  package_mix: how many members are on each package now
  renewal_rate: how many members renewed when their package ended
  member_counts: how many members are active, ended or waiting
  ending_soon: packages ending soon; "days" = how many days ahead (default 7)
  inactive_members: members with a package who haven't come in; "days" = for how many days (default 14)
  top_members: members who came most often
  find_member: one member; "name" = the name, phone number or member code asked about
  Set "period" for reports over time: "week" (last 7 days, today, this week), "month" (last 30 days; the default), "quarter" (last 3 months), "year" (last 6 or 12 months, this year).
- "help" when they ask how to do something in SportsHub. Set "page" to the page that does it, and "answer" to at most three short sentences from this guide; if the guide doesn't say, send them to the page:
  check_in: Check-in. Scan the member's QR card with the camera or a USB scanner, or type their 6-character member code or phone number. It is recorded only if their package covers today; if not, it says why and offers Renew.
  register_member: Register member. Fill in their details, take their photo with the webcam (Retake before saving, or Upload), choose the package and months and enter what they paid; the expiry date is worked out. Then download or share their QR card, or send it on WhatsApp.
  members: Members. Search the register, filter by status and open a member to see their package, visits and card. On their page: Renew (it starts the day the current package ends, or today once it has ended), Edit details, and New card (the old card stops working).
  packages: Memberships & packages. Add packages and set their prices; turn one off to stop selling it.
  income: Payments & income. Every payment, month by month and by method.
  reports: Reports & analytics. New members, visits by day and hour, renewal rate, package mix and revenue.
  staff: Staff. Add staff by email and choose their role.
  roles: Roles & permissions. Choose what each role may do at the gym.
  settings: Gym settings. The gym's name, place, phone and how members pay.
- "other" for anything else. Set "answer" to one short friendly sentence: you answer questions about the gym and how to use SportsHub.

Questions may be in English, Dzongkha or a mix.`;

/** The shape Workers AI's JSON mode holds the model to. */
export const SCHEMA = {
  type: 'object',
  properties: {
    kind: { type: 'string', enum: ['report', 'help', 'other'] },
    report: { type: 'string', enum: [...REPORTS] },
    period: { type: 'string', enum: [...PERIODS] },
    days: { type: 'integer' },
    name: { type: 'string' },
    page: { type: 'string', enum: [...PAGES] },
    answer: { type: 'string' },
  },
  required: ['kind'],
};

export const cleanQuestion = (value: unknown) => cleanText(value, 300);

const isOneOf = <T extends string>(list: readonly T[], value: unknown): value is T =>
  typeof value === 'string' && (list as readonly string[]).includes(value);

function wholeIn(value: unknown, min: number, max: number, fallback: number): number {
  const n = typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : NaN;
  return Number.isFinite(n) ? Math.min(max, Math.max(min, Math.round(n))) : fallback;
}

/** The model's reply (an object, or JSON text, perhaps in a code fence) as
 *  something the app can act on; anything it can't is 'other'. */
export function sanitize(raw: unknown): Reply {
  const r = asObject(raw);
  if (!r) return { kind: 'other', answer: OTHER_ANSWER };
  const page = isOneOf(PAGES, r.page) ? r.page : undefined;

  if (r.kind === 'report' && isOneOf(REPORTS, r.report)) {
    const out: Reply = {
      kind: 'report',
      report: r.report,
      period: isOneOf(PERIODS, r.period) ? r.period : 'month',
    };
    if (r.report === 'ending_soon') out.days = wholeIn(r.days, 1, 60, 7);
    if (r.report === 'inactive_members') out.days = wholeIn(r.days, 3, 180, 14);
    if (r.report === 'find_member') {
      const name = cleanText(r.name, 60);
      if (!name) return { kind: 'other', answer: WHO_ANSWER };
      out.name = name;
    }
    return out;
  }
  const answer = cleanText(r.answer, 500);
  if ((r.kind === 'help' || (r.kind === 'report' && page)) && (answer || page)) {
    return { kind: 'help', ...(page ? { page } : {}), ...(answer ? { answer } : {}) };
  }
  return { kind: 'other', answer: r.kind === 'other' && answer ? answer.slice(0, 300) : OTHER_ANSWER };
}

/** The conversation's last three turns from the app, checked again: they
 *  come from the browser. Answers are left out (the choice is what matters). */
export function cleanHistory(value: unknown): Turn[] {
  if (!Array.isArray(value)) return [];
  const turns: Turn[] = [];
  for (const item of value.slice(-10)) {
    if (item === null || typeof item !== 'object') continue;
    const question = cleanQuestion((item as Record<string, unknown>).question);
    if (!question) continue;
    const { answer: _answer, ...reply } = sanitize((item as Record<string, unknown>).reply);
    turns.push({ question, reply });
  }
  return turns.slice(-3);
}

/** What the model is sent: the instructions, the last turns, the question. */
export function messages(question: string, history: Turn[]) {
  return [
    { role: 'system' as const, content: SYSTEM_PROMPT },
    ...history.flatMap((t) => [
      { role: 'user' as const, content: t.question },
      { role: 'assistant' as const, content: JSON.stringify(t.reply) },
    ]),
    { role: 'user' as const, content: question },
  ];
}
