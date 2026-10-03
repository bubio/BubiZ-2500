#!/usr/bin/env bash
# Windows向け配布物(zip)を作る。事前に scripts/build.sh release を実行しておくこと。
# 環境変数: BUILD_DIR(既定 build) / DIST_DIR(既定 dist)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
VERSION="$("$ROOT/scripts/version.sh")"
BIN="$BUILD_DIR/bin/bubiz.exe"

[ -f "$BIN" ] || { echo "実行ファイルがありません: $BIN (先にscripts/build.sh)" >&2; exit 1; }
mkdir -p "$DIST_DIR"
WORK="$BUILD_DIR/package/BubiZ-2500-${VERSION}"
rm -rf "$BUILD_DIR/package"
mkdir -p "$WORK/licenses/csp-license"

cp "$BIN" "$WORK/bubiz.exe"
cp "$ROOT/LICENSE" "$WORK/licenses/LICENSE"
cp -R "$ROOT/core/csp/license/." "$WORK/licenses/csp-license/"

ZIP="$DIST_DIR/BubiZ-2500-${VERSION}-windows-x86_64.zip"
rm -f "$ZIP"
# zipの作成はPythonに統一する(Windows/Linux/macOSで同じ手順になる)
PY="$(command -v python3 || command -v python)"
"$PY" - "$BUILD_DIR/package" "BubiZ-2500-${VERSION}" "$ZIP" <<'PYEOF'
import os
import sys
import zipfile

base, top, out = sys.argv[1:4]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(os.path.join(base, top)):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, base))
PYEOF
echo "配布物:"; ls -l "$DIST_DIR"
