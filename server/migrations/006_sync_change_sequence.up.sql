-- 006_sync_change_sequence.up.sql
--
-- Replaces the timestamp watermark used by sync with a server-issued monotonic
-- sequence, fixing a defect that permanently hid records from other devices.
--
-- THE BUG THIS FIXES
--
-- Pull returned rows WHERE updated_at > last_sync, and handed the client the
-- server's clock to store as its next last_sync. Push stamped updated_at = NOW().
--
-- In PostgreSQL, NOW() is the *transaction start* time, but rows become visible
-- to other sessions only at *commit*. Those are different instants:
--
--   Device A   BEGIN(t1) ......................... COMMIT(t3)
--              rows stamped updated_at = t1        rows now visible
--   Device B              pull at t2 -> sees nothing, saves last_sync = t2
--
-- A's rows carry t1, below B's new watermark of t2. Every later pull asks for
-- updated_at > t2 and can never return them. The records are not delayed, they
-- are permanently invisible -- until last_sync is destroyed, which is why
-- logging out and back in appeared to "fix" it: logout clears that value.
--
-- THE REPLACEMENT
--
-- One sequence shared by both tables, so a single cursor orders changes across
-- them. A client advances its cursor only as far as the highest value it
-- actually received, so it can never step over a row it has not seen.
--
-- The sequence alone is not sufficient: values are allocated at write time, not
-- at commit, so two concurrent writers can still commit out of order and leave a
-- gap below a cursor that has already advanced. The application closes that by
-- holding a per-business advisory lock for the duration of a push, making commit
-- order match allocation order within a business. See SyncRepository.Push.

-- One sequence for both tables. Two separate BIGSERIALs would require two
-- cursors and could not express "this customer change preceded that transaction
-- change".
CREATE SEQUENCE IF NOT EXISTS sync_change_seq;

ALTER TABLE customers    ADD COLUMN IF NOT EXISTS change_seq BIGINT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS change_seq BIGINT;

-- Backfill existing rows across BOTH tables in one interleaved ordering, so the
-- history a client receives on first sync matches the order things happened.
--
-- This runs before the trigger is created, deliberately: a BEFORE UPDATE trigger
-- assigning nextval() would overwrite every value computed here.
WITH all_rows AS (
    SELECT 'c'::text AS src, id, updated_at FROM customers
    UNION ALL
    SELECT 't'::text AS src, id, updated_at FROM transactions
),
numbered AS (
    SELECT src, id, row_number() OVER (ORDER BY updated_at, id) AS rn FROM all_rows
)
UPDATE customers c SET change_seq = n.rn
FROM numbered n WHERE n.src = 'c' AND c.id = n.id;

WITH all_rows AS (
    SELECT 'c'::text AS src, id, updated_at FROM customers
    UNION ALL
    SELECT 't'::text AS src, id, updated_at FROM transactions
),
numbered AS (
    SELECT src, id, row_number() OVER (ORDER BY updated_at, id) AS rn FROM all_rows
)
UPDATE transactions t SET change_seq = n.rn
FROM numbered n WHERE n.src = 't' AND t.id = n.id;

-- Advance the sequence past the backfilled values, or the first live write would
-- reuse numbers already assigned and appear to clients as old history.
SELECT setval('sync_change_seq', GREATEST(
    (SELECT COALESCE(MAX(change_seq), 0) FROM customers),
    (SELECT COALESCE(MAX(change_seq), 0) FROM transactions),
    1
));

ALTER TABLE customers    ALTER COLUMN change_seq SET NOT NULL;
ALTER TABLE transactions ALTER COLUMN change_seq SET NOT NULL;

-- A trigger rather than explicit assignment in each statement.
--
-- The defect being fixed was, at root, a write path that forgot to advance the
-- sync marker: mobile soft-deletes never bumped updated_at, so voided
-- transactions never synced at all. A trigger cannot be forgotten by a future
-- endpoint, which is precisely the point.
CREATE OR REPLACE FUNCTION bump_change_seq() RETURNS TRIGGER AS $$
BEGIN
    NEW.change_seq := nextval('sync_change_seq');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_customers_change_seq ON customers;
CREATE TRIGGER trg_customers_change_seq
    BEFORE INSERT OR UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION bump_change_seq();

DROP TRIGGER IF EXISTS trg_transactions_change_seq ON transactions;
CREATE TRIGGER trg_transactions_change_seq
    BEFORE INSERT OR UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION bump_change_seq();

-- Pull reads (business_id, change_seq) in ascending order, so the index must
-- cover both. This turns the query into a range scan instead of a filter and
-- sort across everything the business owns.
CREATE INDEX IF NOT EXISTS idx_customers_sync_cursor
    ON customers(business_id, change_seq);
CREATE INDEX IF NOT EXISTS idx_transactions_sync_cursor
    ON transactions(business_id, change_seq);
