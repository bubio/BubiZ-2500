#!/bin/sh
# 試験用: 構文チェック
cd "$(dirname "$0")"
for f in "$@"; do
  g++ -std=gnu++17 -fsyntax-only -D_MZ2500 -DBUBIZ_HOST -include compat/bubiz_prelude.h -Icompat -w $f 2>&1 | grep -E "error" | head -5 | sed "s|^|$f: |"
done
