// 最小限のPNGエンコーダー。deflateは固定ハフマン符号 + 簡易LZ77で圧縮する
#include "png_writer.h"
#include <string.h>
#include <vector>

namespace {

struct BitWriter {
	std::vector<uint8_t> out;
	uint32_t acc = 0;
	int nbits = 0;
	// 下位ビットから詰める(値そのものを書く)
	void put(uint32_t v, int n)
	{
		acc |= v << nbits;
		nbits += n;
		while(nbits >= 8) {
			out.push_back((uint8_t)acc);
			acc >>= 8;
			nbits -= 8;
		}
	}
	// ハフマン符号は上位ビットから書く
	void put_code(uint32_t code, int n)
	{
		uint32_t r = 0;
		for(int i = 0; i < n; i++) {
			r = (r << 1) | ((code >> i) & 1);
		}
		put(r, n);
	}
	void flush()
	{
		if(nbits > 0) {
			out.push_back((uint8_t)acc);
			acc = 0;
			nbits = 0;
		}
	}
};

void put_literal(BitWriter &bw, int v)
{
	if(v < 144) bw.put_code(0x30 + v, 8);
	else if(v < 256) bw.put_code(0x190 + (v - 144), 9);
	else if(v < 280) bw.put_code(v - 256, 7);
	else bw.put_code(0xC0 + (v - 280), 8);
}

const uint16_t len_base[29] = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
const uint8_t len_extra[29] = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
const uint16_t dist_base[30] = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
const uint8_t dist_extra[30] = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};

void put_match(BitWriter &bw, int len, int dist)
{
	int li = 28;
	while(len_base[li] > len) li--;
	put_literal(bw, 257 + li);
	if(len_extra[li]) bw.put(len - len_base[li], len_extra[li]);
	int di = 29;
	while(dist_base[di] > dist) di--;
	bw.put_code(di, 5);
	if(dist_extra[di]) bw.put(dist - dist_base[di], dist_extra[di]);
}

// zlibストリーム(固定ハフマン1ブロック)
std::vector<uint8_t> zlib_compress(const std::vector<uint8_t> &data, uint32_t &adler)
{
	BitWriter bw;
	bw.out.push_back(0x78);
	bw.out.push_back(0x01);
	bw.put(1, 1);	// 最終ブロック
	bw.put(1, 2);	// 固定ハフマン
	const int HASH = 1 << 15;
	std::vector<int> head(HASH, -1);
	const int n = (int)data.size();
	int i = 0;
	while(i < n) {
		int best_len = 0, best_dist = 0;
		if(i + 3 <= n) {
			uint32_t h = ((data[i] << 10) ^ (data[i + 1] << 5) ^ data[i + 2]) & (HASH - 1);
			int cand = head[h];
			head[h] = i;
			if(cand >= 0 && i - cand <= 32768) {
				int l = 0, maxl = n - i < 258 ? n - i : 258;
				while(l < maxl && data[cand + l] == data[i + l]) l++;
				if(l >= 3) {
					best_len = l;
					best_dist = i - cand;
				}
			}
		}
		if(best_len >= 3) {
			put_match(bw, best_len, best_dist);
			// 一致部分もハッシュに登録しておく
			for(int k = 1; k < best_len && i + k + 3 <= n; k++) {
				uint32_t h = ((data[i + k] << 10) ^ (data[i + k + 1] << 5) ^ data[i + k + 2]) & (HASH - 1);
				head[h] = i + k;
			}
			i += best_len;
		} else {
			put_literal(bw, data[i]);
			i++;
		}
	}
	put_literal(bw, 256);
	bw.flush();
	uint32_t a = 1, b = 0;
	for(int k = 0; k < n; k++) {
		a = (a + data[k]) % 65521;
		b = (b + a) % 65521;
	}
	adler = (b << 16) | a;
	for(int s = 24; s >= 0; s -= 8) bw.out.push_back((uint8_t)(adler >> s));
	return bw.out;
}

uint32_t crc32_update(uint32_t crc, const uint8_t *p, size_t n)
{
	static uint32_t table[256];
	static bool ready = false;
	if(!ready) {
		for(uint32_t i = 0; i < 256; i++) {
			uint32_t c = i;
			for(int k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
			table[i] = c;
		}
		ready = true;
	}
	crc = ~crc;
	for(size_t i = 0; i < n; i++) crc = table[(crc ^ p[i]) & 0xFF] ^ (crc >> 8);
	return ~crc;
}

void write_chunk(FILE *fp, const char *type, const uint8_t *data, uint32_t len)
{
	uint8_t be[4] = {(uint8_t)(len >> 24), (uint8_t)(len >> 16), (uint8_t)(len >> 8), (uint8_t)len};
	fwrite(be, 1, 4, fp);
	fwrite(type, 1, 4, fp);
	if(len) fwrite(data, 1, len, fp);
	uint32_t crc = crc32_update(0, (const uint8_t *)type, 4);
	crc = crc32_update(crc, data, len);
	uint8_t c[4] = {(uint8_t)(crc >> 24), (uint8_t)(crc >> 16), (uint8_t)(crc >> 8), (uint8_t)crc};
	fwrite(c, 1, 4, fp);
}

}

bool write_png_rgb(FILE *fp, int width, int height, const uint32_t *(*row)(void *, int), void *ctx)
{
	if(width <= 0 || height <= 0) {
		return false;
	}
	std::vector<uint8_t> raw;
	raw.reserve((size_t)height * (1 + width * 3));
	for(int y = 0; y < height; y++) {
		const uint32_t *line = row(ctx, y);
		raw.push_back(0);	// フィルターなし
		for(int x = 0; x < width; x++) {
			uint32_t p = line[x];
			raw.push_back((uint8_t)(p >> 16));
			raw.push_back((uint8_t)(p >> 8));
			raw.push_back((uint8_t)p);
		}
	}
	uint32_t adler;
	std::vector<uint8_t> z = zlib_compress(raw, adler);

	static const uint8_t sig[8] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
	fwrite(sig, 1, 8, fp);
	uint8_t ihdr[13] = {
		(uint8_t)(width >> 24), (uint8_t)(width >> 16), (uint8_t)(width >> 8), (uint8_t)width,
		(uint8_t)(height >> 24), (uint8_t)(height >> 16), (uint8_t)(height >> 8), (uint8_t)height,
		8, 2, 0, 0, 0	// 8bit / RGB / 標準の圧縮・フィルター / インターレースなし
	};
	write_chunk(fp, "IHDR", ihdr, 13);
	write_chunk(fp, "IDAT", z.data(), (uint32_t)z.size());
	write_chunk(fp, "IEND", NULL, 0);
	return true;
}
