-- 003_add_transaction_updated_at.up.sql
-- Adds updated_at to transactions so the sync engine can properly track 
-- when a transaction was soft-deleted/voided by an owner.

ALTER TABLE transactions ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Create an index to make Pull queries extremely fast during sync
CREATE INDEX idx_transactions_sync ON transactions(business_id, updated_at);
