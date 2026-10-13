#!/bin/sh
# Runs once, when the PostgreSQL container first creates its data directory
# (the official image executes /docker-entrypoint-initdb.d/*.sh as the
# superuser). Creates the owner and application roles from deploy/.env.
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v db_name="$POSTGRES_DB" \
  -v owner_role="$SALIO_OWNER_USER" -v owner_password="$SALIO_OWNER_PASSWORD" \
  -v app_role="$SALIO_APP_USER" -v app_password="$SALIO_APP_PASSWORD" \
  -f /salio/roles.sql
