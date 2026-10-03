#!/usr/bin/env bash
# mise.toml に固定したOdinのバージョンを取り出す(CIとローカルで共通に使う)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sed -n 's/^odin *= *"\(.*\)"/\1/p' "$ROOT/mise.toml"
