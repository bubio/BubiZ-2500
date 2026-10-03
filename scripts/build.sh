#!/usr/bin/env bash
# ビルドスクリプト: ローカルとCIで共通に使う
#   scripts/build.sh [release|debug]
#
# 環境変数:
#   ODIN       Odinコンパイラのパス (既定: PATH上のodin)
#   SOKOL_DIR  sokol-odinのsokolディレクトリ (既定: .tools/sokol-odin/sokol)
#   BUILD_DIR  出力先 (既定: build)
# Windowsでは、MSVCの環境(vcvars)を有効にしたシェルから実行すること。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-release}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
ODIN="${ODIN:-odin}"
SOKOL_DIR="${SOKOL_DIR:-$ROOT/.tools/sokol-odin/sokol}"

case "$(uname -s)" in
  Linux|Darwin) EXE=bubiz; WINDOWS=0 ;;
  MINGW*|MSYS*|CYGWIN*) EXE=bubiz.exe; WINDOWS=1 ;;
  *) echo "未対応のOSです" >&2; exit 1 ;;
esac

if ! command -v "$ODIN" >/dev/null 2>&1; then
  echo "odinが見つかりません。scripts/setup.shを実行するかODINを指定してください。" >&2
  exit 1
fi
if [ ! -d "$SOKOL_DIR" ]; then
  echo "sokol-odinが見つかりません: $SOKOL_DIR (scripts/setup.shを実行してください)" >&2
  exit 1
fi

# 1. エミュレーションコア (静的ライブラリ)
if [ "$MODE" = "debug" ]; then CMAKE_TYPE=Debug; else CMAKE_TYPE=Release; fi
CMAKE_ARGS=(-S "$ROOT/core" -B "$BUILD_DIR/core" -DCMAKE_BUILD_TYPE="$CMAKE_TYPE")
if [ "$WINDOWS" = 1 ]; then
  # 単一構成にするためNinja + MSVC(cl)を使う
  CMAKE_ARGS+=(-G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl)
fi
cmake "${CMAKE_ARGS[@]}"
cmake --build "$BUILD_DIR/core" --parallel

# 2. アプリケーション層 (Odin)
if [ "$MODE" = "debug" ]; then ODIN_FLAGS=(-debug); else ODIN_FLAGS=(-o:speed); fi
if [ "$WINDOWS" = 1 ]; then
  LINK_FLAGS="/LIBPATH:$(cygpath -w "$BUILD_DIR/core")"
else
  LINK_FLAGS="-L$BUILD_DIR/core"
fi
mkdir -p "$BUILD_DIR/bin"
"$ODIN" build "$ROOT/app" \
  -out:"$BUILD_DIR/bin/$EXE" \
  -collection:sokol="$SOKOL_DIR" \
  -extra-linker-flags:"$LINK_FLAGS" \
  "${ODIN_FLAGS[@]}"

echo "ビルド完了: ${BUILD_DIR#"$ROOT"/}/bin/$EXE"
