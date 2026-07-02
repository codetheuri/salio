-- 003_add_transaction_updated_at.down.sql
DROP INDEX IF EXISTS idx_transactions_sync;
ALTER TABLE transactions DROP COLUMN IF EXISTS updated_at;
