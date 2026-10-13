-- +goose Up

-- How money moved, when debts fall due, how much credit a customer may run up,
-- and the shop's own debts to its suppliers.

-- ---------------------------------------------------------------------------
-- 1. Payment method and reference on customer payments
-- ---------------------------------------------------------------------------
--
-- Cash-up needs to know how each payment arrived, and a dispute ("I already
-- paid you!") is settled by finding the M-Pesa code. Payments recorded before
-- this migration keep a NULL method: guessing "cash" for them would make every
-- historical cash-up wrong by every M-Pesa payment it contained.
ALTER TABLE transactions
    ADD COLUMN payment_method VARCHAR(10) CHECK (payment_method IN ('cash', 'mpesa', 'bank')),
    ADD COLUMN reference      VARCHAR(30),
    ADD COLUMN due_date       DATE;

ALTER TABLE transactions
    -- A debt is not paid by anything; only a payment has a method.
    ADD CONSTRAINT transactions_method_only_on_payments
        CHECK (type = 'payment' OR (payment_method IS NULL AND reference IS NULL)),
    -- Cash leaves no reference to quote.
    ADD CONSTRAINT transactions_reference_needs_method
        CHECK (reference IS NULL OR payment_method IN ('mpesa', 'bank')),
    -- A payment is never "due"; a debt may be, and not before it was incurred.
    ADD CONSTRAINT transactions_due_only_on_debts
        CHECK (type = 'debt' OR due_date IS NULL),
    ADD CONSTRAINT transactions_due_not_before_date
        CHECK (due_date IS NULL OR due_date >= transaction_date);

-- One M-Pesa payment, recorded once. Safaricom never reuses a code, so a second
-- live payment quoting it is the same money entered twice — typically by two
-- phones offline — and crediting it twice would forgive debt nobody paid.
-- Voided entries are excluded so a mistaken payment can be voided and entered
-- again correctly.
CREATE UNIQUE INDEX idx_transactions_mpesa_ref
    ON transactions(business_id, reference)
    WHERE payment_method = 'mpesa' AND reference IS NOT NULL AND is_deleted = false;

-- ---------------------------------------------------------------------------
-- 2. Sales: M-Pesa and bank as well as cash, and a due date on credit
-- ---------------------------------------------------------------------------
ALTER TABLE sales DROP CONSTRAINT sales_payment_method_check;
ALTER TABLE sales ADD CONSTRAINT sales_payment_method_check
    CHECK (payment_method IN ('cash', 'mpesa', 'bank', 'credit'));

ALTER TABLE sales DROP CONSTRAINT sales_credit_needs_customer;
ALTER TABLE sales ADD CONSTRAINT sales_credit_needs_customer
    CHECK (payment_method <> 'credit' OR customer_id IS NOT NULL);

ALTER TABLE sales
    ADD COLUMN reference VARCHAR(30),
    ADD COLUMN due_date  DATE;

ALTER TABLE sales
    ADD CONSTRAINT sales_reference_needs_method
        CHECK (reference IS NULL OR payment_method IN ('mpesa', 'bank')),
    ADD CONSTRAINT sales_due_only_on_credit
        CHECK (payment_method = 'credit' OR due_date IS NULL),
    ADD CONSTRAINT sales_due_not_before_date
        CHECK (due_date IS NULL OR due_date >= sale_date);

CREATE UNIQUE INDEX idx_sales_mpesa_ref
    ON sales(business_id, reference)
    WHERE payment_method = 'mpesa' AND reference IS NOT NULL AND is_deleted = false;

-- ---------------------------------------------------------------------------
-- 3. Credit limits
-- ---------------------------------------------------------------------------
--
-- NULL is "no limit", which is every existing customer. Advisory: the server
-- never refuses a debt over the limit, because a phone that recorded one
-- offline has already handed the goods over, and refusing the record would only
-- lose the fact that the money is owed. The app warns at the counter; reports
-- show who is over.
ALTER TABLE customers
    ADD COLUMN credit_limit NUMERIC(12, 2) CHECK (credit_limit >= 0);

-- ---------------------------------------------------------------------------
-- 4. Suppliers and what the shop owes them
-- ---------------------------------------------------------------------------
--
-- The customer ledger turned around. A bill is goods or services received on
-- credit (the supplier's invoice); a payment is the shop paying it. The balance
-- is derived, never stored: SUM(bill) - SUM(payment) is what the shop owes, and
-- below zero the supplier holds the shop's prepayment.
CREATE TABLE suppliers (
    id          UUID         PRIMARY KEY,
    business_id UUID         NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name        VARCHAR(255) NOT NULL CHECK (btrim(name) <> ''),
    phone       VARCHAR(50),
    notes       TEXT,
    created_by  UUID         NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted  BOOLEAN      NOT NULL DEFAULT FALSE,
    change_seq  BIGINT       NOT NULL DEFAULT 0
);

CREATE INDEX idx_suppliers_business    ON suppliers(business_id);
CREATE INDEX idx_suppliers_name        ON suppliers(business_id, name);
CREATE INDEX idx_suppliers_sync_cursor ON suppliers(business_id, change_seq);

CREATE TRIGGER trg_suppliers_change_seq
    BEFORE INSERT OR UPDATE ON suppliers
    FOR EACH ROW EXECUTE FUNCTION bump_change_seq();

CREATE TABLE supplier_transactions (
    id                UUID           PRIMARY KEY,
    business_id       UUID           NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    supplier_id       UUID           NOT NULL REFERENCES suppliers(id),
    user_id           UUID           NOT NULL REFERENCES users(id),
    type              VARCHAR(10)    NOT NULL CHECK (type IN ('bill', 'payment')),
    amount            NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    description       TEXT           NOT NULL CHECK (btrim(description) <> ''),
    transaction_date  DATE           NOT NULL,
    due_date          DATE,
    payment_method    VARCHAR(10)    CHECK (payment_method IN ('cash', 'mpesa', 'bank')),
    reference         VARCHAR(30),

    -- The order a bill is for, when there was one: "delivery of PO-0007".
    purchase_order_id UUID           REFERENCES purchase_orders(id),

    created_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN        NOT NULL DEFAULT FALSE,
    change_seq        BIGINT         NOT NULL DEFAULT 0,

    -- The same shape as the customer ledger, with every rule stated here too.
    CONSTRAINT supplier_tx_method_only_on_payments
        CHECK ((type = 'payment' AND payment_method IS NOT NULL)
            OR (type = 'bill' AND payment_method IS NULL AND reference IS NULL)),
    CONSTRAINT supplier_tx_reference_needs_method
        CHECK (reference IS NULL OR payment_method IN ('mpesa', 'bank')),
    CONSTRAINT supplier_tx_due_only_on_bills
        CHECK (type = 'bill' OR due_date IS NULL),
    CONSTRAINT supplier_tx_due_not_before_date
        CHECK (due_date IS NULL OR due_date >= transaction_date),
    CONSTRAINT supplier_tx_order_only_on_bills
        CHECK (type = 'bill' OR purchase_order_id IS NULL)
);

CREATE INDEX idx_supplier_tx_business    ON supplier_transactions(business_id);
CREATE INDEX idx_supplier_tx_supplier    ON supplier_transactions(supplier_id);
CREATE INDEX idx_supplier_tx_date        ON supplier_transactions(business_id, transaction_date DESC);
CREATE INDEX idx_supplier_tx_sync_cursor ON supplier_transactions(business_id, change_seq);

CREATE UNIQUE INDEX idx_supplier_tx_mpesa_ref
    ON supplier_transactions(business_id, reference)
    WHERE payment_method = 'mpesa' AND reference IS NOT NULL AND is_deleted = false;

CREATE TRIGGER trg_supplier_transactions_change_seq
    BEFORE INSERT OR UPDATE ON supplier_transactions
    FOR EACH ROW EXECUTE FUNCTION bump_change_seq();

-- The same three-part RLS shape as every tenanted table: tenant-scoped reads
-- and writes, the console's read-only door, and a RESTRICTIVE delete policy so
-- that door can never delete.
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers FORCE ROW LEVEL SECURITY;
CREATE POLICY tusk_tenant_isolation ON suppliers
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tusk_tenant_delete ON suppliers AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE supplier_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_transactions FORCE ROW LEVEL SECURITY;
CREATE POLICY tusk_tenant_isolation ON supplier_transactions
    USING      (business_id = current_setting('app.tenant_id', true)::uuid
                OR current_setting('app.platform_admin', true) = 'on')
    WITH CHECK (business_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tusk_tenant_delete ON supplier_transactions AS RESTRICTIVE FOR DELETE
    USING (business_id = current_setting('app.tenant_id', true)::uuid);

-- +goose Down
DROP TABLE IF EXISTS supplier_transactions;
DROP TABLE IF EXISTS suppliers;

ALTER TABLE customers DROP COLUMN IF EXISTS credit_limit;

DROP INDEX IF EXISTS idx_sales_mpesa_ref;
ALTER TABLE sales
    DROP CONSTRAINT IF EXISTS sales_due_not_before_date,
    DROP CONSTRAINT IF EXISTS sales_due_only_on_credit,
    DROP CONSTRAINT IF EXISTS sales_reference_needs_method,
    DROP COLUMN IF EXISTS due_date,
    DROP COLUMN IF EXISTS reference;
ALTER TABLE sales DROP CONSTRAINT sales_credit_needs_customer;
ALTER TABLE sales ADD CONSTRAINT sales_credit_needs_customer
    CHECK (payment_method = 'cash' OR customer_id IS NOT NULL);
ALTER TABLE sales DROP CONSTRAINT sales_payment_method_check;
ALTER TABLE sales ADD CONSTRAINT sales_payment_method_check
    CHECK (payment_method IN ('cash', 'credit'));

DROP INDEX IF EXISTS idx_transactions_mpesa_ref;
ALTER TABLE transactions
    DROP CONSTRAINT IF EXISTS transactions_due_not_before_date,
    DROP CONSTRAINT IF EXISTS transactions_due_only_on_debts,
    DROP CONSTRAINT IF EXISTS transactions_reference_needs_method,
    DROP CONSTRAINT IF EXISTS transactions_method_only_on_payments,
    DROP COLUMN IF EXISTS due_date,
    DROP COLUMN IF EXISTS reference,
    DROP COLUMN IF EXISTS payment_method;
