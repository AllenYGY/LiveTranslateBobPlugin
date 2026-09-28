#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:?Usage: ./scripts/notarize-app.sh <notarytool-keychain-profile>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT="$ROOT_DIR/dist/LiveTranslate-app.zip"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT_DIR/app/Info.plist")"
OUTPUT="$ROOT_DIR/dist/LiveTranslate-macOS-$VERSION.zip"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

# Submit the exact signed ZIP produced by build-app.sh. Never fall back to
# ad-hoc signing or publish a ZIP before Apple accepts the submission.
xcrun notarytool submit "$INPUT" --keychain-profile "$PROFILE" --wait --output-format json > "$STAGE_DIR/notary.json"
python3 - "$STAGE_DIR/notary.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as result_file:
    result = json.load(result_file)
if result.get("status") != "Accepted":
    raise SystemExit(f"Notarization was not accepted: {result.get('status', 'unknown')} (id: {result.get('id', 'unknown')})")
print(f"Notarization accepted: {result['id']}")
PY
ditto -x -k "$INPUT" "$STAGE_DIR"
xcrun stapler staple "$STAGE_DIR/LiveTranslate.app"
xcrun stapler validate "$STAGE_DIR/LiveTranslate.app"
codesign --verify --deep --strict "$STAGE_DIR/LiveTranslate.app"
ditto -c -k --norsrc --keepParent "$STAGE_DIR/LiveTranslate.app" "$OUTPUT"
shasum -a 256 "$OUTPUT"
echo "$OUTPUT"
