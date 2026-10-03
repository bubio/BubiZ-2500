/*
	BubiZ-2500 ホスト層 (CSPのOSDインターフェースのLinux/macOS/Windows共通実装)

	[ BubiZ host dependent ]
*/

#ifndef _BUBIZ_OSD_H_
#define _BUBIZ_OSD_H_

#include <stdint.h>
#include <string.h>
#include <mutex>
#include <vector>
#include "../csp/vm/vm.h"
#include "../csp/common.h"
#include "../csp/config.h"
#include "vk.h"

#ifdef USE_SOCKET
#define SOCKET_MAX 4
#define SOCKET_BUFFER_MAX 0x100000
#ifndef _WIN32
typedef int SOCKET;
#endif
#endif

#define SCREEN_FILTER_NONE	0
#define SCREEN_FILTER_RGB	1
#define SCREEN_FILTER_RF	2

#define OSD_CONSOLE_BLUE	1 // 文字色に青を含む
#define OSD_CONSOLE_GREEN	2 // 文字色に緑を含む
#define OSD_CONSOLE_RED		4 // 文字色に赤を含む
#define OSD_CONSOLE_INTENSITY	8 // 文字色を強調する

class FIFO;
class FILEIO;

// ビットマップ（上から下へ並んだ32bit画素）
typedef struct bitmap_s {
	inline bool initialized() const
	{
		return (!pixels.empty());
	}
	inline scrntype_t* get_buffer(int y)
	{
		return pixels.data() + (size_t)width * y;
	}
	int width = 0, height = 0;
	std::vector<scrntype_t> pixels;
} bitmap_t;

typedef struct font_s {
	inline bool initialized() const
	{
		return valid;
	}
	_TCHAR family[64];
	int width, height, rotate;
	bool bold, italic;
	bool valid;
} font_t;

typedef struct pen_s {
	inline bool initialized() const
	{
		return valid;
	}
	int width;
	uint8_t r, g, b;
	bool valid;
} pen_t;

// スクリーンショットの保存先ディレクトリ(空ならデータディレクトリ)
extern std::string g_snap_dir;

class OSD
{
private:
	int lock_count;
	std::recursive_mutex vm_mutex;
	bool console_open;
	bool console_closed;
	void* console_saved;	// 端末設定の退避先(実装側で確保)

	// 入力
	void initialize_input();
	uint8_t key_status[256];	// Windows仮想キーコード
	bool key_shift_pressed, key_shift_released;
	bool lost_focus;
#ifdef USE_JOYSTICK
	uint32_t joy_status[4];
#endif
#ifdef USE_MOUSE
	int32_t mouse_status[3];	// x, y, button (b0 = left, b1 = right)
	bool mouse_enabled;
#endif

	// 画面
	void initialize_screen_buffer(bitmap_t *buffer, int width, int height);
	bitmap_t vm_screen_buffer;
	int host_window_width, host_window_height;
	bool host_window_mode;
	int vm_screen_width, vm_screen_height;
	int vm_window_width, vm_window_height;
	int vm_window_width_aspect, vm_window_height_aspect;
	bool screen_changed;

	// サウンド（VMが生成したチャンクを溜め、ホスト側が取り出す）
	int sound_rate, sound_samples;
	std::mutex sound_mutex;
	std::vector<int16_t> sound_ring;	// ステレオ
	size_t sound_ring_r, sound_ring_w, sound_ring_fill;	// サンプル(フレーム)単位
	bool sound_muted;
	FILEIO* rec_sound_fio;
	int rec_sound_bytes;
	_TCHAR sound_file_path[_MAX_PATH];

public:
	OSD();
	~OSD() {}

	// common
	VM_TEMPLATE* vm;
	void initialize(int rate, int samples);
	void release();
	void power_off();
	void suspend();
	void restore();
	void lock_vm();
	void unlock_vm();
	bool is_vm_locked()
	{
		return (lock_count != 0);
	}
	void force_unlock_vm();
	void sleep(uint32_t ms);
	bool power_off_requested;

	// common debugger
#ifdef USE_DEBUGGER
	void start_waiting_in_debugger() {}
	void finish_waiting_in_debugger() {}
	// CPUがブレークで止まっている間、待機ループから繰り返し呼ばれる
	void process_waiting_in_debugger();
	// 待機中に呼ばれるフック(ウィンドウへ最新の画面を渡すためなどに使う)
	void (*waiting_hook)();
#endif

	// common console（デバッガー用。端末の標準入出力を使う）
	void open_console(int width, int height, const _TCHAR* title);
	void close_console();
	unsigned int get_console_code_page();
	void set_console_text_attribute(unsigned short attr);
	void write_console(const _TCHAR* buffer, unsigned int length);
	int read_console_input(_TCHAR* buffer, unsigned int length);
	bool is_console_key_pressed(int vk);
	bool is_console_closed();
	void close_debugger_console();
	bool console_opened()
	{
		return console_open;
	}

	// common input
	void update_input();
	void key_down(int code, bool extended, bool repeat);
	void key_up(int code, bool extended);
	void key_down_native(int code, bool repeat);
	void key_up_native(int code);
	void key_lost_focus()
	{
		lost_focus = true;
	}
#ifdef USE_MOUSE
	void enable_mouse();
	void disable_mouse();
	void toggle_mouse();
	bool is_mouse_enabled()
	{
		return mouse_enabled;
	}
	// ホスト側から相対移動量とボタン状態を与える
	void set_mouse_state(int dx, int dy, int buttons);
#endif
	uint8_t* get_key_buffer()
	{
		return key_status;
	}
#ifdef USE_JOYSTICK
	uint32_t* get_joy_buffer()
	{
		return joy_status;
	}
#endif
#ifdef USE_MOUSE
	int32_t* get_mouse_buffer()
	{
		return mouse_status;
	}
#endif
#ifdef USE_AUTO_KEY
	bool now_auto_key;
#endif

	// common screen
	double get_window_mode_power(int mode);
	int get_window_mode_width(int mode);
	int get_window_mode_height(int mode);
	void set_host_window_size(int window_width, int window_height, bool window_mode);
	void set_vm_screen_size(int screen_width, int screen_height, int window_width, int window_height, int window_width_aspect, int window_height_aspect);
	void set_vm_screen_lines(int lines);
	int get_vm_window_width()
	{
		return vm_window_width;
	}
	int get_vm_window_height()
	{
		return vm_window_height;
	}
	int get_vm_window_width_aspect()
	{
		return vm_window_width_aspect;
	}
	int get_vm_window_height_aspect()
	{
		return vm_window_height_aspect;
	}
	scrntype_t* get_vm_screen_buffer(int y);
	int draw_screen();
	const bitmap_t* get_draw_buffer()
	{
		return &vm_screen_buffer;
	}
	void capture_screen();
	bool start_record_video(int fps)
	{
		return false;
	}
	void stop_record_video() {}
	void restart_record_video() {}
	void add_extra_frames(int extra_frames) {}
	bool now_record_video;
#ifdef USE_SCREEN_FILTER
	bool screen_skip_line;
#endif

	// common sound
	void update_sound(int* extra_frames);
	void mute_sound();
	void stop_sound();
	void start_record_sound(const _TCHAR* path = NULL);	// pathが無ければ日時付きの名前でデータディレクトリに保存
	void stop_record_sound();
	void restart_record_sound();
	bool now_record_sound;
	// ホスト側（オーディオスレッド）が呼ぶ。frames個のステレオサンプルを取り出す
	size_t pull_sound(int16_t* dest, size_t frames);
	int get_sound_rate()
	{
		return sound_rate;
	}

	// common printer
#ifdef USE_PRINTER
	void create_bitmap(bitmap_t *bitmap, int width, int height);
	void release_bitmap(bitmap_t *bitmap);
	void create_font(font_t *font, const _TCHAR *family, int width, int height, int rotate, bool bold, bool italic);
	void release_font(font_t *font);
	void create_pen(pen_t *pen, int width, uint8_t r, uint8_t g, uint8_t b);
	void release_pen(pen_t *pen);
	void clear_bitmap(bitmap_t *bitmap, uint8_t r, uint8_t g, uint8_t b);
	int get_text_width(bitmap_t *bitmap, font_t *font, const char *text);
	void draw_text_to_bitmap(bitmap_t *bitmap, font_t *font, int x, int y, const char *text, uint8_t r, uint8_t g, uint8_t b);
	void draw_line_to_bitmap(bitmap_t *bitmap, pen_t *pen, int sx, int sy, int ex, int ey);
	void draw_rectangle_to_bitmap(bitmap_t *bitmap, int x, int y, int width, int height, uint8_t r, uint8_t g, uint8_t b);
	void draw_point_to_bitmap(bitmap_t *bitmap, int x, int y, uint8_t r, uint8_t g, uint8_t b);
	void stretch_bitmap(bitmap_t *dest, int dest_x, int dest_y, int dest_width, int dest_height, bitmap_t *source, int source_x, int source_y, int source_width, int source_height);
#endif
	void write_bitmap_to_file(bitmap_t *bitmap, const _TCHAR *file_path);

	// common socket（未実装: 常に失敗を返す）
#ifdef USE_SOCKET
	SOCKET get_socket(int ch)
	{
		return (SOCKET)-1;
	}
	void notify_socket_connected(int ch) {}
	void notify_socket_disconnected(int ch) {}
	void update_socket() {}
	bool initialize_socket_tcp(int ch) { return false; }
	bool initialize_socket_udp(int ch) { return false; }
	bool connect_socket(int ch, uint32_t ipaddr, int port) { return false; }
	void disconnect_socket(int ch) {}
	bool listen_socket(int ch) { return false; }
	void send_socket_data_tcp(int ch) {}
	void send_socket_data_udp(int ch, uint32_t ipaddr, int port) {}
	void send_socket_data(int ch) {}
	void recv_socket_data(int ch) {}
#endif

	// common midi（未実装）
#ifdef USE_MIDI
	void send_to_midi(uint8_t data) {}
	bool recv_from_midi(uint8_t *data) { return false; }
#endif
};

#endif
