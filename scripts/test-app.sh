#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/dist"
swiftc -parse-as-library -swift-version 5 \
  "$ROOT_DIR/app/Services/TranscriptionProvider.swift" \
  "$ROOT_DIR/tests/AssemblerTests.swift" \
  -o "$ROOT_DIR/dist/assembler-tests"
"$ROOT_DIR/dist/assembler-tests"
"$ROOT_DIR/scripts/build-app.sh"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
ditto -x -k "$ROOT_DIR/dist/LiveTranslate-app.zip" "$CHECK_DIR"
xattr -cr "$CHECK_DIR/LiveTranslate.app"
codesign --verify --deep --strict "$CHECK_DIR/LiveTranslate.app"
