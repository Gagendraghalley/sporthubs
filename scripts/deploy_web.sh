#!/usr/bin/env bash
# Builds the website and publishes it to the Cloudflare Pages project
# 'sporthubs' (https://sporthubs.pages.dev), as a push to main would.
#
#   CLOUDFLARE_API_TOKEN=... scripts/deploy_web.sh
#
# CLOUDFLARE_API_TOKEN: dash.cloudflare.com/profile/api-tokens -> Create Token ->
# Custom token, permission Account -> Cloudflare Pages -> Edit. (Or run
# `npx wrangler login` once instead.)
# Needs apps/sportshub_app/env.json (scripts/deploy_supabase.sh writes it).
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f apps/sportshub_app/env.json ]] || { echo "apps/sportshub_app/env.json is missing (README, 'Run the app')." >&2; exit 1; }
bash scripts/build_web.sh
export npm_config_cache="${TMPDIR:-/tmp}/sportshub-npm-cache"
npx -y wrangler@4 pages deploy apps/sportshub_app/build/web --project-name sporthubs --branch main --commit-dirty=true
