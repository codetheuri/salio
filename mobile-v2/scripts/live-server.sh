#!/usr/bin/env bash
# Starts a throwaway server-v2 for the app's live tests (docs/10, §8.2):
# a fresh database, the two roles, migrations, a small published app
# release, then the API, run as the restricted role with row-level security
# required, as in production.
#
#   mobile-v2/scripts/live-server.sh            # runs in the foreground
#   SALIO_LIVE_URL=http://127.0.0.1:8091 flutter test --tags live
#
# Settings (defaults suit this laptop's test PostgreSQL on 5434, and CI's):
#   LIVE_ADMIN_URL  a superuser connection, used only to create the database
#                   and the roles
#   LIVE_DB         database name, dropped and re-created   (salio_v2_live)
#   LIVE_PORT       the API's port                           (8091)
#
# Its own database and role names, so it never touches the dev or test
# databases. The binaries run from a temporary folder: Tusk reads a .env
# from the working directory, and server-v2's own .env must not leak in.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ADMIN_URL="${LIVE_ADMIN_URL:-postgres://root:root@127.0.0.1:5434/postgres}"
DB="${LIVE_DB:-salio_v2_live}"
PORT="${LIVE_PORT:-8091}"
OWNER=salio_live_owner
APP=salio_live_app
# Throwaway credentials for a throwaway database.
OWNER_PASS=live-owner-pass
APP_PASS=live-app-pass

command -v psql >/dev/null || { echo "psql not found." >&2; exit 1; }
command -v go >/dev/null || { echo "go not found." >&2; exit 1; }

# Same server, same credentials, other database.
db_url() { echo "$ADMIN_URL" | sed "s#/[^/?]*\(?.*\)\{0,1\}\$#/$1\1#"; }

echo "live-server: fresh database $DB"
psql "$ADMIN_URL" -q -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS \"$DB\" WITH (FORCE)" \
  -c "CREATE DATABASE \"$DB\""
psql "$(db_url "$DB")" -q -v db_name="$DB" \
  -v owner_role="$OWNER" -v owner_password="$OWNER_PASS" \
  -v app_role="$APP" -v app_password="$APP_PASS" \
  -f "$ROOT/server-v2/deploy/postgres/roles.sql" >/dev/null

BIN="$(mktemp -d)"
trap 'rm -rf "$BIN"' EXIT
echo "live-server: building server-v2"
(cd "$ROOT/server-v2" && go build -o "$BIN/api" ./cmd/api && go build -o "$BIN/migrate" ./cmd/migrate)

HOST_PORT="$(echo "$ADMIN_URL" | sed -n 's#.*@\([^/]*\)/.*#\1#p')"
export DB_DRIVER=postgres DB_HOST="${HOST_PORT%%:*}" DB_PORT="${HOST_PORT##*:}" \
  DB_NAME="$DB" DB_SSLMODE=disable \
  DB_USER="$APP" DB_PASS="$APP_PASS" \
  MIGRATION_DB_USER="$OWNER" MIGRATION_DB_PASS="$OWNER_PASS" \
  APP_NAME=Salio APP_VERSION=live APP_MODE=dev SERVER_PORT="$PORT" \
  JWT_SECRET=live-tests-only-not-a-real-secret-0123456789 \
  MIGRATE_ON_BOOT=false REQUIRE_RLS=true DOCS_ENABLED=true LOG_LEVEL=warn

# A small published release, so the live tests can run the app's updater
# against the real endpoints: check, download, checksum.
RELEASES="$BIN/releases"
mkdir -p "$RELEASES"
head -c 300000 /dev/urandom > "$RELEASES/Salio-9.9.9-arm64.apk"
python3 - "$RELEASES" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
name = "Salio-9.9.9-arm64.apk"
data = open(os.path.join(d, name), "rb").read()
json.dump({
    "version": "9.9.9", "build": 999, "min_build": 0, "rollout_percent": 100,
    "notes": {"en": "Live test release", "sw": "Toleo la majaribio"},
    "published_at": "2026-10-19T00:00:00Z",
    "files": {"arm64": {"name": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}},
}, open(os.path.join(d, "latest.json"), "w"))
PY
export APP_RELEASES_DIR="$RELEASES"

cd "$BIN"
./migrate up >/dev/null
echo "live-server: http://127.0.0.1:$PORT"
./api
