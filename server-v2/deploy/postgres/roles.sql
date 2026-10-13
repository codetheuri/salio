-- Database roles for Salio v2. Run once per database, as a superuser or the
-- database owner, BEFORE the first migration:
--
--   psql "$ADMIN_URL" -v db_name=salio_v2 -v owner_role=salio_owner \
--        -v owner_password='...' -v app_role=salio_app -v app_password='...' \
--        -f deploy/postgres/roles.sql
--
-- (make db-roles does this from .env.) Safe to run again: it creates what is
-- missing and re-applies the grants.
--
-- Two roles, because they need opposite things:
--
--   owner  owns the schema and runs migrations (cmd/migrate). It can create
--          and drop tables. Never used by the running API.
--
--   app    what the API, syncgc and the import connect as. Reads and writes
--          rows; cannot change the schema; is NOT a superuser and does NOT
--          hold BYPASSRLS — so PostgreSQL's row-level security applies to it,
--          and one shop's request cannot read another shop's rows even if the
--          application forgot to filter. (A superuser is exempt from every
--          policy, silently. The API refuses to start as one in production:
--          REQUIRE_RLS.)

\set ON_ERROR_STOP on

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB',
              :'owner_role', :'owner_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'owner_role') \gexec

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB',
              :'app_role', :'app_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_role') \gexec

-- Re-runs keep the passwords in step with what the caller passed.
SELECT format('ALTER ROLE %I PASSWORD %L', :'owner_role', :'owner_password') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'app_role', :'app_password') \gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO %I, %I', :'db_name', :'owner_role', :'app_role') \gexec

-- The owner owns the schema the tables live in, so the tables it creates are
-- its own.
SELECT format('ALTER SCHEMA public OWNER TO %I', :'owner_role') \gexec

-- Tables that already exist (a database migrated before this script was run):
-- hand them to the owner, and give the app the same grants new ones will get.
SELECT format('ALTER TABLE public.%I OWNER TO %I', tablename, :'owner_role')
FROM pg_tables WHERE schemaname = 'public' \gexec
SELECT format('ALTER SEQUENCE public.%I OWNER TO %I', sequencename, :'owner_role')
FROM pg_sequences WHERE schemaname = 'public' \gexec
SELECT format('ALTER FUNCTION public.%I() OWNER TO %I', proname, :'owner_role')
FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND pronargs = 0 \gexec

SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'app_role') \gexec
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %I', :'app_role') \gexec
SELECT format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO %I', :'app_role') \gexec

-- Tables created by FUTURE migrations. Without this, every new table would be
-- invisible to the API ("permission denied") until someone remembered to grant
-- it by hand — in production, after the deploy that needed it.
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I',
              :'owner_role', :'app_role') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO %I',
              :'owner_role', :'app_role') \gexec

-- The app must never be able to change the schema.
SELECT format('REVOKE CREATE ON SCHEMA public FROM %I', :'app_role') \gexec
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
