-- +goose Up

-- Sales, stock requests, purchase orders, and the business profile that every
-- printed document carries in its letterhead.

-- ---------------------------------------------------------------------------
-- 1. Business profile and logo
-- ---------------------------------------------------------------------------
--
-- Contact details printed on purchase orders and customer statements. Optional:
-- a business registered before this migration has none, and a document without
-- a phone number is still a valid document.
ALTER TABLE businesses
    ADD COLUMN phone   VARCHAR(50),
    ADD COLUMN email   VARCHAR(255),
    ADD COLUMN address TEXT;

-- The logo lives in its own table rather than as a column on businesses.
-- Business rows are read on almost every request; a logo is read only when a
-- PDF is rendered. Keeping the bytes out of the hot row stops every business
-- lookup from dragging a few hundred kilobytes along with it.
--
-- Stored in the database rather than on disk so the deployment stays one binary
-- and one database: no shared volume to mount, back up, or lose.
CREATE TABLE business_logos (
    business_id  UUID        PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
    content_type VARCHAR(20) NOT NULL CHECK (content_type IN ('image/png', 'image/jpeg')),
    data         BYTEA       NOT NULL,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 2. Sales
-- ---------------------------------------------------------------------------
--
-- A sale is immutable, like a ledger entry: corrected by voiding it, never by
-- editing it. A credit sale also puts a debt on the customer's account; that
-- debt is an ordinary transaction carrying sale_id, so the one balance formula
-- (SUM(debt) - SUM(payment)) keeps working without knowing sales exist.
CREATE TABLE sales (
    id             UUID           PRIMARY KEY,
    business_id    UUID           NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    customer_id    UUID           REFERENCES customers(id),
    user_id        UUID           NOT NULL REFERENCES users(id),
    product_name   VARCHAR(255)   NOT NULL CHECK (btrim(product_name) <> ''),
    quantity       NUMERIC(12, 3) NOT NULL CHECK (quantity > 0),
    amount         NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    payment_method VARCHAR(10)    NOT NULL CHECK (payment_method IN ('cash', 'credit')),
    notes          TEXT,
    sale_date      DATE           NOT NULL,
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN        NOT NULL DEFAULT FALSE,
    change_seq     BIGINT         NOT NULL DEFAULT 0,

    -- Credit has to be owed by somebody. Enforced here as well as in the
    -- application, because a credit sale with no customer is a debt nobody can
    -- ever be asked to pay.
    CONSTRAINT sales_credit_needs_customer
        CHECK (payment_method = 'cash' OR customer_id IS NOT NULL)
);

CREATE INDEX idx_sales_business      ON sales(business_id);
CREATE INDEX idx_sales_business_date ON sales(business_id, sale_date DESC);
CREATE INDEX idx_sales_customer      ON sales(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX idx_sales_sync_cursor   ON sales(business_id, change_seq);

CREATE TRIGGER trg_sales_change_seq
    BEFORE INSERT OR UPDATE ON sales
    FOR EACH ROW EXECUTE FUNCTION bump_change_seq();

-- The debt a credit sale creates. Unique, so a sale can never put two debts on
-- an account — not through a retried push, not through the phone and the server
-- both creating it. The debt's id is also derived from the sale's id (see
-- domain.SaleDebtID), so the two would collide on the primary key first; this
-- index states the rule in terms a reader of the schema can see.
ALTER TABLE transactions ADD COLUMN sale_id UUID REFERENCES sales(id);
CREATE UNIQUE INDEX idx_transactions_sale ON transactions(sale_id) WHERE sale_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. Purchase orders and stock requests
-- ---------------------------------------------------------------------------
--
-- A stock request is a note that something has run out ("Duodip 20ml, needed
-- since Tuesday"). Requests not yet on an order are the draft. A purchase order
-- is made from some of them once quantities and a supplier are known.
--
-- Requests sync, so a shop can note an empty shelf with no signal. Orders are
-- made online: the server numbers them and renders the PDF, and sending one to a
-- supplier needs a connection anyway.
CREATE TABLE purchase_orders (
    id             UUID         PRIMARY KEY,
    business_id    UUID         NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    created_by     UUID         NOT NULL REFERENCES users(id),

    -- Human-readable and per business: PO-0001, PO-0002. What a supplier quotes
    -- back on the phone, which a UUID never will be.
    order_number   INTEGER      NOT NULL CHECK (order_number > 0),

    supplier_name  VARCHAR(255) NOT NULL CHECK (btrim(supplier_name) <> ''),
    supplier_phone VARCHAR(50),
    notes          TEXT,
    status         VARCHAR(10)  NOT NULL CHECK (status IN ('ordered', 'cancelled')),
    ordered_on     DATE         NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    UNIQUE (business_id, order_number)
);

CREATE TABLE stock_requests (
    id                UUID         PRIMARY KEY,
    business_id       UUID         NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    user_id           UUID         NOT NULL REFERENCES users(id),
    product_name      VARCHAR(255) NOT NULL CHECK (btrim(product_name) <> ''),
    needed_on         DATE         NOT NULL,
    notes             TEXT,

    -- Set by the server when the request goes onto an order, cleared again if
    -- that order is cancelled. Never accepted from a device.
    purchase_order_id UUID         REFERENCES purchase_orders(id),

    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN      NOT NULL DEFAULT FALSE,
    change_seq        BIGINT       NOT NULL DEFAULT 0
);

CREATE INDEX idx_stock_requests_business    ON stock_requests(business_id);
CREATE INDEX idx_stock_requests_pending     ON stock_requests(business_id)
    WHERE purchase_order_id IS NULL AND is_deleted = false;
CREATE INDEX idx_stock_requests_sync_cursor ON stock_requests(business_id, change_seq);

CREATE TRIGGER trg_stock_requests_change_seq
    BEFORE INSERT OR UPDATE ON stock_requests
    FOR EACH ROW EXECUTE FUNCTION bump_change_seq();

-- An order's lines copy the product name at the moment of ordering. A request
-- edited afterwards must not change an order that has already gone to a
-- supplier — what was sent is what the order says.
CREATE TABLE purchase_order_lines (
    id                UUID           PRIMARY KEY,
    business_id       UUID           NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    purchase_order_id UUID           NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    stock_request_id  UUID           REFERENCES stock_requests(id),
    product_name      VARCHAR(255)   NOT NULL,
    quantity          NUMERIC(12, 3) NOT NULL CHECK (quantity > 0),
    position          INTEGER        NOT NULL
);

CREATE INDEX idx_purchase_order_lines_order ON purchase_order_lines(purchase_order_id, position);

-- ---------------------------------------------------------------------------
-- 4. Row-level security for every new tenanted table
-- ---------------------------------------------------------------------------
--
-- The same three-part shape as 00003-00005: tenant-scoped reads and writes, the
-- console's read-only platform-admin door, and a RESTRICTIVE delete policy so
-- that door can never delete.

ALTER TABLE business_logos ENABLE ROW LEVEL SECURITY;
ALTER TABLE business_logos FORCE ROW LEVEL SECURITY;
CREATE POLICY tusk_tenant_isolation ON business_logos
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tusk_tenant_delete ON business_logos AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales FORCE ROW LEVEL SECURITY;
CREATE POLICY tusk_tenant_isolation ON sales
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tusk_tenant_delete ON sales AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders FORCE ROW LEVEL SECURITY;
CREATE POLICY tusk_tenant_isolation ON purchase_orders
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tusk_tenant_delete ON purchase_orders AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE stock_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_requests FORCE ROW LEVEL SECURITY;
CREATE POLICY tusk_tenant_isolation ON stock_requests
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tusk_tenant_delete ON stock_requests AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE purchase_order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY tusk_tenant_isolation ON purchase_order_lines
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tusk_tenant_delete ON purchase_order_lines AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

-- +goose Down

DROP TABLE IF EXISTS purchase_order_lines;
DROP TABLE IF EXISTS stock_requests;
DROP TABLE IF EXISTS purchase_orders;

DROP INDEX IF EXISTS idx_transactions_sale;
ALTER TABLE transactions DROP COLUMN IF EXISTS sale_id;

DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS business_logos;

ALTER TABLE businesses
    DROP COLUMN IF EXISTS address,
    DROP COLUMN IF EXISTS email,
    DROP COLUMN IF EXISTS phone;
