#!/usr/bin/env bash
# app/version.odin からバージョン(セマンティックバージョニング)を取り出す
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sed -n 's/^VERSION :: "\(.*\)"/\1/p' "$ROOT/app/version.odin"
