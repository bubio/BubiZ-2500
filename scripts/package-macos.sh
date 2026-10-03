#!/usr/bin/env bash
# macOS向け配布物(dmg)を作る。事前に scripts/build.sh release を実行しておくこと。
# 環境変数: BUILD_DIR(既定 build) / DIST_DIR(既定 dist) / BUILD_NUMBER(既定 1)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
VERSION="$("$ROOT/scripts/version.sh")"
BIN="$BUILD_DIR/bin/bubiz"
ARCH="$(uname -m)"   # arm64 / x86_64

[ -x "$BIN" ] || { echo "実行ファイルがありません: $BIN (先にscripts/build.sh)" >&2; exit 1; }
mkdir -p "$DIST_DIR"
WORK="$BUILD_DIR/package"
rm -rf "$WORK"
APP="$WORK/stage/BubiZ-2500.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/bubiz"
strip -x "$APP/Contents/MacOS/bubiz" || true
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD_NUMBER@/$BUILD_NUMBER/" \
  "$ROOT/packaging/macos/Info.plist.in" > "$APP/Contents/Info.plist"

# アイコン: PNGからicnsを作る
ICONSET="$WORK/bubiz.iconset"
mkdir -p "$ICONSET"
for s in 16 32 64 128 256; do
  sips -z $s $s "$ROOT/packaging/icons/bubiz.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
done
cp "$ICONSET/icon_32x32.png" "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png" "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
rm -f "$ICONSET/icon_64x64.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/bubiz.icns"

mkdir -p "$APP/Contents/Resources/licenses"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/licenses/LICENSE"
cp -R "$ROOT/core/csp/license/." "$APP/Contents/Resources/licenses/csp-license/"

# 未署名のままだとApple Siliconで起動できないため、アドホック署名を付ける
codesign --force --deep --sign - "$APP"

ln -s /Applications "$WORK/stage/Applications"
DMG="$DIST_DIR/BubiZ-2500-${VERSION}-macos-${ARCH}.dmg"
rm -f "$DMG"
hdiutil create -volname "BubiZ-2500 ${VERSION}" -srcfolder "$WORK/stage" -ov -format UDZO "$DMG"
echo "配布物:"; ls -l "$DIST_DIR"
