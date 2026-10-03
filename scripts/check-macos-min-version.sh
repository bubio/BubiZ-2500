#!/usr/bin/env bash
# macOSの実行ファイルが、最低対応バージョン(14.0)で作られているかを確認する
#   scripts/check-macos-min-version.sh [実行ファイル]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-$ROOT/build/bin/bubiz}"
EXPECTED="14.0"

# LC_BUILD_VERSION の minos(最低対応OS) を取り出す
MINOS="$(otool -l "$BIN" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
echo "minos: ${MINOS:-不明} (期待値 ${EXPECTED})"
if [ "$MINOS" != "$EXPECTED" ]; then
  echo "最低対応OSが ${EXPECTED} ではありません: ${MINOS:-不明}" >&2
  exit 1
fi
