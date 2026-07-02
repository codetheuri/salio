# Salio — Data Models

**Version:** 1.1  
**Date:** June 2026

This document defines all core entities, their fields, relationships, and the local SQLite schema for the Salio mobile app, as well as the conceptual server schema.

---

## 1. Entity Relationship Overview

```
BUSINESS (1) ──────< (N) USER
BUSINESS (1) ──────< (N) CUSTOMER
                             │
USER (1) ──────────< (N) TRANSACTION
CUSTOMER (1) ──────< (N) TRANSACTION
```

- A **Business** represents the shop itself.
- A **User** (Owner or Staff) belongs to one Business.
- A **Customer** belongs to a Business (shared across all Users of that Business).
- A **Transaction** belongs to a Customer, but is recorded by a specific User.

---

## 2. Core Entities (Local SQLite & Server)

### 2.1 Business (Server & Local Cache)
Represents the retail shop. Locally, the app usually only stores the Business the logged-in User belongs to.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | TEXT | PRIMARY KEY | UUID v4. |
| `name` | TEXT | NOT NULL | Shop name (e.g., "Kamau's Agrovet"). |
| `type` | TEXT | NULLABLE | Shop category. |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp. |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp. |

### 2.2 User (Server & Local Cache)
Represents the staff member or owner logging into the app.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | TEXT | PRIMARY KEY | UUID v4. |
| `business_id` | TEXT | FOREIGN KEY | The shop they belong to. |
| `name` | TEXT | NOT NULL | Staff name. |
| `phone` | TEXT | UNIQUE, NOT NULL | Used for login. |
| `role` | TEXT | NOT NULL | `owner` or `staff`. |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp. |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp. |

### 2.3 Customer
Represents a person who buys on credit from the Business.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | TEXT | PRIMARY KEY | UUID v4. |
| `business_id` | TEXT | FOREIGN KEY | Links customer to the shop. |
| `name` | TEXT | NOT NULL | Full name of the customer. |
| `phone` | TEXT | NULLABLE | Phone number (optional). |
| `notes` | TEXT | NULLABLE | Any extra notes. |
| `created_by` | TEXT | FOREIGN KEY (User) | Which User originally added them. |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp. |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp. |
| `is_deleted` | INTEGER | DEFAULT 0 | Soft delete flag (0=active, 1=deleted). |

### 2.4 Transaction
Represents a single financial event.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | TEXT | PRIMARY KEY | UUID v4. |
| `business_id` | TEXT | FOREIGN KEY | Scopes to the shop. |
| `customer_id` | TEXT | FOREIGN KEY | Links to the customer. |
| `user_id` | TEXT | FOREIGN KEY | Which User (staff) recorded this. |
| `type` | TEXT | NOT NULL CHECK | `debt` or `payment`. |
| `amount` | REAL | NOT NULL CHECK > 0 | The monetary amount. |
| `description` | TEXT | NULLABLE | Optional note. |
| `transaction_date` | TEXT | NOT NULL | ISO 8601 date. |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp. |
| `is_deleted` | INTEGER | DEFAULT 0 | Soft delete flag. |

---

## 3. Derived Values (Not Stored)

As a robust offline system, we never store running balances directly. We calculate them on the fly.

| Value | Calculation |
|---|---|
| `customer.balance` | `SUM(amount WHERE type='debt') - SUM(amount WHERE type='payment')` for a given `customer_id` |
| `total_outstanding` | `SUM(balance)` across all active customers for the current `business_id` |

---

## 4. SQLite Schema (DDL)

```sql
-- BUSINESS & USERS are often cached simply for UI presentation
CREATE TABLE IF NOT EXISTS business (
    id           TEXT    PRIMARY KEY NOT NULL,
    name         TEXT    NOT NULL,
    type         TEXT,
    created_at   TEXT    NOT NULL,
    updated_at   TEXT    NOT NULL
);

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

-- CUSTOMERS TABLE
CREATE TABLE IF NOT EXISTS customers (
    id           TEXT    PRIMARY KEY NOT NULL,
    business_id  TEXT    NOT NULL,
    name         TEXT    NOT NULL,
    phone        TEXT,
    notes        TEXT,
    created_by   TEXT    NOT NULL,
    created_at   TEXT    NOT NULL,
    updated_at   TEXT    NOT NULL,
    is_deleted   INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (business_id) REFERENCES business (id),
    FOREIGN KEY (created_by) REFERENCES users (id)
);
CREATE INDEX IF NOT EXISTS idx_customers_business ON customers (business_id);
CREATE INDEX IF NOT EXISTS idx_customers_name ON customers (name);

-- TRANSACTIONS TABLE
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
    is_deleted       INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (business_id) REFERENCES business (id),
    FOREIGN KEY (customer_id) REFERENCES customers (id),
    FOREIGN KEY (user_id) REFERENCES users (id)
);
CREATE INDEX IF NOT EXISTS idx_transactions_customer ON transactions (customer_id);
```

## 5. Security & Multi-Tenant Data Isolation
- Even though the local SQLite database is stored securely on the device sandbox, every query must explicitly scope `WHERE business_id = ?` to prevent accidental data leakage if device storage is ever shared or reset improperly.
- The JWT Token stores the `user_id` and `business_id`.
