#!/usr/bin/env bash
# Runs the SportsHub website locally on http://localhost:3000, like a React
# dev server. Run from the sporthubs folder:
#
#   ./scripts/run_web.sh            # port 3000, or 3001 when 3000 is taken
#   ./scripts/run_web.sh 3001       # that port, exactly
#   SERVE_ONLY=1 ./scripts/run_web.sh
#                                   # serve without opening Chrome; open the
#                                   # address in any browser yourself
#
# In the terminal: r hot-reloads, R restarts, q quits.
set -euo pipefail

in_use() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

if [ $# -ge 1 ]; then
  PORT="$1"
  if in_use "$PORT"; then
    echo "Port $PORT is already in use. Stop what's on it, or pick another port." >&2
    exit 1
  fi
else
  PORT=3000
  if in_use 3000; then
    if in_use 3001; then
      echo "Ports 3000 and 3001 are both in use. Pass another: ./scripts/run_web.sh 3002" >&2
      exit 1
    fi
    echo "Port 3000 is in use; using 3001."
    PORT=3001
  fi
fi

cd "$(dirname "$0")/../apps/sportshub_app"
if [ ! -f env.json ]; then
  echo "apps/sportshub_app/env.json is missing: copy env.example.json to env.json and fill it in (see README)." >&2
  exit 1
fi

DEVICE=chrome
[ "${SERVE_ONLY:-0}" = 1 ] && DEVICE=web-server

echo "SportsHub: http://localhost:$PORT"
exec flutter run -d "$DEVICE" --web-hostname localhost --web-port "$PORT" --dart-define-from-file=env.json
