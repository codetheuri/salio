#!/usr/bin/env bash
# Runs the tombstone sweep (server-v2's cmd/syncgc) on the live-test
# database as if every deletion were older than the retention period, so
# live scenario 10 can see a phone told to resync. Only for the throwaway
# database live-server.sh makes; the same settings apply.
#
#   mobile-v2/scripts/live-gc.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ADMIN_URL="${LIVE_ADMIN_URL:-postgres://root:root@127.0.0.1:5434/postgres}"
DB="${LIVE_DB:-salio_v2_live}"
case "$DB" in
  *live*) ;;
  *) echo "live-gc: refusing to touch $DB, which is not a live-test database" >&2; exit 1 ;;
esac

db_url() { echo "$ADMIN_URL" | sed "s#/[^/?]*\(?.*\)\{0,1\}\$#/$1\1#"; }

# Ages every deleted record past the retention. The sweep itself is the
# real one, run as the app role under row-level security, as in production.
psql "$(db_url "$DB")" -q -v ON_ERROR_STOP=1 <<'SQL'
UPDATE customers             SET updated_at = NOW() - INTERVAL '400 days' WHERE is_deleted;
UPDATE transactions          SET updated_at = NOW() - INTERVAL '400 days' WHERE is_deleted;
UPDATE sales                 SET updated_at = NOW() - INTERVAL '400 days' WHERE is_deleted;
UPDATE stock_requests        SET updated_at = NOW() - INTERVAL '400 days' WHERE is_deleted;
UPDATE suppliers             SET updated_at = NOW() - INTERVAL '400 days' WHERE is_deleted;
UPDATE supplier_transactions SET updated_at = NOW() - INTERVAL '400 days' WHERE is_deleted;
SQL

HOST_PORT="$(echo "$ADMIN_URL" | sed -n 's#.*@\([^/]*\)/.*#\1#p')"
BIN="$(mktemp -d)"
trap 'rm -rf "$BIN"' EXIT
(cd "$ROOT/server-v2" && go build -o "$BIN/syncgc" ./cmd/syncgc)
cd "$BIN" # Tusk reads a .env from here; server-v2's own must not leak in
DB_DRIVER=postgres DB_HOST="${HOST_PORT%%:*}" DB_PORT="${HOST_PORT##*:}" \
  DB_NAME="$DB" DB_SSLMODE=disable DB_USER=salio_live_app DB_PASS=live-app-pass \
  APP_NAME=Salio APP_MODE=dev JWT_SECRET=live-tests-only-not-a-real-secret-0123456789 \
  ./syncgc
