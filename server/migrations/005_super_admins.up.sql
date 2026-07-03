-- 002_super_admins.up.sql
-- Creates the super_admins table for the Salio Console (admin web panel).
-- Super admins are NOT business owners or staff — they are the Salio platform operators.
-- They have a completely separate auth flow (session cookies, not mobile JWT).

CREATE TABLE IF NOT EXISTS super_admins (
    id            UUID         PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    name          VARCHAR(255) NOT NULL,
    email         VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Tracks active console sessions (cookie-based, not JWT)
CREATE TABLE IF NOT EXISTS console_sessions (
    id            UUID         PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    admin_id      UUID         NOT NULL REFERENCES super_admins(id) ON DELETE CASCADE,
    expires_at    TIMESTAMPTZ  NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_console_sessions_admin ON console_sessions(admin_id);
