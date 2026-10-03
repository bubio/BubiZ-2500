#!/usr/bin/env bash
# 開発環境のセットアップ: Odin(mise経由)とsokol-odinを用意する
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOKOL_ODIN_REV="132fa9d26acf98cf6358a61e8baadf985196ab42"
DEST="$ROOT/.tools/sokol-odin"

# Odin: miseが使えるなら mise.toml に従ってインストールする
if command -v mise >/dev/null 2>&1; then
  (cd "$ROOT" && mise install)
else
  echo "miseが見つかりません。https://mise.jdx.dev を参照してインストールしてください。" >&2
fi

# cmake: すでに入っているものを使う(バージョンは変えない)。無いときだけmiseで導入する
if ! command -v cmake >/dev/null 2>&1; then
  if command -v mise >/dev/null 2>&1; then
    echo "cmakeが見つからないため、miseで導入します。"
    mise use --global cmake@latest
  else
    echo "cmakeが見つかりません。インストールしてください。" >&2
    exit 1
  fi
fi

# sokol-odin: 固定リビジョンを取得してCライブラリをビルドする
if [ ! -d "$DEST/.git" ]; then
  mkdir -p "$ROOT/.tools"
  git clone https://github.com/floooh/sokol-odin "$DEST"
fi
git -C "$DEST" fetch origin "$SOKOL_ODIN_REV" 2>/dev/null || git -C "$DEST" fetch origin
git -C "$DEST" checkout --quiet "$SOKOL_ODIN_REV"

cd "$DEST/sokol"
case "$(uname -s)" in
  Linux)  sh build_clibs_linux.sh ;;
  Darwin)
    # arm64の最低配備ターゲットは11.0。スクリプト既定の10.13から置き換える。
    # PATH上にApple純正でないclang(Homebrewなど)があるとFoundationのヘッダを解釈できないため、純正を明示する
    sed 's#MACOSX_DEPLOYMENT_TARGET=10.13 clang#MACOSX_DEPLOYMENT_TARGET=11.0 /usr/bin/clang#' build_clibs_macos.sh | sh
    ;;
  MINGW*|MSYS*|CYGWIN*) cmd //c build_clibs_windows.cmd ;;
  *) echo "このOSではscripts/setup.shは未対応です" >&2; exit 1 ;;
esac
echo "セットアップ完了"
