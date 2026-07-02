-- 002_add_user_active_status.down.sql
DROP INDEX IF EXISTS idx_users_active;
ALTER TABLE users DROP COLUMN IF EXISTS is_active;
