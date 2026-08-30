#!/bin/bash
# Generates and signs appcast.xml for a release.
#
# Run this locally, never in CI. The EdDSA private key lives in the login
# Keychain and is deliberately not exported: CI having it would mean a
# compromised runner could sign an update that every install would trust.
#
#   ./Tools/make-appcast.sh dist/FunNotch-1.0.2.dmg
#
# Then commit appcast.xml and push, since SUFeedURL reads it from the repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
"./Tools/fetch-sparkle.sh"

DMG="${1:-}"
if [ -z "$DMG" ] || [ ! -f "$DMG" ]; then
  echo "usage: $0 path/to/FunNotch-<version>.dmg" >&2
  exit 1
fi

VERSION="$(defaults read "$ROOT/build/FunNotch.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
  echo "ERROR: build/FunNotch.app not found. Build before generating the appcast." >&2
  exit 1
fi

# generate_appcast wants a directory of releases; give it one containing only
# the dmg being published so it cannot pick up stale builds.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$DMG" "$STAGE/"

# Carry the existing appcast in so previous entries survive.
[ -f appcast.xml ] && cp appcast.xml "$STAGE/appcast.xml"

echo "==> Signing and generating appcast for $VERSION"
./Vendor/bin/generate_appcast \
  --download-url-prefix "https://github.com/JoshuaT1105/FunNotch/releases/download/v${VERSION}/" \
  --link "https://funnotch.xyz" \
  "$STAGE"

cp "$STAGE/appcast.xml" appcast.xml
echo "==> Wrote appcast.xml"
grep -c '<item>' appcast.xml | xargs -I{} echo "    {} release(s) listed"
echo
echo "Next:"
echo "  1. Check the release notes in appcast.xml read sensibly"
echo "  2. git add appcast.xml && git commit -m 'Publish $VERSION appcast' && git push"
echo "     (SUFeedURL reads it from main, so it is live the moment it is pushed)"
