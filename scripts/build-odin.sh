#!/usr/bin/env bash
# mise.tomlで固定したバージョンのOdinを、ソースから .tools/odin にビルドする。
#
# 配布されているOdinのバイナリが、お使いのOSで動かないときに使う
# (例: macOS 14では、配布バイナリが macOS 15 以上を要求して起動しない)。
# ビルドしたOdinは scripts/build.sh が自動的に使う。
#
# 前提: LLVM 17以上
#   macOS: brew install llvm@18
#   Linux: apt.llvm.org などから llvm-18-dev を入れる(LLVM_CONFIG=llvm-config-18 を指定してもよい)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$("$ROOT/scripts/odin-version.sh")"
DEST="$ROOT/.tools/odin"

if [ ! -d "$DEST/.git" ]; then
  mkdir -p "$ROOT/.tools"
  git clone --depth 1 --branch "$VERSION" https://github.com/odin-lang/Odin "$DEST"
fi

cd "$DEST"
if [ "$(uname -s)" = "Darwin" ]; then
  # 作ったOdinが古いmacOSでも動くよう、配備ターゲットを14.0にする
  export MACOSX_DEPLOYMENT_TARGET=14.0
fi
./build_odin.sh release
echo "ビルド完了: $("$DEST/odin" version)  (${DEST#"$ROOT"/}/odin)"
