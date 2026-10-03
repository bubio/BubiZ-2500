#!/usr/bin/env python3
"""アイコン(256x256 PNG)を生成する。標準ライブラリのみで動く。
使い方: python3 make_icon.py bubiz.png
"""
import struct
import sys
import zlib

SIZE = 256


def inside_round_rect(x, y, r):
    # 角丸の正方形(余白8px)
    m = 8
    cx = min(max(x, m + r), SIZE - 1 - m - r)
    cy = min(max(y, m + r), SIZE - 1 - m - r)
    return m <= x < SIZE - m and m <= y < SIZE - m and (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def on_z(x, y):
    # 「Z」: 上辺・下辺・斜線
    t = 14
    top = 70 <= y < 70 + t and 66 <= x < 190
    bottom = 186 - t <= y < 186 and 66 <= x < 190
    # 斜線: 右上(190,84) → 左下(66,172)
    dx, dy = 190 - 66, 172 - 84
    d = abs(dy * (x - 66) - dx * (y - 84)) / (dx * dx + dy * dy) ** 0.5
    diag = d <= t / 2 + 2 and 66 <= x <= 190 and 84 <= y <= 172
    return top or bottom or diag


rows = []
for y in range(SIZE):
    row = bytearray([0])
    for x in range(SIZE):
        if not inside_round_rect(x, y, 44):
            row += bytes([0, 0, 0, 0])
        elif on_z(x, y):
            row += bytes([0xF2, 0xF4, 0xF8, 0xFF])
        else:
            row += bytes([0x1F, 0x3A, 0x5F, 0xFF])
    rows.append(bytes(row))


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
png += chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
