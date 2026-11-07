// Deletes the signed-in user's account (Account -> Delete my account), as the
// app stores require. Removing the login (auth.users) removes, through the
// database's "on delete cascade", their profile, memberships, check-ins,
// staff places, reviews and notifications. Payments stay in the venues'
// records without their name (payments.user_id is set to null).
//
// Needs the service-role key, which only Edge Functions have: Supabase
// gives every function SUPABASE_URL, SUPABASE_ANON_KEY and
// SUPABASE_SERVICE_ROLE_KEY. Nothing to set by hand.
//
// Deploy: supabase functions deploy delete-account
import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function reply(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Use POST' }, 405);

  const authorization = req.headers.get('Authorization');
  if (!authorization) return reply({ error: 'Not signed in' }, 401);

  const url = Deno.env.get('SUPABASE_URL')!;
  // Who is asking: their own token, checked by Supabase Auth.
  const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error } = await asUser.auth.getUser();
  if (error || !data.user) return reply({ error: 'Not signed in' }, 401);

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  if (deleteError) {
    console.error('delete-account failed', deleteError.message);
    return reply({ error: 'Could not delete the account. Please try again.' }, 500);
  }
  return reply({ deleted: true }, 200);
});
