-- Reverts 006. The sync API keeps accepting the legacy last_sync timestamp, so
-- rolling this back leaves older clients working exactly as before.
DROP TRIGGER IF EXISTS trg_transactions_change_seq ON transactions;
DROP TRIGGER IF EXISTS trg_customers_change_seq ON customers;
DROP FUNCTION IF EXISTS bump_change_seq();
DROP INDEX IF EXISTS idx_transactions_sync_cursor;
DROP INDEX IF EXISTS idx_customers_sync_cursor;
ALTER TABLE transactions DROP COLUMN IF EXISTS change_seq;
ALTER TABLE customers    DROP COLUMN IF EXISTS change_seq;
DROP SEQUENCE IF EXISTS sync_change_seq;
