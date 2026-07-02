# Salio — Product Requirements Document (PRD)

**Version:** 1.1  
**Date:** June 2026  
**Status:** Active Development  
**Changelog:** v1.1 — Added multi-user Business model, User roles, and Authentication requirements.

---

## 1. Product Vision

> **"Replace the debt notebook. One tap at a time."**

Salio is a mobile-first, offline-first debt and credit tracking system that empowers small retail business owners and their staff to manage customer debts digitally — without needing constant internet access, accounting knowledge, or expensive hardware.

---

## 2. Core Concepts

Understanding three concepts is key to understanding Salio:

### 2.1 The Business
A **Business** is a shop, agrovet, kiosk, or any small retail operation. It is the central account in Salio. Every customer and every transaction belongs to a Business.

- Examples: "Kamau's Agrovet", "Mama Pima Kiosk", "Zawadi General Store"
- A Business has one **Owner** and can have multiple **Staff** members.
- All data (customers, debts, payments) is shared across all users of the same Business.

### 2.2 The User
A **User** is a person who manages the Business through the Salio app on their own phone.

- A Business owner and their staff each install the app on their own phones.
- They each log in with their own credentials.
- They all see and manage the same shared Business data.
- A User can only belong to one Business at a time.

### 2.3 The Customer (Buyer)
A **Customer** is a person who buys goods from the Business on credit. Customers do NOT have accounts in Salio — they are managed by the Business.

---

## 3. Target Users

### Primary User: The Business Owner
- Runs a small retail shop, agrovet, kiosk, or mobile stall.
- Sells goods on credit to regular customers.
- May have 1–4 staff members who also handle sales and credit.
- Currently tracks debts in a shared physical exercise book.
- Operates in areas with unreliable or slow internet.
- **Role in Salio:** `owner` — full control of the Business account.

### Secondary User: The Staff Member
- Works at the shop and handles sales and credit transactions on behalf of the owner.
- Has their own Android phone.
- Should be able to record debts and payments without the owner's phone.
- **Role in Salio:** `staff` — operational access (record debts/payments, view history).

### Tertiary User: The Customer (Indirect)
- A regular buyer who purchases goods on credit.
- Does not have a Salio account or access to the app.
- May verbally ask the shop owner for their current balance.

---

## 4. Problem Statement

Small retailers commonly extend credit to trusted customers. Existing workflows are entirely manual:
- Debt notebooks get lost, damaged, or are hard to read.
- When a shop has 2–3 staff, there is no single shared record — each person may have their own notebook or rely on memory.
- Partial payments are hard to track accurately.
- Overdue debts are forgotten or disputed.
- No quick way to view the total amount owed across all customers.

---

## 5. Goals & Non-Goals

### Goals ✅
- Allow a Business to onboard with a single account (owner creates the business).
- Allow the owner to invite staff members who can all share the same business data.
- Allow any authorized User to add customers, record debts, and record payments.
- View a customer's running balance and full transaction history.
- See a dashboard summary of all outstanding debts for the Business.
- Work fully offline after the initial setup — no internet required for day-to-day operations.
- Be fast — key actions should take under 3 taps.

### Non-Goals ❌ (Phase 1)
- No cloud backup or background sync (Phase 2).
- No invoice generation or printing.
- No SMS or WhatsApp notifications to customers.
- No accounting reports or charts.
- No multiple Business accounts per User.
- No customer-facing portal.

---

## 6. User Roles & Permissions

| Permission | `owner` | `staff` |
|---|---|---|
| View dashboard & all customers | ✅ | ✅ |
| Add new customer | ✅ | ✅ |
| Record debt | ✅ | ✅ |
| Record payment | ✅ | ✅ |
| View transaction history | ✅ | ✅ |
| Edit customer details | ✅ | ✅ |
| Delete a customer | ✅ | ❌ |
| Invite new staff member | ✅ | ❌ |
| Remove a staff member | ✅ | ❌ |
| View all staff members | ✅ | ✅ (read-only) |
| Change Business name/details | ✅ | ❌ |

---

## 7. Authentication Requirements

### Registration Flow (Owner)
1. Owner creates a new Business account (name, type, location).
2. Owner provides their name, phone number or email, and password.
3. Salio creates the Business and the Owner User account on the backend.
4. Owner is logged in and data is initialized on their device.

### Staff Invitation Flow
1. Owner taps "Invite Staff" in the app settings.
2. A unique invite code or link is generated for the Business.
3. Staff member enters the invite code during their own registration.
4. Staff account is created and linked to the Business on the backend.
5. Staff data syncs down to their device.

### Login (Returning User)
1. User enters their phone/email and password.
2. App sends credentials to the Go backend.
3. Backend validates and returns a JWT token.
4. Token is stored securely on the device (`flutter_secure_storage`).
5. Business data is synced to local SQLite.
6. App is ready for offline use.

### Offline Behaviour
- After the first successful login, the app works 100% offline.
- JWT is cached securely. Local SQLite is the source of truth for all operations.
- When internet is next available, the app auto-syncs changes to the backend silently.
- If the JWT expires while offline, the user is shown a gentle warning but can still use the app. A re-login is required on next internet connection.

---

## 8. Core Features — Phase 1 (MVP)

### F-00: Authentication
| # | Requirement |
|---|---|
| F-00.1 | Owner can create a new Business account (requires internet, one-time). |
| F-00.2 | Owner can invite staff via an invite code (requires internet, one-time). |
| F-00.3 | User can log in with phone/email and password (requires internet, first login). |
| F-00.4 | App works fully offline after first login using cached JWT + local SQLite. |
| F-00.5 | User can log out (clears token and local data from device). |

### F-01: Customer Management
| # | Requirement |
|---|---|
| F-01.1 | Any authorized User can add a customer with name and optional phone number. |
| F-01.2 | Users can view all customers for the Business with their current balance. |
| F-01.3 | Users can search/filter customers by name. |
| F-01.4 | Users can edit a customer's name or phone number. |
| F-01.5 | Only the `owner` role can delete a customer (with zero balance). |

### F-02: Debt Recording
| # | Requirement |
|---|---|
| F-02.1 | Any authorized User can record a new debt entry against a customer. |
| F-02.2 | Debt entry includes: amount, description/note, and date. |
| F-02.3 | Debt is immediately reflected in the customer's total balance. |

### F-03: Payment Recording
| # | Requirement |
|---|---|
| F-03.1 | Any authorized User can record a payment (full or partial) against a customer. |
| F-03.2 | Payment reduces the customer's outstanding balance. |
| F-03.3 | A customer's balance cannot go below zero (overpayment guard). |

### F-04: Customer Balance & History View
| # | Requirement |
|---|---|
| F-04.1 | Users can tap on a customer to view their full transaction history. |
| F-04.2 | History shows each debt and payment in chronological order. |
| F-04.3 | A running balance is visible at the top of the history screen. |
| F-04.4 | Each transaction shows which User recorded it (name of staff member). |

### F-05: Dashboard
| # | Requirement |
|---|---|
| F-05.1 | The home screen shows the total outstanding balance across all customers for the Business. |
| F-05.2 | The home screen shows a list of customers sorted by balance (highest first). |
| F-05.3 | Customers with a zero balance are visually distinct (labelled "Cleared"). |

### F-06: Business Settings
| # | Requirement |
|---|---|
| F-06.1 | Owner can view the list of all staff members. |
| F-06.2 | Owner can invite a new staff member via invite code. |
| F-06.3 | Owner can remove a staff member (revokes their access on next sync). |
| F-06.4 | Owner can view and edit the Business name and type. |

---

## 9. Success Metrics

| Metric | Target |
|---|---|
| Time to add a new customer | < 15 seconds |
| Time to record a debt | < 10 seconds |
| App load time (cold start, offline) | < 2 seconds |
| Crash rate | < 0.1% of sessions |
| Core operations without internet | 100% |
| First login/setup time | < 3 minutes |

---

## 10. Development Roadmap

### Phase 1: Mobile App MVP
- Auth (register business, login, invite staff)
- Customer management (all roles)
- Debt & payment recording (all roles)
- Local SQLite as source of truth
- JWT cached for offline use

### Phase 2: Go Backend
- REST API for auth, businesses, users, customers, transactions
- PostgreSQL as server-side source of truth

### Phase 3: Background Sync
- Bidirectional sync between local SQLite and backend PostgreSQL
- UUID-based conflict resolution
- Multi-device consistency

### Phase 4 (Future Ideas)
- SMS / WhatsApp debt reminders to customers
- Business analytics and reports
- Offline invite flow (QR code-based)
- Multiple business support per owner
