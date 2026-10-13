# Salio

Offline-first debt and credit tracker for small retailers — shops, agrovets, kiosks. It replaces the paper debt notebook. Currency is KES; users often have no working internet, so the app must be fully usable offline after first login.

Monorepo: `mobile/` (Flutter) · `server/` (Go, currently live) · `docs/` (specs)

---

## Domain invariants

Violating any of these is a bug, not a style preference.

1. **Every query is scoped by `business_id`.** A Business is the tenant. There is no such thing as an unscoped read of customers or transactions. This has already leaked once — see `docs/feedback.txt`.
2. **Transactions are immutable.** A mistake is corrected with an offsetting entry or a void, never by editing an existing row. This mirrors how a paper ledger works and is a deliberate product decision.
3. **Balances are always derived**, never stored: `SUM(debt) - SUM(payment)` over non-deleted transactions. Same formula on both sides of the wire.
4. **Nothing is hard-deleted.** `is_deleted` tombstones everywhere, so deletions can propagate through sync. A physically deleted row will be resurrected by the next device that syncs.
5. **The server clock is authoritative.** Never stamp sync state with device time — cheap Android clocks drift badly.

Four entities, in this hierarchy: **Business** (tenant) → **User** (owner or staff, logs in by *phone*, not email) → **Customer** (owes money, has no login) → **Transaction** (`debt` or `payment`, amount always > 0).

Roles: `staff` does all day-to-day work. `owner` additionally deletes customers, voids transactions, manages staff, and edits business details.

---

## Commands

```bash
# server/
make run              # dev server
make migrate-up       # apply migrations
make migrate-create NAME=add_something
make build            # → ./bin/salio-server
make create-admin NAME= EMAIL= PASSWORD=    # seed a console super-admin

# mobile/
flutter run --dart-define=API_URL=http://127.0.0.1:8080/v1
flutter analyze
```

`server/Makefile` does `include .env`, so database variables come from there.

---

## Layout and conventions

**Server** (chi + pgx, raw SQL, PostgreSQL). Strict one-way layering, declared in `internal/app/app.go`: repositories are the only layer touching the database; handlers are the only layer touching repositories, and they receive interfaces (`internal/api/interfaces.go`) so they mock cleanly. All routes are declared in one place — `buildRouter` in `app.go`. Migrations run through a hand-rolled runner in `cmd/migrate`, not the golang-migrate CLI.

The `/console/*` admin panel is server-rendered HTML in the same binary, with a **completely separate auth world**: `super_admins` + `console_sessions` and cookie sessions, never JWT, never business users.

**Mobile** (Flutter, `provider`). Feature-first: `lib/core/` plus `lib/features/<feature>/` holding a `*_provider.dart` (ChangeNotifier), an abstract `*_repository.dart`, and a `sqflite_*_repository.dart` implementation. There is no routing package — `AuthWrapper` in `main.dart` switches on `AuthState`. Providers are scoped through `ChangeNotifierProxyProvider<AuthProvider, X>`, which is what stops data leaking between accounts on a shared phone. Local database file is `salio_v3.db`.

Every SQLite query needs `business_id = ? AND is_deleted = 0`.

---

## Active work

**Backend rewrite onto the Tusk framework** — [`docs/08-tusk-rewrite-plan.md`](docs/08-tusk-rewrite-plan.md) is the authoritative plan. Read §2.3 for vocabulary and §5 before touching anything sync-related. Tusk itself lives at `/var/www/html/go/Tusk`.

The existing `server/` stays live and untouched until the replacement reaches parity.

**Running server-v2** — security model, the two database roles, Docker deployment and CI: [`docs/09-operations.md`](docs/09-operations.md). It must never run as a superuser: PostgreSQL silently exempts superusers from row-level security, which is how server-v2 ran from Phase 3 until 2026-10-13 without RLS ever being exercised.

**Known defects** are catalogued in the plan (§5, §8) and in `docs/feedback.txt`, which holds raw notes from a three-business field test. Two matter most:

- Sync silently and *permanently* hides records from other devices. Root cause is a commit-visibility race in the timestamp watermark, diagnosed in §5 — not a missing filter.
- `SqfliteSettingsRepository.getAllUsers()` has no `business_id` filter, so the staff list can show another business's users. Compounded by logout never clearing local SQLite.

---

## Docs

`docs/` is the written source of truth — check it before inventing requirements. `01-product-requirements.md` holds the roles/permissions matrix and feature IDs, though its "Phase 1 non-goals" list is stale (sync, roles and reports all shipped). `07-phase4-analytics-and-roles.md` is the most current architecture description of the shipped system.
