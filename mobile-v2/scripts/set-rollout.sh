#!/usr/bin/env bash
# Widens (or narrows) the share of phones offered the published release.
#
#   mobile-v2/scripts/set-rollout.sh 50
#
# Phones keep a fixed bucket from 0 to 99, so going from 10 to 50 adds
# phones without taking the release from any that already have it. With
# SALIO_RELEASE_TARGET set, uploads the new latest.json; the server reads
# it on its next request, with no restart.
set -euo pipefail

cd "$(dirname "$0")/../.."
MANIFEST="server-v2/releases/latest.json"
PERCENT="${1:-}"
[[ "$PERCENT" =~ ^[0-9]+$ ]] && (( PERCENT <= 100 )) || { echo "Give a percentage, 0 to 100." >&2; exit 2; }
[[ -f "$MANIFEST" ]] || { echo "$MANIFEST not found: release first." >&2; exit 1; }

python3 - "$MANIFEST" "$PERCENT" <<'PY'
import json, os, sys
path, percent = sys.argv[1], int(sys.argv[2])
m = json.load(open(path))
m["rollout_percent"] = percent
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(m, f, indent=2)
os.replace(tmp, path)
print(f"Build {m['build']} is now offered to {percent}% of phones.")
PY
if [[ -n "${SALIO_RELEASE_TARGET:-}" ]]; then
  rsync -av "$MANIFEST" "$SALIO_RELEASE_TARGET/"
fi
