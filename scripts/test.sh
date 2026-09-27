#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/scripts/package.sh" >/dev/null
python3 -m json.tool "$ROOT_DIR/dist/LiveTranslate.bobplugin/info.json" >/dev/null
node --check "$ROOT_DIR/dist/LiveTranslate.bobplugin/main.js"
files="$(find "$ROOT_DIR/dist/LiveTranslate.bobplugin" -type f | wc -l | tr -d ' ')"
[[ "$files" == 3 ]]
node "$ROOT_DIR/scripts/test-plugin.js"
echo 'Plugin package and callback tests passed'
