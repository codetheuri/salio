#!/bin/sh
# Creates Salio v2's two database roles (salio_owner, salio_app) in salio_dbv2,
# through the PostgreSQL container that is already running. Run once, from
# server-v2/, before the first `docker compose up`. Safe to run again.
#
#   deploy/postgres/apply-roles.sh [container] [superuser]
#   deploy/postgres/apply-roles.sh                     # = postgres legendroot
#
# Nothing is pulled and no superuser password is needed: it runs psql INSIDE
# that container (docker exec), over its local socket, which the official
# image trusts. The role names and passwords are read from docker-compose.yml,
# so they are written in one place only.
set -eu

container=${1:-postgres}
superuser=${2:-legendroot}

here=$(cd "$(dirname "$0")" && pwd)
compose="$here/../../docker-compose.yml"
[ -f "$compose" ] || { echo "cannot find $compose" >&2; exit 1; }

# Reads "  key: &key value" from the x-settings block at the top of the file.
setting() {
  sed -n "s/^  $1: &$1 \([^ ]*\).*/\1/p" "$compose" | head -n 1
}
db_name=$(setting db_name)
owner_user=$(setting owner_user)
owner_password=$(setting owner_password)
app_user=$(setting app_user)
app_password=$(setting app_password)
for v in "$db_name" "$owner_user" "$owner_password" "$app_user" "$app_password"; do
  [ -n "$v" ] || { echo "a setting is missing from the x-settings block of $compose" >&2; exit 1; }
done

docker exec -i "$container" psql --username "$superuser" --dbname "$db_name" \
  -v ON_ERROR_STOP=1 \
  -v db_name="$db_name" \
  -v owner_role="$owner_user" -v owner_password="$owner_password" \
  -v app_role="$app_user" -v app_password="$app_password" \
  -f - < "$here/roles.sql" > /dev/null

# What matters: neither role may be a superuser or bypass row-level security.
docker exec -i "$container" psql --username "$superuser" --dbname "$db_name" -At \
  -c "SELECT rolname || '  superuser=' || rolsuper || '  bypassrls=' || rolbypassrls FROM pg_roles WHERE rolname IN ('$owner_user', '$app_user') ORDER BY 1"
