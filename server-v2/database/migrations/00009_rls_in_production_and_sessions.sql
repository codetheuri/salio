-- +goose Up

-- Row-level security that works under the role production must use, and
-- sessions that can be ended.
--
-- Found 2026-10-13 by running the API as an unprivileged role for the first
-- time: registration failed with "new row violates row-level security policy
-- for table users". Every earlier run used a superuser, which PostgreSQL
-- silently exempts from all policies, so the third layer of tenant isolation
-- had never actually been exercised. See internal/tenantconn for the request
-- side of the fix; this file is the database side.

-- ---------------------------------------------------------------------------
-- 1. A cleared tenant setting means "no tenant", not an error
-- ---------------------------------------------------------------------------
--
-- Once app.tenant_id has been set on a connection — even with SET LOCAL, even
-- in a transaction that has since ended — current_setting returns '' rather
-- than NULL for the rest of that connection's life. The policies cast it to
-- uuid, and ''::uuid is an error. So after any tenant-scoped transaction (the
-- tombstone sweep, the v1 import), a later query on the same pooled connection
-- that carried no tenant did not see "no rows": it failed outright.
--
-- One function, so every policy reads the setting the same way.
CREATE OR REPLACE FUNCTION app_current_tenant() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$ SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid $$;

-- Rewrite every existing policy to use it. Done by pattern over pg_policies
-- rather than by restating 24 policies by hand: a hand-written list would be
-- one more place for a table to be missed.
-- +goose StatementBegin
DO $$
DECLARE
    p record;
    raw constant text := '(current_setting(''app.tenant_id''::text, true))::uuid';
    qual_sql text;
    check_sql text;
BEGIN
    FOR p IN SELECT schemaname, tablename, policyname, qual, with_check
             FROM pg_policies WHERE schemaname = 'public'
    LOOP
        qual_sql  := replace(p.qual, raw, 'app_current_tenant()');
        check_sql := replace(p.with_check, raw, 'app_current_tenant()');
        IF qual_sql IS DISTINCT FROM p.qual THEN
            EXECUTE format('ALTER POLICY %I ON %I.%I USING (%s)',
                           p.policyname, p.schemaname, p.tablename, qual_sql);
        END IF;
        IF check_sql IS DISTINCT FROM p.with_check THEN
            EXECUTE format('ALTER POLICY %I ON %I.%I WITH CHECK (%s)',
                           p.policyname, p.schemaname, p.tablename, check_sql);
        END IF;
    END LOOP;

    -- Nothing may still read the raw setting: that would be the bug again.
    IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
               AND (strpos(coalesce(qual, ''), raw) > 0 OR strpos(coalesce(with_check, ''), raw) > 0)) THEN
        RAISE EXCEPTION 'a policy still casts app.tenant_id directly';
    END IF;
END $$;
-- +goose StatementEnd

-- ---------------------------------------------------------------------------
-- 2. A read-only door for signing in
-- ---------------------------------------------------------------------------
--
-- Signing in finds a user by phone before anyone knows which business they
-- belong to; registering checks a phone is free across every business; joining
-- finds the invite a code belongs to. None of these can declare a tenant first.
--
-- The door is SELECT-only, so it can never write, and it opens only for a
-- transaction that sets app.identity_lookup — see internal/identity, the one
-- place that does. The same shape as the console's platform_admin door
-- (migration 00004), and like it, it relaxes reads alone.
CREATE POLICY salio_identity_lookup ON users
    FOR SELECT USING (current_setting('app.identity_lookup', true) = 'on');

CREATE POLICY salio_identity_lookup ON business_invites
    FOR SELECT USING (current_setting('app.identity_lookup', true) = 'on');

-- ---------------------------------------------------------------------------
-- 3. Sessions that can be ended
-- ---------------------------------------------------------------------------
--
-- Tokens last 30 days so an offline shop is never locked out. Without a way to
-- end them, a password change protected nothing — a stolen phone kept working —
-- and a deactivated member of staff kept full access until expiry.
--
-- sessions_valid_after: a token issued before this instant is refused. Moved by
-- a password change or reset. NULL means every unexpired token is good.
--
-- must_change_password: set when an owner resets a staff password, so the
-- temporary password the owner read out is replaced before anything else.
ALTER TABLE users
    ADD COLUMN sessions_valid_after TIMESTAMPTZ,
    ADD COLUMN must_change_password BOOLEAN NOT NULL DEFAULT FALSE;

-- +goose Down
ALTER TABLE users
    DROP COLUMN IF EXISTS must_change_password,
    DROP COLUMN IF EXISTS sessions_valid_after;

DROP POLICY IF EXISTS salio_identity_lookup ON business_invites;
DROP POLICY IF EXISTS salio_identity_lookup ON users;

-- +goose StatementBegin
DO $$
DECLARE
    p record;
    raw constant text := '(current_setting(''app.tenant_id''::text, true))::uuid';
BEGIN
    FOR p IN SELECT schemaname, tablename, policyname, qual, with_check
             FROM pg_policies WHERE schemaname = 'public'
    LOOP
        IF strpos(coalesce(p.qual, ''), 'app_current_tenant()') > 0 THEN
            EXECUTE format('ALTER POLICY %I ON %I.%I USING (%s)', p.policyname, p.schemaname, p.tablename,
                           replace(p.qual, 'app_current_tenant()', raw));
        END IF;
        IF strpos(coalesce(p.with_check, ''), 'app_current_tenant()') > 0 THEN
            EXECUTE format('ALTER POLICY %I ON %I.%I WITH CHECK (%s)', p.policyname, p.schemaname, p.tablename,
                           replace(p.with_check, 'app_current_tenant()', raw));
        END IF;
    END LOOP;
END $$;
-- +goose StatementEnd

DROP FUNCTION IF EXISTS app_current_tenant();
