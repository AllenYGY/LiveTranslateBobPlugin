#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/dist"
swiftc -parse-as-library -swift-version 5 \
  "$ROOT_DIR/app/Services/TranscriptionProvider.swift" \
  "$ROOT_DIR/tests/AssemblerTests.swift" \
  -o "$ROOT_DIR/dist/assembler-tests"
"$ROOT_DIR/dist/assembler-tests"
swiftc -swift-version 5 \
  "$ROOT_DIR/app/Services/LessonArchive.swift" \
  "$ROOT_DIR/tests/ArchiveTests.swift" \
  -o "$ROOT_DIR/dist/archive-tests"
"$ROOT_DIR/dist/archive-tests"
"$ROOT_DIR/scripts/build-app.sh"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
ditto -x -k "$ROOT_DIR/dist/LiveTranslate-app.zip" "$CHECK_DIR"
xattr -cr "$CHECK_DIR/LiveTranslate.app"
codesign --verify --deep --strict "$CHECK_DIR/LiveTranslate.app"
python3 - "$CHECK_DIR/LiveTranslate.app" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == '1.3.0'
assert info['CFBundleIconFile'] == 'LiveTranslate.icns'
assert (app / 'Contents/Resources/LiveTranslate.icns').is_file()
PY
