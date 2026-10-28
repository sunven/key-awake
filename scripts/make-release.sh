#!/bin/zsh
# Produces the publishable binaries in dist/: a DMG and a ZIP.
#
# They are ALWAYS signed ad-hoc, on purpose. A personal certificate embeds the developer's
# name and email in the binary, and macOS shows them in Login Items to everyone who
# installs it. For a third party a self-signed certificate buys nothing over ad-hoc:
# without Apple notarisation, Gatekeeper warns either way.
#
# KEYAWAKE_VERSION / KEYAWAKE_BUILD stamp the bundle when set; the release workflow does.
# KEYAWAKE_CI=1 skips the final rebuild with the local signing identity.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="${KEYAWAKE_VERSION:-${1:-1.1.1}}"
BUILD_NUMBER="${KEYAWAKE_BUILD:-3}"
export KEYAWAKE_VERSION="$VERSION" KEYAWAKE_BUILD="$BUILD_NUMBER"

mkdir -p dist
rm -f "dist/KeyAwake-$VERSION.dmg" "dist/KeyAwake-$VERSION.zip"

echo "▸ Building the publishable copy (ad-hoc)"
KEYAWAKE_ADHOC=1 ./build.sh >/dev/null 2>&1 || { echo "build failed"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/KeyAwake.app" "$STAGE/KeyAwake.app"

echo "▸ ZIP"
(cd "$STAGE" && zip -qry "$ROOT/dist/KeyAwake-$VERSION.zip" KeyAwake.app)

echo "▸ DMG"
ln -s /Applications "$STAGE/Applications"       # the classic drag-and-drop layout
hdiutil create -quiet -volname "KeyAwake" -srcfolder "$STAGE" \
  -ov -format UDZO "dist/KeyAwake-$VERSION.dmg"

if [[ "${KEYAWAKE_CI:-0}" == "1" ]]; then
  echo "▸ KEYAWAKE_CI=1 -> leaving the ad-hoc build in place"
else
  echo "▸ Restoring your local build (signed with your own identity)"
  ./build.sh >/dev/null 2>&1 || { echo "local rebuild failed"; exit 1; }
fi

echo
echo "✓ Done:"
ls -lh dist/ | tail -n +2 | awk '{printf "   %-28s %s\n", $9, $5}'
echo
echo "Signature of what ships:"
hdiutil attach -quiet -nobrowse -mountpoint "$STAGE/mnt" "dist/KeyAwake-$VERSION.dmg"
codesign -dvv "$STAGE/mnt/KeyAwake.app" 2>&1 | grep -E "Signature|TeamIdentifier" | sed 's/^/   /'
hdiutil detach -quiet "$STAGE/mnt"
