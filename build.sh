#!/bin/zsh
# Builds KeyAwake: the interface (with a Dock icon) and the engine nested inside it.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
BUILD="$ROOT/.build"
rm -rf "$BUILD"; mkdir -p "$BUILD"

SHARED=(Sources/Shared/*.swift)
POLICY=(Sources/Policy/*.swift)

# Signing with a stable identity is what makes the Bluetooth permission survive rebuilds.
# With an ad-hoc signature macOS cannot recognise the app between builds and asks again.
#   1) Prefer a self-signed certificate named "KeyAwake" (scripts/make-signing-cert.sh).
#      Stable AND anonymous: macOS shows "KeyAwake" in Login Items, not your name.
#   2) Otherwise any signing identity. Stable, but it puts the certificate's name and
#      email in the background-item notice and in Login Items.
#   3) Otherwise ad-hoc: no personal data, but macOS re-asks for Bluetooth after rebuilds.
IDENTITY=$(security find-certificate -c "KeyAwake" -Z 2>/dev/null \
             | awk '/SHA-1 hash:/ {print $3; exit}' || true)
if [[ -n "$IDENTITY" ]]; then
  echo "▸ Signing with the self-signed “KeyAwake” certificate"
else
  IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)
  IDENTITY=$(<<<"$IDENTITIES" awk '/[0-9A-F]{40}/ {print $2; exit}')
  if [[ -n "$IDENTITY" ]]; then
    NAME=$(<<<"$IDENTITIES" sed -n 's/.*"\(.*\)".*/\1/p' | head -1)
    echo "▸ Signing with: $NAME"
    echo "  Heads-up: macOS will show that name in Login Items."
    echo "  Run scripts/make-signing-cert.sh to sign as “KeyAwake” instead."
  else
    IDENTITY="-"
    echo "▸ No identity: ad-hoc signature (macOS will re-ask for Bluetooth after rebuilds)"
  fi
fi

# Force ad-hoc for the binaries you publish: KEYAWAKE_ADHOC=1 ./build.sh
if [[ "${KEYAWAKE_ADHOC:-0}" == "1" ]]; then
  IDENTITY="-"
  echo "▸ KEYAWAKE_ADHOC=1 -> forcing an ad-hoc signature"
fi

bundle() {           # bundle <name> <bundle-id> <LSUIElement true|false> <directory>
  local name=$1 ident=$2 agent=$3 dest=$4
  local app="$dest/$name.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                    <string>$name</string>
    <key>CFBundleDisplayName</key>             <string>$name</string>
    <key>CFBundleExecutable</key>              <string>$name</string>
    <key>CFBundleIdentifier</key>              <string>$ident</string>
    <key>CFBundleDevelopmentRegion</key>       <string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>es</string><string>zh-Hans</string></array>
    <key>CFBundlePackageType</key>             <string>APPL</string>
    <key>CFBundleShortVersionString</key>      <string>1.1.1</string>
    <key>CFBundleVersion</key>                 <string>3</string>
    <key>LSMinimumSystemVersion</key>          <string>14.0</string>
    <key>CFBundleIconFile</key>                <string>AppIcon</string>
    <key>LSUIElement</key>                     <$agent/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>KeyAwake needs Bluetooth to keep your keyboard on a low-latency link.</string>
    <key>NSHumanReadableCopyright</key>        <string>MIT licensed</string>
</dict>
</plist>
PLIST
  cp "$ROOT/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
  # Translations. English is the base language; Spanish and Simplified Chinese sit
  # alongside it, and macOS picks by system language. Both bundles get a copy, because
  # each process reads its own.
  # InfoPlist.strings is what localises the Bluetooth permission dialog.
  for lproj in "$ROOT"/Resources/*.lproj; do
    cp -R "$lproj" "$app/Contents/Resources/"
  done
  mv "$BUILD/$name" "$app/Contents/MacOS/$name"
  codesign --force --sign "$IDENTITY" --timestamp=none "$app" >/dev/null 2>&1 \
    && echo "  signed" || echo "  WARNING: could not sign"
}

echo "▸ Interface (KeyAwake)"
swiftc -O -swift-version 5 \
  -framework AppKit -framework SwiftUI \
  -o "$BUILD/KeyAwake" "${SHARED[@]}" Sources/App/*.swift
bundle KeyAwake com.keyawake.app false "$ROOT"

echo "▸ Engine (KeyAwakeAgent), nested as a login item"
swiftc -O -swift-version 5 \
  -framework AppKit -framework CoreBluetooth -framework CoreGraphics \
  -o "$BUILD/KeyAwakeAgent" "${SHARED[@]}" "${POLICY[@]}" Sources/Agent/*.swift
LOGIN_ITEMS="$ROOT/KeyAwake.app/Contents/Library/LoginItems"
mkdir -p "$LOGIN_ITEMS"
bundle KeyAwakeAgent com.keyawake.agent true "$LOGIN_ITEMS"

# Nesting invalidates the container's signature, so re-sign it outside-in.
codesign --force --sign "$IDENTITY" --timestamp=none "$ROOT/KeyAwake.app" >/dev/null 2>&1 \
  && echo "  container re-signed" || echo "  WARNING: could not re-sign the container"

rm -rf "$BUILD"
echo "✓ Done: $ROOT/KeyAwake.app (engine bundled inside)"
