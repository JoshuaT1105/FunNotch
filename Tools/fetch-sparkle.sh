#!/bin/bash
# Fetches the Sparkle framework into Vendor/ if it is not already there.
#
# Sparkle ships as a prebuilt binary framework, so it is downloaded rather than
# committed: a 15 MB binary in git costs every clone forever. The version and
# checksum are pinned here, and a mismatch is a hard failure rather than a
# warning, because this framework is what installs code onto users' machines.
set -euo pipefail

SPARKLE_VERSION="2.9.6"
SPARKLE_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Vendor"
FRAMEWORK="$VENDOR/Sparkle.framework"
STAMP="$VENDOR/.sparkle-version"

if [ -d "$FRAMEWORK" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$SPARKLE_VERSION" ]; then
  exit 0
fi

echo "==> Fetching Sparkle $SPARKLE_VERSION"
mkdir -p "$VENDOR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
curl -fsSL "$URL" -o "$TMP/sparkle.tar.xz"

ACTUAL="$(shasum -a 256 "$TMP/sparkle.tar.xz" | cut -d' ' -f1)"
if [ "$ACTUAL" != "$SPARKLE_SHA256" ]; then
  echo "ERROR: Sparkle checksum mismatch." >&2
  echo "  expected $SPARKLE_SHA256" >&2
  echo "  got      $ACTUAL" >&2
  exit 1
fi

tar xf "$TMP/sparkle.tar.xz" -C "$TMP"
rm -rf "$FRAMEWORK"
cp -R "$TMP/Sparkle.framework" "$FRAMEWORK"
# The signing and appcast tools travel with the framework so the release
# workflow does not have to download Sparkle a second time.
rm -rf "$VENDOR/bin"; cp -R "$TMP/bin" "$VENDOR/bin"
printf '%s' "$SPARKLE_VERSION" > "$STAMP"
echo "==> Sparkle $SPARKLE_VERSION ready in Vendor/"
