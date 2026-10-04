/*
	BubiZ-2500 コアC API 実装

	スレッドの扱い:
	  エミュレーションを進める bubiz_run() は1つのスレッドから呼ぶ(ウィンドウ版では専用スレッド)。
	  入力・メディア操作・リセットなどVMの状態を変える呼び出しは、どのスレッドから呼んでもよい。
	  それらは一旦キューに積まれ、次の bubiz_run() の冒頭でエミュレーションスレッドが実行する。
	  これにより、デバッガーでCPUが止まっている間も、呼び出し側(UIスレッド)がブロックされない。
	  画面は bubiz_run() の末尾で最新のフレームとして公開され、bubiz_copy_frame() で取り出す。
*/

#include <stdio.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <vector>
#include "bubiz_core.h"
#include "csp/emu.h"
#include "csp/config.h"
#include "csp/common.h"

extern std::string cpp_homedir;

static EMU *g_emu = NULL;
static bool g_config_loaded = false;

// ---------------------------------------------------------------------------
// コマンドキュー
// ---------------------------------------------------------------------------

static std::mutex g_cmd_mutex;
static std::deque<std::function<void()> > g_cmds;

static void post(std::function<void()> f)
{
	std::lock_guard<std::mutex> lock(g_cmd_mutex);
	g_cmds.push_back(f);
}

static void drain_commands()
{
	std::deque<std::function<void()> > cmds;
	{
		std::lock_guard<std::mutex> lock(g_cmd_mutex);
		cmds.swap(g_cmds);
	}
	for(std::deque<std::function<void()> >::iterator it = cmds.begin(); it != cmds.end(); ++it) {
		(*it)();
	}
}

// ---------------------------------------------------------------------------
// 最新フレームの公開
// ---------------------------------------------------------------------------

static std::mutex g_frame_mutex;
static std::vector<uint8_t> g_frame_rgba;
static int g_frame_w = 0, g_frame_h = 0;
static uint64_t g_frame_seq = 0;
static bool g_frame_skip_line = false;

// OSDの画面バッファをRGBA8へ変換して公開する
static void publish_frame()
{
	if(g_emu == NULL) {
		return;
	}
	const bitmap_t *b = g_emu->get_osd()->get_draw_buffer();
	if(b == NULL || !b->initialized()) {
		return;
	}
	std::lock_guard<std::mutex> lock(g_frame_mutex);
	g_frame_w = b->width;
	g_frame_h = b->height;
#ifdef USE_SCREEN_FILTER
	g_frame_skip_line = g_emu->get_osd()->screen_skip_line;
#endif
	size_t n = (size_t)b->width * b->height;
	g_frame_rgba.resize(n * 4);
	uint8_t *out = g_frame_rgba.data();
	for(size_t i = 0; i < n; i++) {
		scrntype_t c = b->pixels[i];
		out[i * 4    ] = R_OF_COLOR(c);
		out[i * 4 + 1] = G_OF_COLOR(c);
		out[i * 4 + 2] = B_OF_COLOR(c);
		out[i * 4 + 3] = 0xff;
	}
	g_frame_seq++;
}

// ---------------------------------------------------------------------------
// 生成・設定
// ---------------------------------------------------------------------------

void bubiz_set_data_dir(const char *dir)
{
	std::string d = dir;
	if(!d.empty() && d.back() != '/' && d.back() != '\\') {
		d += '/';
	}
	cpp_homedir = d;
}

void bubiz_set_snap_dir(const char *dir)
{
	g_snap_dir = dir ? dir : "";
	while(!g_snap_dir.empty() && (g_snap_dir.back() == '/' || g_snap_dir.back() == '\\')) {
		g_snap_dir.pop_back();
	}
}

void bubiz_load_config(const char *name)
{
	// 設定ファイルが無ければ既定値で初期化される
	load_config(create_local_path(_T("%s"), name));
	g_config_loaded = true;
}

void bubiz_save_config(const char *name)
{
	save_config(create_local_path(_T("%s"), name));
}

bool bubiz_set_config(const char *key, int value)
{
	if(!g_config_loaded) {
		bubiz_load_config(CONFIG_NAME ".ini");
	}
	std::string k = key;
	if(k == "boot_mode") config.boot_mode = value;
	else if(k == "monitor_type") config.monitor_type = value;
	else if(k == "option_switch") config.option_switch = value;
	else if(k == "sound_frequency") config.sound_frequency = value;
	else if(k == "sound_latency") config.sound_latency = value;
	else if(k == "scan_line") config.scan_line = (value != 0);
	else if(k == "printer_type") config.printer_type = value;
	else return false;
	return true;
}

static void waiting_hook()
{
	// CPUがデバッガーで止まっている間も、ウィンドウへ最新の画面を渡し続ける
	publish_frame();
}

bool bubiz_create(void)
{
	if(g_emu != NULL) {
		return true;
	}
	if(!g_config_loaded) {
		bubiz_load_config(CONFIG_NAME ".ini");
	}
	g_emu = new EMU();
#ifdef USE_DEBUGGER
	g_emu->get_osd()->waiting_hook = waiting_hook;
#endif
	return true;
}

void bubiz_destroy(void)
{
	if(g_emu == NULL) {
		return;
	}
#ifdef USE_DEBUGGER
	// デバッガーのスレッドを先に終わらせる(CPUの待機も解除される)
	g_emu->close_debugger();
#endif
	delete g_emu;
	g_emu = NULL;
	std::lock_guard<std::mutex> lock(g_cmd_mutex);
	g_cmds.clear();
}

// ---------------------------------------------------------------------------
// エミュレーション駆動・画面
// ---------------------------------------------------------------------------

int bubiz_run(void)
{
	if(g_emu == NULL) {
		return 0;
	}
	drain_commands();
#ifdef USE_DEBUGGER
	// Qコマンドなどでデバッガーのスレッドが終わっていたら後始末する
	if(g_emu->now_debugging && !g_emu->debugger_thread_param.running) {
		g_emu->close_debugger();
	}
#endif
	int frames = g_emu->run();
	g_emu->draw_screen();
	publish_frame();
	return frames;
}

double bubiz_frame_rate(void)
{
	return g_emu ? g_emu->get_frame_rate() : 55.49;
}

const char *bubiz_device_name(void)
{
	return g_emu ? g_emu->device_name() : "";
}

void bubiz_draw_screen(void)
{
	// 描画は bubiz_run() の中で行い公開済み。互換のために残してある
}

void bubiz_screen_size(int *width, int *height)
{
	std::lock_guard<std::mutex> lock(g_frame_mutex);
	*width = g_frame_w;
	*height = g_frame_h;
}

void bubiz_screen_aspect(int *width, int *height)
{
	OSD *osd = g_emu ? g_emu->get_osd() : NULL;
	*width = osd ? osd->get_vm_window_width_aspect() : 0;
	*height = osd ? osd->get_vm_window_height_aspect() : 0;
}

bool bubiz_copy_frame(uint8_t *out_pixels, int width, int height, uint64_t *seq)
{
	std::lock_guard<std::mutex> lock(g_frame_mutex);
	if(g_frame_w != width || g_frame_h != height || g_frame_rgba.empty()) {
		return false;
	}
	memcpy(out_pixels, g_frame_rgba.data(), g_frame_rgba.size());
	if(seq != NULL) {
		*seq = g_frame_seq;
	}
	return true;
}

bool bubiz_frame_skip_line(void)
{
	std::lock_guard<std::mutex> lock(g_frame_mutex);
	return g_frame_skip_line;
}

void bubiz_read_screen_rgba(uint8_t *out_pixels)
{
	std::lock_guard<std::mutex> lock(g_frame_mutex);
	if(!g_frame_rgba.empty()) {
		memcpy(out_pixels, g_frame_rgba.data(), g_frame_rgba.size());
	}
}

// ---------------------------------------------------------------------------
// サウンド
// ---------------------------------------------------------------------------

int bubiz_sound_rate(void)
{
	return g_emu ? g_emu->get_sound_rate() : 48000;
}

size_t bubiz_pull_sound(int16_t *dest, size_t frames)
{
	if(g_emu == NULL) {
		for(size_t i = 0; i < frames * 2; i++) {
			dest[i] = 0;
		}
		return 0;
	}
	return g_emu->get_osd()->pull_sound(dest, frames);
}

// ---------------------------------------------------------------------------
// 入力・操作(キュー経由)
// ---------------------------------------------------------------------------

void bubiz_key_down(int vk, bool repeat)
{
	post([=]() { if(g_emu) g_emu->key_down(vk, false, repeat); });
}

void bubiz_key_up(int vk)
{
	post([=]() { if(g_emu) g_emu->key_up(vk, false); });
}

void bubiz_key_lost_focus(void)
{
	post([]() { if(g_emu) g_emu->key_lost_focus(); });
}

void bubiz_set_joystick(int index, uint32_t status)
{
#ifdef USE_JOYSTICK
	post([=]() {
		if(g_emu && 0 <= index && index < 4) {
			g_emu->get_osd()->get_joy_buffer()[index] = status;
		}
	});
#endif
}

void bubiz_set_mouse(int dx, int dy, int buttons)
{
#ifdef USE_MOUSE
	post([=]() { if(g_emu) g_emu->get_osd()->set_mouse_state(dx, dy, buttons); });
#endif
}

void bubiz_enable_mouse(bool enable)
{
#ifdef USE_MOUSE
	post([=]() {
		if(g_emu) {
			if(enable) {
				g_emu->enable_mouse();
			} else {
				g_emu->disable_mouse();
			}
		}
	});
#endif
}

void bubiz_reset(void)
{
	post([]() { if(g_emu) g_emu->reset(); });
}

void bubiz_special_reset(void)
{
	post([]() { if(g_emu) g_emu->special_reset(); });
}

// ---------------------------------------------------------------------------
// メディア(キュー経由)
// ---------------------------------------------------------------------------

void bubiz_open_floppy(int drive, const char *path, int bank)
{
	std::string p = path;
	post([=]() { if(g_emu) g_emu->open_floppy_disk(drive, p.c_str(), bank); });
}

void bubiz_close_floppy(int drive)
{
	post([=]() { if(g_emu) g_emu->close_floppy_disk(drive); });
}

bool bubiz_floppy_inserted(int drive)
{
	return g_emu && g_emu->is_floppy_disk_inserted(drive);
}

void bubiz_open_hard_disk(int drive, const char *path)
{
	std::string p = path;
	post([=]() { if(g_emu) g_emu->open_hard_disk(drive, p.c_str()); });
}

void bubiz_close_hard_disk(int drive)
{
	post([=]() { if(g_emu) g_emu->close_hard_disk(drive); });
}

void bubiz_play_tape(int drive, const char *path)
{
	std::string p = path;
	post([=]() { if(g_emu) g_emu->play_tape(drive, p.c_str()); });
}

void bubiz_rec_tape(int drive, const char *path)
{
	std::string p = path;
	post([=]() { if(g_emu) g_emu->rec_tape(drive, p.c_str()); });
}

void bubiz_close_tape(int drive)
{
	post([=]() { if(g_emu) g_emu->close_tape(drive); });
}

// ---------------------------------------------------------------------------
// ステート・録画・その他
// ---------------------------------------------------------------------------

void bubiz_save_state(const char *path)
{
	std::string p = path;
	post([=]() { if(g_emu) g_emu->save_state(p.c_str()); });
}

void bubiz_load_state(const char *path)
{
	std::string p = path;
	post([=]() { if(g_emu) g_emu->load_state(p.c_str()); });
}

bool bubiz_state_slot_info(int slot, char *buf, int cap)
{
	if(g_emu == NULL || cap <= 0) {
		return false;
	}
	std::string path = g_emu->state_file_path(slot);
	struct stat st;
	if(stat(path.c_str(), &st) != 0 || st.st_size <= 0) {
		return false;
	}
	size_t sep = path.find_last_of("/\\");
	std::string name = (sep == std::string::npos) ? path : path.substr(sep + 1);
	time_t t = st.st_mtime;
	struct tm *lt = localtime(&t);
	char when[32] = "";
	if(lt != NULL) {
		strftime(when, sizeof(when), "%Y-%m-%d %H:%M:%S", lt);
	}
	snprintf(buf, cap, "%s  %s", name.c_str(), when);
	return true;
}

void bubiz_save_state_slot(int slot)
{
	post([=]() { if(g_emu) g_emu->save_state(g_emu->state_file_path(slot)); });
}

void bubiz_load_state_slot(int slot)
{
	post([=]() { if(g_emu) g_emu->load_state(g_emu->state_file_path(slot)); });
}

void bubiz_capture_screen(void)
{
	post([]() { if(g_emu) g_emu->capture_screen(); });
}

bool bubiz_write_screenshot(const char *path)
{
	if(g_emu == NULL) {
		return false;
	}
	OSD *osd = g_emu->get_osd();
	osd->write_bitmap_to_file(const_cast<bitmap_t *>(osd->get_draw_buffer()), path);
	return true;
}

void bubiz_start_record_sound(void)
{
	post([]() { if(g_emu) g_emu->start_record_sound(); });
}

bool bubiz_start_record_sound_to(const char *path)
{
	if(g_emu == NULL) {
		return false;
	}
	g_emu->get_osd()->start_record_sound(path);
	return g_emu->get_osd()->now_record_sound;
}

void bubiz_stop_record_sound(void)
{
	post([]() { if(g_emu) g_emu->stop_record_sound(); });
}

bool bubiz_power_off_requested(void)
{
	return g_emu && g_emu->get_osd()->power_off_requested;
}

// ---------------------------------------------------------------------------
// デバッガー
// ---------------------------------------------------------------------------

void bubiz_open_debugger(int cpu_index)
{
#ifdef USE_DEBUGGER
	post([=]() {
		if(g_emu) {
			// 前回のスレッドがQコマンドなどで終わっていたら後始末してから開く
			if(g_emu->now_debugging && !g_emu->debugger_thread_param.running) {
				g_emu->close_debugger();
			}
			g_emu->open_debugger(cpu_index);
		}
	});
#endif
}

void bubiz_close_debugger(void)
{
#ifdef USE_DEBUGGER
	if(g_emu) {
		g_emu->close_debugger();
	}
#endif
}

bool bubiz_debugger_active(void)
{
#ifdef USE_DEBUGGER
	return g_emu && g_emu->now_debugging && g_emu->debugger_thread_param.running;
#else
	return false;
#endif
}

// ---------------------------------------------------------------------------
// メディア(追加)・履歴・自動キー・汎用設定
// ---------------------------------------------------------------------------

bool bubiz_create_blank_floppy(const char *path, int type)
{
	return g_emu && g_emu->create_blank_floppy_disk(path, type == 0 ? 0x00 : 0x10);
}

bool bubiz_create_blank_hard_disk(const char *path)
{
	return g_emu && g_emu->create_blank_hard_disk(path, 256, 33, 4, 615);
}

bool bubiz_floppy_protected(int drive)
{
	return g_emu && g_emu->is_floppy_disk_protected(drive);
}

void bubiz_set_floppy_protected(int drive, bool protect)
{
	post([=]() { if(g_emu) g_emu->is_floppy_disk_protected(drive, protect); });
}

int bubiz_floppy_bank_count(int drive)
{
	return (g_emu && drive >= 0 && drive < USE_FLOPPY_DISK) ? g_emu->d88_file[drive].bank_num : 0;
}

const char *bubiz_floppy_bank_name(int drive, int bank)
{
	if(g_emu && drive >= 0 && drive < USE_FLOPPY_DISK && bank >= 0 && bank < g_emu->d88_file[drive].bank_num) {
		return g_emu->d88_file[drive].disk_name[bank];
	}
	return "";
}

int bubiz_floppy_cur_bank(int drive)
{
	return (g_emu && drive >= 0 && drive < USE_FLOPPY_DISK) ? g_emu->d88_file[drive].cur_bank : 0;
}

void bubiz_select_floppy_bank(int drive, int bank)
{
	post([=]() {
		if(g_emu && drive >= 0 && drive < USE_FLOPPY_DISK && g_emu->d88_file[drive].bank_num > 0) {
			std::string path = g_emu->d88_file[drive].path;
			g_emu->open_floppy_disk(drive, path.c_str(), bank);
		}
	});
}

const char *bubiz_floppy_path(int drive)
{
	if(g_emu && drive >= 0 && drive < USE_FLOPPY_DISK && g_emu->is_floppy_disk_inserted(drive)) {
		return g_emu->d88_file[drive].path;
	}
	return "";
}

const char *bubiz_tape_message(int drive)
{
	return g_emu ? g_emu->get_tape_message(drive) : "";
}

bool bubiz_hard_disk_inserted(int drive)
{
	return g_emu && g_emu->is_hard_disk_inserted(drive);
}

bool bubiz_tape_inserted(int drive)
{
	return g_emu && g_emu->is_tape_inserted(drive);
}

bool bubiz_tape_playing(int drive)
{
	return g_emu && g_emu->is_tape_playing(drive);
}

bool bubiz_tape_recording(int drive)
{
	return g_emu && g_emu->is_tape_recording(drive);
}

void bubiz_tape_button(int drive, int button)
{
	post([=]() {
		if(!g_emu) return;
		switch(button) {
		case 0: g_emu->push_play(drive); break;
		case 1: g_emu->push_stop(drive); break;
		case 2: g_emu->push_fast_forward(drive); break;
		case 3: g_emu->push_fast_rewind(drive); break;
		}
	});
}

// 履歴の保存先を引く。範囲外ならNULL
static _TCHAR (*recent_list(int kind, int drive))[_MAX_PATH]
{
	switch(kind) {
	case 0: if(drive >= 0 && drive < USE_FLOPPY_DISK) return config.recent_floppy_disk_path[drive]; break;
	case 1: if(drive >= 0 && drive < USE_HARD_DISK) return config.recent_hard_disk_path[drive]; break;
	case 2: if(drive >= 0 && drive < USE_TAPE) return config.recent_tape_path[drive]; break;
	}
	return NULL;
}

const char *bubiz_recent_path(int kind, int drive, int index)
{
	_TCHAR (*list)[_MAX_PATH] = recent_list(kind, drive);
	if(list == NULL || index < 0 || index >= MAX_HISTORY) {
		return "";
	}
	return list[index];
}

void bubiz_add_recent(int kind, int drive, const char *path)
{
	_TCHAR (*recent)[_MAX_PATH] = recent_list(kind, drive);
	if(recent == NULL) {
		return;
	}
	// 元の実装(UPDATE_HISTORY)と同じ: 既存の同じパスは先頭へ移す
	int index = MAX_HISTORY - 1;
	for(int i = 0; i < MAX_HISTORY; i++) {
		if(_tcsicmp(recent[i], path) == 0) {
			index = i;
			break;
		}
	}
	for(int i = index; i > 0; i--) {
		my_tcscpy_s(recent[i], _MAX_PATH, recent[i - 1]);
	}
	my_tcscpy_s(recent[0], _MAX_PATH, path);
}

static _TCHAR *initial_dir_ptr(int kind)
{
	switch(kind) {
	case 0: return config.initial_floppy_disk_dir;
	case 1: return config.initial_hard_disk_dir;
	case 2: return config.initial_tape_dir;
	}
	return NULL;
}

const char *bubiz_initial_dir(int kind)
{
	_TCHAR *p = initial_dir_ptr(kind);
	return p ? p : "";
}

void bubiz_set_initial_dir(int kind, const char *dir)
{
	_TCHAR *p = initial_dir_ptr(kind);
	if(p) {
		my_tcscpy_s(p, _MAX_PATH, dir);
	}
}

void bubiz_paste_text(const char *text, int size)
{
	if(size <= 0) {
		return;
	}
	std::string t(text, size);
	post([=]() {
		if(g_emu) {
			g_emu->stop_auto_key();
			g_emu->set_auto_key_list(const_cast<char *>(t.data()), (int)t.size());
			g_emu->start_auto_key();
		}
	});
}

void bubiz_stop_auto_key(void)
{
	post([=]() { if(g_emu) g_emu->stop_auto_key(); });
}

void bubiz_set_romaji_to_kana(bool enable)
{
	post([=]() {
		if(g_emu) {
			g_emu->set_auto_key_char(enable ? 1 : 0);
		}
		config.romaji_to_kana = enable;
	});
}

uint32_t bubiz_floppy_accessed(void)
{
	return g_emu ? g_emu->is_floppy_disk_accessed() : 0;
}

uint32_t bubiz_floppy_indicator_color(void)
{
	return g_emu ? g_emu->floppy_disk_indicator_color() : 0;
}

uint32_t bubiz_hard_disk_accessed(void)
{
	return g_emu ? g_emu->is_hard_disk_accessed() : 0;
}

uint32_t bubiz_tape_accessed(void)
{
	return 0;
}

// 汎用の設定項目
namespace {
struct OptionEntry {
	const char *name;
	void *ptr;
	char type;	// 'i':int 'b':bool
	int count;	// 配列の要素数(単独は1)
	bool apply;	// 変更時にupdate_config()を呼ぶか
};
}

static const OptionEntry g_options[] = {
	{"boot_mode", &config.boot_mode, 'i', 1, true},
	{"option_switch", &config.option_switch, 'i', 1, true},
	{"monitor_type", &config.monitor_type, 'i', 1, true},
	{"scan_line", &config.scan_line, 'b', 1, true},
	{"printer_type", &config.printer_type, 'i', 1, false},
	{"cpu_power", &config.cpu_power, 'i', 1, true},
	{"full_speed", &config.full_speed, 'b', 1, false},
	{"drive_vm_in_opecode", &config.drive_vm_in_opecode, 'b', 1, false},
	{"correct_disk_timing", config.correct_disk_timing, 'b', USE_FLOPPY_DISK, false},
	{"ignore_disk_crc", config.ignore_disk_crc, 'b', USE_FLOPPY_DISK, false},
	{"wave_shaper", config.wave_shaper, 'b', USE_TAPE, false},
	{"window_mode", &config.window_mode, 'i', 1, false},
	{"window_stretch_type", &config.window_stretch_type, 'i', 1, false},
	{"fullscreen_stretch_type", &config.fullscreen_stretch_type, 'i', 1, false},
	{"rotate_type", &config.rotate_type, 'i', 1, false},
	{"filter_type", &config.filter_type, 'i', 1, false},
	{"sound_frequency", &config.sound_frequency, 'i', 1, true},
	{"sound_latency", &config.sound_latency, 'i', 1, true},
	{"sound_strict_rendering", &config.sound_strict_rendering, 'b', 1, true},
	{"sound_noise_fdd", &config.sound_noise_fdd, 'b', 1, true},
	{"sound_noise_cmt", &config.sound_noise_cmt, 'b', 1, true},
	{"sound_tape_signal", &config.sound_tape_signal, 'b', 1, false},
	{"sound_tape_voice", &config.sound_tape_voice, 'b', 1, false},
	{"sound_volume_l", config.sound_volume_l, 'i', USE_SOUND_VOLUME, false},
	{"sound_volume_r", config.sound_volume_r, 'i', USE_SOUND_VOLUME, false},
	{"use_joy_to_key", &config.use_joy_to_key, 'b', 1, false},
	{"romaji_to_kana", &config.romaji_to_kana, 'b', 1, false},
	{"show_status_bar", &config.show_status_bar, 'b', 1, false},
	{"wait_vsync", &config.wait_vsync, 'b', 1, false},
	{"keyboard_joystick", &config.keyboard_joystick, 'i', 1, false},
};

static const OptionEntry *find_option(const char *key, int *index)
{
	std::string k = key;
	int idx = 0;
	size_t colon = k.find(':');
	if(colon != std::string::npos) {
		idx = atoi(k.c_str() + colon + 1);
		k = k.substr(0, colon);
	}
	for(const OptionEntry &e : g_options) {
		if(k == e.name && idx >= 0 && idx < e.count) {
			*index = idx;
			return &e;
		}
	}
	return NULL;
}

bool bubiz_set_option(const char *key, int value)
{
	if(!g_config_loaded) {
		bubiz_load_config(CONFIG_NAME ".ini");
	}
	int idx;
	const OptionEntry *e = find_option(key, &idx);
	if(e == NULL) {
		return false;
	}
	if(e->type == 'b') {
		((bool *)e->ptr)[idx] = (value != 0);
	} else {
		((int *)e->ptr)[idx] = value;
	}
	if(e->apply) {
		post([=]() { if(g_emu) g_emu->update_config(); });
	}
	// 音量はVMへも反映する
	if(std::string(e->name).compare(0, 12, "sound_volume") == 0) {
		post([=]() {
			if(g_emu) {
				for(int i = 0; i < USE_SOUND_VOLUME; i++) {
					g_emu->set_sound_device_volume(i, config.sound_volume_l[i], config.sound_volume_r[i]);
				}
			}
		});
	}
	return true;
}

int bubiz_get_option(const char *key)
{
	if(!g_config_loaded) {
		bubiz_load_config(CONFIG_NAME ".ini");
	}
	int idx;
	const OptionEntry *e = find_option(key, &idx);
	if(e == NULL) {
		return -1;
	}
	return e->type == 'b' ? (((bool *)e->ptr)[idx] ? 1 : 0) : ((int *)e->ptr)[idx];
}

int bubiz_sound_device_count(void)
{
	return USE_SOUND_VOLUME;
}

const char *bubiz_sound_device_name(int index)
{
	return (index >= 0 && index < USE_SOUND_VOLUME) ? sound_device_caption[index] : "";
}
