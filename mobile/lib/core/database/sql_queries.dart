// lib/core/database/sql_queries.dart

const String createBusinessTable = '''
  CREATE TABLE IF NOT EXISTS business (
    id           TEXT    PRIMARY KEY NOT NULL,
    name         TEXT    NOT NULL,
    type         TEXT,
    created_at   TEXT    NOT NULL,
    updated_at   TEXT    NOT NULL
  );
''';

const String createUsersTable = '''
  CREATE TABLE IF NOT EXISTS users (
    id           TEXT    PRIMARY KEY NOT NULL,
    business_id  TEXT    NOT NULL,
    name         TEXT    NOT NULL,
    phone        TEXT    NOT NULL,
    role         TEXT    NOT NULL,
    created_at   TEXT    NOT NULL,
    updated_at   TEXT    NOT NULL,
    FOREIGN KEY (business_id) REFERENCES business (id)
  );
''';

const String createCustomersTable = '''
  CREATE TABLE IF NOT EXISTS customers (
    id           TEXT    PRIMARY KEY NOT NULL,
    business_id  TEXT    NOT NULL,
    name         TEXT    NOT NULL,
    phone        TEXT,
    notes        TEXT,
    created_by   TEXT    NOT NULL,
    created_at   TEXT    NOT NULL,
    updated_at   TEXT    NOT NULL,
    is_deleted   INTEGER NOT NULL DEFAULT 0
  );
''';

const String createTransactionsTable = '''
  CREATE TABLE IF NOT EXISTS transactions (
    id               TEXT    PRIMARY KEY NOT NULL,
    business_id      TEXT    NOT NULL,
    customer_id      TEXT    NOT NULL,
    user_id          TEXT    NOT NULL,
    type             TEXT    NOT NULL CHECK (type IN ('debt', 'payment')),
    amount           REAL    NOT NULL CHECK (amount > 0),
    description      TEXT,
    transaction_date TEXT    NOT NULL,
    created_at       TEXT    NOT NULL,
    updated_at       TEXT    NOT NULL,
    is_deleted       INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (customer_id) REFERENCES customers (id)
  );
''';

const String createIdxCustomerBusiness = 'CREATE INDEX IF NOT EXISTS idx_customers_business ON customers (business_id);';
const String createIdxCustomerName = 'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers (name);';
const String createIdxTransactionCustomer = 'CREATE INDEX IF NOT EXISTS idx_transactions_customer ON transactions (customer_id);';
