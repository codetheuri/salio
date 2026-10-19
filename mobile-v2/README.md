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

## Layout

```text
lib/
  app/        app.dart, environment, router, adaptive shell, theme, translations
  core/       database (drift), sync engine, network, money, server clock,
              session and accounts, layout rules, logging, shared widgets
  features/   one folder per feature: data → domain → presentation
test/
  layout/     the layout harness and tests (from DairyGo)
  live/       simulated phones against a real server-v2
  support/    the simulated phone, seeded data, fakes
drift_schemas/ every database schema version, for migration tests
scripts/      create-release-key.sh, check-apks.sh, live-server.sh
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
