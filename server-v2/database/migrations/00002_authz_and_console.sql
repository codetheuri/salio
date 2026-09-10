-- +goose Up

-- Tables required by Tusk's pkg/authz, plus the operator console's own identity.
--
-- The RBAC tables are written out here rather than inherited from Tusk's
-- migrations, because Tusk's set also creates its own users table — with NOT NULL
-- email and username, which Salio users do not have. pkg/authz itself needs only
-- these four tables and never reads users directly: user_roles.user_id is a bare
-- UUID, so it points at Salio's users perfectly well.

-- The permission catalogue, synchronised from code by `tusk auth sync`.
CREATE TABLE permissions (
    name        VARCHAR(191) PRIMARY KEY,
    description TEXT,
    created_at  TIMESTAMPTZ,
    updated_at  TIMESTAMPTZ
);

CREATE TABLE roles (
    id          UUID         PRIMARY KEY,
    name        VARCHAR(191) NOT NULL UNIQUE,
    description TEXT,
    created_at  TIMESTAMPTZ,
    updated_at  TIMESTAMPTZ
);

CREATE TABLE role_permissions (
    role_id         UUID         NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_name VARCHAR(191) NOT NULL REFERENCES permissions(name) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ,
    PRIMARY KEY (role_id, permission_name)
);

-- The composite primary key already indexes (role_id, permission_name), covering
-- lookups by role. The reverse — "which roles grant this permission?" — is not.
CREATE INDEX idx_role_permissions_permission ON role_permissions(permission_name);

CREATE TABLE user_roles (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id    UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, role_id)
);

CREATE INDEX idx_user_roles_role ON user_roles(role_id);

-- ---------------------------------------------------------------------------
-- Operator console
-- ---------------------------------------------------------------------------
--
-- Super admins run the Salio platform. They are not business owners or staff,
-- and they authenticate in a completely separate world: email and a cookie
-- session, never a phone and a JWT.
CREATE TABLE super_admins (
    id            UUID         PRIMARY KEY,
    name          VARCHAR(255) NOT NULL,
    email         VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Browser sessions, for Tusk's pkg/session.
--
-- This replaces v1's console_sessions, whose primary key WAS the cookie value —
-- the raw token sat unhashed in the database, so any dump or leaked replica
-- handed over every live session. Only the SHA-256 digest is stored here.
--
-- subject_id has no foreign key on purpose: it points at super_admins today and
-- could point at users tomorrow, and subject_kind is what keeps those apart.
CREATE TABLE sessions (
    id           UUID         PRIMARY KEY,
    token_hash   VARCHAR(64)  NOT NULL UNIQUE,
    subject_kind VARCHAR(64)  NOT NULL,
    subject_id   UUID         NOT NULL,
    ip           VARCHAR(45)  NOT NULL DEFAULT '',
    user_agent   VARCHAR(255) NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ  NOT NULL,
    last_seen_at TIMESTAMPTZ  NOT NULL,
    expires_at   TIMESTAMPTZ  NOT NULL
);

-- Covers "every session for this person", which signing someone out everywhere
-- has to do.
CREATE INDEX idx_sessions_subject ON sessions(subject_kind, subject_id);

-- Covers the periodic sweep of expired rows. Nothing else deletes them.
CREATE INDEX idx_sessions_expires ON sessions(expires_at);

-- +goose Down
DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS super_admins;
DROP TABLE IF EXISTS user_roles;
DROP TABLE IF EXISTS role_permissions;
DROP TABLE IF EXISTS roles;
DROP TABLE IF EXISTS permissions;
