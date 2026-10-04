#!/usr/bin/env bash
# Linux向け配布物(deb / rpm / AppImage)を作る
#   scripts/package-linux.sh [deb|rpm|appimage|all]
#
# 事前に scripts/build.sh release を実行しておくこと。
# 環境変数:
#   BUILD_DIR     ビルド出力 (既定: build)
#   DIST_DIR      配布物の出力先 (既定: dist)
#   BUILD_NUMBER  ビルド番号。1からの連番 (既定: 1)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-all}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
VERSION="$("$ROOT/scripts/version.sh")"
BIN="$BUILD_DIR/bin/BubiZ-2500"

case "$(uname -m)" in
  x86_64)        DEB_ARCH=amd64; RPM_ARCH=x86_64;  APPIMAGE_ARCH=x86_64 ;;
  aarch64|arm64) DEB_ARCH=arm64; RPM_ARCH=aarch64; APPIMAGE_ARCH=aarch64 ;;
  *) echo "未対応のCPUです: $(uname -m)" >&2; exit 1 ;;
esac

[ -x "$BIN" ] || { echo "実行ファイルがありません: $BIN (先にscripts/build.sh)" >&2; exit 1; }
mkdir -p "$DIST_DIR"
WORK="$BUILD_DIR/package"
rm -rf "$WORK"
mkdir -p "$WORK"

# 共通: インストール先のファイルツリー(/usr 以下)を組み立てる
stage_tree() {
  local root="$1"
  install -Dm755 "$BIN" "$root/usr/bin/BubiZ-2500"
  strip "$root/usr/bin/BubiZ-2500" || true
  install -Dm644 "$ROOT/packaging/linux/bubiz.desktop" "$root/usr/share/applications/bubiz.desktop"
  install -Dm644 "$ROOT/packaging/icons/bubiz.png" "$root/usr/share/icons/hicolor/256x256/apps/bubiz.png"
  install -Dm644 "$ROOT/LICENSE" "$root/usr/share/doc/bubiz-2500/LICENSE"
  mkdir -p "$root/usr/share/doc/bubiz-2500/csp-license"
  cp -r "$ROOT/core/csp/license/." "$root/usr/share/doc/bubiz-2500/csp-license/"
}

make_deb() {
  local root="$WORK/deb"
  stage_tree "$root"
  mkdir -p "$root/DEBIAN"
  local size
  size=$(du -sk "$root/usr" | cut -f1)
  cat > "$root/DEBIAN/control" <<CONTROL
Package: bubiz-2500
Version: ${VERSION}-${BUILD_NUMBER}
Section: otherosfs
Priority: optional
Architecture: ${DEB_ARCH}
Installed-Size: ${size}
Depends: libasound2 | libasound2t64, libgl1, libx11-6, libxi6, libxcursor1
Maintainer: BubiZ-2500 maintainers <noreply@example.invalid>
Description: SHARP MZ-2500 emulator
 MZ-2500エミュレーター。エミュレーションコアにCommon Source Code Projectの
 EmuZ-2500を利用しています。BIOS ROMは含まれません。
CONTROL
  dpkg-deb --root-owner-group --build "$root" "$DIST_DIR/BubiZ-2500-${VERSION}-linux-${DEB_ARCH}.deb"
}

make_rpm() {
  command -v rpmbuild >/dev/null || { echo "rpmbuildが必要です (apt install rpm)" >&2; exit 1; }
  local top="$WORK/rpm" root="$WORK/rpm-root"
  mkdir -p "$top"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
  stage_tree "$root"
  cat > "$top/SPECS/bubiz-2500.spec" <<SPEC
Name:           bubiz-2500
Version:        ${VERSION}
Release:        ${BUILD_NUMBER}
Summary:        SHARP MZ-2500 emulator
License:        GPLv2
AutoReqProv:    no
Requires:       alsa-lib, mesa-libGL, libX11, libXi, libXcursor
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

%description
MZ-2500エミュレーター。エミュレーションコアにCommon Source Code Projectの
EmuZ-2500を利用しています。BIOS ROMは含まれません。

%install
mkdir -p %{buildroot}
cp -a ${root}/usr %{buildroot}/usr

%files
/usr/bin/BubiZ-2500
/usr/share/applications/bubiz.desktop
/usr/share/icons/hicolor/256x256/apps/bubiz.png
/usr/share/doc/bubiz-2500
SPEC
  rpmbuild -bb --target "$RPM_ARCH" --define "_topdir $top" "$top/SPECS/bubiz-2500.spec"
  cp "$top"/RPMS/*/bubiz-2500-*.rpm "$DIST_DIR/BubiZ-2500-${VERSION}-linux-${RPM_ARCH}.rpm"
}

make_appimage() {
  local appdir="$WORK/BubiZ-2500.AppDir"
  stage_tree "$appdir"
  cp "$ROOT/packaging/linux/bubiz.desktop" "$appdir/bubiz.desktop"
  cp "$ROOT/packaging/icons/bubiz.png" "$appdir/bubiz.png"
  ln -s usr/bin/BubiZ-2500 "$appdir/AppRun"
  local tool="$WORK/appimagetool"
  if [ -z "${APPIMAGETOOL:-}" ]; then
    curl -fsSL -o "$tool" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage"
    chmod +x "$tool"
    APPIMAGETOOL="$tool"
  fi
  # FUSEが無い環境(CIなど)でも動くよう、展開して実行させる
  ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" "$appdir" \
    "$DIST_DIR/BubiZ-2500-${VERSION}-linux-${APPIMAGE_ARCH}.AppImage"
}

case "$TARGET" in
  deb) make_deb ;;
  rpm) make_rpm ;;
  appimage) make_appimage ;;
  all) make_deb; make_rpm; make_appimage ;;
  *) echo "使い方: $0 [deb|rpm|appimage|all]" >&2; exit 2 ;;
esac
echo "配布物:"; ls -l "$DIST_DIR"
