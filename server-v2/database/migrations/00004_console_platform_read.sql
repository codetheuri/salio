-- +goose Up

-- A read-only door through row-level security, for the platform console.
--
-- WHY THIS EXISTS
--
-- 00003 put users, business_invites, customers and transactions under policies
-- keyed on app.tenant_id. That is correct for the API, where every request
-- belongs to exactly one business. The admin console is the opposite case: it
-- reports across every business at once, and it authenticates a super_admin who
-- belongs to none of them.
--
-- Without this, the console works perfectly in development and shows all zeroes
-- in production. Development connects as `root`, a superuser, which PostgreSQL
-- exempts from every policy silently; a correctly configured production role is
-- not exempt, so `business_id = current_setting('app.tenant_id', true)::uuid`
-- with the setting unset evaluates to NULL, and every console query returns no
-- rows. Nothing errors. The dashboard just reads zero.
--
-- WHY THE EXEMPTION IS ON `USING` ONLY
--
-- USING decides what a statement may read; WITH CHECK decides what it may write.
-- Only USING is relaxed here, so the door is read-only *at the database level* —
-- a bug, or an attacker, holding a console session still cannot insert or move a
-- row across a business boundary. WITH CHECK is left exactly as 00003 wrote it.
--
-- HOW IT IS OPENED
--
-- app.platform_admin is set with SET LOCAL, inside a transaction, only after a
-- console session has been resolved to a real super_admin — console.Repository
-- .readAll is the single place that does it. SET LOCAL reverts on commit, so a
-- pooled connection cannot carry the flag into the next request. Nothing else in
-- the codebase sets this parameter, and a request that does not set it sees
-- exactly what it saw before this migration.

DROP POLICY IF EXISTS tusk_tenant_isolation ON users;
CREATE POLICY tusk_tenant_isolation ON users
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

DROP POLICY IF EXISTS tusk_tenant_isolation ON business_invites;
CREATE POLICY tusk_tenant_isolation ON business_invites
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

DROP POLICY IF EXISTS tusk_tenant_isolation ON customers;
CREATE POLICY tusk_tenant_isolation ON customers
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

DROP POLICY IF EXISTS tusk_tenant_isolation ON transactions;
CREATE POLICY tusk_tenant_isolation ON transactions
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

-- +goose Down

DROP POLICY IF EXISTS tusk_tenant_isolation ON transactions;
CREATE POLICY tusk_tenant_isolation ON transactions
    USING      (business_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

DROP POLICY IF EXISTS tusk_tenant_isolation ON customers;
CREATE POLICY tusk_tenant_isolation ON customers
    USING      (business_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

DROP POLICY IF EXISTS tusk_tenant_isolation ON business_invites;
CREATE POLICY tusk_tenant_isolation ON business_invites
    USING      (business_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

DROP POLICY IF EXISTS tusk_tenant_isolation ON users;
CREATE POLICY tusk_tenant_isolation ON users
    USING      (business_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);
