-- +goose Up

-- Row-level security: the layer that still holds when the application layer is
-- wrong.
--
-- Salio has already leaked across businesses once — SqfliteSettingsRepository
-- .getAllUsers() has no business_id filter — which is the argument for a check
-- the database performs regardless of what the application asks for.
--
-- These statements are what tusk's tenant.PolicyStatements() generates, written
-- out because a migration must be a fixed record of a change. Generating this
-- SQL at run time would mean the migration's meaning changed whenever the
-- framework was upgraded, which is the one thing a migration must never do.
-- Policy name and shape are kept identical so the two stay comparable.
--
-- TWO THINGS THAT MAKE THIS SILENTLY INERT
--
-- 1. FORCE is required. Without it PostgreSQL exempts a table's owner from its
--    own policies, and applications very often connect as the owner.
--
-- 2. Superusers, and any role holding BYPASSRLS, are exempt no matter what.
--    Nothing errors; the policies simply never apply. The development database
--    connects as `root`, which is both — so this protection does nothing there.
--    Salio v2 must run as a dedicated non-superuser role in production, and
--    calls tenant.VerifyEnforcement() at startup to say so out loud.
--
-- current_setting(..., true) returns NULL rather than erroring when the
-- parameter is unset, and `column = NULL` is NULL rather than true. A connection
-- that never declared its tenant therefore sees nothing, not everything.

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tusk_tenant_isolation ON users;
CREATE POLICY tusk_tenant_isolation ON users
    USING      (business_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE business_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE business_invites FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tusk_tenant_isolation ON business_invites;
CREATE POLICY tusk_tenant_isolation ON business_invites
    USING      (business_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tusk_tenant_isolation ON customers;
CREATE POLICY tusk_tenant_isolation ON customers
    USING      (business_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tusk_tenant_isolation ON transactions;
CREATE POLICY tusk_tenant_isolation ON transactions
    USING      (business_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

-- businesses is deliberately NOT under a policy.
--
-- The tenant identifier for that table is its own id, and registration creates a
-- business before any tenant exists to declare — so a WITH CHECK on it would
-- refuse the one statement that has to work before anything else can. The
-- application layer still scopes it: Business implements TenantColumn() as "id",
-- so an authenticated request can only ever read its own, and the registration
-- path says tenant.Unscoped explicitly.

-- +goose Down
DROP POLICY IF EXISTS tusk_tenant_isolation ON transactions;
ALTER TABLE transactions NO FORCE ROW LEVEL SECURITY;
ALTER TABLE transactions DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tusk_tenant_isolation ON customers;
ALTER TABLE customers NO FORCE ROW LEVEL SECURITY;
ALTER TABLE customers DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tusk_tenant_isolation ON business_invites;
ALTER TABLE business_invites NO FORCE ROW LEVEL SECURITY;
ALTER TABLE business_invites DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tusk_tenant_isolation ON users;
ALTER TABLE users NO FORCE ROW LEVEL SECURITY;
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
