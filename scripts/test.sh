#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/dist/LiveTranslate.bobplugin"
"$ROOT_DIR/scripts/package.sh" >/dev/null
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
ditto -x -k "$OUTPUT" "$CHECK"
python3 -m json.tool "$CHECK/info.json" >/dev/null
node --check "$CHECK/main.js"
files="$(find "$CHECK" -type f | wc -l | tr -d ' ')"
[[ "$files" == 3 ]]
cmp "$ROOT_DIR/plugin/logo.png" "$CHECK/icon.png"
node "$ROOT_DIR/scripts/test-plugin.js"
echo 'Plugin package and callback tests passed'
