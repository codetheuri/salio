-- +goose Up

-- Phase 6: the sync engine, rebuilt.
--
-- The change sequence, its trigger and its indexes already exist (00001). What
-- this migration adds is everything the *cursor alone* does not solve: replayed
-- pushes, concurrent edits to different fields of one record, and tombstones
-- that must eventually be collected without resurrecting deleted rows.
--
-- It also closes a hole in 00004, described at the bottom.

-- ---------------------------------------------------------------------------
-- 1. Idempotent push
-- ---------------------------------------------------------------------------
--
-- A push that times out has an unknown outcome: the client cannot tell a request
-- that never arrived from one that was applied and whose response was lost. It
-- retries either way. Without a record of what has already been applied, the
-- retry of a batch containing "record a 500 debt" records it twice — and in a
-- ledger, a duplicated debt is money a customer is wrongly told they owe.
--
-- The client names each push attempt with an operation_id it generates and
-- reuses across retries of that attempt. The server records the outcome under
-- that name and, on seeing it again, replays the stored response instead of the
-- work. The response is stored whole so a retry is answered identically,
-- conflict reports included.
CREATE TABLE sync_operations (
    business_id  UUID        NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    operation_id UUID        NOT NULL,
    result       JSONB       NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Keyed on both, so looking up an operation requires naming the business it
    -- belongs to. One device cannot probe for another business's operation ids.
    PRIMARY KEY (business_id, operation_id)
);

-- Covers the retention sweep. Records exist to answer a retry, and a retry
-- arriving a week later is not a retry.
CREATE INDEX idx_sync_operations_created ON sync_operations(created_at);

ALTER TABLE sync_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_operations FORCE ROW LEVEL SECURITY;
CREATE POLICY tusk_tenant_isolation ON sync_operations
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);

-- ---------------------------------------------------------------------------
-- 2. Per-field merge for customers
-- ---------------------------------------------------------------------------
--
-- Whole-record last-write-wins is unsafe once a record holds facts that change
-- independently. Two members of staff, both offline: one corrects a customer's
-- phone, the other adds a note. Whichever pushes second overwrites the whole
-- row, and the first correction is gone — with a 200 and no indication that
-- anything was lost.
--
-- field_versions records when each field last accepted a write: {"phone":
-- "2026-09-08T10:04:00Z"}. A push carries the fields it actually changed, and
-- each is applied only if it is newer than that field's own version. The two
-- edits above then both survive, because they touch different keys.
--
-- Empty by default, which is also what every pre-existing row carries. A field
-- with no recorded version falls back to the row's updated_at — the best
-- available answer, and exactly today's behaviour.
ALTER TABLE customers ADD COLUMN field_versions JSONB NOT NULL DEFAULT '{}'::jsonb;

-- ---------------------------------------------------------------------------
-- 3. Tombstone horizon
-- ---------------------------------------------------------------------------
--
-- Deleted rows are kept, not removed, so the deletion can reach every device;
-- a row physically deleted while a device still holds it is resurrected by that
-- device's next push. The cost is that tombstones accumulate forever.
--
-- The rule that ends this: past a maximum offline age, a device's cursor is
-- declared too old to be honoured. It is told to resync from zero, which
-- discards its local state, and its stale rows die with it. Only then is a
-- tombstone safe to collect, because no cursor that could have missed the
-- deletion is still valid.
--
-- One row, global, because the sequence it refers to is global. change_seq is
-- the highest value whose tombstones have been collected: any cursor at or below
-- it belongs to a device that has been away too long.
CREATE TABLE sync_tombstone_horizon (
    -- A one-row table: the CHECK constraint and the boolean key together make a
    -- second row impossible, rather than merely unusual.
    only_row   BOOLEAN     PRIMARY KEY DEFAULT true CHECK (only_row),
    change_seq BIGINT      NOT NULL DEFAULT 0,
    purged_at  TIMESTAMPTZ
);

INSERT INTO sync_tombstone_horizon (only_row, change_seq) VALUES (true, 0);

-- Not tenanted and deliberately not under a policy: it describes the sequence,
-- which is shared, and every device needs to read it to learn whether its own
-- cursor is still good.

-- ---------------------------------------------------------------------------
-- 4. Correcting 00004: the platform-admin door also permitted DELETE
-- ---------------------------------------------------------------------------
--
-- 00004 relaxed USING and left WITH CHECK strict, on the reasoning that USING
-- governs reads and WITH CHECK governs writes, making the console's door
-- read-only. That is true for INSERT and UPDATE and NOT TRUE FOR DELETE: a
-- delete has no WITH CHECK at all, so USING alone decides which rows may be
-- removed. Verified against PostgreSQL directly — with app.platform_admin set,
-- `DELETE FROM customers` reported `DELETE 1` on another business's row.
--
-- A RESTRICTIVE policy is ANDed with the permissive ones rather than ORed, so
-- adding one for DELETE requires a real tenant no matter what else is set. The
-- permissive policy still admits the console's reads; the restrictive one
-- refuses every delete that cannot name the business it belongs to.
--
-- This is also what keeps the tombstone sweep honest: it cannot take a shortcut
-- through the console's door, and has to declare each business it collects for.
CREATE POLICY tusk_tenant_delete ON users AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tusk_tenant_delete ON business_invites AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tusk_tenant_delete ON customers AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tusk_tenant_delete ON transactions AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tusk_tenant_delete ON sync_operations AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

-- +goose Down

DROP POLICY IF EXISTS tusk_tenant_delete ON sync_operations;
DROP POLICY IF EXISTS tusk_tenant_delete ON transactions;
DROP POLICY IF EXISTS tusk_tenant_delete ON customers;
DROP POLICY IF EXISTS tusk_tenant_delete ON business_invites;
DROP POLICY IF EXISTS tusk_tenant_delete ON users;

DROP TABLE IF EXISTS sync_tombstone_horizon;

ALTER TABLE customers DROP COLUMN IF EXISTS field_versions;

DROP TABLE IF EXISTS sync_operations;
