# Salio mobile v2

The new Android app for Salio, built against server-v2. The plan, with the
reasons for each choice, is [docs/10-mobile-app-plan.md](../docs/10-mobile-app-plan.md).
The old app in `../mobile/` keeps serving the v1 server until cutover.

## Setup

Flutter **3.44.4** exactly (pinned in `pubspec.yaml` and `.fvmrc`). On this
laptop it is at `~/flutter/bin`, which is not on `PATH`. Add it once:

```bash
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

With [FVM](https://fvm.app) installed, `fvm use` picks the version from
`.fvmrc` instead.

```bash
cd mobile-v2
flutter pub get        # also generates the translations
```

## Builds

There are three flavours. Each has its own app ID, so all three can be
installed on one phone at the same time.

| Flavour | App ID | Name on the phone | Server |
| --- | --- | --- | --- |
| `dev` | `ke.co.urizon.salio.dev` | Salio Dev | server-v2 on the laptop, `http://127.0.0.1:8090` |
| `staging` | `ke.co.urizon.salio.staging` | Salio Staging | the live server until a staging server exists (M8) |
| `prod` | `ke.co.urizon.salio` | Salio | `https://apis.salio.urizon.co.ke` |

The app ID `ke.co.urizon.salio` can never change once shops install the app.
Only `dev` may use plain HTTP.

**Against server-v2 on the laptop.** Start it (`cd server-v2 && make run`,
port 8090). Then, with the phone plugged in by USB or an emulator running:

```bash
adb reverse tcp:8090 tcp:8090      # the phone's 127.0.0.1:8090 is now the laptop's
flutter run --flavor dev
```

`adb reverse` needs re-running after the phone is unplugged. Over Wi-Fi
instead, use the laptop's address:
`--dart-define=API_URL=http://192.168.x.x:8090`.

**Against the live server**, still as a dev build:

```bash
flutter run --flavor dev --dart-define=API_URL=https://apis.salio.urizon.co.ke
```

More → About this app shows which environment and server a build uses.

## Checks

```bash
dart format lib test
flutter analyze --fatal-infos
flutter test                       # everything, about a minute
flutter test test/layout           # every screen × 8 sizes × 2 text sizes × 2 languages × 2 roles
```

**Live tests**: simulated phones (the app's own database, sync and network
code) against a real server-v2 (docs/10, §8.2):

```bash
scripts/live-server.sh &                     # a throwaway server-v2 on :8091
SALIO_LIVE_URL=http://127.0.0.1:8091 flutter test test/live
```

The script creates its own database (`salio_v2_live`) and roles in the test
PostgreSQL on port 5434, so the dev and test databases are not touched.
Without `SALIO_LIVE_URL` the live tests are skipped.
Scenario 10 runs `scripts/live-gc.sh`, which ages the live database's
deletions and runs the real tombstone sweep, so a phone is told to resync.
It refuses any database whose name lacks "live".

**The sync engine's failure tests** (`test/sync/`) run the engine against
`test/support/fake_server.dart`, which can lose answers, time out, fail with
a 500, replay a push and forget deletions. They need no server.

**The API contract.** `test/contract/openapi.json` is the app's copy of
server-v2's API, and `test/contract_test.dart` checks the app against it,
without a server. After a server change, refresh it against the live-test
server and review the difference:

```bash
SALIO_LIVE_URL=http://127.0.0.1:8091 scripts/contract.sh            # check
SALIO_LIVE_URL=http://127.0.0.1:8091 scripts/contract.sh --update   # refresh
```

The layout tests fail on any overflow and name the screen size, the text
size and the file and line. To look at the screens:

```bash
flutter test test/layout/layout_test.dart --update-goldens --dart-define=SCREENSHOTS=true
# → test/layout/screenshots/ (not committed)
```

CI (`.github/workflows/ci.yml`, job `mobile-v2`) runs all of this, builds the
dev APKs, and checks their version codes and native libraries with
`scripts/check-apks.sh`. The `mobile-v2-live` job runs the live tests.

## The release key

Android installs an update only if it is signed with the same key as the app
already on the phone. Create the key **once**:

```bash
scripts/create-release-key.sh
```

It writes the key to `~/.salio/salio-release.jks`, its password to
`android/key.properties` (never committed), and its public fingerprint to
`android/release-cert.sha256` (committed). **Back up both the key and
`key.properties` straight away, in two places**, such as a password manager
and a USB drive. If they are lost, no future update can be installed, and
every shop has to uninstall and reinstall.

Release builds stop with instructions when the key is missing. Debug builds
use this laptop's debug key, so a debug build and a release build of the same
flavour cannot update each other: uninstall one first.

```bash
flutter build apk --release --flavor prod --split-per-abi
```

## Releasing

The app updates itself (docs/10, §6). A release goes out like this:

1. **Server first.** Deploy any server-v2 change the release needs before the app. A newer app on an older server fails its syncs.
2. **Version.** Raise `version:` in `pubspec.yaml`, for example from `2.0.2+14` to `2.0.3+15`, and commit.
3. **Release:**

   ```bash
   SALIO_RELEASE_TARGET=user@server:/path/to/server-v2/releases \
   SALIO_RELEASE_URL=https://apis.salio.urizon.co.ke \
   scripts/release.sh --notes-en "Faster customer list" --notes-sw "Orodha ya wateja ni ya haraka" --rollout 10
   ```

   It refuses a dirty tree, runs the checks, builds and checks the prod APKs, refuses any APK not signed with the Salio key, writes `server-v2/releases/`, uploads the APKs first and the manifest last, confirms the live server offers the new build, and tags `app-v<version>+<build>` locally.
4. **Widen the rollout** when nothing has gone wrong: `scripts/set-rollout.sh 50`, then `100`.

`--required` makes phones below this build stop syncing until they update. They keep working offline, and their records wait on the phone. Use it only when older apps can no longer sync correctly with the server.

**On the phone.**
- On Wi-Fi a new version downloads by itself, then a bar offers **Restart**.
- On mobile data the bar shows the size and waits for **Update**.
- A download that drops carries on from where it stopped.
- Every file is checked against its SHA-256 before Android installs it, and Android also checks the signature.
- On Android 12 and newer, updates after the first install go through without a question.

**Rolling back means rolling forward.** Android won't install a lower version code. To undo a bad release, publish the previous code under a higher build number.

## Layout

```text
lib/
  app/        app.dart, environment, router, adaptive shell, theme, translations
  core/       database (drift), sync engine, network, money, server clock,
              session and accounts, layout rules, logging, shared widgets
  features/   one folder per feature: data → domain → presentation
test/
  database/   every schema upgrade path, with data
  layout/     the layout harness and tests (from DairyGo)
  live/       simulated phones against a real server-v2
  sync/       the sync engine against a failing fake server
  support/    the simulated phone, seeded data, fakes
drift_schemas/ every database schema version, for migration tests
scripts/      create-release-key.sh, release.sh, set-rollout.sh,
              check-apks.sh, live-server.sh, live-gc.sh, contract.sh
```

Screens never touch the database or the network; controllers (Riverpod) call
repositories (docs/10, §4.1).

## Data on the phone

Each account that signs in gets its own database file,
`accounts/<user id>.db`, so one shop's records can never appear on another's
screens (docs/10, D5). The token is in Android's secure storage. Signing out
keeps the file and anything not yet sent.

After changing a table in `lib/core/database/tables.dart`:

```bash
dart run build_runner build            # regenerates app_database.g.dart (committed)
dart run drift_dev make-migrations     # after raising schemaVersion: saves the new schema
```

`make-migrations` also writes the helpers in `test/database/generated/`, and
the step functions in `app_database.steps.dart` that `onUpgrade` uses. Add
data checks for the new step to `test/database/generated/app/migration_test.dart`:
unsent records, a frozen push and the cursor must come through every
upgrade. Declare indexes with `@TableIndex` on the table, not in SQL, so the
snapshots include them.

**Sync, in one paragraph** (docs/10, §4.3). Every write marks its record
pending. A push freezes a batch, operation id and exact body, and a retry
sends that body again. The answer marks only the version sent as synced,
takes the server's copy (`current`, B2) for a conflict the server won, and
keeps anything else aside in `sync_issues` for **More → Needs attention**.
A pull saves each page with its cursor in one transaction. A resync pulls
everything again and only then removes what the server no longer has. What
differs between the six kinds of record is in `lib/core/sync/sync_kinds.dart`.
