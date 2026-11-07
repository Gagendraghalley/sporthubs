#!/usr/bin/env bash
# Puts SportsHub's whole backend on its Supabase project:
#   1. the database: supabase/migrations (tables, security rules, functions,
#      the daily gym job), only those not applied yet;
#   2. the Edge Functions: supabase/functions;
#   3. the auth settings in supabase/config.toml (6-digit email codes, their
#      email template, password length);
#   4. apps/sportshub_app/env.json for running the app, if it isn't there.
#
#   SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_DB_PASSWORD=... scripts/deploy_supabase.sh
#
# SUPABASE_ACCESS_TOKEN: supabase.com/dashboard/account/tokens -> Generate new token.
# SUPABASE_DB_PASSWORD:  the database password chosen when the project was made
#                        (Project Settings -> Database -> Reset database password).
# Neither is saved in the project.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_REF="${SUPABASE_PROJECT_REF:-iagqntjaywpdxvoxgfhl}"
: "${SUPABASE_ACCESS_TOKEN:?Set SUPABASE_ACCESS_TOKEN (supabase.com/dashboard/account/tokens)}"
: "${SUPABASE_DB_PASSWORD:?Set SUPABASE_DB_PASSWORD (the database password of the project)}"
export SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD

# Supabase CLI 3 (its flags differ from 2's), through npx with its own
# cache so a broken ~/.npm cache doesn't get in the way.
export npm_config_cache="${TMPDIR:-/tmp}/sportshub-npm-cache"
sb() { npx -y supabase@3 "$@"; }

echo "== Linking to project $PROJECT_REF"
sb link --project-ref "$PROJECT_REF" --yes

echo "== Database: applying new migrations"
sb db push --remote --password "$SUPABASE_DB_PASSWORD" --yes

echo "== Edge Functions"
sb functions deploy --use-api --yes

echo "== Auth settings (email codes)"
sb config push --yes

env_file=apps/sportshub_app/env.json
if [[ ! -f "$env_file" ]]; then
  echo "== Writing $env_file"
  keys_json="$(sb projects api-keys -o json)"
  KEYS_JSON="$keys_json" PROJECT_REF="$PROJECT_REF" node -e '
    const parsed = JSON.parse(process.env.KEYS_JSON);
    const keys = Array.isArray(parsed) ? parsed : (parsed.keys || parsed.api_keys || []);
    const pick = (k) => k.find((x) => x.name === "anon") || k.find((x) => (x.type || "") === "publishable");
    const key = pick(keys);
    if (!key) { console.error("No anon/publishable key found"); process.exit(1); }
    const env = {
      SUPABASE_URL: `https://${process.env.PROJECT_REF}.supabase.co`,
      SUPABASE_ANON_KEY: key.api_key,
      GROUND_BOOKING_URL: "https://kuzuhelp.com",
    };
    require("fs").writeFileSync(process.argv[1], JSON.stringify(env, null, 2) + "\n");
  ' "$env_file"
fi

echo
echo "Done. Next:"
echo "  - Make yourself an admin (README, 'Make yourself an admin')."
echo "  - Run the app: cd apps/sportshub_app && flutter run -d chrome --web-port 8080 --dart-define-from-file=env.json"
