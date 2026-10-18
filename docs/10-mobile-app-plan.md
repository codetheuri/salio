# 10 — Salio mobile app v2: execution plan

**Status:** proposed on 2026-10-14. M0 (foundations) done on 2026-10-19, in `mobile-v2/`; see the outcome note under M0 in §10.
**Builds on:** [08 — backend rewrite](08-tusk-rewrite-plan.md) (server-v2, complete) and [09 — operations](09-operations.md) (security model, deployment).
**Borrows from:** the DairyGo app (`/var/www/html/startup/Dairy/mobile`), which already solved self-updating, layout testing and slow networks with real users.

How to read this: §0 is the whole plan on one page. §3 lists every important decision with its reason. §10 is the order of work; each milestone ends with checks that prove it works, not just that the code exists. Terms are explained in §14.

---

## 0. The plan on one page

**What we are building.** A new Android app for Salio that:

- **Works offline, safely.** It works completely offline and syncs with server-v2 without ever losing or doubling a record, on 2 GB phones and 100 kbps connections.
- **Does everything server-v2 can do:**
  - customers;
  - debts and payments, with M-Pesa codes, due dates and credit limits;
  - sales, stock and purchase orders;
  - suppliers;
  - reports and PDFs;
  - staff and sessions.
- **Makes a shopkeeper's day easier:**
  - paste an M-Pesa message to record a payment;
  - send a reminder or receipt on WhatsApp;
  - a "who to call today" list;
  - today's money by cash, M-Pesa and bank.
- **Fits every screen,** from a 320 dp phone to a tablet, in English and Swahili.
- **Updates itself,** the way DairyGo does.

**How.**

1. **A new app in `mobile-v2/`.** The old `mobile/` keeps serving the live v1 server until cutover, the same pattern as `server/` and `server-v2/`.
2. **Reuse what DairyGo already proved:** the updater, the layout tests, the network layer and the release script, rather than new versions of them.
3. **A *walking skeleton* first:**
   - sign in;
   - record a debt offline;
   - see it on a second phone;
   - ship an update to the phone.

   Then widen it.
4. **Prove "everything works" with tests** that drive two simulated phones against a real server-v2 in CI.

**The five decisions that matter most** (all in §3):

1. **One database file per signed-in account.** One shop's data cannot appear on another's screens, because it is never in the same file.
2. **Every change is saved on the phone first, then synced.** The app behaves the same with or without a connection.
3. **A required update stops syncing, never the ledger.** A shop can always record a sale.
4. **A new permanent app ID and signing key, chosen now.** These are the only choices that can never be changed once shops install the app.
5. **Direct download with self-update first, Google Play later,** from the same code.

**Backend work needed before the beta** (§7). Several items were found while writing this plan:

- **App release endpoints.**
- **Conflict answers that include the server's copy of the record.**
- **A rate-limiter fix:** sign-in is effectively unthrottled today.
- **Phone numbers stored in one format.**
- **HTTPS and backups.**

**Time.** Eleven milestones, M0 to M10. Roughly 11–16 weeks to cutover for one developer working with Claude, re-estimated after M1 (§10).

**Your decisions** (§13): the app ID, the Google developer account type, and the crash-reporting service.

---

## 1. Where we start

### 1.1 The old app

`mobile/` is about 4,400 lines: provider, sqflite and http against the v1 API. Three shops field-tested it and liked it (`feedback.txt`). It is rebuilt rather than upgraded, because its problems are in its structure:

| Problem | Where | What it caused |
|---|---|---|
| Every account that signs in shares one database | `salio_v3.db`; `getAllUsers()` has no shop filter | Another shop's staff appeared offline (field test) |
| Sync by timestamp, whole-record overwrite | `sync_service.dart` | The server was fixed in Phase 6; the phone side must change completely (cursor, operation IDs, changed fields, conflicts) |
| Database migrations can never run | `version: 1` with an `oldVersion < 2` branch | The first schema change would break silently |
| Voiding an entry did not mark it changed | `softDelete()` | Voids never reached the server |
| Errors read the v1 envelope | `http_auth_repository.dart` | Every error message would be blank against v2 (08 §8, C1) |
| App ID `com.example.mobile`, signed with this laptop's debug key | `android/app/build.gradle.kts` | Google Play refuses `com.example`. A debug key's password is public, and the key exists on one laptop only |
| No router, no tests, no way to update itself | — | Every fix needs a manual reinstall |

Changing it in place would touch almost every file, and the three shops would lose a working app while it happened.

### 1.2 What server-v2 gives the app

| | |
|---|---|
| **Routes** | `/api/v1/...`. Tusk envelope `{success, message, data}`; errors are `{success, message, errors: {field: message}}` |
| **Sign-in** | Phone and password. A 30-day token. `must_change_password` on the user |
| **Sync** | `POST /sync/push` with an `operation_id`; `GET /sync/pull?cursor=&limit=` (500 per kind by default, 2,000 at most). Six kinds: customers, transactions, sales, stock requests, suppliers, supplier transactions. Staff phones never receive supplier records |
| **Conflicts** | `stale_write`, `immutable`, `already_voided`, `unknown_customer`, `unknown_supplier`, `unknown_sale`, `invalid`, `forbidden`, `has_balance`, `duplicate`, `already_ordered` |
| **Values** | Money as decimal strings of cents (`"1500.50"`); quantities to three decimals; business dates in the shop's own time zone. A credit sale's debt ID is derived from the sale ID (`SaleDebtID`, a UUIDv5) |
| **Sessions** | 401 for a deactivated account or a session ended by a password change; 403 while a reset password must be changed (09 §4) |
| **Online only** | Reports and PDFs, purchase orders, staff, the business profile, invites |

### 1.3 What we take from DairyGo

| DairyGo piece | What it already does | Salio change |
|---|---|---|
| **The updater:** Flutter `features/app_update`, `MainActivity.kt` (PackageInstaller), `UpdatedReceiver.kt`; server `internal/appupdate`; `release.sh` and `ship.sh` | Resumable downloads checked by SHA-256; quiet download on Wi-Fi, asks first on mobile data; installs without a question on Android 12+; forced updates; reopens itself after updating | §6.2 |
| **`test/layout`:** every screen on six sizes at normal and largest text; safe-area and loading-state tests | Catches overflow and hidden buttons before users do | Add Swahili and two-pane screens |
| **Network layer:** dio interceptors, connection monitor, retries | Usable at 100 kbps; tells "slow" from "offline" | Saves go through sync instead |
| **Layout rules** in `docs/navigation-and-layout.md` | Text that shrinks, readable widths, safe areas, the back button | Same rules |
| **Permissions sent by the server** (`user.can(...)`) | A role can change without a new app | Needs backend B5 |
| **Report downloads** | Saves, opens and shares PDFs, kept 30 days | Same |

Why copy: these pieces have met real phones and real users. Tusk's own rule applies: *a little copying is better than a little dependency.* The server part moves into Tusk (`pkg/appupdate`) because both products already depend on Tusk. The Flutter part is copied now and shared later, once Salio's changes have settled.

### 1.4 Who and what we design for

- **Phones:** Android 7 to 16, 2–3 GB of RAM, 720p screens, 320–430 dp wide. Tecno, Infinix, itel and Samsung A-series, whose battery savers stop background work.
- **Networks:** hours without signal; 2G/3G at around 100 kbps; data bundles cost money; "connected" with no bundle.
- **People:** busy, often standing at a counter; some use large text; many prefer Swahili; one phone is often shared by owner and staff.
- **Clocks:** a phone's clock can be days wrong.

---

## 2. What the app does

### 2.1 Roles

The app checks permissions, never role names (§4.7). By default:

| Action | Owner | Staff |
|---|---|---|
| Add, edit and search customers; record debts, payments and sales; note stock that ran out | ✅ | ✅ |
| See reports and the team list | ✅ | ✅ (read only) |
| Void an entry or a sale; delete a customer whose balance is zero | ✅ | ❌ |
| Set credit limits | ✅ | ❌ |
| Suppliers and what the shop owes them | ✅ | ❌ (never on the phone) |
| Place or cancel purchase orders | ✅ | ❌ |
| Invite, deactivate and reset staff; edit the business | ✅ | ❌ |

### 2.2 Navigation

| Screen width | Navigation | Layout |
|---|---|---|
| Under 600 dp (phones) | Bottom bar: Home · Customers · Sales · Stock · More | One screen at a time |
| 600–839 dp (phones in landscape, small tablets, open foldables) | Side rail with every section, including Suppliers and Reports for owners | One screen; forms at most 720 dp wide |
| 840 dp and wider (tablets) | Rail, with labels from 1,200 dp | **Two panes:** the list on the left, the chosen customer, sale or supplier on the right |

A **+** button on Home and Customers opens Record debt, Record payment or New sale. The product rule is that key actions take under three taps (PRD §5).

Bottom-bar labels are one word in both languages, so none wraps on a 320 dp phone. The Swahili wording will be checked with the shops.

### 2.3 Launch scope (v2.0)

| Area | What | Offline? |
|---|---|---|
| **Account** | Register a business, sign in, join with an invite code | Needs a connection once |
| | Change password; the forced change after a reset; clear messages when a session ends | Shown offline; changing needs a connection |
| **Customers** | Add, with the phone picked from contacts: required, with a "no phone" choice for walk-in customers. Edit. Search by name **or phone**. Filters: owing, overdue, over limit, holding an advance, cleared | Yes |
| | Delete (owner, zero balance only); credit limit (owner) | Yes; checked by the server on sync |
| **Debts and payments** | Debt: amount, a required description, an optional due date, a warning when over the credit limit | Yes |
| | Payment: amount, method (cash, M-Pesa or bank), the M-Pesa code checked as it is typed. A payment above the balance becomes an advance | Yes |
| | Every entry shows its date **and time** and who recorded it. Owners void entries | Yes |
| **Sales** | Cash, M-Pesa, bank or credit. A credit sale puts the debt on the customer at once. Owners void sales | Yes |
| **Stock** | Note what ran out | Yes |
| | Purchase orders from those notes (owner), shared as a PDF; cancel | Needs a connection |
| **Suppliers (owner)** | Suppliers, bills and payments, voids, and what the shop owes | Yes |
| **Reports** | Home figures, due today, overdue | Yes, computed on the phone |
| | Debt ageing, sales, collections, customer statement, and what the shop owes suppliers, each as a PDF | Needs a connection; the last copy stays readable offline |
| **Team** | Share an invite code on WhatsApp; the staff list; deactivate; reset a password and show the temporary one once | Needs a connection; the list is readable offline |
| **Business** | Name, contacts, logo, time zone | Needs a connection; readable offline |
| **App** | Language, app lock, sync status and "Needs attention", updates, help | Yes |

All four field-test requests are on this list:
- the phone is required and picked from contacts;
- customers can be searched by phone;
- the description is required;
- entries show the time.

### 2.4 Features that make shops love it

The product review found that shops want three things:
- to be paid back faster;
- to know where today's money went;
- to restock in time.

The features below were chosen for real value, low cost, and working offline.

**In v2.0**

| Feature | Why a shop cares | Cost |
|---|---|---|
| **Paste an M-Pesa message** to record a payment: the amount, code, date and payer fill themselves in, and a code already used is caught | No mistyped codes; a dispute ends by searching the code. Needs no SMS permission (§2.5) | Small: a parser tested on real, anonymised messages |
| **One-tap reminder** on WhatsApp or SMS: polite, in Swahili or English, with the balance, the due date and how to pay | Money comes back sooner. Free, because it uses the shop's own WhatsApp or SMS | Small; needs the business's payment details (B12) |
| **Receipt after a payment**, shared on WhatsApp: "Received KES 500 by M-Pesa (code). Balance KES 1,200." | Trust; fewer disputes | Small |
| **Today list:** due today, overdue and promised payments, largest first, with Call and Remind buttons | Turns the ledger into a plan for the day | Small: first-in-first-out matching runs on the phone |
| **Credit-limit warning** before a debt or a credit sale | Stops one customer quietly reaching KES 40,000 | Already on the server; the warning is only screen work |
| **Today's money:** what came in by cash, M-Pesa and bank today, and who took it | The owner's cash-up at closing | Small, computed on the phone |
| **Large amount keypad** with quick amounts and recent descriptions | Speed at the counter | Small |
| **"Saved on this phone" everywhere:** a badge on unsent entries, how many are waiting, the last sync time | Confidence that nothing is lost offline | Part of sync |
| **App lock** with fingerprint or PIN | Phones are shared and passed around | Small |
| **Swahili and English** | Many owners and staff prefer Swahili | Planned from the first screen |
| **Try with a sample shop** | Shows Salio to a new shop in seconds, and lets an owner explore safely | Small: a separate sample database that never syncs |
| **How-to cards and short videos**, made from the app's own screens, in both languages | Fewer support calls; DairyGo already does this | Small |

**In v2.1 and later** (each needs backend work):

- **Price list of products:** faster sales, correct spelling, cleaner reports.
- **Expenses:** an honest profit, not just sales.
- **Cash-up records:** cash counted against expected, per staff member, synced.
- **SMS reminders sent by the server** through Africa's Talking, paid for with credits. A revenue line, with a history of reminders sent.
- **Owner notifications,** such as "Jane recorded KES 5,000 for Otieno".
- **Bluetooth receipt printers** (58 mm), common in shops.
- **Export to Excel.**
- **A home-screen widget.**
- **Daraja on the shop's own Till,** so M-Pesa payments record themselves.

### 2.5 Not in v2.0, and why

- **iPhone.** Few target users have one. It would add a Mac, a paid Apple account and App Store-only updates. The code stays portable.
- **Reading M-Pesa SMS automatically.** It needs the SMS permission, which Google Play grants only to default SMS apps or a short, reviewed list of exceptions, and users rightly distrust it. Pasting needs no permission.
- **Editing a recorded entry.** Entries are immutable by design; a void and a new entry correct a mistake. An entry the server *refused* can still be fixed and resent, because it never entered the ledger.
- **Purchase orders offline.** The server numbers them (`PO-0001`) when they are placed.
- **One person in several businesses.** Not supported in v2.0.
- **A web app.** Not in v2.0.
- **A dark theme.** A high-contrast light theme comes first, for bright shops.

---

## 3. Decisions

Each row gives the choice and the reason. 🔒 marks a *one-way door*: a choice that cannot be undone after shops install the app.

| # | Decision | Why | What it costs |
|---|---|---|---|
| D1 | A new app in `mobile-v2/`; `mobile/` untouched until cutover | The field-test shops keep a working app, and a way to fix it; clean architecture from the first line | Two apps for a few months |
| D2 🔒 | A new permanent app ID (the reverse of a domain you own) and a new release signing key | Play refuses `com.example`. Android installs an update only if it is signed with the same key, forever | The three shops install the new app once instead of upgrading |
| D3 | Riverpod for state, as in DairyGo | You already know it. Logic can be tested without screens. It replaces the old ProxyProvider scoping, which leaked between accounts | Nothing new to learn |
| D4 | Drift, with its own bundled SQLite | Typed queries, screens that update themselves, tested migrations. Android 7's built-in SQLite (3.9) has no upsert and no window functions; bundling gives every phone the same modern SQLite | A code-generation step; about 1–2 MB more per APK |
| D5 | One database file per signed-in account | A cross-shop leak becomes impossible rather than merely avoided. Unsent work survives sign-out | A second account on the same phone downloads its own copy |
| D6 | Changes to synced records go only through the phone's database and sync, never REST | One path, so online and offline behave alike. Since Phase 7b the server applies the same rules to sync | None: the phone shows its own changes instantly anyway |
| D7 | Money in whole cents and quantities in thousandths; never floating point | A ledger must match to the cent. The server made the same choice (the `money` package) | None |
| D8 | Dates in the shop's time zone, with "now" corrected by the server's clock | Phones with a wrong clock or zone would otherwise misdate entries and due dates | Small |
| D9 | go_router with one stack per tab, as in DairyGo | Each tab keeps its place. Sign-in, forced password change and updates are redirects in one place | Nothing new to learn |
| D10 | Hand-written models (freezed). The contract is checked by live tests against a real server-v2, plus a snapshot of its OpenAPI document | Dart generators for OpenAPI 3.1, which Huma produces, are immature. A real-server test catches more than a schema check | Models are kept in step by hand; the tests catch drift |
| D11 | Direct APK with self-update first; Google Play later from the same code | Ship and fix quickly now. A new personal Play account must first run a 12-tester, 14-day closed test (§6.5) | Play's reach and trust come later |
| D12 | A required update stops syncing, not the ledger | DairyGo blocks the whole app. For a shop's ledger that would stop sales being recorded | Unsent records wait until the update |
| D13 | Android first | Target users are on Android | iPhone later |
| D14 | Crashes and release health in Sentry (or self-hosted GlitchTip), with names, phones and amounts removed | Release health is the gate for staged rollouts. It needs no Google services, and can cover the Go API too | Free-tier limits |
| D15 | English and Swahili from the first screen | Adding a language later means touching every string | Two copies of every text |
| D16 | No database encryption by default; an app lock instead | Phones that launched with Android 10 or newer encrypt storage already. A lost encryption key, which happens after some backup restores and system updates, would destroy unsent records: worse, for a ledger, than the risk it removes | Revisit if a client or regulator requires it |
| D17 | Minimum Android 7.0 (API 24), target Android 16 (API 36) | Flutter 3.44's defaults. Play requires API 36 for new apps and updates since 31 August 2026 | Older phones are left out |
| D18 | Flutter pinned with FVM, the same version in CI | DairyGo and Salio may need different versions, and builds must be repeatable | None |
| D19 | No processor-type offset on the version code: every APK of build N has version code N | Removes DairyGo's "% 1000" correction and its 1,000-build limit, and lets the Play and direct builds update each other | Check in M0 that Gradle allows the override; otherwise keep DairyGo's scheme for both channels |

**The one-way doors together:** the app ID (D2), the signing key (D2), and later the Play signing setup (§6.5). Everything else can change in a later release.

---

## 4. Architecture

### 4.1 Layers

```
mobile-v2/
  lib/
    app/            router, adaptive shell, theme, translations
    core/           database, sync engine, network, money, quantity,
                    time, session, layout rules, shared widgets
    features/<x>/   data (database access, API) → domain (rules)
                    → presentation (controllers, screens)
  test/             rules, database, sync, screens, layout,
                    shared vectors, live (real server)
  integration_test/ journeys on an emulator
  android/          flavours, signing, the installer bridge
  scripts/          release.sh
```

Rules:

- **Screens** show state and send actions. They never touch the database or the network.
- **Controllers** (Riverpod) call repositories.
- **A repository** writes a record and marks it for sync in one SQLite transaction, so a crash cannot leave one without the other.
- **Only the sync engine** talks to `/sync`. REST is for the online-only actions in §1.2.
- **Screens update themselves:** they read through Drift streams, so another phone's record appears on its own when sync brings it in.

```
Screen ─action─► Controller ─► Repository ─(one SQLite transaction)─► record + "pending"
  ▲                                                                       │
  └────────────── Drift stream: the screen re-renders ◄──────────────────┘

Sync engine (one at a time)
  push: frozen batch ─► server ─► applied / conflicts (with the server's copy)
  pull: page after cursor ─► save rows and the new cursor in one transaction
```

### 4.2 The phone's database

- **One file per account:** `accounts/<user id>.db` in the app's private storage, plus a small list of the accounts on the phone (name, shop, last used). Tokens stay in secure storage.
- **Tables:**
  - **The six synced kinds,** with the server's fields: amounts in whole cents, quantities in thousandths, times in UTC.
  - **Cached copies** of the staff list (for "recorded by" names) and the business profile.
  - **Sync bookkeeping:** pending changes, frozen push batches, the cursor, and the issues that need attention.
  - **A local log** of reminders sent.
- **Balances are computed, never stored,** by the server's formula, in one SQL view.
  - **Budget:** with 5,000 customers and 100,000 entries, the customer list appears in under 300 ms on the reference phone (§5).
  - **Only if that fails,** add a cache rebuilt from the ledger, and have debug builds check it against the ledger.
- **Search:** names and phone numbers are stored normalised, with indexes. `0712…`, `712…` and `+254712…` are the same number (B15).
- **Migrations:**
  - Every schema version is snapshotted, and CI tests every path from each old version to the newest.
  - Before migrating during an update, the app copies the file. A failed migration therefore loses nothing that was not yet synced.

### 4.3 The sync engine

This is where data is kept or lost, so it gets the most care and the most tests.

**Pushing** (the phone sends its changes):

1. **Marking.** Every change marks its record *pending*. For customers and suppliers it also notes which fields changed (`changed_fields`), so two people editing different fields both keep their edit.
2. **Forming a batch.**
   - Order: pending records in the order the server needs them, customers and suppliers before the entries that point to them.
   - Size: at most 200 records or 64 KB. At 100 kbps, 64 KB uploads in about 5 seconds, well within the server's 30-second read limit.
3. **Freezing the batch.**
   - The batch's `operation_id` and exact body are saved before sending, and a retry sends exactly that body again. The server recognises the `operation_id` and replays its first answer, so nothing is recorded twice.
   - **The trap this avoids:** if a retry rebuilt the body, edits made in the meantime would go out under the old `operation_id`. The server would replay its old answer, and those edits would be lost without any error.
   - Edits made while a batch is in flight wait for the next one.
4. **Reading the answer.**
   - Applied records become synced, unless they were edited after the batch was frozen.
   - Each conflict becomes an issue, and the record is replaced by the server's copy (B2), so the phone shows what the server holds.

**Pulling** (the phone receives everyone else's changes):

1. **Ask for the pages after the saved cursor.** The page size adapts:
   - start at 200 records of each kind;
   - double while pages arrive within 5 seconds;
   - halve after a timeout.

   The server stops writing an answer after 60 seconds, so a maximum-size page on 2G might never arrive.
2. **Save each page and its new cursor in one transaction.** A crash can never keep the cursor without the rows, which is how v1 lost records for good. An interrupted first sync continues from the last saved page.
3. **Keep local changes on top.** A record still pending on this phone keeps its own changes until they are pushed.
4. **Resync without emptying the screens.** `resync_required` means the phone was offline longer than the server keeps deletions. The app then pulls everything again from zero:
   - rows are marked as they arrive;
   - rows not seen again are removed at the end;
   - pending changes are kept throughout.

**When it runs:**

- **On events:** at start, on return to the app, when the connection comes back, and a few seconds after each change.
- **While the app is open:** every 2 minutes, so other phones' records appear. An empty pull costs under 1 KB.
- **On request:** when the user taps Sync.
- **One at a time.** After a failure it waits 5 s, then 15 s, then 1 minute, and at most 5 minutes.
- **Background sync** (Android WorkManager, at most every 15 minutes) is a bonus. Many phones' battery savers stop it, so nothing depends on it.

**What each conflict does:**

| Reason | Usual cause | What the app does | What the user sees |
|---|---|---|---|
| `duplicate`: M-Pesa code | The same payment recorded on two phones | Keeps the refused payment aside | "Already recorded by Jane at 10:15", with **Discard mine** |
| `duplicate`: customer phone | The same customer added on two phones | Keeps the refused customer aside | **Use the existing customer**: this phone's waiting entries move to the existing customer, and the copy is dropped |
| `forbidden` | The role changed while offline | Takes the server's copy | A short note |
| `has_balance` | Deleting a customer who owes, or is owed, money | Restores the customer | "Not deleted: the balance is not zero" |
| `stale_write` | Someone else's newer edit to the same field | Takes the server's copy | Nothing; it is logged |
| `immutable`, `already_voided` | The entry was changed elsewhere | Takes the server's copy | Nothing |
| `unknown_customer`, `unknown_supplier`, `unknown_sale` | What it points to never reached the server | Waits for the record it points to | The issue says which record it is waiting for |
| `already_ordered` | A stock note already on a purchase order | Takes the server's copy | A short note |
| `invalid` | The phone's checks and the server's disagree: **a bug** | Keeps the record aside and reports it to Sentry | "Needs attention" |

**Session and role events:**

- **A role change** makes the app resync everything. An owner who becomes staff loses supplier data; staff promoted to owner receive it.
- **Deactivation** stops syncing and shows the reason. Unsent records stay in the file.
- **A password change elsewhere** asks the user to sign in again to the same account. The same file and its waiting records continue.

**A self-check in the field.** When nothing is pending and a pull has finished, the app compares its total outstanding with the server's summary.
- A difference that survives a second pull is reported to Sentry, with record IDs only, never names or amounts.
- It is an alarm for sync bugs that no test imagined.

### 4.4 Rules the phone repeats, and how they stay identical

The phone checks the server's rules so the shopkeeper sees a problem at once, not at the next sync. The server stays the judge.

| Rule | Where on the server |
|---|---|
| Balance = debts − payments over live entries. Above zero is owing; below zero is an advance | ledger |
| Every new entry has a description; every new payment has a method. An M-Pesa code is 10 letters or digits, stored in capitals, and used once per shop among live payments | ledger, payment |
| A due date is not before the entry's date | ledger, sales |
| A credit limit warns but never blocks | customer |
| Payments clear the oldest debt first (due lists, overdue lists, ageing) | reports (FIFO) |
| A credit sale's debt ID is `SaleDebtID(sale ID)`, and the phone never sends that debt | domain |
| Only a customer with a zero balance can be deleted. Voids are for owners. Entries never change | customer, ledger |
| "Today" is the shop's day, in its time zone | shopclock |

**Shared test vectors.** A folder at the repository root, `testdata/shared/`, holds test cases as data. Both the Go tests and the Dart tests read the same files:

- `SaleDebtID` inputs and outputs;
- first-in-first-out cases;
- valid and invalid M-Pesa codes;
- real M-Pesa messages, anonymised, with the fields they should give;
- phone numbers and their normalised form;
- money strings and their cents;
- the role-to-permission table.

A rule changed on one side only then fails CI. Salio already pins `SaleDebtID` this way in Go; this extends it to both languages.

### 4.5 Accounts and sessions on the phone

| Event | What the app does |
|---|---|
| Sign in | Opens or creates that account's file; the first sync downloads the shop |
| The token expires while offline | Everything keeps working. The sync strip says "Sign in again to sync". Nothing is deleted |
| 401, account deactivated | Signs out with the server's message. The file and its unsent records stay |
| 401, session ended by a password change | Asks for the password again; the same file continues |
| 403, password must be changed | Shows only the change-password screen |
| Sign out with unsent records | Warns: "3 records are not sent yet. They will be sent the next time you sign in on this phone" |
| Remove the account from this phone | Deletes the file, after the same warning |
| Someone else uses the same phone | They sign in to their own account and file, and see nothing of the previous one |
| The role changes | A full resync (§4.3) |

### 4.6 Network

- **Client:** dio with DairyGo's interceptors:
  - **the token;**
  - **an app-version header** (`X-Salio-App: 2.0.3+15; android 34; direct`), for support and forced updates (B6);
  - **connectivity, judged from real traffic** (DairyGo's connection monitor), which tells "slow" from "offline";
  - **retries.**
- **What is retried:** reads, and sync pushes, which the `operation_id` makes safe to repeat.
  - Online-only saves, such as placing a purchase order or creating an invite, are not retried until the server accepts an `Idempotency-Key` (B8).
  - Otherwise, an answer lost on the way back could place the same order twice.
- **Timeouts:** 20 seconds to connect and 45 to receive, as in DairyGo. Uploads stay small because batches are capped (§4.3).
- **Errors:** the Tusk envelope's `errors` map is shown beside the matching form fields, and `message` everywhere else. A test makes sure no error message is ever blank (08 §8, C1).
- **Addresses:** one per build flavour: dev on the local network, staging, and production. Plain HTTP is allowed in the dev flavour only; DairyGo allows it everywhere.

### 4.7 What each person may do

Screens ask `user.can(permission)`.

- **Until B5:** the permissions come from a role table that mirrors `rbac.go`, and a shared test vector proves it matches.
- **After B5:** the server sends the list at sign-in and from `/users/me`. A role then changes with no new app version, as in DairyGo.
- **Paid plans** will later use the same check with *entitlements*, so pricing can change without a release.

---

## 5. Screens that fit every phone

**Layout rules.** These are DairyGo's, from its `navigation-and-layout.md`, plus Salio's own:

- Names and labels in a row may shrink, ending in "…" or wrapping. Amounts shrink to fit and never wrap.
- No fixed-ratio grids: how many cards fit in a row depends on the width and the text size.
- Forms are at most 720 dp wide and lists 900 dp, so tablets do not stretch them edge to edge.
- Nothing hides under status bars, camera cutouts, gesture bars or curved edges. Android 15 and 16 draw apps edge to edge, so this is required, not optional.
- On a 320 × 640 phone the Save button stays visible above the keyboard.
- Two panes from 840 dp. On a foldable, nothing sits under the hinge.
- Touch targets are at least 48 dp. Text contrast is at least 4.5 : 1, for shops in bright light.
- Colour is never the only signal: a debt is red **and** labelled as a debt.

**Text size.** It follows the phone's setting up to 1.3×, the ceiling DairyGo tested. Every layout test runs at that ceiling. A higher ceiling is your choice (§13).

**Languages.**
- All text comes from the English and Swahili translation files.
- A test checks that both files have the same keys and placeholders.
- The layout tests run in Swahili too, because its words are often longer.
- Money reads "KES 1,250.50" and dates read "Tue 14 Oct, 10:15", in the shop's time zone.

**Test sizes:** DairyGo's six, plus two more.

| Name | Size (dp) | Why |
|---|---|---|
| phone-small | 320 × 640 | Older and budget phones |
| phone | 360 × 800 | The most common size |
| phone-large | 430 × 932 | Large phones |
| phone-landscape | 800 × 360 | Rotation |
| foldable | 673 × 841 | Unfolded |
| small-3-button | 360 × 640, with a 48 dp button bar | Cheap phones with button navigation |
| tablet | 800 × 1280 | The rail |
| tablet-landscape | 1280 × 800 | Two panes |

Each size runs on every main screen:
- at 1.0× and at 1.3× text;
- in both languages;
- as owner and as staff.

Any overflow fails the test, and the failure names the file and line.

**Speed budgets,** measured on a **reference phone**. Buy one low-end phone (2 GB RAM, Android Go edition) and test on it from M1.
- **Cold start:** the app opens in under 2.5 seconds.
- **Lists:** they scroll smoothly with 5,000 customers.
- **Recording:** a recorded debt appears in under 100 ms.
- **First sync:** a shop with 10,000 entries syncs in under a minute on 3G.
- **Size:** each APK is at most 25 MB.

---

## 6. Updates and distribution

### 6.1 How DairyGo does it

1. **Checking.** The app asks a public endpoint for the latest version: at start, on return to the app, and at most every 6 hours (or when the user taps Check).
2. **Downloading.**
   - On Wi-Fi it downloads the new APK quietly.
   - On mobile data it shows the size and asks first.
   - A dropped download continues where it stopped.
3. **Checking the file.** Each file is checked against the SHA-256 in the release manifest. Android then checks the signature.
4. **Installing.** Android's PackageInstaller does the install.
   - On Android 12 and newer, once the app itself installed the current version, updates install without a question.
   - The app reopens itself afterwards.
5. **The first time,** Android asks to allow installs from the app, and the app guides the user through it.
6. **A release marked required** shows only an update screen.
7. **Publishing.** A script copies releases to the server, APKs first and the manifest last. The API has no upload endpoint, so a stolen password cannot replace the app.

### 6.2 What Salio changes, and why

| Change | Why |
|---|---|
| A required update blocks **sync**, not the app. A banner says "Update to keep syncing. Your records are safe on this phone". A full block is reserved for a version that damages data | A shop must always be able to record a sale (D12) |
| The server also refuses sync from builds below the minimum, with 426 Upgrade Required | The app's check is for the user; the server's check is the guarantee (B6) |
| One version-code scale (D19) | Removes the correction whose absence hid every update from DairyGo 1.4.0 and 1.4.1 |
| **Staged rollout:** the manifest gives a percentage, and each phone falls in a fixed bucket based on a random install ID | Ship to 10% first, and raise to 100% only if release health stays good |
| Release notes in English and Swahili | Users read the update bar |
| A real release key from the first build | DairyGo started with a debug key and had to keep it |
| The updater is in the **first** build anyone outside the team installs | It cannot be added afterwards: DairyGo's 1.3 users had to reinstall by hand once |

**Roll back by rolling forward.** Android refuses to install an older version code over a newer one. A bad release is therefore fixed by publishing the previous code under a higher build number.

### 6.3 Server side (B1)

DairyGo's `internal/appupdate` moves into Tusk as `pkg/appupdate`, and both products use it:

- **`GET /api/v1/app/version`:** public, so an app that cannot sign in can still update.
- **`/app`:** the download page, with install steps in English and Swahili.
- **`/app/download/{abi}`:** resumable downloads.
- **Storage:** releases live in a read-only `releases` volume in `deploy/compose.yaml`.

### 6.4 Releasing

The release tools are `mobile-v2/scripts/release.sh`, and a root `ship.sh` like DairyGo's. In order:

1. **Checks:** a clean tree, the tests, the analyzer.
2. **Build** one APK per processor type, refusing any not signed with the Salio key. The key's fingerprint is in git.
3. **Deploy the server first. Never the reverse.** The server rejects request fields it does not know (Huma's default), so a newer app on an older server would fail every sync (B14).
4. **Publish** the APKs first and the manifest last.
5. **Tag** `app-v2.0.3+15`, and check that the live endpoint answers with the new build.

**The signing key:**
- It lives outside git.
- It is backed up in two places: a password manager and a USB drive.
- Its public fingerprint is in git.

Losing it means every shop must uninstall and reinstall.

### 6.5 Google Play, later (M10)

- **A `play` flavour** without the self-updater and without the install permission.
  - Play forbids apps that update themselves outside Play.
  - It uses Play's in-app updates instead: flexible for normal releases, immediate for required ones.
  - The minimum-build rule still comes from the server.
- **One signing key for both channels.** When enrolling in Play App Signing, upload your own key instead of letting Google create one. A phone can then move between the website build and the Play build.
- **The account type matters.**
  - A new *personal* account must run a closed test with at least 12 testers for 14 days before it can publish.
  - *Organisation* accounts (a registered company with a D-U-N-S number) are reported to be exempt. Check Play's current rules when you open the account.
- **Store requirements:**
  - target API 36;
  - a privacy policy;
  - the data safety form;
  - in-app account deletion, which Play requires of apps that create accounts (B10).

### 6.6 Android developer verification

From 30 September 2026, certified Android phones in Brazil, Indonesia, Singapore and Thailand install apps only from verified developers. This includes **apps installed outside Play**. The rest of the world follows from 2027.

After that, an unverified app can still be installed, but only through a harder "advanced" flow that no shopkeeper should face. Before then:

1. Verify your identity in the Android Developer Console.
2. Register Salio's package name and signing key.

**The same applies to DairyGo,** which is only ever sideloaded.

Sources, checked on 2026-10-14:
- **Developer verification:** [Android developer verification](https://developer.android.com/developer-verification), and the [Android Developers Blog announcement](https://android-developers.googleblog.com/2026/06/android-developer-verification.html).
- **Target API level:** [Play's requirement](https://developer.android.com/google/play/requirements/target-sdk).
- **The closed-testing rule:** summarised by [testerscommunity.com](https://www.testerscommunity.com/blog/google-play-closed-testing-requirements-2026). That is a third-party source; confirm it in the Play Console.

---

## 7. Backend work the app needs

| # | Change | Why | When |
|---|---|---|---|
| B1 | App releases: DairyGo's `appupdate` moved into Tusk as `pkg/appupdate`, with staged-rollout percentages, notes in two languages, and a releases volume | Self-update (§6) | P0, M1 |
| B2 | Each sync conflict includes the server's current copy of the record | Otherwise a refused change stays on the phone forever: the server's row did not change, so no pull ever corrects it | P0, M2 |
| B3 | **Fix Tusk's rate limiter.** See the note after this table | Phone numbers are easy to guess, so sign-in must resist password guessing. Found while writing this plan | P0, before the beta |
| B4 | An HTTPS reverse proxy (Caddy) with gzip; automated backups with a tested restore (09 §3) | Tokens and ledgers cross the internet; sync pages shrink by about 85%; no data loss | P0, before the beta |
| B5 | `permissions` in sign-in and `/users/me` | Roles change without an app release | P1, M3 |
| B6 | Record each user's app version and last sync from the version header. Add a "Devices" page in the console. Refuse sync below the minimum build with 426 | Support can see which version a shop runs, and forced updates become a guarantee | P1, M6 |
| B7 | `POST /auth/refresh`: a new 30-day token while the session is valid | An active shop is never signed out in the middle of a day | P1, M6 |
| B8 | `Idempotency-Key` for online-only saves (port DairyGo's into Tusk). `create-purchase-order` takes no client ID today | An answer lost on the way back must not place an order twice | P1, M4 |
| B9 | Owner password recovery in the console: support confirms who is calling, then sets a temporary password that must be changed. It writes through a tenant declared for that one business, because the console's database door is read-only by design | Today an owner who forgets their password cannot get back in. There is no email or SMS reset, and the console is read-only | P1, before the beta |
| B10 | Requests to delete an account or a business, in the app and on a web page | Google Play's rule, and the Data Protection Act | P1, before Play |
| B11 | CI publishes server-v2's OpenAPI document for the app's contract snapshot | Contract changes show up in the app's pull requests | P2, M1 |
| B12 | The business's payment details ("Till 123456") on its profile | Reminders and statements say how to pay | P1, M7 |
| B13 | A read-only switch on the v1 server for cutover | Nothing is written to v1 after the final copy (§11) | Cutover |
| B14 | Sync ignores unknown fields instead of refusing the batch. Huma rejects them by default (`AllowAdditionalPropertiesByDefault` is false) | A server rollback, or mismatched environments, must not stop every newer phone from syncing. Phase 6's own rule is that one bad field never costs a batch. REST stays strict, where strictness catches typos | P1, M2 |
| B15 | **Phone numbers stored in one format** (E.164, Kenyan by default) for customers, suppliers and sign-in, through one shared function for REST, sync and the v1 import. A migration converts stored numbers and *reports* the duplicates it uncovers rather than merging them | Today `0712 345 678`, `0712345678` and `+254712345678` are three different customers, and three different sign-ins. The sync path does not even trim spaces. Picking customers from contacts makes this common | P1, M3 |
| — | Release Tusk v2.0.1 (the testdb lock fix) and remove Salio's workaround | Housekeeping (09 §6) | Any time |

**B3, the rate limiter.** As written, it does not stop password guessing:

- **The key includes the port.** It uses the client address *including its port*, so every new connection gets a fresh allowance.
- **`X-Forwarded-For` is trusted from anyone,** so a made-up header bypasses the limit and grows its memory.

The fix:

- **Key on the IP alone,** and trust the header only from the reverse proxy.
- **For signed-in requests, key on the user.** Safaricom's carrier NAT puts many phones behind one address.
- **Cap the table's size.**
- **Add a per-phone sign-in limit.**
- **Check DairyGo's copy too.**

---

## 8. Proving it works

### 8.1 Test layers

| Layer | What it covers | When it runs |
|---|---|---|
| Rules | Money, quantities, dates, FIFO, `SaleDebtID`, M-Pesa codes and messages, phone numbers, from the shared vectors | Every push, in seconds |
| Database | Queries, and every migration path, on in-memory SQLite | Every push |
| Sync engine | Against a fake server that drops answers, repeats them, times out and fails, with the clock moved | Every push |
| Screens | Widget tests of each flow; layout, safe-area and loading tests on every size (§5) | Every push |
| **Live** | **Two or three simulated phones against a real server-v2 in Docker** (§8.2) | Every push to `mobile-v2/` or `server-v2/` |
| On a device | Five journeys on an Android emulator: register; record offline then sync; a payment with M-Pesa paste; sign out with unsent records; the forced password change | Nightly, and before each release |
| By hand | The update flow and the checklist in §8.5, on the reference phone | Before each release |
| In the field | The beta with real shops (M8) | Two weeks |

### 8.2 Live scenarios

Each scenario runs the app's real database, sync and network code, with simulated phones against one real server:

1. A debt recorded offline on phone A appears on phone B after both sync.
2. **A write committed during B's pull still reaches B on the next pull.** This is the field-test bug, from the phone's side.
3. The same push sent twice, after a lost answer, is recorded once.
4. Two phones edit the same customer's phone and notes offline, and both edits survive.
5. The same M-Pesa code is recorded on both phones offline. One is accepted; the other is a `duplicate` the user can discard.
6. Staff void an entry and delete a customer. Both are refused, and the phone shows the server's copy.
7. Deleting a customer with a balance is refused, and the customer comes back.
8. A credit sale made offline leaves exactly one debt, with the same ID on every phone.
9. A staff phone never receives supplier records. After a promotion to owner and a resync, it does.
10. A phone offline past the deletion horizon is told to resync, and keeps its unsent records.
11. A password reset by the owner ends the staff member's session, and the forced change works.
12. Deactivation stops sync and shows the message.
13. **Convergence:** three phones perform 500 random operations with random network failures. Every phone ends with the server's balances, with nothing lost and nothing doubled.

### 8.3 CI

A `mobile-v2` job:

- **Checks:** formatting, the analyzer, the tests, a dev build, and a dependency vulnerability scan (osv-scanner reads `pubspec.lock`, as `govulncheck` does for Go).
- **The live job:** starts `deploy/compose.yaml` and runs the live tests.

Release signing stays on your machine until there is a reason to move it. A signing key in CI is a key that can leak.

### 8.4 Definition of done, for every feature

A feature is done when all of these are true:

- **Works offline,** where §2.3 says it does.
- **Survives being killed mid-way:** the app can be closed in the middle of the action without losing anything.
- **Translated:** its text exists in both languages.
- **Fits every screen:** it passes the layout tests at every size and text size.
- **Tested:** it has rule tests and a flow test, and a synced feature also has a live scenario.
- **Recorded:** its row in Appendix A is marked, and the milestone's outcome note in this document is updated.

### 8.5 Before every release

Check on real phones, in these conditions:

- **Phones:**
  - the reference phone;
  - a mid-range Android 14 phone;
  - an Android 16 phone with gesture navigation;
  - a tablet.
- **Network:**
  - airplane mode turned on and off during a sync;
  - mobile data with no bundle;
  - a throttled 2G connection.
- **Display and language:** Swahili, at the largest text size.
- **Updates:**
  - an update over mobile data with the connection cut midway;
  - an update on Wi-Fi, where Restart appears.

---

## 9. Running it in the field

### 9.1 Crashes and health

Sentry receives:
- crashes and freezes;
- slow syncs;
- `invalid` conflicts;
- balance self-check differences;
- release health (the share of sessions without a crash).

It **never** receives names, phone numbers, amounts or descriptions. They are removed before sending, and a test checks that they are.

Builds are obfuscated, and their symbol files go to Sentry so crash reports stay readable.

### 9.2 Support

- **More → Help → Send diagnostics:** the user chooses to share a redacted log and the sync status on WhatsApp.
- **The console's Devices page** (B6): app version, last sync and waiting issues, per user.

### 9.3 Security

**Sign-in and the network:**
- Tokens live only in secure storage and are never logged.
- Release builds use HTTPS only.

**What can leave the phone:**
- Android backup is off, and the database and secrets are excluded from transfers to a new phone. A restored phone with an old token and a key it cannot read is worse than a fresh sign-in.

**Shared phones:**
- One file per account (D5).
- An optional app lock, which locks again after a few minutes in the background.

**Permissions:**
- Only internet, network state, notifications (when they are added), and installing updates (direct build only).
- No SMS, contacts or storage permission: Android's own pickers are used instead.

**Dependencies:**
- Pinned versions, a monthly review, and the vulnerability scan in CI.

### 9.4 Privacy and the law

Salio holds the names, phone numbers and debts of people who never signed up for it. Before launch:

- **Kenya's Data Protection Act:**
  - check whether registration with the Office of the Data Protection Commissioner applies;
  - publish a privacy policy.
- **Reminders:**
  - only to the debtor, never to anyone else;
  - polite;
  - at most once every 3 days per customer.
- **Shops own their data:** they can export it (v2.1) and delete it (B10).

---

## 10. Milestones

Estimates are working days for one developer working with Claude. They will be re-estimated after M1, once real speed is known.

- **Branches:** branch from `v2`, one branch per milestone, merged once its exit checks pass.
- **Outcome notes:** each milestone adds one here, as 08 did.

**M0 — Foundations (3–5 days)**

- **Toolchain:**
  - Flutter 3.44 on `PATH`, pinned with FVM.
  - Android licences accepted.
  - Emulators for Android 7 and 16.
  - The reference phone bought.
- **Identity:** choose the app ID (§13), create the release key, back it up twice, and commit its fingerprint.
- **Project:** `mobile-v2/` with dev, staging and prod flavours, each with its own ID suffix and name, so all three install side by side.
- **Android settings:**
  - API 24 minimum and 36 target.
  - Backup off.
  - Plain HTTP in dev only.
  - Check the version-code override (D19).
- **Quality tooling:** strict analyzer rules, formatting, and the CI job.
- **App skeleton:**
  - theme tokens from `05-design-system.md`;
  - English and Swahili files;
  - the router and adaptive shell, with placeholder screens;
  - DairyGo's layout-test harness running on them;
  - logging, and Sentry for dev.
- **Exit:**
  - CI is green.
  - A signed dev build installs on the reference phone.
  - The layout tests run on every size, at both text sizes, in both languages.

> **M0 outcome (2026-10-19, branch `mobile/m0-foundations`).**
>
> **Built:**
> - `mobile-v2/`, app ID `ke.co.urizon.salio`, with dev, staging and prod flavours (`.dev` and `.staging` suffixes, "Salio Dev", "Salio Staging").
>   - Dev points at server-v2 on the laptop (`http://127.0.0.1:8090` through `adb reverse`).
>   - Staging and prod point at `https://apis.salio.urizon.co.ke`.
>   - `--dart-define=API_URL=` points any build elsewhere, but plain HTTP is accepted in dev only, both by the app and by Android's network security config.
> - Android settings: min API 24 and target 36, written out rather than inherited from Flutter. Backup and device-to-device transfer are off.
> - A release build stops without the release key. `scripts/create-release-key.sh` creates the key.
> - Riverpod 3, go_router 17, and the translations generated from English and Swahili ARB files.
> - The adaptive shell: the bottom bar under 600 dp, the rail from 600 dp, rail labels from 1200 dp.
> - Placeholder sections, and a More page with the version, the environment and the server.
> - The permission table mirrors `rbac.go` and is pinned by `testdata/shared/role_permissions.json`, read by tests on both sides.
> - Strict analyzer settings, and a `mobile-v2` CI job.
>
> **Tests:** 58 tests, about a minute.
> - The layout tests run 13 role-and-screen pairs × 8 sizes × 2 text sizes × 2 languages, plus DairyGo's safe-area devices. They were checked against a deliberate overflow, which they caught and named per size.
> - Also: ARB parity, colour contrast and the environment rules.
>
> **What changed from the plan:**
> - **D19 is confirmed.** Flutter's plugin sets `versionCodeOverride = ABI × 1000 + N` in a variant callback registered when the plugin is applied. `build.gradle.kts` registers a second callback that runs after it and restores N. Every split APK has version code N, and `scripts/check-version-codes.sh` checks this in CI.
>   - In `afterEvaluate` the same override fails: Gradle has already locked the value.
> - **Sentry is not in the app yet.** `sentry_flutter` 10 requires API 26 (Android 8), against our 24.
>   - Logging goes through `package:logging` in one file (`core/logging/app_logging.dart`), so the chosen service is added there.
>   - This is now part of decision 3 in §13.
> - **go_router is held at 17.** go_router 18 moved to the new `material_ui` package, while the app and `flutter_localizations` use Flutter's built-in Material. Mixing the two would give pages a different `Theme`. Move when `flutter_localizations` has moved.
> - **Roboto is bundled** (400, 500, 700, from the Flutter SDK). Some phone makers replace the system font, and the layout tests must measure the same font the phones draw.
> - **`textSecondary` is #616161, not #757575.** The old colour measures 4.2 : 1 on the background, under 4.5. A contrast test now checks every text colour.
>
> **Not done yet:**
> - **On the developer's side:**
>   - create the release key and back it up twice (`scripts/create-release-key.sh`);
>   - install a signed build on a phone (none was connected);
>   - put Flutter on `PATH`.
> - **Waiting on later milestones:**
>   - an emulator and FVM itself;
>   - the reference phone (before M1's speed checks).

**M1 — Walking skeleton (6–9 days)**

- **Sign in:** creates the account's file and stores the token.
- **First data:** pull customers and transactions, and show the customer list with balances, offline.
- **Record and send:** record a debt offline and push it.
- **Updates:** the update check, download and install, with backend B1 and `release.sh`.
- **Backend:** B11.
- **Exit:**
  - Live scenarios 1 and 2 pass in CI.
  - A release published by the script installs on the reference phone (a quiet Wi-Fi download, then Restart), and the app reopens on the new version.

**M2 — Sync, complete (6–9 days)**

- **The engine:** all six record kinds, frozen batches, conflicts, resync without emptying screens, resync on a role change, triggers and backoff.
- **Screens:** the "Needs attention" screen, the sync status, and badges on unsent records.
- **Self-check:** the balance self-check.
- **Backend:** B2 and B14.
- **Exit:**
  - Live scenarios 3–7, 10 and 13 pass.
  - The fake-server failure tests pass: killed mid-push, duplicate answers, timeouts, a 500, a moved clock.

**M3 — Customers and the ledger (6–9 days)**

- **Customers:**
  - search by name or phone, and filters;
  - the contact picker, with a required phone and a no-phone choice;
  - the customer screen, with balance, available credit and dues;
  - delete (owner).
- **Debts and payments:**
  - record a debt or payment, with method, code, due date and limit warning;
  - entry detail, with the time and who recorded it;
  - void (owner) and credit limits (owner);
  - staff names from the cached list.
- **Backend:** B5 and B15.
- **Exit:**
  - The four field-test requests are done.
  - The customer and ledger rows of Appendix A are marked.
  - Live scenarios 4–7 pass through the real screens' code.

**M4 — Sales, stock and suppliers (5–8 days)**

- **Sales:** cash, M-Pesa, bank and credit, with the credit sale's debt from `SaleDebtID`; void.
- **Stock:** stock notes; purchase orders online, with PDF sharing and cancelling.
- **Suppliers:** suppliers, bills, payments, voids, and what is owed.
- **Backend:** B8.
- **Exit:**
  - Live scenarios 8 and 9 pass.
  - A purchase-order PDF opens in WhatsApp.

**M5 — Home and reports (4–6 days)**

- **Home,** by role, computed on the phone.
- **The Today list,** and today's money by method and by staff member.
- **Reports:** ageing, sales, collections, statement and payables. Online, with the last copy cached and its "as of" time; PDFs saved, opened and shared.
- **Exit:**
  - The phone's Home figures equal the server's summary in the live tests.
  - Every PDF opens and shares.

**M6 — Team, account and settings (4–6 days)**

- **Team:** sharing invites, the staff list, deactivating, resetting a password.
- **Account:** the profile, changing the password, and the forced change.
- **Business:** the profile, logo and time zone.
- **Settings:** language, app lock, sync and data, accounts on this phone, help.
- **Backend:** B6, B7 and B9.
- **Exit:**
  - Every row of the session table in 09 §4 has a screen test.
  - Live scenarios 11 and 12 pass.

**M7 — The extras shops will love (5–7 days)**

- **Payments and customers:** M-Pesa paste; reminders on WhatsApp and SMS, with the 3-day limit; receipts.
- **Help:** the sample shop and the how-to cards.
- **Backend:** B12.
- **Exit:**
  - The M-Pesa parser passes test vectors collected from at least three shops (anonymised).
  - Reminders respect the limit across app restarts.

**M8 — Hardening and beta (5–8 days, then a 2-week beta)**

- **Before the beta:**
  - The speed budgets met on the reference phone.
  - TalkBack labels on the main screens.
  - The security checklist (§9.3) and the privacy policy.
  - Backend B3 and B4, and B10's web page.
  - A staging server.
- **The beta:**
  - The three field-test shops plus two new ones.
  - A staged rollout.
  - Sentry and sync issues reviewed daily, and fixed forward.
- **Exit:**
  - At least 99.5% of sessions without a crash over the last 7 days.
  - No unexplained sync issue, and a silent balance self-check.
  - The owners confirm their balances.
  - No open P0 or P1 bug.

**M9 — Cutover (1–2 days, then a 2-week rollback window).** Done together with the live-server move (§11).

**M10 — Google Play (3–5 days, plus 14 days of closed testing on a personal account)**

- **The build:** the `play` flavour, with Play's in-app updates.
- **The listing:**
  - English and Swahili screenshots, taken from the layout tests;
  - the data safety form;
  - account deletion.
- **The rollout:** a staged production release.

**Total:** roughly 11–16 weeks to cutover.

**To ship sooner:** move M7 to v2.1. v2.0 is then about 2 weeks earlier, and still includes:
- everything the shops have today;
- the four field-test requests;
- the new backend features;
- self-update.

After v2.0 come the v2.1 features in §2.4.

---

## 11. Cutover, done with the live-server move

**Before:**
- **The beta's exit checks** are passed.
- **Production is ready:** HTTPS, backups with a tested restore, and B13 on v1.
- **A rehearsal:** the import, run with `make import-v1` against a copy of production, matches every balance.

**Steps:**

1. **A week before:** tell the shops, and install the new app beside the old one. They can coexist because the app IDs differ (D2).
2. **After closing on the day:**
   1. Each shop opens the old app online and syncs. Check in the v1 console that each shop's latest entries have arrived.
   2. Switch v1 to read-only (B13).
   3. Snapshot the v1 database.
   4. Import into v2, verifying balances. The import stops on any difference.
3. **The shops sign in to the new app** with the same phone and password, because password hashes carry across. The first sync downloads everything. On screen, compare three customers per shop with the old app.
4. **Two weeks of rollback window:** keep v1 read-only, then remove the old app from the phones.

**Rollback:** if a balance differs or a serious bug appears, lift v1's read-only switch. The shops carry on with the old app; fix the problem and repeat.

**The edge case:** an entry recorded in the old app after the freeze cannot sync, because v1 refuses it with a clear message. Re-enter it in the new app. With three shops on the phone, the numbers are tiny.

---

## 12. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A sync bug loses or doubles records | Severe: it breaks the product's whole promise | Frozen batches, page-and-cursor transactions, live and convergence tests, the self-check in the field, backups |
| A local migration fails during an update | Severe | Every migration path tested; a copy of the file before migrating; a Sentry alert |
| The signing key is lost | Severe: every shop reinstalls | Two backups; a fingerprint check in the release script |
| Developer verification blocks installs in 2027 | High | Register early (§6.6); the Play channel |
| Play rejects the app | Medium | A Play flavour without the updater; account deletion; the data safety form |
| Slow on cheap phones | High | The reference phone from M1; speed budgets; profiling |
| Scope creep | High | Exit checks per milestone; the v2.1 list; ship without M7 if needed |
| Wrong phone clocks | Medium | Server cursors; clock correction; a warning when the clock is off |
| A token expires offline | Medium | Offline use never needs the token; renewal (B7) |
| Password guessing at sign-in | High | B3 before the beta |
| Duplicate customers from inconsistent phone formats | Medium | B15, and "Use the existing customer" (§4.3) |
| The learning curve: Riverpod, Drift, sync | Medium | DairyGo's patterns; the reasons in this document; small milestones |
| The server is down, or data is lost | Severe | Backups and HTTPS (09); the app keeps working offline meanwhile |

---

## 13. Decisions needed from you

1. **🔒 The app ID.** The reverse of a domain you own and will keep, for example `ke.co.<your-domain>.salio`. It can never change once shops install the app.
2. **The Google developer account:**
   - **Personal:** the 12-tester closed test applies.
   - **Organisation:** needs a registered company and a D-U-N-S number.

   Either way, verify it for developer verification (§6.6).
3. **Crash reporting:**
   - **Sentry's free tier:** recommended, the simplest.
   - **Self-hosted GlitchTip:** free, but one more thing to run.
   - **Firebase Crashlytics:** free, but ties the app to Firebase.

   Found in M0: the current Sentry Flutter SDK (10.x, which GlitchTip also uses) requires Android 8 (API 26), while D17 sets Android 7 (API 24). Choosing Sentry or GlitchTip therefore means one of three things:
   - raise the minimum to API 26;
   - use the older 9.x SDK;
   - keep Android 7 phones without crash reports.

   Decide before the beta (M8). Until then the app logs locally only.
4. **The text-size ceiling:** 1.3×, as in DairyGo (recommended for v2.0), or higher at the cost of more layout work.
5. **The production addresses** for the API and the download page, for example `api.<domain>` and `<domain>/app`.
6. **The sample shop:** is it worth it for your sales visits? Recommended: yes.

---

## 14. Glossary

- **Pending / outbox:** changes saved on the phone that the server has not confirmed yet.
- **Cursor:** a number the server gives with each pull, meaning "you have everything up to here". Unlike a clock time, it cannot skip a record that was committed late.
- **operation_id / idempotency:** an ID that makes a repeated request count only once.
- **Tombstone:** a deleted record kept as "deleted", so other phones learn about the deletion.
- **Resync:** downloading everything again from zero.
- **Per-field merge:** two people changing different fields of the same record both keep their change.
- **Conflict:** a change the server did not accept, with the reason.
- **Walking skeleton:** the thinnest version that works end to end, built first to prove the architecture.
- **dp:** a screen unit that is the same physical size on every phone.
- **ABI:** the phone's processor type: arm64 on most phones, armv7 on older ones. Each gets its own APK.
- **Version code:** Android's build number. An update must have a higher one.
- **Signing key:** proves an update comes from the same developer. Android refuses an update signed with a different key.
- **Flavour:** a variant of the app built from the same code: dev, staging or prod; direct or Play.
- **Shared test vectors:** test cases stored as data and run by both the Go tests and the Dart tests.
- **Staged rollout:** offering an update to a percentage of phones first.
- **Release health:** the share of sessions without a crash, for each version.
- **One-way door:** a decision that cannot be undone later.

---

## Appendix A — Every server operation, and where the app uses it

| Server operation | In the app | How | Milestone |
|---|---|---|---|
| register-business, login, join-business | Welcome, Sign in, Join | Online | M1 (sign in), M6 |
| get-me, update-me | Refresh at start, My account | Online, cached | M1, M6 |
| change-my-password | Change password, the forced change | Online | M6 |
| get-business, update-business, business logo | Business profile, PDFs | Online, cached | M1 (read), M6 |
| create-invite, list-staff, deactivate-staff, reset-staff-password | Team | Online; the list is cached | M3 (names), M6 |
| sync-pull, sync-push | The sync engine | In the background | M1, M2 |
| create/update/delete-customer, set-customer-credit-limit | Customers | Through sync | M2, M3 |
| create-transaction, void-transaction | Debts and payments | Through sync | M2, M3 |
| record-sale, void-sale | Sales | Through sync | M4 |
| create/update/delete-stock-request | Stock | Through sync | M4 |
| create/cancel/list/get-purchase-order, purchase-order-pdf | Purchase orders | Online, owner | M4 |
| create/update/delete-supplier, create-supplier-entry, void-supplier-entry | Suppliers | Through sync, owner | M4 |
| list/get for customers, transactions, sales, stock requests, suppliers and supplier entries | — | Read from the phone's database instead | — |
| reports-summary | The self-check, parity tests | Online | M2, M5 |
| reports-due | Today list | Computed on the phone, by the same FIFO rule | M5 |
| reports-ageing, -sales, -collections, -customer-statement, -payables, and their PDFs | Reports | Online, cached | M5 |
| *new:* get-app-version, `/app`, `/app/download/{abi}` | The updater | Public | M1 |
