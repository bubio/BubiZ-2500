/*
	BubiZ-2500 コアC API 実装

	スレッドの扱い:
	  エミュレーションを進める bubiz_run() は1つのスレッドから呼ぶ(ウィンドウ版では専用スレッド)。
	  入力・メディア操作・リセットなどVMの状態を変える呼び出しは、どのスレッドから呼んでもよい。
	  それらは一旦キューに積まれ、次の bubiz_run() の冒頭でエミュレーションスレッドが実行する。
	  これにより、デバッガーでCPUが止まっている間も、呼び出し側(UIスレッド)がブロックされない。
	  画面は bubiz_run() の末尾で最新のフレームとして公開され、bubiz_copy_frame() で取り出す。
*/

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
