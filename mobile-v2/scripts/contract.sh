#!/usr/bin/env bash
# The app's snapshot of server-v2's API contract (docs/10, D10 and B11).
#
#   SALIO_LIVE_URL=http://127.0.0.1:8091 scripts/contract.sh            # check
#   SALIO_LIVE_URL=http://127.0.0.1:8091 scripts/contract.sh --update   # refresh
#
# Fetches the running server's OpenAPI document and compares it with
# test/contract/openapi.json. A server change that touches the API then shows
# up as a change to that file in the pull request, where the app's side of it
# can be reviewed; test/contract_test.dart checks that everything the app
# calls is still in it. CI runs the check against the live-test server.
set -euo pipefail

cd "$(dirname "$0")/.."
URL="${SALIO_LIVE_URL:?set SALIO_LIVE_URL to a running server-v2 with docs on}"
SNAPSHOT="test/contract/openapi.json"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Sorted keys and no server version, so only real changes differ.
curl -sf "$URL/openapi.json" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
doc.get("info", {}).pop("version", None)
json.dump(doc, sys.stdout, indent=2, sort_keys=True, ensure_ascii=False)
print()
' > "$TMP"

if [[ "${1:-}" == "--update" ]]; then
  cp "$TMP" "$SNAPSHOT"
  echo "Updated $SNAPSHOT."
elif ! diff -u "$SNAPSHOT" "$TMP"; then
  echo >&2
  echo "server-v2's API differs from $SNAPSHOT (above)." >&2
  echo "Check the app still matches, then run: scripts/contract.sh --update" >&2
  exit 1
else
  echo "The API matches $SNAPSHOT."
fi
