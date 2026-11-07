#!/usr/bin/env bash
# Builds the website and puts it on Cloudflare Workers (wrangler.jsonc).
#
#   CLOUDFLARE_API_TOKEN=... scripts/deploy_web.sh
#
# CLOUDFLARE_API_TOKEN: dash.cloudflare.com/profile/api-tokens -> Create Token ->
# 'Edit Cloudflare Workers' template. (Or run `npx wrangler login` once instead.)
# Needs apps/sportshub_app/env.json (scripts/deploy_supabase.sh writes it).
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f apps/sportshub_app/env.json ]] || { echo "apps/sportshub_app/env.json is missing (README, 'Run the app')." >&2; exit 1; }
bash scripts/build_web.sh
export npm_config_cache="${TMPDIR:-/tmp}/sportshub-npm-cache"
npx -y wrangler@4 deploy
