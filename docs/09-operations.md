# 09 — Running Salio v2: security model, database roles, deployment

How server-v2 keeps shops' data apart, how to run it locally and in production, and why each piece is the way it is. Written 2026-10-13, after the production-readiness work that found the API could not run under the database role production must use.

---

## 1. Keeping shops apart: three layers

Every shop is a **tenant**. One shop must never see another's customers, debts or sales. Salio enforces that three times, so a mistake in any one layer is caught by the next:

| Layer | Where | What it does |
|---|---|---|
| 1. Token | `tenant` middleware | The shop comes **only** from the signed token's `tenant_id` claim — never from a URL, query or body. |
| 2. Query filter | GORM tenant callbacks | Every query on a tenanted table automatically gets `WHERE business_id = <shop>`. A tenanted query with no shop **errors** instead of reading everything. |
| 3. Database | PostgreSQL row-level security (RLS) | The database itself refuses rows from other shops, even if the application forgot the filter. |

### What was wrong (found 2026-10-13)

Layer 3 had never actually been switched on.

- RLS policies read the shop from a connection setting, `app.tenant_id`. **Nothing in the API ever set it.** Only the cleanup job and the importer did.
- Every run so far used the `root` **superuser**, and PostgreSQL silently exempts superusers from all RLS policies. So everything appeared to work.
- When the API was run as a restricted role for the first time, it could not even register a business: `new row violates row-level security policy for table "users"`.

Nothing leaked, because layers 1 and 2 were working. But production would have had two layers, not three. Or, run as a superuser to make it work, a system whose database-level protection did nothing.

Two more defects surfaced while fixing it:

- **A cleared setting broke queries.** Once `app.tenant_id` has been set on a pooled connection, it reads back as `''` rather than NULL, and the policies cast it to `uuid`. So the next shop-less query on that connection **errored** instead of seeing nothing.
- **Signed-in sessions could not be ended.** A deactivated member of staff kept full access, through the app and through sync, until their 30-day token expired. A code comment promised sync would re-check this; it never did. Changing a password also ended no sessions.

### How it works now

- **`internal/tenantconn`:** every signed-in request gets **its own database connection**. The shop is declared on that connection, and every query of the request, including transactions, runs on it. When the request ends, the setting is cleared and the connection goes back to the pool. If clearing fails, the connection is destroyed rather than reused. No repository code changed, so none of the ~111 database calls can forget it.
- **Migration 00009:** every policy now reads the shop through `app_current_tenant()`, which treats `''` as "no shop".
- **`internal/identity`:** the only place allowed to read users and invites **before** the shop is known (sign-in by phone, "is this phone taken?", invite codes). It uses a **SELECT-only** policy, `salio_identity_lookup`, so it can never write.
- **`internal/session`:** checks every signed-in request (see §4).
- **`internal/server`** builds the API, and `internal/server/server_test.go` runs it **as a restricted role over HTTP**. That test fails if layer 3 or the session check is removed (both verified). It is the test that would have caught the original problem.
- The API **refuses to start** as a superuser or `BYPASSRLS` role when `REQUIRE_RLS=true`, which is the default in production.

---

## 2. Database roles

Two roles, because they need opposite things (`deploy/postgres/roles.sql`):

| Role | Used by | Can |
|---|---|---|
| **owner** (`salio_owner`) | `cmd/migrate` only | Own and change the schema (create/drop tables). |
| **app** (`salio_app`) | the API, `syncgc`, `createadmin`, `importv1` | Read and write rows. **Cannot** change the schema. **Not** a superuser, **no** `BYPASSRLS`, so RLS applies. |

Why it matters: if the API were ever compromised, the attacker would have the app role. That role cannot drop a table and cannot read across shops.

`roles.sql` also sets **default privileges**, so tables created by future migrations are automatically usable by the app role. Without this, the first deploy with a new table would fail in production with `permission denied`.

Verified: the app role's `CREATE TABLE` gives "permission denied for schema public", and its `DROP TABLE` gives "must be owner"; a table the owner creates later is usable by the app role at once.

---

## 3. Running it

### Locally (development)

Development uses the same two roles, so RLS bugs show up on your machine, not after a deploy.

```bash
cd server-v2
cp .env.example .env          # fill in passwords and JWT_SECRET (openssl rand -base64 48)
make db-roles                 # once: creates salio_owner and salio_app (uses DB_ADMIN_URL)
make dev                      # migrates as the owner, then runs the API (as salio_app) with hot reload
```

Tests use their own database (`salio_v2_test`, a superuser connection, because they create databases and roles). `make test` runs everything; `internal/server` is the part that runs as a restricted role.

### On a server (Docker Compose)

```bash
cd server-v2
cp deploy/.env.example deploy/.env    # replace every secret
make docker-up                        # = docker compose -f deploy/compose.yaml up -d --build
```

What starts, in order (enforced by `depends_on`):

1. **db:** PostgreSQL 15. On first start, `deploy/postgres/init.sh` runs `roles.sql`. Not published to the host.
2. **migrate:** one-off, as the **owner**. The API does not start unless it succeeds.
3. **api:** as the **app** role, `APP_MODE=production`, so RLS is required and boot-time migration is off.
4. **syncgc:** as the **app** role, running `-every 24h`: the tombstone sweep on a schedule.

The image (`Dockerfile`) is ~75 MB. Everything is compiled statically into a **distroless** image: no shell, no package manager, a non-root user. Time zones and console templates are built into the binaries.

Verified end to end on 2026-10-13 from an empty volume: all 31 feature checks and all 22 session checks pass against the container.

### On a server that already runs v1 (shared PostgreSQL)

When the server already has a PostgreSQL container and Nginx Proxy Manager on a shared Docker network (here `tigerforge-db`), v2 joins that network instead of starting its own database. The file is **`server-v2/docker-compose.yml`**. v1 is not touched.

| | v1 (live) | v2 |
|---|---|---|
| Database | `salio_db` | `salio_dbv2`, same PostgreSQL container |
| Database user | the shared superuser | `salio_owner` (migrations) and `salio_app` (everything else) |
| Container names | `salio_api` | `salio_v2_api`, `salio_v2_syncgc`, `salio_v2_migrate` |
| Address on the network | `172.20.0.15` | `.40` api, `.41` syncgc, `.42` migrate |
| Port | `8080`, published | `8090`, **not** published: only the proxy reaches it |
| Domain | v1's | its own, through Nginx Proxy Manager |

```bash
cd server-v2
docker network inspect tigerforge-db        # 1. check .40-.42 are free
deploy/postgres/apply-roles.sh              # 2. once: the two roles, through the running "postgres" container
docker compose up -d --build                # 3. every deploy
```

Then, in Nginx Proxy Manager, add a proxy host: the v2 domain, scheme `http`, forward host `172.20.0.40`, port `8090`, with a Let's Encrypt certificate and Force SSL. That is the HTTPS item below, done.

**Three services, because they run on three different schedules.** `v2-migrate` runs once per deploy as the schema owner and exits (it is a job, not a server). `v2-api` runs all the time. `v2-syncgc` wakes once a day to clear old deletion markers, and is safe to remove for the first weeks. The migration is separate so that the API never holds the owner's password: a compromised API then cannot drop a table. No PostgreSQL is started or pulled: all three use the existing `postgres` container.

Why each choice:

- **The shared superuser is used once, not by the API.** PostgreSQL silently exempts superusers from row-level security, and the API refuses to start as one (`REQUIRE_RLS`). `deploy/postgres/apply-roles.sh` runs `psql` inside the existing `postgres` container (`docker exec`, over its local socket, which the official image trusts) to create two ordinary roles; after that only those are used. So the shared superuser's password is not needed and is not in the file. (An earlier version used a separate `postgres:15-alpine` job just for the `psql` tool; replaced because the existing container already has it.) Rehearsed: the API as the shared superuser exits with "row-level security is not enforced for this database role". Running as the superuser anyway needs `REQUIRE_RLS: "false"` and `MIGRATE_ON_BOOT: "true"` (the comment in the file says how); it works, and tenant isolation drops from three layers to two.
- **Service names `v2-*`.** On a shared network every container answers to its service name. v1 also has a service called `api`; two containers with one name make DNS hand out either, so a v2 request could reach v1.
- **Fixed addresses.** Only the proxy needs one (`.40`); the others have them so a `docker network inspect` shows who is who. "Address already in use" means two containers were given the same one: `docker network inspect <network>` lists who holds each.
- **Passwords are in the compose file,** by the owner's choice for a private repository. Anything committed stays in git history: rotate them if the repository is ever shared. (`deploy/compose.yaml` is the separate setup for a machine with no PostgreSQL yet; it takes its secrets from `deploy/.env`.)

Rehearsed end to end on 2026-10-18 on a throwaway network and database, from this file against PostgreSQL 16 (the server's version): `apply-roles.sh` (twice, idempotent, no password), migration as the owner (all 21 tables owned by `salio_owner`), register, sign in and sync over the container's fixed address, and the sweep. Not yet run on the real server.

**Before real shops use it**, still to do:

- **HTTPS.** Put a reverse proxy (Caddy or nginx) in front of port 8090. The API speaks plain HTTP.
- **Backups.** Schedule `pg_dump`, keep copies off the machine, and **test a restore**. There is no backup automation yet.
- **CORS.** Set `ALLOWED_ORIGINS` only if a browser front end will call the API. The mobile app does not need it.
- **Secrets.** `deploy/.env` must stay off git (it is ignored) and readable only by the deploy user.

### Migrations

Each schema change is a new file in `server-v2/database/migrations/`. In production, the `migrate` step applies pending files as the owner on every `up`. Locally, `make migrate-up` does the same. Never edit a migration that has already run anywhere; add a new one.

---

## 4. Sessions and passwords

Tokens last **30 days** on purpose, so an offline shop is never locked out of its own ledger. Because a token can't be recalled, the session check (`internal/session`) runs on every signed-in request:

| Situation | Response | What the app should do |
|---|---|---|
| Account deactivated | **401** "This account has been deactivated…" | Sign out and show the message. Unsynced records stay in the outbox until someone signs in on that phone. |
| Token issued before the last password change or reset | **401** "You were signed out because the password was changed…" | Sign out and show the sign-in screen. |
| Owner reset this user's password and it hasn't been changed yet | **403** "Choose a new password before continuing." on everything except `GET /users/me` and `PUT /users/me/password` | Show only the change-password screen. Sign-in also returns `must_change_password: true`. |

Routes:

- `PUT /api/v1/users/me/password` with `{current_password, new_password}` (8–72 characters). Signs out **every other** device and returns a fresh token for this one. A wrong current password is **422, not 401**, because a 401 would make the app sign out.
- `POST /api/v1/staff/{id}/reset-password`, owner only. Returns a one-time 10-character temporary password with no look-alike characters (0/O, 1/I/L). The owner reads it to the staff member, whose sessions end and who must choose their own password at the next sign-in. **Staff only:** one co-owner cannot reset another's password, or either could lock the other out.

Registration now requires an 8-character password. It said "at least 8" but accepted 4.

---

## 5. CI

`.github/workflows/ci.yml` runs on every push and pull request:

- **server-v2:**
  - gofmt check, `go vet`, build
  - **all tests with the race detector against a real PostgreSQL.** `REQUIRE_DB_TESTS=1` makes "no database, skipped" a failure, so a green build can't mean nothing ran.
  - `govulncheck`
- **server-v2-image:** the Docker image builds.
- **server (v1):** build and vet.

The old `go.yml` ran at the repository root, which has no Go module, with Go 1.20, and only for `main`. It never checked anything.

**Toolchain.** `go.mod` pins `toolchain go1.26.9`. Upgrading `golang.org/x/crypto` (bcrypt) to clear three advisories required Go 1.26, and 1.26.9 is the patch that fixes the standard-library `net/http` advisories reported against 1.26.0. `govulncheck` now reports no vulnerabilities reachable from our code.

---

## 6. Follow-ups

- **Tusk:** `testdb.ConnectWith` migrated before taking its test lock. Fixed on Tusk branch `fix/testdb-migrate-under-lock`. Once released, delete the workaround in `server-v2/internal/testsupport`.
- **Candidate for Tusk:** `internal/tenantconn` (one connection per request, with the shop declared) is generic. Any Tusk application that turns on RLS needs it. Consider moving it into `pkg/tenant`.
- **Backups and HTTPS** (§3).
- **Data move from v1:** deliberately not rehearsed yet. It belongs with the move of the live v1 server.
