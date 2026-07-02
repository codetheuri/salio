-- 002_add_user_active_status.up.sql
-- Adds is_active to users so we can deactivate staff without deleting their row.
-- Deleting a user is impossible because transactions.user_id references users(id).
-- Deactivating sets is_active = FALSE — the user's JWT becomes invalid on next login attempt.
ALTER TABLE users ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- Create index for login performance (always filters by phone AND is_active)
CREATE INDEX idx_users_active ON users(phone, is_active);
