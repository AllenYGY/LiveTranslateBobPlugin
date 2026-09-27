#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/LiveTranslate.app"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE_APP="$STAGE_DIR/LiveTranslate.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$STAGE_APP/Contents/MacOS" "$ROOT_DIR/dist"
cp "$ROOT_DIR/app/Info.plist" "$STAGE_APP/Contents/Info.plist"
swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx26.0 -sdk "$SDK" \
  -framework Cocoa -framework SwiftUI -framework AVFoundation -framework Translation \
  -framework CryptoKit -framework Security \
  "$ROOT_DIR/app/LiveTranslateApp.swift" "$ROOT_DIR"/app/Services/*.swift \
  -o "$STAGE_APP/Contents/MacOS/LiveTranslate"
codesign --force --sign - "$STAGE_APP"
codesign --verify --deep --strict "$STAGE_APP"
rm -rf "$APP"
ditto --norsrc "$STAGE_APP" "$APP"
ditto -c -k --norsrc --keepParent "$STAGE_APP" "$ROOT_DIR/dist/LiveTranslate-app.zip"
echo "$APP"
