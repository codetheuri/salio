# Salio — Technical Design Document (TDD)

**Version:** 1.1  
**Date:** June 2026

This document describes the low-level technical decisions, implementation strategies, and developer conventions for the Salio system, updated for the multi-user and multi-tenant architecture.

---

## 1. System Overview

```
┌─────────────────────────────────────────────────────┐
│                 Salio Ecosystem                     │
│                                                     │
│  [Owner's Phone]          [Staff Member's Phone]    │
│  (Local SQLite)           (Local SQLite)            │
│         │                        │                  │
│         └─── Background Sync ────┘                  │
│                     ↓                               │
│              [Go REST API]                          │
│               (JWT Auth)                            │
│                     ↓                               │
│             [PostgreSQL DB]                         │
│            (Source of Truth)                        │
└─────────────────────────────────────────────────────┘
```

---

## 2. Security & Authentication Strategy

### 2.1 JWT (JSON Web Tokens)
Authentication is stateless on the server, handled via JWT.
- **Payload**: Contains `user_id`, `business_id`, `role`, and `exp`.
- **Expiration**: Set to 30 days.
- **Storage**: Stored locally on the mobile device using `flutter_secure_storage` (which uses Keystore on Android and Keychain on iOS).
- **Offline usage**: The mobile app decodes the JWT locally (without verifying the signature, since it already trusts its own secure storage) to extract the `business_id` for local SQLite queries.

### 2.2 Invite Code System
To link staff to a Business without exposing business IDs:
1. Owner requests an invite code: `POST /api/v1/business/invite`.
2. Server generates a random 6-character alphanumeric string (e.g., `X7K-9P2`), stores it in Redis or a `business_invites` table with a 24-hour expiration, linked to the `business_id`.
3. Staff registers with the code: Server looks up the code, finds the `business_id`, and assigns the new user to it.

---

## 3. Backend Technical Decisions (Phase 2)

### 3.1 Project Structure (Go)
```
server/
├── cmd/
│   └── api/
│       └── main.go
├── internal/
│   ├── api/
│   │   ├── auth.go              # NEW: Login, Register, Invite handlers
│   │   ├── customers.go
│   │   └── transactions.go
│   ├── middleware/              # NEW: Auth middleware
│   │   └── jwt.go               # Validates token, sets context values
│   ├── db/
│   │   └── db.go
│   ├── models/
│   │   ├── business.go          # NEW
│   │   ├── user.go              # NEW
│   │   ├── customer.go
│   │   └── transaction.go
│   └── repository/
│       ├── auth_repo.go         # NEW
│       ├── customer_repo.go
│       └── transaction_repo.go
├── go.mod
└── go.sum
```

### 3.2 PostgreSQL Schema (Multi-Tenant)

All core tables must reference `business_id` to enforce strict row-level multitenancy.

```sql
CREATE TABLE businesses (
    id           UUID        PRIMARY KEY NOT NULL,
    name         VARCHAR(255) NOT NULL,
    type         VARCHAR(100),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE users (
    id           UUID        PRIMARY KEY NOT NULL,
    business_id  UUID        NOT NULL REFERENCES businesses(id),
    name         VARCHAR(255) NOT NULL,
    phone        VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role         VARCHAR(20) NOT NULL CHECK (role IN ('owner', 'staff')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE customers (
    id           UUID        PRIMARY KEY NOT NULL,
    business_id  UUID        NOT NULL REFERENCES businesses(id),
    name         VARCHAR(255) NOT NULL,
    phone        VARCHAR(50),
    notes        TEXT,
    created_by   UUID        NOT NULL REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted   BOOLEAN     NOT NULL DEFAULT FALSE
);

CREATE TABLE transactions (
    id               UUID        PRIMARY KEY NOT NULL,
    business_id      UUID        NOT NULL REFERENCES businesses(id),
    customer_id      UUID        NOT NULL REFERENCES customers(id),
    user_id          UUID        NOT NULL REFERENCES users(id),
    type             VARCHAR(10) NOT NULL CHECK (type IN ('debt', 'payment')),
    amount           NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    description      TEXT,
    transaction_date DATE        NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN     NOT NULL DEFAULT FALSE
);

-- Essential Indexes for Multitenancy
CREATE INDEX idx_customers_business ON customers(business_id);
CREATE INDEX idx_transactions_business ON transactions(business_id);
```

### 3.3 REST API Design (Updated)

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/auth/register-business` | None | Create business + owner |
| `POST` | `/api/v1/auth/login` | None | Get JWT |
| `POST` | `/api/v1/auth/invite` | Owner | Generate staff invite code |
| `POST` | `/api/v1/auth/join` | None | Staff registers via invite code |
| `GET` | `/api/v1/customers` | Staff/Owner | List customers (scoped to token's business_id) |
| `POST` | `/api/v1/transactions` | Staff/Owner | Create transaction |

---

## 4. Sync Architecture (Phase 3)

### 4.1 Syncing Multi-User Data
Because multiple users can modify the same Business data offline, conflict resolution is critical.

- **Last-Write-Wins (LWW)**: The server looks at the `updated_at` timestamp. If Bob (offline) updates Customer A, and Alice (online) updates Customer A, whoever's local timestamp is more recent wins when Bob eventually syncs.
- **Append-Only Transactions**: Transactions are immutable. If a mistake is made, we do not edit the transaction amount. Instead, we allow soft-deleting the transaction, or adding an offsetting transaction. This massively reduces sync conflicts.
- **Pulling Changes**: Every time the app comes online, it hits `/api/v1/sync/pull?last_sync=...`. The server returns all records for the `business_id` modified after that timestamp by *other* users. The local SQLite database is updated with these records.
