#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/dist/LiveTranslate.bobplugin"
python3 -m json.tool "$ROOT_DIR/plugin/info.json" >/dev/null
node --check "$ROOT_DIR/plugin/main.js"
rm -rf "$OUTPUT"
# Bob plugins are zip archives: the files must live at the archive root.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$ROOT_DIR/plugin/info.json" "$ROOT_DIR/plugin/main.js" "$STAGE/"
cp "$ROOT_DIR/plugin/logo.png" "$STAGE/icon.png"
python3 -m json.tool "$STAGE/info.json" >/dev/null
node --check "$STAGE/main.js"
(cd "$STAGE" && zip -q -r "$OUTPUT" info.json main.js icon.png)
printf '%s\n' "$OUTPUT"
