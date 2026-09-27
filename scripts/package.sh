#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/dist/LiveTranslate.bobplugin"
python3 -m json.tool "$ROOT_DIR/plugin/info.json" >/dev/null
node --check "$ROOT_DIR/plugin/main.js"
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"
cp "$ROOT_DIR/plugin/info.json" "$ROOT_DIR/plugin/main.js" "$ROOT_DIR/plugin/icon.png" "$OUTPUT/"
python3 -m json.tool "$OUTPUT/info.json" >/dev/null
node --check "$OUTPUT/main.js"
printf '%s\n' "$OUTPUT"
