#!/usr/bin/env bash
# Makes the user with this phone number an owner in the live-test database,
# as the operator console would, so live scenario 9 can see a promoted phone
# start receiving suppliers. The server has no route for it: a role change is
# rare, and an owner promoting another is not in v2.0. Only for the
# throwaway database live-server.sh makes.
#
#   mobile-v2/scripts/live-promote.sh +254712345678
set -euo pipefail

PHONE="${1:?usage: live-promote.sh <phone, as stored>}"
ADMIN_URL="${LIVE_ADMIN_URL:-postgres://root:root@127.0.0.1:5434/postgres}"
DB="${LIVE_DB:-salio_v2_live}"
case "$DB" in
  *live*) ;;
  *) echo "live-promote: refusing to touch $DB, which is not a live-test database" >&2; exit 1 ;;
esac

db_url() { echo "$ADMIN_URL" | sed "s#/[^/?]*\(?.*\)\{0,1\}\$#/$1\1#"; }

# The role on the user, and the role its permissions are read from (B5),
# changed together, as the server's own code does.
psql "$(db_url "$DB")" -q -v ON_ERROR_STOP=1 -v phone="$PHONE" <<'SQL'
BEGIN;
UPDATE users SET role = 'owner', updated_at = NOW() WHERE phone = :'phone';
DELETE FROM user_roles WHERE user_id = (SELECT id FROM users WHERE phone = :'phone');
INSERT INTO user_roles (user_id, role_id, created_at)
  SELECT u.id, r.id, NOW() FROM users u, roles r
  WHERE u.phone = :'phone' AND r.name = 'owner';
SELECT CASE WHEN count(*) = 1 THEN 'promoted' ELSE 'no such user' END
  FROM users WHERE phone = :'phone' AND role = 'owner';
COMMIT;
SQL
