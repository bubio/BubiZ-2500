#!/usr/bin/env bash
# 配布物の基本名 BubiZ-2500-{version}-{platform}-{arch} を表示する(実行環境のOS/CPUから決める)
#   platform: linux / macos / windows
#   arch    : 各プラットフォームの慣例に従う
#             linux=amd64,arm64 / macos=intel,apple-silicon / windows=x64,arm64
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$("$ROOT/scripts/version.sh")"
M="$(uname -m)"
case "$(uname -s)" in
  Linux)
    PLATFORM=linux
    case "$M" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) ARCH="$M" ;; esac ;;
  Darwin)
    PLATFORM=macos
    case "$M" in x86_64) ARCH=intel ;; arm64) ARCH=apple-silicon ;; *) ARCH="$M" ;; esac ;;
  MINGW*|MSYS*|CYGWIN*)
    PLATFORM=windows
    case "$M" in x86_64|AMD64) ARCH=x64 ;; aarch64|arm64) ARCH=arm64 ;; *) ARCH="$M" ;; esac ;;
  *) echo "未対応のOSです" >&2; exit 1 ;;
esac
echo "BubiZ-2500-${VERSION}-${PLATFORM}-${ARCH}"
