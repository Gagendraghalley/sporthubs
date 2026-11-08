// Account jobs that need Supabase Auth's admin API, and so the service-role
// key, which only Edge Functions have:
//
//   { action: 'create', email, full_name, phone?, venue_id?, venue_role?, platform_role_ids? }
//     Makes an account (they sign in with the emailed code; no password) and
//     gives it roles. Someone who already has an account just gets the roles.
//     For people with 'users.manage', or with 'venue.staff' at [venue_id]
//     (a gym owner making their front desk's account).
//
//   { action: 'set_active', user_id, active }
//     Turns a person off (they lose every role and can't sign in) or on.
//
// Who may do what is decided by the database: the permission checks and the
// role changes run as the caller (their own token), exactly as if the app
// had called them. Only the Auth calls use the service role.
//
// Deploy: supabase functions deploy admin-users
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Long enough to mean "until turned on again".
const BANNED_FOR = '876000h';

function reply(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}

const text = (value: unknown, max: number): string | null => {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim().replace(/\s+/g, ' ');
  return trimmed.length === 0 ? null : trimmed.slice(0, max);
};

const uuid = (value: unknown): string | null =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value) ? value : null;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Use POST' }, 405);

  const authorization = req.headers.get('Authorization');
  if (!authorization) return reply({ error: 'Not signed in' }, 401);

  const url = Deno.env.get('SUPABASE_URL')!;
  const asCaller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: who, error: whoError } = await asCaller.auth.getUser();
  if (whoError || !who.user) return reply({ error: 'Not signed in' }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply({ error: 'Send JSON' }, 400);
  }
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });

  switch (body.action) {
    case 'create':
      return await create(body, asCaller, admin);
    case 'set_active':
      return await setActive(body, asCaller, admin);
    default:
      return reply({ error: 'Unknown action' }, 400);
  }
});

async function create(body: Record<string, unknown>, asCaller: SupabaseClient, admin: SupabaseClient) {
  const email = text(body.email, 320)?.toLowerCase() ?? null;
  const fullName = text(body.full_name, 100);
  const phone = text(body.phone, 20);
  const venueId = uuid(body.venue_id);
  const venueRole = text(body.venue_role, 40);
  const platformRoleIds = Array.isArray(body.platform_role_ids) ? body.platform_role_ids.map(uuid) : [];

  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return reply({ error: 'Enter a valid email.' }, 400);
  if (!fullName) return reply({ error: 'Enter their name.' }, 400);
  if (phone && !/^\+[0-9]{8,15}$/.test(phone)) return reply({ error: 'Enter the phone as +975 and the number.' }, 400);
  if (platformRoleIds.some((id) => id === null)) return reply({ error: 'Unknown role.' }, 400);
  if ((venueId === null) !== (venueRole === null)) return reply({ error: 'Choose the venue and the role together.' }, 400);

  const { data: allowed, error: checkError } = await asCaller.rpc('can_create_users', { venue: venueId });
  if (checkError) return reply({ error: checkError.message }, 400);
  if (!allowed) return reply({ error: 'You can\'t make accounts here.' }, 403);

  // The account, or the one this email already has.
  let userId: string;
  let existed = false;
  const { data: made, error: makeError } = await admin.auth.admin.createUser({
    email,
    email_confirm: true, // they prove it's theirs with the code each time they sign in
    user_metadata: { full_name: fullName, ...(phone ? { phone } : {}) },
  });
  if (made?.user) {
    userId = made.user.id;
  } else {
    const { data: found } = await admin.from('profiles').select('id').eq('email', email).maybeSingle();
    if (!found) {
      console.error('admin-users create failed', makeError?.message);
      return reply({ error: 'Could not make the account. Please try again.' }, 500);
    }
    userId = found.id as string;
    existed = true;
  }

  // Roles, as the caller: the database decides whether they may give them.
  if (venueId && venueRole) {
    const { error } = await asCaller.rpc('set_venue_staff_role', { venue_id: venueId, user_id: userId, role_key: venueRole });
    if (error) return reply({ error: error.message, user_id: userId, existed }, 400);
  }
  if (platformRoleIds.length > 0) {
    const { error } = await asCaller.rpc('set_user_platform_roles', { user_id: userId, role_ids: platformRoleIds });
    if (error) return reply({ error: error.message, user_id: userId, existed }, 400);
  }
  return reply({ user_id: userId, existed }, 200);
}

async function setActive(body: Record<string, unknown>, asCaller: SupabaseClient, admin: SupabaseClient) {
  const userId = uuid(body.user_id);
  if (!userId || typeof body.active !== 'boolean') return reply({ error: 'Say whose account and on or off.' }, 400);

  // Checks the caller may, then turns their roles off or on.
  const { error } = await asCaller.rpc('set_user_active', { user_id: userId, active: body.active });
  if (error) return reply({ error: error.message }, 400);

  const { error: banError } = await admin.auth.admin.updateUserById(userId, {
    ban_duration: body.active ? 'none' : BANNED_FOR,
  });
  if (banError) {
    console.error('admin-users set_active failed', banError.message);
    return reply({ error: 'Their roles changed, but signing in could not be blocked. Please try again.' }, 500);
  }
  return reply({ user_id: userId, active: body.active }, 200);
}
