/*
	BubiZ-2500 ホスト層 (CSPのOSDインターフェースの実装)

	[ BubiZ host dependent ]
*/

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif
#include "osd.h"
#include "png_writer.h"
#include "vk.h"
#include "../csp/emu.h"
#include "../csp/fifo.h"
#include "../csp/fileio.h"

#ifndef KEY_KEEP_FRAMES
#define KEY_KEEP_FRAMES 3
#endif

OSD::OSD()
{
	lock_count = 0;
	vm = NULL;
	power_off_requested = false;
	console_open = false;
	console_closed = false;
	console_saved = NULL;
#ifdef USE_DEBUGGER
	waiting_hook = NULL;
#endif
	now_record_video = now_record_sound = false;
	rec_sound_fio = NULL;
	rec_sound_bytes = 0;
	sound_muted = false;
#ifdef USE_SCREEN_FILTER
	screen_skip_line = false;
#endif
#ifdef USE_AUTO_KEY
	now_auto_key = false;
#endif
}

void OSD::initialize(int rate, int samples)
{
	// 画面: VMの既定サイズで初期化（バッファは上から下の並び）
	host_window_width = WINDOW_WIDTH;
	host_window_height = WINDOW_HEIGHT;
	host_window_mode = true;
	vm_screen_width = SCREEN_WIDTH;
	vm_screen_height = SCREEN_HEIGHT;
	vm_window_width = WINDOW_WIDTH;
	vm_window_height = WINDOW_HEIGHT;
	vm_window_width_aspect = WINDOW_WIDTH_ASPECT;
	vm_window_height_aspect = WINDOW_HEIGHT_ASPECT;
	screen_changed = false;
	initialize_screen_buffer(&vm_screen_buffer, vm_screen_width, vm_screen_height);

	// サウンド: VMが1回に生成するsamples分を2チャンク持てるリング
	sound_rate = rate;
	sound_samples = samples;
	sound_ring.assign((size_t)samples * 2 * 2, 0);
	sound_ring_r = sound_ring_w = sound_ring_fill = 0;
	sound_file_path[0] = _T('\0');

	initialize_input();
}

void OSD::release()
{
	stop_record_sound();
}

void OSD::power_off()
{
	power_off_requested = true;
}

void OSD::suspend()
{
	mute_sound();
}

void OSD::restore()
{
}

void OSD::lock_vm()
{
	vm_mutex.lock();
	lock_count++;
}

void OSD::unlock_vm()
{
	if(lock_count > 0) {
		lock_count--;
		vm_mutex.unlock();
	}
}

void OSD::force_unlock_vm()
{
	while(lock_count > 0) {
		unlock_vm();
	}
}

void OSD::sleep(uint32_t ms)
{
#ifdef _WIN32
	Sleep(ms);
#else
	struct timespec ts;
	ts.tv_sec = ms / 1000;
	ts.tv_nsec = (long)(ms % 1000) * 1000000L;
	nanosleep(&ts, NULL);
#endif
}

// ----------------------------------------------------------------------------
// input
// ----------------------------------------------------------------------------

void OSD::initialize_input()
{
	memset(key_status, 0, sizeof(key_status));
#ifdef USE_JOYSTICK
	memset(joy_status, 0, sizeof(joy_status));
#endif
#ifdef USE_MOUSE
	memset(mouse_status, 0, sizeof(mouse_status));
	mouse_enabled = false;
#endif
	key_shift_pressed = key_shift_released = false;
	lost_focus = false;
}

void OSD::update_input()
{
	// キーを離したあと一定フレーム保持するキーの処理
	if(lost_focus) {
		for(int i = 0; i < 256; i++) {
			if(key_status[i] & 0x80) {
				key_status[i] &= 0x7f;
				if(!key_status[i]) {
					vm->key_up(i);
				}
			}
		}
		lost_focus = false;
	}
	for(int i = 0; i < 256; i++) {
		if(key_status[i] & 0x7f) {
			key_status[i] = (key_status[i] & 0x80) | ((key_status[i] & 0x7f) - 1);
			if(key_status[i] == 0) {
				vm->key_up(i);
			}
		}
	}
}

void OSD::key_down(int code, bool extended, bool repeat)
{
#ifdef USE_AUTO_KEY
	if(now_auto_key || config.romaji_to_kana) {
		return;
	}
#endif
	key_down_native(code, repeat);
}

void OSD::key_up(int code, bool extended)
{
#ifdef USE_AUTO_KEY
	if(now_auto_key || config.romaji_to_kana) {
		return;
	}
#endif
	key_up_native(code);
}

void OSD::key_down_native(int code, bool repeat)
{
	bool keep_frames = false;

	if(code == 0xf0) {
		code = VK_CAPITAL;
		keep_frames = true;
	} else if(code == 0xf1 || code == 0xf2) {
		code = VK_KANA;
		keep_frames = true;
	} else if(code == 0xf3 || code == 0xf4) {
		code = VK_KANJI;
		keep_frames = true;
	}
	code &= 0xff;
	if(key_status[code] == 0 || keep_frames) {
		repeat = false;
	}
	key_status[code] = keep_frames ? KEY_KEEP_FRAMES : 0x80;

	uint8_t prev_shift = key_status[VK_SHIFT];
	uint8_t prev_control = key_status[VK_CONTROL];
	uint8_t prev_menu = key_status[VK_MENU];

	key_status[VK_SHIFT] = key_status[VK_LSHIFT] | key_status[VK_RSHIFT];
	key_status[VK_CONTROL] = key_status[VK_LCONTROL] | key_status[VK_RCONTROL];
	key_status[VK_MENU] = key_status[VK_LMENU] | key_status[VK_RMENU];

	if(code == VK_LSHIFT || code == VK_RSHIFT) {
		if(prev_shift == 0 && key_status[VK_SHIFT] != 0) {
			vm->key_down(VK_SHIFT, repeat);
		}
	} else if(code == VK_LCONTROL || code == VK_RCONTROL) {
		if(prev_control == 0 && key_status[VK_CONTROL] != 0) {
			vm->key_down(VK_CONTROL, repeat);
		}
	} else if(code == VK_LMENU || code == VK_RMENU) {
		if(prev_menu == 0 && key_status[VK_MENU] != 0) {
			vm->key_down(VK_MENU, repeat);
		}
	}
	vm->key_down(code, repeat);
}

void OSD::key_up_native(int code)
{
	code &= 0xff;
	if(key_status[code] == 0) {
		return;
	}
	if((key_status[code] &= 0x7f) != 0) {
		return;
	}
	vm->key_up(code);

	uint8_t prev_shift = key_status[VK_SHIFT];
	uint8_t prev_control = key_status[VK_CONTROL];
	uint8_t prev_menu = key_status[VK_MENU];

	key_status[VK_SHIFT] = key_status[VK_LSHIFT] | key_status[VK_RSHIFT];
	key_status[VK_CONTROL] = key_status[VK_LCONTROL] | key_status[VK_RCONTROL];
	key_status[VK_MENU] = key_status[VK_LMENU] | key_status[VK_RMENU];

	if(code == VK_LSHIFT || code == VK_RSHIFT) {
		if(prev_shift != 0 && key_status[VK_SHIFT] == 0) {
			vm->key_up(VK_SHIFT);
		}
	} else if(code == VK_LCONTROL || code == VK_RCONTROL) {
		if(prev_control != 0 && key_status[VK_CONTROL] == 0) {
			vm->key_up(VK_CONTROL);
		}
	} else if(code == VK_LMENU || code == VK_RMENU) {
		if(prev_menu != 0 && key_status[VK_MENU] == 0) {
			vm->key_up(VK_MENU);
		}
	}
}

#ifdef USE_MOUSE
void OSD::enable_mouse()
{
	mouse_enabled = true;
}

void OSD::disable_mouse()
{
	mouse_enabled = false;
	memset(mouse_status, 0, sizeof(mouse_status));
}

void OSD::toggle_mouse()
{
	if(mouse_enabled) {
		disable_mouse();
	} else {
		enable_mouse();
	}
}

void OSD::set_mouse_state(int dx, int dy, int buttons)
{
	mouse_status[0] = dx;
	mouse_status[1] = dy;
	mouse_status[2] = buttons;
}
#endif

// ----------------------------------------------------------------------------
// screen
// ----------------------------------------------------------------------------

void OSD::initialize_screen_buffer(bitmap_t *buffer, int width, int height)
{
	buffer->width = width;
	buffer->height = height;
	buffer->pixels.assign((size_t)width * height, 0);
	screen_changed = true;
}

double OSD::get_window_mode_power(int mode)
{
	if(mode + 1 <= 4) {
		return 1.0 + 0.5 * mode;
	}
	return 1.0;
}

int OSD::get_window_mode_width(int mode)
{
	return (int)(vm_window_width_aspect * get_window_mode_power(mode));
}

int OSD::get_window_mode_height(int mode)
{
	return (int)(vm_window_height_aspect * get_window_mode_power(mode));
}

void OSD::set_host_window_size(int window_width, int window_height, bool window_mode)
{
	if(window_width != -1) {
		host_window_width = window_width;
	}
	if(window_height != -1) {
		host_window_height = window_height;
	}
	host_window_mode = window_mode;
}

void OSD::set_vm_screen_size(int screen_width, int screen_height, int window_width, int window_height, int window_width_aspect, int window_height_aspect)
{
	if(vm_screen_width != screen_width || vm_screen_height != screen_height) {
		if(window_width == -1) {
			window_width = screen_width;
		}
		if(window_height == -1) {
			window_height = screen_height;
		}
		if(window_width_aspect == -1) {
			window_width_aspect = window_width;
		}
		if(window_height_aspect == -1) {
			window_height_aspect = window_height;
		}
		vm_screen_width = screen_width;
		vm_screen_height = screen_height;
		vm_window_width = window_width;
		vm_window_height = window_height;
		vm_window_width_aspect = window_width_aspect;
		vm_window_height_aspect = window_height_aspect;
	}
	if(vm_screen_buffer.width != vm_screen_width || vm_screen_buffer.height != vm_screen_height) {
		initialize_screen_buffer(&vm_screen_buffer, vm_screen_width, vm_screen_height);
	}
}

void OSD::set_vm_screen_lines(int lines)
{
	// 現在は未使用（画面サイズ変更はset_vm_screen_sizeで行う）
}

scrntype_t* OSD::get_vm_screen_buffer(int y)
{
	return vm_screen_buffer.get_buffer(y);
}

int OSD::draw_screen()
{
	if(vm_screen_buffer.width != vm_screen_width || vm_screen_buffer.height != vm_screen_height) {
		initialize_screen_buffer(&vm_screen_buffer, vm_screen_width, vm_screen_height);
	}
#ifdef USE_SCREEN_FILTER
	screen_skip_line = false;
#endif
	vm->draw_screen();
	return 1;
}

std::string g_snap_dir;
std::string g_sound_dir;

void OSD::capture_screen()
{
	// 日時付きファイル名でPNG保存
	time_t t = time(NULL);
	struct tm *lt = localtime(&t);
	_TCHAR name[_MAX_PATH];
	my_stprintf_s(name, _MAX_PATH, _T("%04d-%02d-%02d_%02d-%02d-%02d.png"), lt->tm_year + 1900, lt->tm_mon + 1, lt->tm_mday, lt->tm_hour, lt->tm_min, lt->tm_sec);
	if(!g_snap_dir.empty()) {
		std::string path = g_snap_dir + (char)'/' + name;
		write_bitmap_to_file(&vm_screen_buffer, path.c_str());
	} else {
		write_bitmap_to_file(&vm_screen_buffer, create_local_path(name));
	}
}

static const uint32_t *bitmap_row(void *ctx, int y)
{
	return (const uint32_t *)((bitmap_t *)ctx)->get_buffer(y);
}

struct thumb_rows_t {
	std::vector<uint32_t> px;
	int width;
};

static const uint32_t *thumb_row(void *ctx, int y)
{
	thumb_rows_t *t = (thumb_rows_t *)ctx;
	return &t->px[(size_t)y * t->width];
}

bool OSD::write_thumbnail(const _TCHAR *file_path, int tw, int th)
{
	bitmap_t *src = &vm_screen_buffer;
	if(!src->initialized() || src->width <= 0 || src->height <= 0 || tw <= 0 || th <= 0) {
		return false;
	}
	const int sw = src->width, sh = src->height;
	thumb_rows_t t;
	t.width = tw;
	t.px.resize((size_t)tw * th);
	// 範囲の平均で縮小する
	for(int y = 0; y < th; y++) {
		int y0 = y * sh / th, y1 = (y + 1) * sh / th;
		if(y1 <= y0) y1 = y0 + 1;
		for(int x = 0; x < tw; x++) {
			int x0 = x * sw / tw, x1 = (x + 1) * sw / tw;
			if(x1 <= x0) x1 = x0 + 1;
			uint32_t r = 0, g = 0, b = 0, n = 0;
			for(int yy = y0; yy < y1 && yy < sh; yy++) {
				const uint32_t *line = (const uint32_t *)src->get_buffer(yy);
				for(int xx = x0; xx < x1 && xx < sw; xx++) {
					uint32_t p = line[xx];
					r += (p >> 16) & 0xFF;
					g += (p >> 8) & 0xFF;
					b += p & 0xFF;
					n++;
				}
			}
			if(n == 0) n = 1;
			t.px[(size_t)y * tw + x] = ((r / n) << 16) | ((g / n) << 8) | (b / n);
		}
	}
	FILE *fp = fopen(file_path, "wb");
	if(fp == NULL) {
		return false;
	}
	bool ok = write_png_rgb(fp, tw, th, thumb_row, &t);
	fclose(fp);
	return ok;
}

void OSD::write_bitmap_to_file(bitmap_t *bitmap, const _TCHAR *file_path)
{
	// PNGで保存する
	if(!bitmap->initialized()) {
		return;
	}
	FILE *fp = fopen(file_path, "wb");
	if(fp == NULL) {
		return;
	}
	write_png_rgb(fp, bitmap->width, bitmap->height, bitmap_row, bitmap);
	fclose(fp);
}

// ----------------------------------------------------------------------------
// sound
// ----------------------------------------------------------------------------

void OSD::update_sound(int* extra_frames)
{
	*extra_frames = 0;
	sound_muted = false;

	size_t chunk = (size_t)sound_samples;
	size_t capacity = sound_ring.size() / 2;
	bool need_update;
	{
		std::lock_guard<std::mutex> lock(sound_mutex);
		need_update = (capacity - sound_ring_fill >= chunk);
	}
	if(!need_update) {
		return;
	}

	// VMにサウンドチャンクを生成させる（不足分はVMが追加フレームを駆動する）
	uint16_t* sound_buffer = vm->create_sound(extra_frames);
	if(sound_buffer == NULL) {
		return;
	}
	if(now_record_sound && rec_sound_fio != NULL) {
		int length = (int)(chunk * sizeof(uint16_t) * 2);
		rec_sound_fio->Fwrite(sound_buffer, length, 1);
		rec_sound_bytes += length;
	}
	std::lock_guard<std::mutex> lock(sound_mutex);
	const int16_t* src = (const int16_t*)sound_buffer;
	for(size_t i = 0; i < chunk; i++) {
		sound_ring[sound_ring_w * 2    ] = src[i * 2    ];
		sound_ring[sound_ring_w * 2 + 1] = src[i * 2 + 1];
		sound_ring_w = (sound_ring_w + 1) % capacity;
	}
	sound_ring_fill += chunk;
}

size_t OSD::pull_sound(int16_t* dest, size_t frames)
{
	std::lock_guard<std::mutex> lock(sound_mutex);
	size_t capacity = sound_ring.size() / 2;
	size_t n = (frames < sound_ring_fill) ? frames : sound_ring_fill;
	for(size_t i = 0; i < n; i++) {
		dest[i * 2    ] = sound_ring[sound_ring_r * 2    ];
		dest[i * 2 + 1] = sound_ring[sound_ring_r * 2 + 1];
		sound_ring_r = (sound_ring_r + 1) % capacity;
	}
	sound_ring_fill -= n;
	for(size_t i = n; i < frames; i++) {
		dest[i * 2] = dest[i * 2 + 1] = 0;
	}
	return n;
}

void OSD::mute_sound()
{
	sound_muted = true;
}

void OSD::stop_sound()
{
	std::lock_guard<std::mutex> lock(sound_mutex);
	sound_ring_r = sound_ring_w = sound_ring_fill = 0;
}

void OSD::start_record_sound(const _TCHAR* path)
{
	if(!now_record_sound) {
		_TCHAR full_path[_MAX_PATH];
		if(path != NULL && path[0] != _T('\0')) {
			my_tcscpy_s(sound_file_path, _MAX_PATH, path);
			my_tcscpy_s(full_path, _MAX_PATH, path);
		} else {
			time_t t = time(NULL);
			struct tm *lt = localtime(&t);
			my_stprintf_s(sound_file_path, _MAX_PATH, _T("%04d-%02d-%02d_%02d-%02d-%02d.wav"), lt->tm_year + 1900, lt->tm_mon + 1, lt->tm_mday, lt->tm_hour, lt->tm_min, lt->tm_sec);
			if(!g_sound_dir.empty()) {
				std::string p = g_sound_dir + (char)'/' + sound_file_path;
				my_tcscpy_s(full_path, _MAX_PATH, p.c_str());
			} else {
				my_tcscpy_s(full_path, _MAX_PATH, create_local_path(sound_file_path));
			}
		}
		rec_sound_fio = new FILEIO();
		if(rec_sound_fio->Fopen(full_path, FILEIO_WRITE_BINARY)) {
			// ヘッダ（サイズは終了時に書き換える）
			uint8_t hdr[44] = {0};
			memcpy(hdr, "RIFF", 4);
			memcpy(hdr + 8, "WAVEfmt ", 8);
			uint32_t v32 = 16; memcpy(hdr + 16, &v32, 4);
			uint16_t v16 = 1; memcpy(hdr + 20, &v16, 2);
			v16 = 2; memcpy(hdr + 22, &v16, 2);
			v32 = sound_rate; memcpy(hdr + 24, &v32, 4);
			v32 = sound_rate * 4; memcpy(hdr + 28, &v32, 4);
			v16 = 4; memcpy(hdr + 32, &v16, 2);
			v16 = 16; memcpy(hdr + 34, &v16, 2);
			memcpy(hdr + 36, "data", 4);
			rec_sound_fio->Fwrite(hdr, 44, 1);
			rec_sound_bytes = 0;
			now_record_sound = true;
		} else {
			delete rec_sound_fio;
			rec_sound_fio = NULL;
		}
	}
}

void OSD::stop_record_sound()
{
	if(now_record_sound && rec_sound_fio != NULL) {
		uint32_t riff = rec_sound_bytes + 36, data = rec_sound_bytes;
		rec_sound_fio->Fseek(4, FILEIO_SEEK_SET);
		rec_sound_fio->Fwrite(&riff, 4, 1);
		rec_sound_fio->Fseek(40, FILEIO_SEEK_SET);
		rec_sound_fio->Fwrite(&data, 4, 1);
		rec_sound_fio->Fclose();
		delete rec_sound_fio;
		rec_sound_fio = NULL;
	}
	now_record_sound = false;
}

void OSD::restart_record_sound()
{
	bool tmp = now_record_sound;
	stop_record_sound();
	if(tmp) {
		start_record_sound();
	}
}

// ----------------------------------------------------------------------------
// printer（ソフトウェア描画）
// ----------------------------------------------------------------------------

#ifdef USE_PRINTER
void OSD::create_bitmap(bitmap_t *bitmap, int width, int height)
{
	bitmap->width = width;
	bitmap->height = height;
	bitmap->pixels.assign((size_t)width * height, RGB_COLOR(255, 255, 255));
}

void OSD::release_bitmap(bitmap_t *bitmap)
{
	bitmap->pixels.clear();
	bitmap->pixels.shrink_to_fit();
	bitmap->width = bitmap->height = 0;
}

void OSD::create_font(font_t *font, const _TCHAR *family, int width, int height, int rotate, bool bold, bool italic)
{
	my_tcscpy_s(font->family, 64, family);
	font->width = width;
	font->height = height;
	font->rotate = rotate;
	font->bold = bold;
	font->italic = italic;
	font->valid = true;
}

void OSD::release_font(font_t *font)
{
	font->valid = false;
}

void OSD::create_pen(pen_t *pen, int width, uint8_t r, uint8_t g, uint8_t b)
{
	pen->width = width;
	pen->r = r;
	pen->g = g;
	pen->b = b;
	pen->valid = true;
}

void OSD::release_pen(pen_t *pen)
{
	pen->valid = false;
}

void OSD::clear_bitmap(bitmap_t *bitmap, uint8_t r, uint8_t g, uint8_t b)
{
	std::fill(bitmap->pixels.begin(), bitmap->pixels.end(), RGB_COLOR(r, g, b));
}

int OSD::get_text_width(bitmap_t *bitmap, font_t *font, const char *text)
{
	// 簡易: 半角=幅の1/2想定で文字数から概算
	return (int)strlen(text) * font->width / 2;
}

void OSD::draw_text_to_bitmap(bitmap_t *bitmap, font_t *font, int x, int y, const char *text, uint8_t r, uint8_t g, uint8_t b)
{
	// フォント描画は未実装（ビットマッププリンタ出力のみ対応）
}

void OSD::draw_line_to_bitmap(bitmap_t *bitmap, pen_t *pen, int sx, int sy, int ex, int ey)
{
	int dx = abs(ex - sx), dy = -abs(ey - sy);
	int stepx = (sx < ex) ? 1 : -1, stepy = (sy < ey) ? 1 : -1;
	int err = dx + dy;
	for(;;) {
		draw_rectangle_to_bitmap(bitmap, sx, sy, pen->width, pen->width, pen->r, pen->g, pen->b);
		if(sx == ex && sy == ey) {
			break;
		}
		int e2 = 2 * err;
		if(e2 >= dy) { err += dy; sx += stepx; }
		if(e2 <= dx) { err += dx; sy += stepy; }
	}
}

void OSD::draw_rectangle_to_bitmap(bitmap_t *bitmap, int x, int y, int width, int height, uint8_t r, uint8_t g, uint8_t b)
{
	int x0 = (x < 0) ? 0 : x, y0 = (y < 0) ? 0 : y;
	int x1 = (x + width > bitmap->width) ? bitmap->width : x + width;
	int y1 = (y + height > bitmap->height) ? bitmap->height : y + height;
	scrntype_t c = RGB_COLOR(r, g, b);
	for(int yy = y0; yy < y1; yy++) {
		scrntype_t *p = bitmap->get_buffer(yy);
		for(int xx = x0; xx < x1; xx++) {
			p[xx] = c;
		}
	}
}

void OSD::draw_point_to_bitmap(bitmap_t *bitmap, int x, int y, uint8_t r, uint8_t g, uint8_t b)
{
	if(0 <= x && x < bitmap->width && 0 <= y && y < bitmap->height) {
		bitmap->get_buffer(y)[x] = RGB_COLOR(r, g, b);
	}
}

void OSD::stretch_bitmap(bitmap_t *dest, int dest_x, int dest_y, int dest_width, int dest_height, bitmap_t *source, int source_x, int source_y, int source_width, int source_height)
{
	// 最近傍で拡大縮小
	if(dest_width <= 0 || dest_height <= 0 || source_width <= 0 || source_height <= 0) {
		return;
	}
	for(int dy = 0; dy < dest_height; dy++) {
		int ty = dest_y + dy;
		if(ty < 0 || ty >= dest->height) {
			continue;
		}
		int sy = source_y + dy * source_height / dest_height;
		if(sy < 0 || sy >= source->height) {
			continue;
		}
		scrntype_t *d = dest->get_buffer(ty);
		scrntype_t *s = source->get_buffer(sy);
		for(int dx = 0; dx < dest_width; dx++) {
			int tx = dest_x + dx;
			int sx = source_x + dx * source_width / dest_width;
			if(tx < 0 || tx >= dest->width || sx < 0 || sx >= source->width) {
				continue;
			}
			d[tx] = s[sx];
		}
	}
}
#endif
