/*
	BubiZ-2500 ホスト層: デバッガー用のコンソール入出力
	端末の標準入出力を使う。ANSIエスケープで色を付け、入力は端末が送る文字列をそのまま返す
	(矢印キーは ESC [ A のような列で届くため、デバッガー側の履歴機能がそのまま動く)。

	[ BubiZ host dependent ]
*/

#include <stdio.h>
#include <string.h>
#include <deque>
#include <mutex>
#include <string>
#include "osd.h"
#include "../csp/emu.h"
#include "../bubiz_core.h"

// 仮想コンソール: 端末の代わりに、アプリのウィンドウ内のデバッガー画面と文字をやり取りする。
// 端末が無い起動(ファイルブラウザやFinderから)でもデバッガーを使えるようにするためのもの。
namespace {
struct VChunk {
	unsigned short attr;
	std::string text;
};
bool g_vcon = false;
std::mutex g_vcon_mutex;
std::deque<char> g_vcon_in;
std::deque<VChunk> g_vcon_out;
unsigned short g_vcon_attr = 0;
bool g_vcon_break = false;
}

void bubiz_set_virtual_console(bool on)
{
	g_vcon = on;
}

int bubiz_console_read(unsigned short *attr, char *buf, int cap)
{
	std::lock_guard<std::mutex> lock(g_vcon_mutex);
	if(g_vcon_out.empty() || cap <= 0) {
		return 0;
	}
	VChunk &c = g_vcon_out.front();
	int n = (int)c.text.size();
	if(n > cap) {
		n = cap;
	}
	*attr = c.attr;
	memcpy(buf, c.text.data(), n);
	if(n == (int)c.text.size()) {
		g_vcon_out.pop_front();
	} else {
		c.text.erase(0, n);
	}
	return n;
}

void bubiz_console_write_input(const char *s, int n)
{
	std::lock_guard<std::mutex> lock(g_vcon_mutex);
	for(int i = 0; i < n; i++) {
		g_vcon_in.push_back(s[i]);
	}
}

void bubiz_console_break(void)
{
	std::lock_guard<std::mutex> lock(g_vcon_mutex);
	g_vcon_break = true;
}

static void vcon_write(const char *buffer, unsigned int length)
{
	std::lock_guard<std::mutex> lock(g_vcon_mutex);
	if(!g_vcon_out.empty() && g_vcon_out.back().attr == g_vcon_attr) {
		g_vcon_out.back().text.append(buffer, length);
	} else {
		g_vcon_out.push_back({g_vcon_attr, std::string(buffer, length)});
	}
}

#ifdef _WIN32
#include <windows.h>

struct console_state_t {
	DWORD in_mode, out_mode;
	bool valid;
	_TCHAR pending[8];	// 矢印キーを展開した残り
	int pending_len, pending_ptr;
};

void OSD::open_console(int width, int height, const _TCHAR* title)
{
	if(console_open) {
		return;
	}
	if(g_vcon) {
		console_open = true;
		console_closed = false;
		{
			std::lock_guard<std::mutex> lock(g_vcon_mutex);
			g_vcon_in.clear();
			g_vcon_break = false;
		}
		std::string t = std::string("[") + title + "]\n";
		vcon_write(t.c_str(), (unsigned int)t.size());
		return;
	}
	console_state_t *st = new console_state_t();
	memset(st, 0, sizeof(*st));
	HANDLE in = GetStdHandle(STD_INPUT_HANDLE), out = GetStdHandle(STD_OUTPUT_HANDLE);
	st->valid = GetConsoleMode(in, &st->in_mode) && GetConsoleMode(out, &st->out_mode);
	if(st->valid) {
		SetConsoleMode(in, ENABLE_PROCESSED_INPUT);
		SetConsoleMode(out, st->out_mode | ENABLE_PROCESSED_OUTPUT | 0x0004 /* ENABLE_VIRTUAL_TERMINAL_PROCESSING */);
	}
	console_saved = st;
	console_open = true;
	console_closed = false;
	fprintf(stdout, "\n[%s]\n", title);
	fflush(stdout);
}

void OSD::close_console()
{
	if(!console_open) {
		return;
	}
	if(g_vcon) {
		console_open = false;
		return;
	}
	console_state_t *st = (console_state_t *)console_saved;
	if(st != NULL) {
		if(st->valid) {
			SetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), st->in_mode);
			SetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE), st->out_mode);
		}
		delete st;
	}
	console_saved = NULL;
	console_open = false;
	fputs("\x1b[0m", stdout);
	fflush(stdout);
}

int OSD::read_console_input(_TCHAR* buffer, unsigned int length)
{
	if(g_vcon) {
		std::lock_guard<std::mutex> lock(g_vcon_mutex);
		unsigned int n = 0;
		while(n < length && !g_vcon_in.empty()) {
			buffer[n++] = g_vcon_in.front();
			g_vcon_in.pop_front();
		}
		return (int)n;
	}
	console_state_t *st = (console_state_t *)console_saved;
	HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
	unsigned int count = 0;
	DWORD n = 0;
	if(st == NULL || !GetNumberOfConsoleInputEvents(in, &n) || n == 0) {
		return 0;
	}
	while(n > 0 && count < length) {
		INPUT_RECORD ir;
		DWORD read = 0;
		if(!ReadConsoleInput(in, &ir, 1, &read) || read == 0) {
			break;
		}
		n--;
		if(ir.EventType != KEY_EVENT || !ir.Event.KeyEvent.bKeyDown) {
			continue;
		}
		WORD vk = ir.Event.KeyEvent.wVirtualKeyCode;
		if((vk == VK_UP || vk == VK_DOWN) && count + 3 <= length) {
			buffer[count++] = 0x1b;
			buffer[count++] = 0x5b;
			buffer[count++] = (vk == VK_UP) ? 'A' : 'B';
		} else {
			char c = ir.Event.KeyEvent.uChar.AsciiChar;
			if(c != 0) {
				buffer[count++] = c;
			}
		}
	}
	return (int)count;
}

bool OSD::is_console_key_pressed(int vk)
{
	if(g_vcon) {
		std::lock_guard<std::mutex> lock(g_vcon_mutex);
		bool b = g_vcon_break && vk == VK_ESCAPE;
		if(b) {
			g_vcon_break = false;
		}
		return b;
	}
	return (GetAsyncKeyState(vk) & 0x8000) != 0;
}

#else // POSIX
#include <unistd.h>
#include <termios.h>
#include <poll.h>

struct console_state_t {
	struct termios saved;
	bool tty;
};

void OSD::open_console(int width, int height, const _TCHAR* title)
{
	if(console_open) {
		return;
	}
	if(g_vcon) {
		console_open = true;
		console_closed = false;
		{
			std::lock_guard<std::mutex> lock(g_vcon_mutex);
			g_vcon_in.clear();
			g_vcon_break = false;
		}
		std::string t = std::string("[") + title + "]\n";
		vcon_write(t.c_str(), (unsigned int)t.size());
		return;
	}
	console_state_t *st = new console_state_t();
	st->tty = isatty(STDIN_FILENO) != 0;
	if(st->tty) {
		tcgetattr(STDIN_FILENO, &st->saved);
		struct termios raw = st->saved;
		raw.c_lflag &= ~(ICANON | ECHO);	// 1文字ずつ・エコーなし(Ctrl+Cは有効のまま)
		raw.c_cc[VMIN] = 0;
		raw.c_cc[VTIME] = 0;
		tcsetattr(STDIN_FILENO, TCSANOW, &raw);
	}
	console_saved = st;
	console_open = true;
	console_closed = false;
	fprintf(stdout, "\n[%s]\n", title);
	fflush(stdout);
}

void OSD::close_console()
{
	if(!console_open) {
		return;
	}
	if(g_vcon) {
		console_open = false;
		return;
	}
	console_state_t *st = (console_state_t *)console_saved;
	if(st != NULL) {
		if(st->tty) {
			tcsetattr(STDIN_FILENO, TCSANOW, &st->saved);
		}
		delete st;
	}
	console_saved = NULL;
	console_open = false;
	fputs("\x1b[0m", stdout);
	fflush(stdout);
}

int OSD::read_console_input(_TCHAR* buffer, unsigned int length)
{
	if(g_vcon) {
		std::lock_guard<std::mutex> lock(g_vcon_mutex);
		unsigned int n = 0;
		while(n < length && !g_vcon_in.empty()) {
			buffer[n++] = g_vcon_in.front();
			g_vcon_in.pop_front();
		}
		return (int)n;
	}
	console_state_t *st = (console_state_t *)console_saved;
	if(st == NULL) {
		return 0;
	}
	struct pollfd pfd = {STDIN_FILENO, POLLIN, 0};
	if(poll(&pfd, 1, 0) <= 0) {
		return 0;
	}
	char tmp[16];
	ssize_t n = read(STDIN_FILENO, tmp, length < sizeof(tmp) ? length : sizeof(tmp));
	if(n == 0) {
		// 入力が閉じられた(パイプの終端など)
		console_closed = true;
		return 0;
	}
	if(n < 0) {
		return 0;
	}
	for(ssize_t i = 0; i < n; i++) {
		buffer[i] = (tmp[i] == 0x7f) ? 0x08 : tmp[i];	// DELはバックスペースとして扱う
	}
	return (int)n;
}

bool OSD::is_console_key_pressed(int vk)
{
	if(g_vcon) {
		std::lock_guard<std::mutex> lock(g_vcon_mutex);
		bool b = g_vcon_break && vk == VK_ESCAPE;
		if(b) {
			g_vcon_break = false;
		}
		return b;
	}
	// 単独のESCが入力されたら押されたとみなす(矢印キーなどの列は対象外)
	if(vk != VK_ESCAPE || console_saved == NULL) {
		return false;
	}
	struct pollfd pfd = {STDIN_FILENO, POLLIN, 0};
	if(poll(&pfd, 1, 0) <= 0) {
		return false;
	}
	char c;
	if(read(STDIN_FILENO, &c, 1) == 1 && c == 0x1b) {
		return true;
	}
	return false;
}
#endif

unsigned int OSD::get_console_code_page()
{
	return 0;	// UTF-8の端末を想定(Shift_JIS用の処理は使わない)
}

void OSD::set_console_text_attribute(unsigned short attr)
{
	if(g_vcon) {
		std::lock_guard<std::mutex> lock(g_vcon_mutex);
		g_vcon_attr = attr;
		return;
	}
	// 属性ビット(青=1,緑=2,赤=4,強調=8)をANSIの色番号(赤=1,緑=2,青=4)に変換する
	int idx = ((attr & OSD_CONSOLE_RED) ? 1 : 0) | ((attr & OSD_CONSOLE_GREEN) ? 2 : 0) | ((attr & OSD_CONSOLE_BLUE) ? 4 : 0);
	int base = (attr & OSD_CONSOLE_INTENSITY) ? 90 : 30;
	if(idx == 0 && !(attr & OSD_CONSOLE_INTENSITY)) {
		idx = 7;	// 色指定なしは白
	}
	fprintf(stdout, "\x1b[%dm", base + idx);
}

void OSD::write_console(const _TCHAR* buffer, unsigned int length)
{
	if(g_vcon) {
		vcon_write(buffer, length);
		return;
	}
	fwrite(buffer, 1, length, stdout);
	fflush(stdout);
}

bool OSD::is_console_closed()
{
	return console_closed;
}

void OSD::close_debugger_console()
{
	// 端末は閉じるものではないため何もしない。Qコマンドでデバッガー側のスレッドが自分で終了する
}

#ifdef USE_DEBUGGER
void OSD::process_waiting_in_debugger()
{
	if(waiting_hook != NULL) {
		waiting_hook();
	}
}
#endif
