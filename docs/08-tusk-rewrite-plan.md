# Salio on Tusk — Backend Rewrite Plan

**Version:** 1.2
**Date:** 2026-09-07
**Status:** Proposed — awaiting approval before implementation
**Changelog:**
- v1.2 — §2.1 expanded into a full primary-key analysis (five candidates, six deciding factors, the UUIDv7 timestamp-leak tradeoff, where the standard sits). Added §2.3 vocabulary, §4.2 plain-English explanation of the worst gaps, §6.1 request-flow walkthrough. New open question on public identifiers.
- v1.1 — Added §2.1 and §2.2 (opt-in tenancy). Locked D5 opt-in tenancy, D6 Postgres-only, D7 no compatibility shim. §8 reframed as a mobile work list.

**How to read this document:** §1–6 explain the *why* — the decisions, the vocabulary, the current state of both codebases, and the defect driving the sync rewrite. §7 onward is the *what* — the phased work itself. Read §2.3 first if any terminology is unfamiliar.
**Scope:** Rewrite the Salio Go backend on the Tusk framework, and harden Tusk to production grade in the process.

Companion repo: `github.com/codetheuri/tusk` (local: `/var/www/html/go/Tusk`)

---

## 1. Executive Summary

Salio's backend today is a hand-rolled chi + pgx service: correct in shape, but every cross-cutting concern (auth, validation, responses, pagination, docs) was written once for this one product. Tusk already solves those concerns generically, with OpenAPI documentation, code-first RBAC, and a layered module convention.

This plan moves Salio onto Tusk. It is **not** a straight port. Two things get genuinely rebuilt rather than copied:

1. **The sync engine.** The current timestamp-watermark design has a race that permanently hides records from other devices. This is almost certainly the bug your field testers reported. Section 5 explains the mechanism. It needs a server-issued monotonic cursor, not a rewrite of the same idea.
2. **Multi-tenancy.** Tusk has no tenancy concept at all. Salio is tenant-scoped in every table. Rather than bolt `business_id` filters onto Salio's queries by hand (the current approach, which already leaked once), tenancy becomes a first-class Tusk capability that cannot be forgotten.

Work is sequenced so Tusk is solid *before* Salio rides on it. The existing Salio server keeps running untouched until v2 reaches parity.

---

## 2. Decisions & Key Concepts

| # | Decision | Rationale |
|---|---|---|
| D1 | **Tusk becomes UUID-native** (UUIDv7 primary keys) | Salio's offline-first client generates IDs on the phone before the server ever sees them. Auto-increment `uint` cannot express that. UUIDv7 is time-ordered, so it keeps B-tree index locality. |
| D2 | **New `salio/server-v2/`, existing `server/` stays live** | The current backend serves real businesses. No cutover until v2 has parity and the data migration is proven. |
| D3 | **Port the admin console, and make server-rendered pages a supported Tusk capability** | The console works and is used. Rather than mixing ad-hoc `html/template` into an API-first framework, Tusk gains a documented `pkg/view` + `pkg/session` story that every future project inherits. |
| D4 | **Harden Tusk first, then build Salio on it** | Building on a shifting base means Salio accumulates workarounds that later become load-bearing. |
| D5 | **Tenancy is opt-in per model, not framework-wide** | Tusk is a general framework; most apps are single-tenant. Tenancy that cannot be switched off would make Tusk useless for them. See §2.2. |
| D6 | **PostgreSQL only.** MySQL/SQLite support is deferred, not designed around. | Halves the migration surface, and RLS — the tenancy safety net — is Postgres-only anyway. Other drivers can be reintroduced later behind the same interfaces. |
| D7 | **No response-compatibility shim.** v2 uses Tusk's native envelope and route prefix; the Flutter app is updated to match. | The mobile client is under the same ownership and ships alongside. Building a compatibility layer would mean carrying two response formats forever to avoid a one-time client change. |
| D8 | **UUIDv7 primary keys exposed directly in the API. No public v4, no prefixes.** | Salio's ledger is seen only by the shop's own staff, and the leaked timestamp is a device clock the system already distrusts. See §2.1. |

### 2.1 Choosing a primary key: the full picture

This section exists because the choice is permanent. Changing a primary key type after launch means rewriting every table, every foreign key, and every stored reference in the system. It is worth understanding properly before Phase 2 begins.

#### The candidates

| Option | What it is | Size |
|---|---|---|
| **BIGINT auto-increment** | `1, 2, 3…` — the database hands out the next number | 8 bytes |
| **UUIDv4** | 128 bits of pure randomness | 16 bytes |
| **UUIDv7** | 128 bits: millisecond timestamp in front, randomness behind | 16 bytes |
| **ULID** | Same idea as v7, from userland, written in base32. Superseded now that v7 is an IETF standard and fits the native `uuid` column type. | 16 bytes |
| **Snowflake** | 64 bits: timestamp + machine number + counter. Compact and sortable, but requires assigning machine numbers. | 8 bytes |

```
v4 — fully random           f47ac10b-58cc-4372-a567-0e02b2c3d479
                            └──────── all random ────────┘

v7 — time-ordered           0192f8e2-7c00-7b3a-8f21-5c9e4d1a2b8f
                            └── ms timestamp ──┘└── random ──┘
```

#### The six factors that actually decide it

**1. Who creates the ID?** — usually decisive on its own.

If only the database ever creates IDs, BIGINT is fine, but you must ask the database for one before you can use it. You cannot know an ID in advance.

If anything else creates IDs — a phone, a browser, another service — you need something that cannot collide without coordination. Two machines that have never communicated must never produce the same ID. Randomness provides that; a counter cannot.

**2. Does the ID appear in public?**

Sequential numbers leak two things. They can be walked (`/orders/1`, `/orders/2`, `/orders/3`), and they leak volume — invoice #1847 tells a competitor roughly how much business you do. Sign up twice a week apart, subtract the IDs, and you know how many customers were gained in between. Random IDs leak neither.

**3. How fast do you write?**

A primary key lives in a sorted B-tree. Where a new ID lands decides what an insert costs.

```
BIGINT / UUIDv7  →  every new row lands at the END
                    [....................|NEW]
                    same page every time, already in memory — cheap

UUIDv4           →  every new row lands SOMEWHERE RANDOM
                    [...NEW....|.......NEW...|..NEW....]
                    cold page each time, pages split, index bloats
```

This is the entire reason v7 exists. Benchmarked on PostgreSQL 18, 500k single-client inserts: **BIGINT 278 ms, UUIDv4 705 ms, UUIDv7 455 ms.** Ordered range scans over a million rows run ~3× faster on v7 (~113 ms vs ~318 ms) with roughly 100× fewer buffer hits, since rows created near each other in time also sit near each other on disk. Index sizes: 11 MB / 19 MB / 15 MB.

At a few thousand writes a day this is invisible. At millions it dominates.

**4. Do you ever merge two databases?** Merging BIGINT tables is painful — both sides have a row 1. With UUIDs you concatenate and move on.

**5. Storage cost.** 16 bytes versus 8 doubles the key *and every foreign key and index pointing at it*. On a million rows this is noise. On hundreds of millions across many relationships it is real.

**6. What the ID itself reveals.**

UUIDv7 carries a timestamp. Anyone holding the ID knows when that record was created, to the millisecond, and can order any two IDs by creation time.

A common claim is that v7 is "less secure" than v4 because it has 74 random bits against v4's 122. **That framing is misleading.** 2⁷⁴ is roughly 19 sextillion — neither version is guessable. Guessability is not the concern.

The real concern is **metadata**. Two adjacent user IDs reveal that those two people registered seconds apart. Growth rate becomes readable from a handful of IDs. For ordinary business records this is harmless — `created_at` is usually exposed anyway. For anonymous, medical, or correlation-sensitive data it is a genuine leak.

#### Where the standard actually sits

RFC 9562 standardized UUIDv7 in May 2024; PostgreSQL 18 shipped native `uuidv7()` in late 2025. The prevailing recommendation for new projects is UUIDv7 as the default primary key.

The caveat that travels with it, and is now common practice: **UUIDv7 as the internal primary key, a separate UUIDv4 as the identifier exposed publicly.** Sorted inserts internally, nothing leaked externally. The cost is a second column and a second index.

#### Why D1 lands on UUIDv7

The decisive argument is an **asymmetry in the cost of being wrong**:

- Choose UUIDv7 where BIGINT would have sufficed → you paid 8 extra bytes per key.
- Choose BIGINT where UUID was needed → you cannot generate IDs offline, cannot merge databases, and retrofitting means rewriting every table and foreign key in the system.

One mistake is cheap; the other is close to unrecoverable. Salio sits squarely in the second case — the phone mints IDs while offline, hours before the server sees them. Two devices creating a customer in the same millisecond still produce distinct IDs via the random tail, yet those IDs sort adjacently by time.

In Go this is one call: `uuid.NewV7()`, present in `google/uuid` v1.6.0, already in Tusk's dependency tree.

#### Why the same choice applies to both Tusk and Salio

Tenancy is genuinely **per-model** — within one application some tables are tenant-scoped and some are not, so opt-in (§2.2) is correct there.

ID type is **per-application**. You pick one and use it throughout. Mixing `uint` and `UUID` in a single codebase is the worst available outcome: every join becomes awkward, every signature must state which kind it means, and eventually the wrong one gets passed. That is the hybrid option already rejected in D1.

Tusk's own tables therefore standardise on UUIDv7. **The escape hatch costs nothing:** an application with a measured reason to use BIGINT for its own high-volume domain tables simply defines them that way. GORM is indifferent, and no generic `Repository[T, ID]` machinery is required — which keeps faith with Tusk's rule against abstractions built for hypothetical futures.

#### Settled: public identifiers (D8, 2026-09-08)

**Salio exposes its UUIDv7 primary keys directly. No separate public UUIDv4, and no prefixes.**

The correlation risk that motivates a separate public ID does not apply here: Salio's data is a shop's own ledger, seen only by that shop's staff, and the embedded timestamp comes from a *device* clock the system already treats as unreliable. Prefixed identifiers (`cus_…`) were considered separately and also declined — with four entity types the confusion they prevent is modest, and they remain partly retrofittable by accepting both forms during a transition.

The options weighed:

| | Expose v7 directly | Separate v4 public ID |
|---|---|---|
| Schema | One column | Two columns, two indexes |
| API surface | `/customers/{uuid}` maps straight to the PK | Requires a lookup by public ID |
| Leaks creation time | Yes | No |
| Complexity | None | Every boundary must translate |

Recorded as **D8**. Revisit only if Salio ever exposes a customer-facing link containing an identifier.

### 2.2 How tenancy stays optional

The concern is real: a framework that forces `tenant_id` onto every table is unusable for the single-tenant projects Tusk is also meant to serve. So tenancy is **declared by the model, not imposed by the framework**.

```go
// Tenant-scoped: the model says so itself.
type Customer struct {
    ID         uuid.UUID `gorm:"type:uuid;primaryKey"`
    BusinessID uuid.UUID `gorm:"type:uuid;not null;index"`
}

func (Customer) TenantColumn() string { return "business_id" }

// Not tenant-scoped: nothing happens to it.
// No column, no injected filter, no runtime cost.
type Article struct {
    ID    uuid.UUID
    Title string
}
```

The GORM callback checks for that one interface method and skips every model that lacks it. An application that never implements it gets exactly today's Tusk behaviour.

Three consequences worth stating plainly:

1. **Returning the column name, not a fixed `tenant_id`,** lets Salio keep `business_id` while another product uses `org_id`. No renaming, no mapping table.
2. **RLS policies are written only for opted-in tables**, so a single-tenant schema carries no policies at all.
3. **The tenant middleware is inert unless a resolver is registered.** If an app never tells Tusk how to find a tenant, no tenant context is ever created.

This satisfies Tusk's own architectural test — the abstraction is visible in the model definition rather than hidden in framework configuration, and it is absent entirely for anyone who does not ask for it.

**Open design point for Phase 3:** Tusk's `users` table becomes tenant-scoped (a Salio user belongs to one business), but `roles` and `permissions` stay **global** — `owner` and `staff` mean the same thing in every business. That is correct for Salio today. If a future product needs per-tenant custom roles, `roles` can opt in later without disturbing anything else; that is precisely the flexibility the per-model design buys.

### 2.3 Vocabulary used in this plan

Plain-English definitions of every term that appears below. Skim it once; the phases assume it.

**Multi-tenancy** — one running application and one database serving many separate customers, with each customer's data invisible to the others. In Salio a "tenant" is a Business. The permanent risk is that one forgotten `WHERE business_id = ?` shows one shop another shop's ledger.

**Row-Level Security (RLS)** — a PostgreSQL feature where the *database itself* refuses to return rows that don't belong to the current tenant, no matter what the application asks for. You set a variable at the start of each transaction (`SET LOCAL app.tenant_id = …`) and the database filters everything from then on. It's a safety net beneath the application's own filtering: if a developer forgets a filter, the database still won't hand the rows over.

**Watermark (what Salio's sync uses today)** — the client remembers a timestamp and asks "give me everything changed after this". Simple, and broken in a specific way — see §5.

**Cursor (what it should use)** — the server issues a position marker, and the client asks "give me everything after this marker". The marker only advances past rows actually delivered, so nothing can slip underneath it.

**Tombstone** — a row marked deleted (`is_deleted = true`) rather than physically removed. You need this in a syncing system: if you truly delete a row, another device that never learned about the deletion will happily push it back and resurrect it. The tombstone is the record *of* the deletion.

**Last-Write-Wins (LWW)** — when two devices edit the same record, the later edit replaces the earlier one. Simple, and safe only when a record is a single indivisible fact. It's dangerous when one record holds several independent facts, because changing one field discards someone else's change to a different field.

**Idempotent** — an operation that produces the same result whether it runs once or five times. Critical for sync: if a phone times out mid-push and retries, the retry must not create duplicate transactions.

**RBAC (Role-Based Access Control)** — permissions attach to roles, roles attach to users. Instead of hardcoding `if role == "owner"`, you ask "does this user hold `customers.delete`?" Roles then become configurable data rather than code.

**Code-first permissions** — Tusk's approach: permissions are declared as Go constants in each module, then pushed into the database with `make auth-sync`. The code is the source of truth; the database is a synchronized copy.

**OpenAPI** — a machine-readable description of every endpoint, its inputs and its outputs. Tusk generates it automatically from typed Go structs, which is what powers the interactive `/docs` page. It cannot drift from the real API because it *is* derived from the real API.

**DTO (Data Transfer Object)** — the struct describing what an endpoint accepts or returns, kept deliberately separate from the database model. It lets the API shape change without touching the schema, and stops internal fields leaking outward by accident.

**Migration** — a versioned, ordered SQL file that moves the schema forward, with a matching file to move it back. Both Salio and Tusk use them; Tusk uses the `goose` tool.

**Soft delete** — see *tombstone*. Salio never hard-deletes anything.

**Immutable ledger** — Salio's transactions are never edited. A mistake is corrected by adding an offsetting entry or voiding the original, exactly as a paper accounting book works. This is a deliberate product decision, not a technical limitation, and it is why the sync layer merges only `is_deleted` on transactions.

---

## 3. Current State — Salio Backend

**Stack:** Go 1.25.4, chi v5, pgx v5 (raw SQL, no ORM), PostgreSQL, golang-migrate + a hand-rolled runner.

**Layering** (`internal/app/app.go` documents it explicitly): `main` → `app.New(cfg)` → repositories are the only layer touching the DB → handlers are the only layer touching repositories, and they receive interfaces (`internal/api/interfaces.go`) so they mock cleanly. This is a good structure and maps almost 1:1 onto Tusk's handler/service/repository split — with one difference: **Salio has no service layer.** Business logic currently lives in handlers and repositories.

**Schema** (5 migrations):

| Table | Notes |
|---|---|
| `businesses` | The tenant. UUID PK. |
| `users` | Owner/staff. UUID PK, `phone` UNIQUE, `role CHECK IN ('owner','staff')`, `is_active`. **No email column.** |
| `business_invites` | 6-char code, 24h expiry, single-use. SERIAL PK. |
| `customers` | UUID PK, soft-delete, unique phone per business (partial index). |
| `transactions` | UUID PK, `type CHECK IN ('debt','payment')`, `amount > 0`, soft-delete, immutable. |
| `super_admins` / `console_sessions` | Console auth — separate world, cookie sessions. |

**Route surface** (all under `/v1`, JWT except the auth trio):

```
POST   /v1/auth/register-business      public
POST   /v1/auth/login                  public
POST   /v1/auth/join                   public
POST   /v1/auth/invite                 owner
GET    /v1/customers                   owner+staff
POST   /v1/customers                   owner+staff
GET    /v1/customers/{id}              owner+staff
PUT    /v1/customers/{id}              owner+staff
DELETE /v1/customers/{id}              owner
GET    /v1/customers/{id}/transactions owner+staff
POST   /v1/transactions                owner+staff
DELETE /v1/transactions/{id}           owner        (void)
GET    /v1/users/me                    any
PUT    /v1/users/me                    any
PUT    /v1/business                    owner
GET    /v1/staff                       owner+staff
DELETE /v1/staff/{id}                  owner        (deactivate)
GET    /v1/sync/pull                   any
POST   /v1/sync/push                   any
GET    /v1/reports/summary             any
GET    /console/*                      super-admin, cookie session, HTML
```

**What is genuinely good and should survive the rewrite:**
- Server-authoritative clocks (`updated_at = NOW()` on upsert, never trusting device time)
- Tenant guard baked into the upsert SQL (`WHERE table.business_id = EXCLUDED.business_id`)
- `business_id` taken from JWT claims, never from the request body
- Immutable ledger with soft-delete tombstones
- Balance always derived, never stored

---

## 4. Current State — Tusk, and the Gap Analysis

**Stack:** Go 1.25.7, Huma v2 (OpenAPI 3.1) + chi, GORM (MySQL/Postgres/SQLite), goose migrations, code-first RBAC.

**What Tusk already does better than Salio's backend:**
- Auto-generated OpenAPI spec + interactive docs from typed DTOs
- Standardized response envelopes (`pkg/response`)
- Pagination/filter/sort engine (`pkg/query`)
- Full RBAC: roles, permissions, code-first registry, `tusk auth sync` CLI
- Refresh-token rotation, account lockout after failed logins
- Handler → service → repository with a real service layer

### 4.1 Gaps found (each becomes a Phase 1 task)

| # | Gap | Where | Severity |
|---|---|---|---|
| G1 | **Rate limiter written but never wired.** `internal/middleware/ratelimit.go` exists; `app.New()` never calls it. Salio's current server *does* rate limit — this would be a regression. | `internal/app/app.go` | High |
| G2 | **Per-request DB query in auth middleware.** `HumaAuthenticate` runs `SELECT is_super_user FROM users` on *every authenticated request*. | `internal/middleware/jwt.go` | High |
| G3 | **Invalid tokens fall through silently.** `HumaAuthenticate` does not distinguish "no token" from "malformed/expired token" — both proceed unauthenticated, surfacing as a confusing 403 instead of 401. | `internal/middleware/jwt.go` | High |
| G4 | **Raw-string context keys.** `context.WithValue(ctx, "user_id", ...)` alongside the typed `ContextKeyUserID`. Both are set, so the collision-prone one is load-bearing. Violates Tusk's own `gostyle` rule. | `internal/middleware/jwt.go`, `pkg/authz/middleware.go` | High |
| G5 | **No request body size limit.** Unbounded POST bodies — a DoS vector, and Salio's sync push is the largest body in the system. | `internal/app/app.go` | High |
| G6 | **Migrations are MySQL-only.** `00001_identity_auth_rbac.mysql.sql` is a single goose migration with MySQL syntax. Against Postgres it will fail. Per **D6** this is resolved by rewriting it as Postgres and dropping the other dialects rather than maintaining a set per driver. | `database/migrations/` | High |
| G7 | **Config has no validation.** No JWT secret length check (Salio enforces ≥32 chars), pool sizes hardcoded instead of env-driven, dead commented-out lines, no `IsProduction()` helper. | `config/config.go` | Medium |
| G8 | **Server timeouts too tight for sync.** `ReadTimeout: 5s` / `WriteTimeout: 10s`. A first-sync push from a phone with months of offline data on a 2G connection will be cut off. No `ReadHeaderTimeout` or `MaxHeaderBytes`. | `internal/app/app.go` | Medium |
| G9 | **Docs always public.** `/docs` and `/openapi.json` are served unconditionally. | `internal/app/app.go` | Medium — *your explicit ask* |
| G10 | **Two parallel auth middlewares.** `Authenticate` (net/http) and `HumaAuthenticate` (Huma) duplicate JWT parsing. They will drift. | `internal/middleware/jwt.go` | Medium |
| G11 | **Custom console logger, not structured.** No JSON output, no request/trace correlation IDs. | `pkg/logger/` | Medium |
| G12 | **No multi-tenancy whatsoever.** | framework-wide | Blocking for Salio |
| G13 | **Health checks hand-format JSON strings** with `fmt.Sprintf`; no `/live` vs `/ready` split beyond one DB ping. | `internal/app/app.go` | Low |
| G14 | **No integration tests.** `pkg/*` has unit tests; the auth module and DB layer have none. | repo-wide | Medium |

**Already good, no action needed:** `.env` is correctly gitignored and no secrets are tracked in git.

### 4.2 What the four worst gaps actually mean

The table above is terse. These four deserve plain explanation, because they are the ones that would hurt in production.

**G1 — the rate limiter that isn't running.** The code exists and looks finished, so it reads as "done" at a glance. But `app.New()` never installs it, which means every endpoint currently accepts unlimited requests per second from a single IP. Salio's existing backend *does* rate limit, so migrating to Tusk as-is would quietly remove a protection that is in place today. Anyone who finds the login endpoint can brute-force passwords as fast as the network allows.

**G2 — a database query on every single request.** `HumaAuthenticate` runs `SELECT is_super_user FROM users WHERE id = ?` for every authenticated call, just to learn one boolean. At 100 requests per second that is 100 extra queries per second doing nothing useful. The fix is to put the flag in the JWT where the rest of the identity already lives, so it arrives with the request instead of being fetched. The tradeoff is that a revoked super-user keeps the flag until their token expires — acceptable for a rarely-changing flag, and it is why *permissions* should stay in the database rather than the token.

**G3 — invalid tokens are treated like no token.** If a token is expired or malformed, the middleware currently shrugs and lets the request proceed unauthenticated. The request then fails later at the permission guard, so the caller receives **403 Forbidden** ("you're not allowed") when the truthful answer is **401 Unauthorized** ("your session expired, log in again"). The mobile app cannot tell these apart, so it cannot know to refresh the token. A user whose token expired sees a permissions error instead of being sent to the login screen.

**G4 — context keys that can collide.** Go's `context` is a shared bag of values keyed by any type. When you use a plain string like `"user_id"` as the key, any other library doing the same thing overwrites your value — silently, at runtime, with no compile error. The standard solution is a private named type, which Tusk already defines (`ContextKeyUserID`)… and then sets the raw string version alongside it. Since `pkg/authz` reads the raw string one, the unsafe key is the one actually load-bearing. Tusk's own Go style rules forbid this.

---

## 5. The Critical Finding — Why Sync Silently Loses Records

Your field feedback says:

> *"when a user updates a record/transaction and syncs the change to server they get a success message however when the other staff logs into the business app they can't see the changes even after they hit the sync button but it worked after they logout then login"*

Here is the mechanism.

**Pull** returns rows `WHERE updated_at > last_sync`, and hands the client a `server_time` to store as the next `last_sync`. **Push** stamps rows `updated_at = NOW()`.

In PostgreSQL, `NOW()` returns the **transaction start** time — but rows only become **visible to other transactions at commit**. Those are different instants.

```
Device A  ─── push tx BEGIN ──────────────── COMMIT ───►
              t1: rows stamped              t3: rows visible
              updated_at = t1

Device B  ──────────────── pull @ t2 ──────────────────►
                           (t1 < t2 < t3)
                           sees nothing — A's rows uncommitted
                           saves last_sync = t2
```

Device B now holds a watermark of `t2`. Device A's rows carry `updated_at = t1`, which is **below** that watermark. Every future pull asks for `updated_at > t2` and will never return them.

The records are not delayed. They are permanently invisible — until `last_sync` is destroyed. And `last_sync` lives in secure storage, which **logout clears**, resetting the watermark to epoch and forcing a full re-pull. That is exactly why logging out and back in "fixes" it.

This matches published guidance on sync design directly: *"A simple timestamp can miss changes when clocks differ or several rows share the same precision. Prefer a server-issued monotonic cursor backed by a change sequence."*

**Two secondary defects compound it** (both confirmed in code):
- `SqfliteTransactionRepository.softDelete()` sets `is_deleted = 1` but never bumps `updated_at`, so **voided transactions fall outside the push window and never reach the server at all.**
- The server's transaction upsert merges only `is_deleted` and `updated_at` on conflict, so any edit to `amount`/`description` is accepted with a 200 and silently discarded.

**Conclusion:** the sync engine is rebuilt in Phase 6, not ported. This is the single highest-value item in the plan.

---

## 6. Target Architecture

```
                 ┌──────────────────────────────────┐
                 │   Flutter app (offline-first)     │
                 │   SQLite = local source of truth  │
                 └──────────────┬───────────────────┘
                                │ HTTPS + JWT
                 ┌──────────────▼───────────────────┐
                 │       salio/server-v2 (Tusk)      │
                 │                                   │
                 │  Huma v2 API  ──► OpenAPI 3.1     │
                 │      │           (gated in prod)  │
                 │      ▼                            │
                 │  Handlers ─► Services ─► Repos    │
                 │      │                     │      │
                 │  pkg/tenant (auto-scoping) │      │
                 │      │                     ▼      │
                 │  pkg/authz (RBAC)      PostgreSQL │
                 │  pkg/view + pkg/session   + RLS   │
                 │      └─► /console (HTML admin)    │
                 └───────────────────────────────────┘
```

**Module map — old to new:**

| Salio `server/` | Salio `server-v2/` | Notes |
|---|---|---|
| `internal/api/auth.go` | `internal/business/` | register-business, join, invite. Login/refresh/logout come free from Tusk's auth module. |
| `internal/api/customers.go` | `internal/customer/` | handler + service + repository |
| `internal/api/transactions.go` | `internal/ledger/` | Named for what it is: an immutable ledger. |
| `internal/api/sync.go` | `internal/sync/` | Rebuilt — see Phase 6. |
| `internal/api/reports.go` | `internal/reports/` | Queries port nearly as-is. |
| `internal/console/` | `internal/console/` | Rebuilt on `pkg/view` + `pkg/session`. |
| `middleware.RequireRole("owner")` | `guard.Protected(op, PermCustomersDelete)` | Role checks become permission checks. |
| `businesses` table | tenant table for `pkg/tenant` | |

### 6.1 How one request travels through the system

Worth walking once, because every module in Phase 5 follows this exact path. Take `DELETE /api/v1/customers/{id}` — an owner deleting a customer.

```
1. Middleware chain
   request ID → structured log → panic recovery → CORS
   → security headers → rate limit → body size limit → timeout

2. Authentication
   JWT parsed once. user_id, business_id, role, is_super_user
   land in a typed context value. Invalid token → 401 here,
   not later (fixes G3).

3. Tenant resolution                                    [Phase 3]
   business_id from the token becomes the tenant context.
   A transaction opens and issues SET LOCAL app.tenant_id.
   From here the database itself will not return other
   businesses' rows.

4. Permission guard                                     [pkg/authz]
   Does this user hold customers.delete?
   No → 403. Yes → continue.
   Replaces the old hardcoded RequireRole("owner").

5. Handler                                              [internal/customer]
   Validates the path parameter is a UUID. Nothing else.
   No business rules live here.

6. Service
   Business rules: does the customer exist, is the balance
   zero, is deletion permitted? Returns domain errors —
   it has never heard of HTTP status codes.

7. Repository
   Executes the soft delete. The tenant predicate is injected
   automatically for models declaring TenantColumn(), so it
   cannot be forgotten.

8. Response
   Service error → mapped to a status code by the handler.
   Success → the standard {success, message, data} envelope,
   which is also what the OpenAPI spec documents.
```

Two properties fall out of this arrangement, and they are the reason for the layering:

**Tenant isolation is enforced three times independently** — the token decides the tenant (step 3), the query builder injects the filter (step 7), and the database refuses foreign rows regardless (step 3's RLS). Any one of the three failing still leaves two intact. Salio's current backend has only the middle one, applied by hand.

**The business rules in step 6 are testable without HTTP.** No request, no router, no status codes — just inputs and domain errors. That is what "services never know about HTTP" buys, and it is why the service layer exists even though Salio's current backend does without one.

### 6.2 Role → permission mapping

Salio's two hardcoded roles become seeded Tusk roles:

| Permission | `owner` | `staff` |
|---|---|---|
| `customers.read` / `.create` / `.update` | ✅ | ✅ |
| `customers.delete` | ✅ | ❌ |
| `transactions.create` | ✅ | ✅ |
| `transactions.void` | ✅ | ❌ |
| `staff.read` | ✅ | ✅ |
| `staff.invite` / `staff.remove` | ✅ | ❌ |
| `business.update` | ✅ | ❌ |
| `reports.read` | ✅ | ✅ |
| `sync.push` / `sync.pull` | ✅ | ✅ |

---

## 7. Phased Plan

### Phase 0 — Foundations & agent memory *(both repos)*

- Create `.claude/` in both repos with `CLAUDE.md` as the entry point.
- Migrate Tusk's `.agents/rules/*.md` into the Claude convention. The rules themselves are good and stay verbatim in substance — architecture philosophy, layer responsibilities, Go style, security, performance. Decide whether `.agents/` stays for Windsurf compatibility (recommendation: keep both, single source in `.claude/`, `.agents/` symlinked or generated).
- Salio gets its own `.claude/CLAUDE.md` covering the domain invariants, the tenancy rule, and the ledger-immutability rule.
- **Deliverable:** an agent working in either repo picks up the correct conventions without being told.

### Phase 1 — Tusk hardening *(G1–G11, G13–G14)*

Ordered by risk:

1. Wire the rate limiter; add request body size limits (G1, G5).
2. Consolidate the two auth middlewares into one; reject invalid tokens at the edge with 401; move `is_super_user` into JWT claims to kill the per-request query (G2, G3, G10).
3. Purge raw-string context keys; expose typed accessors only (G4).
4. Rewrite migrations as PostgreSQL and retire the MySQL dialect (G6, D6). Integration tests run against a real throwaway Postgres — **not** SQLite, which would silently diverge on the RLS, partial-index, and `ON CONFLICT` behaviour Salio depends on.
5. Config validation with fail-fast startup, `IsProduction()`, env-driven pool sizing (G7).
6. Realistic server timeouts + `ReadHeaderTimeout`/`MaxHeaderBytes` (G8).
7. **Docs gating (G9).** Huma supports this natively: setting `Config.DocsPath` and `Config.OpenAPIPath` to `""` removes those routes entirely. Design: `DOCS_ENABLED` env var, defaulting to *off* when `APP_MODE=production`. API endpoints stay fully live — only the docs UI and spec disappear. Optional upgrade: serve docs behind a super-admin session so you can still read them in production when you need to.
8. Structured logging on `log/slog` with JSON in production, `request_id` on every line (G11).
9. Health/live/ready split with proper JSON encoding (G13).
10. Integration test harness against a throwaway Postgres (G14).

**Exit criteria:** `make vet` and `make test` clean; a documented `.env.example` that fails loudly when incomplete; docs verifiably absent in production mode.

### Phase 2 — Tusk goes UUID-native *(D1)*

- Adopt `uuid.UUID` (UUIDv7 via `uuid.NewV7()`, available in `google/uuid` v1.6.0) across auth/RBAC models, `authz.Subject`, JWT claims, and the subject extractor.
- Rewrite migration `00001` rather than layering a conversion — Tusk is a boilerplate with no production data to preserve.
- Postgres 18 also has a native `uuidv7()` if you prefer DB-side generation; Salio needs **client-side** generation regardless, so the Go path is the primary one.
- Rationale, benchmarks and the timestamp-leak tradeoff are in **§2.1** — read it before starting this phase rather than re-deriving the argument here.
- **Depends on open question 4** (public identifiers). If Salio carries separate public UUIDv4 IDs, that column belongs in the schema from the start; adding it later means changing every API path and every client that stored one.

**Exit criteria:** full auth flow (register → login → refresh → RBAC guard) green on UUID keys against Postgres.

### Phase 3 — Tusk multi-tenancy (`pkg/tenant`) *(G12)* — ✅ complete (2026-09-08)

The research consensus for B2B SaaS in 2026 is **shared schema + `tenant_id` + application scoping + Postgres RLS as a safety net**. Schema-per-tenant and DB-per-tenant are not worth it at Salio's shape.

Per **D5**, all of this is opt-in per model (§2.2). An application that declares no tenant-scoped models is unaffected by this phase.

Three layers, each independently sufficient to prevent a leak:

1. **Context propagation** — middleware extracts the tenant from JWT claims into a typed context value. Handlers never read it from the request body. Inert unless the app registers a resolver.
2. **Automatic query scoping** — a GORM callback injects the tenant predicate for models implementing `TenantColumn()`, so a developer *cannot forget it*. This is the layer Salio's current backend lacks, and forgetting it by hand is exactly how the mobile staff-list leak happened.
3. **Postgres RLS** — `SET LOCAL app.tenant_id` inside a transaction-per-request, with policies on opted-in tables so the database itself refuses cross-tenant rows regardless of application bugs.

Plus explicit cross-tenant isolation tests — the kind that assert tenant B's token returns 404, not 403, for tenant A's record.

**Exit criteria:** a test suite that attempts cross-tenant access through every route and fails closed at both the app and DB layer — *and* a single-tenant smoke app that builds and runs against the same Tusk build with no tenant columns anywhere, proving D5 holds.

**Outcome.** All three layers shipped in `Tusk/pkg/tenant`, 21 tests green against PostgreSQL 15.

The D5 proof turned out not to need a separate smoke app. The callbacks are registered by `NewGoRMDB` for every connection, and `internal/testdb` mirrors that — so Tusk's own auth suite (no tenanted models, no tenant ever in context) *is* the single-tenant application, running the full register → login → refresh → RBAC flow against the same build. It passes unchanged. A purpose-built smoke app would have proved less, because it would have been written to succeed.

Two findings worth carrying forward into Salio:

- **`root` on the dev container is a superuser with `BYPASSRLS`.** PostgreSQL exempts such roles from every policy, silently — policies install, show up in `\d`, and are never consulted. The RLS tests therefore create a dedicated unprivileged role and connect as it; run as `root` they would have passed while proving nothing. `tenant.VerifyEnforcement(db)` reports this, and **Salio v2 must call it at startup and must not connect as a superuser in production.**
- **The harness had been testing the wrong driver.** `internal/testdb` opened connections with lib/pq while `gorm.io/driver/postgres` uses pgx in production. Fixed. Separately, database tests across packages now serialise on an advisory lock — `go test ./...` runs packages concurrently and each truncates the schema, which produced failures that looked like application bugs.

**Resolved 2026-09-08 — how `server-v2` consumes Tusk.** Hybrid: promote only what is needed. `pkg/middleware` and `pkg/app` moved out of `internal/`, `internal/platform/database/gorm.go` became `database/connect.go` (`NewGoRMDB` → `Connect`), and `internal/auth` stays internal. `pkg/app.New` now takes an `Options` struct and registers no routes; callers register modules against `App.API()`. `server-v2` will therefore be its own module with `require github.com/codetheuri/tusk`, writing its own phone-only auth module against `pkg/authz`.

Original framing, kept for the reasoning: `internal/middleware`, `internal/auth` and `internal/app` are under `internal/`, so a separate `salio/server-v2` module *cannot import them*; it would get `pkg/*` and `config` only, losing the auth module and the middleware chain. Two shapes: (a) `server-v2` is scaffolded from the Tusk repo structure and Tusk improvements are merged in, or (b) what Salio needs is promoted out of `internal/` into `pkg/` and `server-v2` imports `github.com/codetheuri/tusk` as a dependency. This must be settled before Phase 5 begins.

### Phase 4 — Tusk view & session support *(D3)* — ✅ complete (2026-09-08)

- `pkg/view`: `html/template` with layout inheritance, dev-mode hot reload, production caching.
- `pkg/session`: DB-backed cookie sessions, HTTP-only + Secure + SameSite, rotation on privilege change.
- Documented as a first-class Tusk capability so the Huma API and an HTML admin panel coexist cleanly in one binary.

**Outcome.** Both shipped, 22 tests green. Designed against the *existing* console in `server/internal/console/`, which is where the following defects came from — all of them are things the new packages make impossible rather than merely discourage. Fix them during the Phase 5 port:

| Defect in today's console | What replaces it |
|---|---|
| `render()` executes straight to the `ResponseWriter`, so a template error mid-page has already sent `200` and half the HTML | `view.Engine.Render` buffers, and writes nothing until the whole page succeeds |
| Templates are re-parsed on **every** request in production — the "add that optimisation later" comment was never revisited | `view.Config.Reload`, defaulting to cached |
| Only `login.html` is validated at startup; any other broken page fails when a user opens it | `view.New` parses every page, so a bad template stops the process starting |
| `console_sessions.id` **is** the cookie value — the raw token is stored in the clear, so a database dump hands over every live session | `session.Session` stores only the SHA-256 digest |
| `ShowLogin` redirects when the cookie merely *exists*, so a stale cookie loops `/console/login` → `/console/dashboard` → back | `session.Middleware` clears a dead cookie and `FromContext` reports validity, not presence |
| No idle timeout, no "sign out everywhere" | `Options.IdleTimeout`, `DestroyAll` |
| No rotation on privilege change | `session.Rotate`, which inherits the absolute expiry rather than restarting it |

Salio's console authenticates `super_admins`, not Tusk `users`. That works unchanged: `session.Session.SubjectID` deliberately carries no foreign key, and `Options.Kind` keeps console sessions from ever resolving against ordinary user sessions in the same table.

Two framework-level fixes fell out of this phase: `database.ResetMigrations` (the round-trip migration test had been reverting a single step and, with only one migration in the tree, appeared to verify the whole rollback path), and the removal of `lib/pq` — config, the migrate CLI and the tests all used it while GORM used pgx, so the schema was built by one driver and used by another.

### Phase 5 — Salio domain modules — ✅ complete (2026-09-08)

Build in dependency order: `business` → `customer` → `ledger` → `reports` → `console`.

**Status (2026-09-08): all five done — `business`, `customer`, `ledger`, `reports`, `console`. Phase 5 complete.**

**`reports` went beyond v1's single-summary endpoint deliberately.** v1's `GET /v1/reports/summary` returned five scalars, including one single "highest debt customer" name. Discussed with the user and rebuilt as an actual dashboard: the same totals, plus two ranked, capped (10 each) actionable lists — `top_debtors` (by balance, for prioritising collection) and `overdue_debtors` (balance > 0 and no activity in 30+ days, ranked by staleness — the list an owner is most likely to have forgotten). `overdue_debtor_count` reports the true count even when the list itself is capped for display.

This module's queries are the plan's first case of joining two tenanted tables in one query (`transactions` JOIN `customers`). Tusk's automatic tenant scoping only patches the *base* table of a query (the one passed to `.Model()`), not a join partner — so every query states `customers.business_id = ?` explicitly rather than trusting `transactions.customer_id` to only ever point at same-tenant rows. Worth remembering for `console` and anywhere else a report joins tables.

Two real defects found building `ledger`, both fixed in Tusk itself so every future service inherits the fix:

- **`Huma` schema types colliding across modules.** Huma names OpenAPI schemas after a Go type's bare name; `customer.View` and `ledger.View` collided and panicked at boot (`duplicate name: View`). Not a Tusk bug — but worth remembering as a Salio-wide convention: **every module's response DTO type must be package-distinctive** (`CustomerView`, `TransactionView`, not `View`), never assume a bare `View`/`Input`/`Output` is safe just because it compiles.
- **A custom-JSON type needs its own Huma schema, or requests to it fail before your code runs.** `money.Amount` has `MarshalJSON`/`UnmarshalJSON` producing/accepting a decimal string, but Huma's schema generator falls back to the Go *kind* (`int64` → `{"type":"integer"}`) unless a type implements `huma.SchemaProvider`. Every real HTTP request carrying `"amount":"1500.50"` was rejected — "expected integer" — before the handler or `UnmarshalJSON` ever ran; the bug was invisible to service-layer tests because they call `Service.Create` directly with an in-memory `money.Amount`, never through JSON. Fixed with `Amount.Schema(r huma.Registry) *huma.Schema` declaring itself a pattern-validated string. **Any future custom-marshalled type needs the same treatment**, and the way to actually catch this class of bug is a live HTTP request, not just a unit test — which is why every module in this phase has been verified by booting the real server and curling it end to end, not just `go test`.

**`console` is the one component that reads across every business**, and that made it the module where the tenancy design had to be finished rather than merely used.

It authenticates `super_admins` on Tusk's `pkg/session` (cookie, DB-backed, SHA-256 digest only), renders through `pkg/view` (buffered, all pages parsed at boot, templates and CSS embedded in the binary), and mounts on `App.Router()` rather than `App.API()` so none of it appears in the OpenAPI document the phone reads. Everything in the Phase 4 defect table above is now actually fixed, not merely preventable.

**The finding worth carrying forward: row-level security made the console structurally impossible until it was given an explicit door.** Migration 00003 put `users`, `customers`, `transactions` and `business_invites` under policies keyed on `app.tenant_id`. A console query declares no tenant — it is reporting on all of them — so under a correctly configured production role every one of those reads returns *zero rows*. Nothing errors. Development never sees it, because development connects as `root`, a superuser, and PostgreSQL exempts superusers from every policy silently. The console would have shipped working perfectly on this machine and shown a dashboard of zeroes in production.

Migration `00004_console_platform_read.sql` adds `OR current_setting('app.platform_admin', true) = 'on'` to the four policies' **`USING` clause only**, leaving `WITH CHECK` exactly as it was. So the door grants reads and no writes *at the database level*: a bug or an attacker holding a console session still cannot insert or move a row across a business boundary. `console.Repository.readAll` is the single place that opens it, with `SET LOCAL` inside a transaction so the flag cannot survive on a pooled connection into the next request. Three tests connect as a deliberately unprivileged role to prove all of it — that the console reads everything, that a write through the flag is refused *by the policy* and not by a missing grant, and that the flag is gone after the transaction commits.

`cmd/api` now also calls `tenant.VerifyEnforcement` at boot and logs a warning when the role is exempt. A warning rather than a fatal: development connects as a superuser by design, and a check that refuses to start is a check someone deletes.

Two v1 console defects fixed while porting, both in the same query: businesses were joined to `users` on `role = 'owner'` with an **inner** join, so a business with two owners appeared twice, and a business whose only owner had been deactivated **vanished from the console entirely** — the one an operator is most likely to be hunting for. A `LEFT JOIN LATERAL` preferring an active owner fixes both. Also: `super_admins` are created by `cmd/createadmin` reading the password from the environment or stdin, never from a flag as v1's `make create-admin PASSWORD=…` did — arguments are world-readable in `/proc` and land in shell history.

Two smaller traps found here, both worth knowing before Phase 6:

- **GORM resets a struct destination before scanning into it.** Two `Raw(...).Scan(&detail)` calls onto the same value silently zero every column the second query does not name. Caught by a test; it had already emptied a customer count and a balance the first query computed correctly.
- **`testdb.DSN()` does not know about `Options.DefaultDSN`.** A downstream service using `ConnectWith` that opens a second connection of its own gets *Tusk's* test database, and the symptom is `relation "businesses" does not exist` — which reads exactly like a bug in the query. `testsupport.DSN()` now resolves it correctly for Salio; worth fixing in Tusk itself.

Each module follows the Tusk convention: `model.go`, `dto.go`, `permissions.go`, `repository_*.go`, `service_*.go`, `handler_*.go`, `router.go`.

**Known gap to resolve here:** Tusk's `users` table requires `username` and `email` as NOT NULL unique. **Salio users have neither — they authenticate by phone only.** Tusk's flexible login already accepts phone; making `email`/`username` nullable is a small, correct change that benefits any phone-first product.

### Phase 6 — The sync engine, rebuilt — ✅ complete (2026-09-08)

Design changes, each traceable to Section 5 or to published sync guidance:

| Change | Replaces | Why |
|---|---|---|
| Server-issued monotonic **change sequence** (`BIGSERIAL`, or an append-only `sync_log`); pull by cursor | `updated_at > last_sync` watermark | Eliminates the commit-visibility race entirely. A cursor advances only past rows actually returned. |
| **Paginated pull** with a continuation cursor | Unbounded single response | A business with 10k transactions currently pulls everything in one payload. |
| **Idempotent push** keyed on client-generated operation IDs | Best-effort retry | A retried push after a timeout must not double-apply. |
| **Formal tombstones** + max-offline-age policy | Ad-hoc `is_deleted` | Past the max age, invalidate the cursor and force full resync. This GCs tombstones and kills row resurrection in one rule. |
| **Per-field merge** for customers; append-only for transactions | Whole-record LWW | Record-level LWW is unsafe once a record holds independent facts. Transactions stay immutable — only `is_deleted` merges. |
| Explicit **conflict reporting** in the push response | Silent 200 | Today an edit can be discarded while the client is told "Sync successful". |

**Coordinated mobile changes** (unavoidable, and they fix known bugs anyway):
- Bump `updated_at` on transaction soft-delete
- Store and send a cursor instead of a timestamp
- Clear the local SQLite database on logout — this closes the confirmed cross-tenant staff-list leak

**Outcome.** `server-v2/internal/syncengine`, migration `00005_sync_engine.sql`, 22 tests, verified live over HTTP. All six changes above shipped. Named `syncengine` rather than `sync` so the package can use the standard library's `sync` without an alias.

The headline test is `TestPull_DoesNotLoseAWriteCommittedAfterAConcurrentPull`: it holds a write open across a pull — exactly the interleaving §5 diagnoses — and asserts the cursor did **not** advance past a row it never delivered. That single assertion is the fix; a clock-based watermark jumps to "now", which is later than the pending row's timestamp, and the row is then invisible forever.

What each of the other five closes, and the thing worth remembering about it:

- **Paginated pull.** The two tables share one sequence, so their pages interleave, and the cursor may only advance to a point *both* have covered. If customers fill a page to seq 900 while transactions are exhausted at 480, advancing to 900 loses every transaction later written between 481 and 900 — the next pull asks for `> 900` and never looks below again. The page is cut back to the lower boundary instead.
- **Idempotent push.** A client generates an `operation_id` and reuses it across retries; the *whole response* is stored under it, so a retry replays byte-identical output rather than re-applying. Claimed inside the same transaction as the work, so a crash between the two cannot leave a batch applied and unclaimed.
- **Per-field merge.** `customers.field_versions` (JSONB) records when each field last accepted a write, and a push declares `changed_fields`. Two staff editing phone and notes offline now both keep their edit. Written as `field_versions || ?::jsonb` so a server-side merge cannot lose another writer's key in a read-modify-write gap. Absent `changed_fields` falls back to whole-record LWW — old app versions keep working, and are never worse off than before.
- **Tombstones + max offline age.** `sync_tombstone_horizon` holds the highest collected `change_seq`; a cursor at or below it gets `resync_required`. The two halves are one mechanism: collecting tombstones without raising the horizon resurrects rows, raising it without collecting keeps them forever. `cmd/syncgc` runs it deliberately — a timer inside the API quietly deleting ledger history is not a default worth having.
- **Explicit conflicts.** Nothing aborts a batch any more. v1 returned 500 on one bad record, so a device retried the same doomed payload forever and the good records never landed. Everything acceptable is applied and the rest is reported with a reason.

**A decision that touches an invariant, made deliberately.** Per-field merge orders edits by the *device's* clock, which reads against "the server clock is authoritative". That rule is about sync *state* — which is why the cursor is server-issued — whereas ordering two edits needs to know when each person actually typed the change, and only their device knows. Server receipt time would be worse: a device offline for two days would beat this morning's edit simply by reconnecting after it. The exposure is a device with a fast clock winning everything; `domain.ClampToServer` bounds it to a 5-minute tolerance, so a wrong clock wins the edits it is racing and not all future ones.

**Two bugs found here, both of the kind only a real request or a real database finds:**

- **A `DELETE` has no `WITH CHECK`, so migration 00004's console door was not read-only.** Phase 5 relaxed `USING` and left `WITH CHECK` strict, reasoning that reads and writes are governed separately. True for INSERT and UPDATE; a DELETE is governed by `USING` alone. Confirmed directly against PostgreSQL — with `app.platform_admin` set, `DELETE FROM customers` reported `DELETE 1` on another business's row. 00005 adds a `RESTRICTIVE` delete policy, which is ANDed rather than ORed with the permissive one, so a delete needs a real tenant no matter what else is set. Two tests cover it, and it is also what keeps the tombstone sweep honest: it has to declare each business it collects for.
- **Huma requires every non-pointer field by default**, so a client omitting `is_deleted` on a new record got a 422 that failed the entire batch — reintroducing, through a struct tag, the exact behaviour this phase exists to remove. Every field but the identifier is now `required:"false"` at the schema level and validated while applying, so one malformed record costs one line of the conflict report. Unit tests could not see this: they build the struct in Go and never go through JSON. **Second time a Huma schema default has broken real requests while every test passed** (the first was `money.Amount`), which is the standing argument for booting the server and curling it.

Also caught by test: `raiseHorizon` was an `UPDATE` matching zero rows when the seeded horizon row was absent — a sweep would delete tombstones and leave the horizon at zero, which is the resurrection direction. Now an upsert that errors when it affects nothing.

### Phase 7 — Data migration & cutover — backend complete (2026-09-09); mobile steps outstanding

- Export/transform/import from the live Postgres into the v2 schema; verify row counts and, critically, that **every customer balance is identical before and after**.
- Ship the mobile changes from §8 (C1, C3) **before** cutover, pointed at v2 via `--dart-define=API_URL`, so the switch is a build flag in both directions.
- End-to-end tests driving the real Flutter client against v2 — register → login → add customer → record debt → sync → second device sees it.
- Keep the old server running read-only for a rollback window before deleting it.

**Outcome (backend).** `server-v2/internal/dataimport` + `cmd/importv1`, 10 tests, rehearsed end to end against a v1 database built from v1's own migration files. The two mobile items — shipping C1/C3 and driving the real Flutter client — are **not** done and cannot be here: Flutter is not installed in this environment, and mobile work is parked until the backend lands.

**One command does the cutover, and refuses to lie about it.** `make import-v1 SOURCE=<v1 dsn>` migrates the schema, seeds permissions, imports, and then verifies — exiting non-zero if anything differs, so a cutover script cannot proceed past a failed check by accident. `-dry-run` reports what would move; `-verify-only` re-checks an import that already ran.

**The check that decides whether to cut over is balance parity, not row counts.** Counts can match while the ledger is wrong: an entry imported with the wrong sign, or attached to the wrong customer, leaves every count intact and changes what a real person is told they owe. Both sides derive `SUM(debt) − SUM(payment)` over non-tombstoned rows and compare exact decimal text — amounts are carried as `amount::text` end to end, so nothing is ever a float. `TestVerify_ActuallyReportsABalanceThatDoesNotMatch` alters one entry by one cent and asserts the verifier notices; a verifier that cannot fail makes "cutover is safe" a sentence with no content.

**Transforms that were actually needed** (the core tables were written to hold the same rows, so there are few): `business_invites.id` is `SERIAL` in v1 and UUID in v2, so live invites get new identifiers and used or expired ones are dropped as noise; RBAC rows are derived from `users.role` through `rbac.AssignRole`, the same call the running server uses, rather than written by hand as a second definition of what a role means; `customers.field_versions` is left empty, which is correct because an absent version falls back to `updated_at`; `console_sessions` is not migrated, since v1 stored the raw cookie value as its primary key and importing those to save four people one sign-in is a poor trade.

**The import declares a tenant per business** and runs inside `tenant.Transaction`, so it is structurally incapable of writing one shop's rows into another's — and the unit of failure is a business rather than the whole run. `TestImport_LeavesTheV1DatabaseUntouched` snapshots the source before and after: the v1 server keeps serving real shops throughout and stays read-only for the rollback window, so a tool that wrote to it would remove the ability to roll back at all.

**The cutover hazard that has nothing to do with row data.** A phone holding v1 cursor 40,000, pointed at a v2 database whose sequence has reached 900, asks for changes above 40,000 and is told — correctly, and forever — that there are none. Its ledger silently stops updating. Rather than add a rule the client must remember on every future cutover, the import advances `sync_change_seq` past anything v1 issued **before importing a single row**, then sets the tombstone horizon to that boundary. Every existing cursor is below it and trips the resync the engine already knows how to ask for; every imported row and every later write sits above it. Verified live: cursor 11 → `resync_required`, cursor 0 → 3 customers and 5 transactions, a post-cutover write delivered on the next pull.

**Two bugs found here, both caught by test, both of which would have shipped:**

- **The migration would have reactivated every deactivated member of staff.** GORM omits a zero-valued field whose column carries a default, and `users.is_active` defaults to `true` — so `IsActive: false` was silently written as `true`, handing back access to a shop's ledger that someone had deliberately withdrawn. `Select("*")` does *not* fix it, because the skip happens while building the values rather than while choosing the columns; the importer now writes `is_active` again explicitly when it is false. **Third appearance of this trap** (the console test and a sync test hit it too), so it is worth stating as a rule: *a zero value on a column with a non-zero default does not survive a GORM insert.*
- **The obvious ordering of the seal put devices in an infinite resync loop.** Setting the horizon *above* the imported rows leaves a freshly-synced device below it, so its very next pull is told to resync again, with no way out but a new build. Hence the sequence is raised before the import rather than after: the boundary must sit below the imported rows and above every v1 cursor, and those only fit in that order.

**Rehearsal, end to end.** A v1 database built from `server/migrations/*.up.sql` (read at test time, never copied — a copy would drift and the test would then certify a schema that does not exist), seeded with two shops, a deactivated staff member, a walk-in customer with no phone, a tombstoned customer with history, a voided entry, and amounts whose cents matter. Then `cmd/importv1` for real, then a v2 server booted against the result. Over HTTP: **a shopkeeper signed in with the password they had in v1** — bcrypt hashes carry across, so cutover needs no password reset — the deactivated staff member stayed locked out, balances read 1200.35 and 45.00 exactly as v1 computed them, and the migrated super admin reached the console with their v1 password.

**Still outstanding before a real cutover**, and none of it is backend work:
- Mobile C1/C3 from §8, plus sending `changed_fields` and `operation_id` (Phase 6's contract).
- End-to-end runs driving the real Flutter client against v2.
- Run the import against a **snapshot** rather than live production: it takes a consistent view per business, but a shop recording a debt mid-run will have that debt on one side only.
- ~~`go.mod` still carries `replace github.com/codetheuri/tusk => ../../../go/Tusk`; that must become a real tag.~~ **Done 2026-09-09.** Tusk's breaking changes were published as `github.com/codetheuri/tusk/v2` (a real `/v2` module path was required — Go resolves major version from the import path, and `v1.0.0` was already tagged, so a breaking `v1.1.0` would have handed anyone on v1 a broken build on their next `go get -u`). Tagged `v2.0.0`. `server-v2/go.mod` now requires it directly with no `replace`; `go mod tidy` fetched it from GitHub, and the full test suite plus a live boot-and-curl smoke test passed against the published module, not the local checkout.
- Production must connect as a **non-superuser**, or all three tenancy layers reduce to two — `cmd/importv1` and `cmd/api` both say so at startup.

### Phase 8 — Mobile field-test backlog

Held until the backend lands, since several items touch the sync contract:
- Cross-tenant staff list (`getAllUsers()` has no `business_id` filter) — **confirmed leak, highest priority**
- Required customer phone + device contact picker
- Dashboard search by phone as well as name
- Required transaction description; show time as well as date
- Local DB `version: 1` while `_onUpgrade` expects `< 2`, so that migration can never run

---

## 8. Contract Changes

Per **D7**, v2 adopts Tusk's native conventions and the Flutter client is updated to match. No compatibility shim is built. These are therefore a **mobile work list**, not backend constraints — but they must ship *with* the cutover, not after it.

| # | Change | Mobile action required |
|---|---|---|
| C1 | Error envelope: Salio `{success, error: {code, message}}` → Tusk `{success, message, errors: {field: msg}}` | Rewrite `_throwDetailedError` in `http_auth_repository.dart`, which currently reads `data['error']['message']`. Left unchanged, **every error message in the app silently becomes null** — no crash, no log, just blank dialogs. This is the single easiest item on the list to forget. |
| C2 | Success envelope: Salio `{success, data}` → Tusk `{success, message, data}` | None. The client reads `body['data']` and ignores extra keys. |
| C3 | Route prefix: `/v1/...` → `/api/v1/...` | One-line change to `ApiClient.baseUrl`, or set it at build time via `--dart-define=API_URL`. |
| C4 | Auth identity: Salio is phone-only; Tusk's `users` requires username + email | Backend-side fix in Phase 5 — make both nullable. No mobile change. |
| C5 | JWT claims: Salio carries `business_id`/`role`; Tusk carries `user_id`/`role` | Tenancy claim added in Phase 3. `AuthProvider._decodeAndSetUser` reads `business_id`, `user_id`, `role` — keep those claim names to avoid a mobile change. |

**Recommendation:** land C1 and C3 in the mobile app behind the existing `API_URL` build flag *before* cutover, so a single `--dart-define` switches environments and can be switched back.

---

## 9. Risks & Open Questions

**Risks**
- **Scope.** This is a substantial effort. Phases 1–4 deliver no user-visible Salio value — they are the investment that makes Phases 5–7 fast and safe. If that tradeoff needs revisiting, do it now rather than mid-Phase-3.
- **Tusk API churn.** UUID and tenancy are breaking changes. If anything else already depends on Tusk, it needs a pinned version.
- **The sync rewrite requires coordinated mobile work.** Backend-only deployment will not fix the reported bug.

**Resolved since v1.0:** tenancy is opt-in (D5, §2.2); Postgres only (D6); no response-compatibility shim (D7).

**Open questions for you**
1. **Is the sync fix urgent enough to ship ahead of the rewrite?** The commit-visibility race is hurting real users now. A targeted fix on the *current* backend (switch to a sequence cursor) is maybe a day or two of work and could ship in weeks rather than months. Recommendation: yes, fix it in place first.
3. **Does anything else depend on Tusk today?** Determines whether Phase 2 needs a deprecation path or can simply rewrite migration `00001` in place.
4. **Public identifiers — expose UUIDv7 primary keys directly, or carry separate UUIDv4 public IDs?** Tradeoffs in §2.1. Must be settled before Phase 5 defines the DTOs, since retrofitting means changing every API path and every client that stored one.

---

## 10. Recommended Immediate Next Steps

1. Approve or amend this plan.
2. **Ship the sync cursor fix to the current backend** (Open Question 1) so field users stop losing data during the rewrite.
3. Phase 0 — write the `.claude/` memory in both repos.
4. Phase 1 — Tusk hardening, starting with G1–G5.
