-- +goose Up

-- Salio's domain schema.
--
-- Written fresh rather than copied from server/migrations/, because that set is
-- a record of six changes applied in sequence to a live database — the sync
-- sequence bolted on in 006, updated_at added in 003 — and replaying that
-- history into an empty database serves no purpose. This is the shape those
-- migrations arrived at, stated once.
--
-- Identifiers carry no DEFAULT. In v1 they defaulted to gen_random_uuid(), which
-- is UUIDv4; Salio now generates UUIDv7 in Go before the row is ever sent, so a
-- row reaching the database without one is a bug. NOT NULL with no default makes
-- that an error rather than a silently wrong identifier of the wrong version.

-- The tenant. Every other table below hangs off it.
CREATE TABLE businesses (
    id         UUID         PRIMARY KEY,
    name       VARCHAR(255) NOT NULL,
    type       VARCHAR(100),
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Owners and staff.
--
-- No email, no username: a shopkeeper signs in with the phone number they
-- already know. phone is globally unique, not unique per business, because login
-- takes a phone and a password with no business selector — two businesses
-- sharing a number would make the credential ambiguous.
CREATE TABLE users (
    id            UUID         PRIMARY KEY,
    business_id   UUID         NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name          VARCHAR(255) NOT NULL,
    phone         VARCHAR(50)  NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(20)  NOT NULL CHECK (role IN ('owner', 'staff')),
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_business ON users(business_id);

-- Login always filters on both columns.
CREATE INDEX idx_users_active ON users(phone, is_active);

-- Short-lived codes linking new staff to a business.
--
-- UUID rather than v1's SERIAL: nothing else in the system counts, and a
-- sequential identifier here would be the one place a row could be enumerated.
CREATE TABLE business_invites (
    id          UUID        PRIMARY KEY,
    business_id UUID        NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    code        VARCHAR(10) NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invites_code ON business_invites(code);

-- People who owe money. Not users; they never sign in.
CREATE TABLE customers (
    id          UUID         PRIMARY KEY,
    business_id UUID         NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name        VARCHAR(255) NOT NULL,
    phone       VARCHAR(50),
    notes       TEXT,
    created_by  UUID         NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted  BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_customers_business ON customers(business_id);
CREATE INDEX idx_customers_name     ON customers(business_id, name);

-- Partial, so walk-in customers with no phone are still allowed — several NULLs
-- do not collide, but two real numbers within one business do.
CREATE UNIQUE INDEX idx_customer_phone_unique
    ON customers(business_id, phone)
    WHERE phone IS NOT NULL AND phone <> '';

-- The ledger. Immutable by product decision: a mistake is corrected with an
-- offsetting entry or a void, never by editing a row, exactly as it works in the
-- paper notebook this replaces.
--
-- NUMERIC, not a floating-point type. Money summed as float accumulates error,
-- and a balance here is SUM(debt) - SUM(payment) over every row a customer has.
CREATE TABLE transactions (
    id               UUID           PRIMARY KEY,
    business_id      UUID           NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    customer_id      UUID           NOT NULL REFERENCES customers(id),
    user_id          UUID           NOT NULL REFERENCES users(id),
    type             VARCHAR(10)    NOT NULL CHECK (type IN ('debt', 'payment')),
    amount           NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    description      TEXT,
    transaction_date DATE           NOT NULL,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN        NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_transactions_business ON transactions(business_id);
CREATE INDEX idx_transactions_customer ON transactions(customer_id);
CREATE INDEX idx_transactions_date     ON transactions(business_id, transaction_date DESC);

-- ---------------------------------------------------------------------------
-- Sync change sequence
-- ---------------------------------------------------------------------------
--
-- One sequence shared by both synced tables, so a single client cursor can order
-- changes across them. Two separate BIGSERIALs would need two cursors and could
-- not express "this customer change preceded that transaction change".
--
-- This replaces the updated_at watermark v1 used, which lost records: NOW() is
-- the transaction *start* time but rows become visible at *commit*, so a device
-- pulling in between saw nothing yet advanced its watermark past a row that was
-- about to land. That row then sat below the watermark forever. See
-- server/migrations/006 for the full diagnosis; here the columns exist from the
-- start, so no backfill is needed.
CREATE SEQUENCE sync_change_seq;

ALTER TABLE customers    ADD COLUMN change_seq BIGINT NOT NULL DEFAULT 0;
ALTER TABLE transactions ADD COLUMN change_seq BIGINT NOT NULL DEFAULT 0;

-- +goose StatementBegin
-- A trigger, not an assignment in each statement. The defect that prompted this
-- design was at root a write path that forgot to move the sync marker: mobile
-- soft-deletes never bumped updated_at, so voided transactions never synced at
-- all. A trigger cannot be forgotten by a future endpoint.
CREATE FUNCTION bump_change_seq() RETURNS TRIGGER AS $$
BEGIN
    NEW.change_seq := nextval('sync_change_seq');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

CREATE TRIGGER trg_customers_change_seq
    BEFORE INSERT OR UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION bump_change_seq();

CREATE TRIGGER trg_transactions_change_seq
    BEFORE INSERT OR UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION bump_change_seq();

-- Pull reads (business_id, change_seq) ascending, so the index must cover both.
-- This makes it a range scan rather than a filter and sort over everything the
-- business owns.
CREATE INDEX idx_customers_sync_cursor    ON customers(business_id, change_seq);
CREATE INDEX idx_transactions_sync_cursor ON transactions(business_id, change_seq);

-- +goose Down
DROP TRIGGER IF EXISTS trg_transactions_change_seq ON transactions;
DROP TRIGGER IF EXISTS trg_customers_change_seq ON customers;
DROP FUNCTION IF EXISTS bump_change_seq();
DROP SEQUENCE IF EXISTS sync_change_seq;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS business_invites;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS businesses;
