-- Salio PostgreSQL Schema — Migration 001
-- Run this once against your production database to create all tables.
-- Command: psql -U salio_user -d salio_db -f migrations/001_initial_schema.sql

-- ============================================================
-- Enable UUID extension for uuid_generate_v4() if needed
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- BUSINESSES
-- The central account. All data belongs to a business.
-- ============================================================
CREATE TABLE IF NOT EXISTS businesses (
    id           UUID         PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    name         VARCHAR(255) NOT NULL,
    type         VARCHAR(100),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ============================================================
-- USERS
-- Staff and owners. Each belongs to exactly one Business.
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
    id            UUID         PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    business_id   UUID         NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name          VARCHAR(255) NOT NULL,
    phone         VARCHAR(50)  UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(20)  NOT NULL CHECK (role IN ('owner', 'staff')),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_business ON users(business_id);

-- ============================================================
-- BUSINESS INVITES
-- Short-lived codes used to link new staff to a Business.
-- ============================================================
CREATE TABLE IF NOT EXISTS business_invites (
    id           SERIAL      PRIMARY KEY,
    business_id  UUID        NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    code         VARCHAR(10) NOT NULL UNIQUE,
    expires_at   TIMESTAMPTZ NOT NULL,
    used_at      TIMESTAMPTZ,           -- NULL = not yet used
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invites_code ON business_invites(code);

-- ============================================================
-- CUSTOMERS
-- Buyers managed by the Business. NOT users of the app.
-- ============================================================
CREATE TABLE IF NOT EXISTS customers (
    id           UUID         PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    business_id  UUID         NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name         VARCHAR(255) NOT NULL,
    phone        VARCHAR(50),
    notes        TEXT,
    created_by   UUID         NOT NULL REFERENCES users(id),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted   BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_customers_business ON customers(business_id);
CREATE INDEX IF NOT EXISTS idx_customers_name     ON customers(business_id, name);

-- ============================================================
-- TRANSACTIONS
-- Immutable financial events (debts and payments).
-- Mistakes are corrected by offsetting entries, NOT by editing.
-- ============================================================
CREATE TABLE IF NOT EXISTS transactions (
    id               UUID           PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    business_id      UUID           NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    customer_id      UUID           NOT NULL REFERENCES customers(id),
    user_id          UUID           NOT NULL REFERENCES users(id),
    type             VARCHAR(10)    NOT NULL CHECK (type IN ('debt', 'payment')),
    amount           NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    description      TEXT,
    transaction_date DATE           NOT NULL,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN        NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_transactions_business  ON transactions(business_id);
CREATE INDEX IF NOT EXISTS idx_transactions_customer  ON transactions(customer_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date      ON transactions(business_id, transaction_date DESC);
