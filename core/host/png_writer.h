// 最小限のPNGエンコーダー(外部ライブラリ不要)
#pragma once
#include <stdint.h>
#include <stdio.h>

// 32bit(0xAARRGGBB)の行ポインタ配列からRGB 8bitのPNGを書き出す。成功時true
bool write_png_rgb(FILE *fp, int width, int height, const uint32_t *(*row)(void *, int), void *ctx);
