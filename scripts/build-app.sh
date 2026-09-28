#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/LiveTranslate.app"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE_APP="$STAGE_DIR/LiveTranslate.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  developer_ids=()
  while IFS= read -r identity; do
    developer_ids+=("$identity")
  done < <(security find-identity -v -p codesigning | sed -n 's/^[[:space:]]*[0-9]*) \([[:xdigit:]]*\) "Developer ID Application:.*$/\1/p')
  if [[ ${#developer_ids[@]} -ne 1 ]]; then
    echo "Expected exactly one Developer ID Application certificate; set CODESIGN_IDENTITY to its SHA-1 fingerprint." >&2
    exit 1
  fi
  CODESIGN_IDENTITY="${developer_ids[0]}"
fi
mkdir -p "$STAGE_APP/Contents/MacOS" "$ROOT_DIR/dist"
cp "$ROOT_DIR/app/Info.plist" "$STAGE_APP/Contents/Info.plist"
ICONSET="$STAGE_DIR/LiveTranslate.iconset"
mkdir -p "$ICONSET" "$STAGE_APP/Contents/Resources"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT_DIR/plugin/logo.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ROOT_DIR/plugin/logo.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGE_APP/Contents/Resources/LiveTranslate.icns"
swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx26.0 -sdk "$SDK" \
  -framework Cocoa -framework SwiftUI -framework AVFoundation -framework Translation \
  -framework CryptoKit -framework Security \
  "$ROOT_DIR/app/LiveTranslateApp.swift" "$ROOT_DIR"/app/Services/*.swift "$ROOT_DIR"/app/Views/*.swift \
  -o "$STAGE_APP/Contents/MacOS/LiveTranslate"
codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp \
  --entitlements "$ROOT_DIR/app/LiveTranslate.entitlements" "$STAGE_APP"
codesign --verify --deep --strict "$STAGE_APP"
rm -rf "$APP"
ditto --norsrc "$STAGE_APP" "$APP"
# File Provider may immediately add Finder metadata in Documents; verify the
# signed staging app above and the distributable ZIP after extraction instead.
ditto -c -k --norsrc --keepParent "$STAGE_APP" "$ROOT_DIR/dist/LiveTranslate-app.zip"
echo "$APP"
