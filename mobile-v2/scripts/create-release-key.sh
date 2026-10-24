#!/usr/bin/env bash
# Creates the key that signs every Salio release, once (docs/10, D2).
#
# Phones only accept an update signed with the same key as the installed app.
# Losing this key means every shop must uninstall and reinstall; leaking it
# lets someone else publish "updates". Back it up (see the message at the end).
#
#   mobile-v2/scripts/create-release-key.sh
#
# Writes:
#   ~/.salio/salio-release.jks              the key (outside the repository)
#   mobile-v2/android/key.properties        where it is and its password (git-ignored)
#   mobile-v2/android/release-cert.sha256   its public fingerprint (committed);
#                                           the release script publishes only
#                                           APKs signed by it
#
# Copied from DairyGo's, without --from-installed: no installed Salio carries
# this app ID yet, so there is no older key to keep.
set -euo pipefail

cd "$(dirname "$0")/.."
KEY_DIR="${SALIO_KEY_DIR:-$HOME/.salio}"
KEYSTORE="$KEY_DIR/salio-release.jks"
PROPS="android/key.properties"
ALIAS="salio"
DNAME="${SALIO_KEY_DNAME:-CN=Salio, O=Urizon, L=Mombasa, C=KE}"
PIN="android/release-cert.sha256"

if [[ $# -gt 0 ]]; then
  echo "Unknown option $1" >&2; exit 2
fi
if [[ -e "$KEYSTORE" || -e "$PROPS" ]]; then
  echo "A release key already exists ($KEYSTORE or $PROPS). Not replacing it:" >&2
  echo "a new key would stop installed apps from accepting updates." >&2
  exit 1
fi
command -v keytool >/dev/null || { echo "keytool not found (install a JDK)." >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl not found." >&2; exit 1; }

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"
PASSWORD="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)"

# PKCS12 uses one password for the store and the key. 10000 days (27 years)
# because a key cannot be renewed without breaking updates.
keytool -genkeypair -v \
  -storetype PKCS12 \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "$DNAME" \
  -storepass "$PASSWORD" -keypass "$PASSWORD" >/dev/null 2>&1
chmod 600 "$KEYSTORE"

umask 077
cat >"$PROPS" <<PROPS
# Salio release signing. Never commit or share this file.
storeFile=$KEYSTORE
storePassword=$PASSWORD
keyAlias=$ALIAS
keyPassword=$PASSWORD
PROPS

# The public fingerprint, as apksigner prints it (lower case, no colons).
( umask 022; keytool -list -v -keystore "$KEYSTORE" -storepass "$PASSWORD" -alias "$ALIAS" \
  | sed -n 's/^[[:space:]]*SHA256: //p' | tr -d ':' | tr 'A-F' 'a-f' >"$PIN" )
[[ -s "$PIN" ]] || { echo "Could not read the key's fingerprint." >&2; exit 1; }

cat <<MSG
Release key created.

  Key:          $KEYSTORE
  Password:     in $(pwd)/$PROPS
  Fingerprint:  $(cat "$PIN")

BACK IT UP NOW, in two places (for example a password manager and a USB drive):
  1. $KEYSTORE
  2. $(pwd)/$PROPS
Commit $PIN (it is public, not a secret).
Without both, no future update can be installed over this release.
MSG
