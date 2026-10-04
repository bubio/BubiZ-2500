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

// 別ウィンドウのコンソール。POSIXでは、ターミナルエミュレーターを起動し、その中で動く中継プロセス
// (自分自身を -dbg_relay 付きで起動したもの)とUNIXドメインソケットで文字をやり取りする。
// Windowsでは専用のコンソールウィンドウ(AllocConsole)を開く。
namespace {
int g_ext_fd = -1;		// POSIX: 中継プロセスとのソケット
bool g_ext_console = false;	// Windows: 専用コンソールを開いている
std::string g_ext_sock;
}

static bool ext_active()
{
#ifdef _WIN32
	return g_ext_console;
#else
	return g_ext_fd >= 0;
#endif
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

bool bubiz_prepare_external_console(const char *self_exe)
{
	if(g_ext_console) {
		return true;
	}
	if(!AllocConsole() && GetConsoleWindow() == NULL) {
		return false;
	}
	// 標準入出力を新しいコンソールへ向ける
	freopen("CONOUT$", "w", stdout);
	freopen("CONIN$", "r", stdin);
	SetConsoleTitleA("BubiZ-2500 Debugger");
	g_ext_console = true;
	return true;
}

int bubiz_run_console_relay(const char *sock)
{
	return 1;	// Windowsでは中継を使わない
}

void OSD::open_console(int width, int height, const _TCHAR* title)
{
	if(console_open) {
		return;
	}
	if(ext_active()) {
		console_open = true;
		console_closed = false;
#ifdef _WIN32
		fprintf(stdout, "\n[%s]\n", title);
		fflush(stdout);
#else
		std::string t = std::string("[") + title + "]\n";
		ext_send(t.c_str(), t.size());
#endif
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
	if(g_vcon && !ext_active()) {
		console_open = false;
		return;
	}
#ifndef _WIN32
	if(g_ext_fd >= 0) {
		close(g_ext_fd);	// 中継プロセスが終わり、ターミナルのウィンドウも閉じる
		g_ext_fd = -1;
		console_open = false;
		return;
	}
#endif
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
	if(g_ext_console) {
		FreeConsole();	// 専用に開いたコンソールウィンドウを閉じる
		g_ext_console = false;
	}
}

int OSD::read_console_input(_TCHAR* buffer, unsigned int length)
{
	if(g_vcon && !ext_active()) {
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
	if(g_vcon && !ext_active()) {
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
#include <signal.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <vector>

static void ext_send(const char *p, size_t n)
{
	while(n > 0) {
		ssize_t w = write(g_ext_fd, p, n);
		if(w <= 0) {
			return;
		}
		p += w;
		n -= (size_t)w;
	}
}

static bool find_in_path(const std::string &name, std::string &out)
{
	if(name.find('/') != std::string::npos) {
		if(access(name.c_str(), X_OK) == 0) {
			out = name;
			return true;
		}
		return false;
	}
	const char *path = getenv("PATH");
	if(path == NULL) {
		return false;
	}
	std::string s = path;
	size_t pos = 0;
	while(pos <= s.size()) {
		size_t e = s.find(':', pos);
		if(e == std::string::npos) {
			e = s.size();
		}
		std::string cand = s.substr(pos, e - pos) + "/" + name;
		if(access(cand.c_str(), X_OK) == 0) {
			out = cand;
			return true;
		}
		pos = e + 1;
	}
	return false;
}

// ターミナルウィンドウを開いて、その中で中継プロセスを動かす
static bool spawn_terminal(const std::string &exe, const std::string &sock)
{
	std::vector<std::string> argv;
#ifdef __APPLE__
	// Terminal.appに.commandファイルを開かせる(Apple Eventsの許可を求められない方法)
	std::string script = sock + ".command";
	FILE *fp = fopen(script.c_str(), "w");
	if(fp == NULL) {
		return false;
	}
	fprintf(fp, "#!/bin/sh\nrm -f \"$0\"\nexec \"%s\" -dbg_relay \"%s\"\n", exe.c_str(), sock.c_str());
	fclose(fp);
	chmod(script.c_str(), 0700);
	argv = {"/usr/bin/open", "-a", "Terminal", script};
#else
	struct Cand { const char *name; const char *opt; };
	std::vector<Cand> cands;
	const char *env_term = getenv("TERMINAL");
	std::string env_name = env_term ? env_term : "";
	if(!env_name.empty()) {
		cands.push_back({env_name.c_str(), "-e"});
	}
	static const Cand table[] = {
		{"x-terminal-emulator", "-e"}, {"gnome-terminal", "--"}, {"konsole", "-e"}, {"xfce4-terminal", "-x"},
		{"mate-terminal", "-x"}, {"lxterminal", "-e"}, {"kitty", ""}, {"alacritty", "-e"}, {"xterm", "-e"},
	};
	for(const Cand &c : table) {
		cands.push_back(c);
	}
	std::string found;
	const Cand *use = NULL;
	for(const Cand &c : cands) {
		if(find_in_path(c.name, found)) {
			use = &c;
			break;
		}
	}
	if(use == NULL) {
		return false;
	}
	argv.push_back(found);
	if(use->opt[0] != '\0') {
		argv.push_back(use->opt);
	}
	argv.push_back(exe);
	argv.push_back("-dbg_relay");
	argv.push_back(sock);
#endif
	pid_t pid = fork();
	if(pid < 0) {
		return false;
	}
	if(pid == 0) {
		setsid();
		std::vector<char *> args;
		for(std::string &a : argv) {
			args.push_back(const_cast<char *>(a.c_str()));
		}
		args.push_back(NULL);
		// 端末に出力が混ざらないよう、標準入出力は捨てる
		int nul = open("/dev/null", O_RDWR);
		if(nul >= 0) {
			dup2(nul, 0);
			dup2(nul, 1);
			dup2(nul, 2);
		}
		execvp(args[0], args.data());
		_exit(127);
	}
	signal(SIGCHLD, SIG_IGN);
	return true;
}

bool bubiz_prepare_external_console(const char *self_exe)
{
	if(g_ext_fd >= 0) {
		return true;
	}
	char dir_tmpl[] = "/tmp/bubiz-dbg-XXXXXX";
	if(mkdtemp(dir_tmpl) == NULL) {
		return false;
	}
	std::string sock = std::string(dir_tmpl) + "/console.sock";
	int ls = socket(AF_UNIX, SOCK_STREAM, 0);
	if(ls < 0) {
		rmdir(dir_tmpl);
		return false;
	}
	struct sockaddr_un addr;
	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	if(sock.size() >= sizeof(addr.sun_path)) {
		close(ls);
		rmdir(dir_tmpl);
		return false;
	}
	strcpy(addr.sun_path, sock.c_str());
	bool ok = bind(ls, (struct sockaddr *)&addr, sizeof(addr)) == 0 && listen(ls, 1) == 0 && spawn_terminal(self_exe, sock);
	int cfd = -1;
	if(ok) {
		struct pollfd pfd = {ls, POLLIN, 0};
		if(poll(&pfd, 1, 8000) > 0) {
			cfd = accept(ls, NULL, NULL);
		}
	}
	close(ls);
	unlink(sock.c_str());
	rmdir(dir_tmpl);
	if(cfd < 0) {
		return false;
	}
	g_ext_fd = cfd;
	return true;
}

// ターミナルウィンドウの中で動く中継: 端末の入力をソケットへ、ソケットの出力を端末へ流す
int bubiz_run_console_relay(const char *sock)
{
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if(fd < 0) {
		return 1;
	}
	struct sockaddr_un addr;
	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, sock, sizeof(addr.sun_path) - 1);
	if(connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
		fprintf(stderr, "cannot connect to the emulator\n");
		return 1;
	}
	struct termios saved;
	bool tty = isatty(STDIN_FILENO) != 0;
	if(tty) {
		tcgetattr(STDIN_FILENO, &saved);
		struct termios raw = saved;
		raw.c_lflag &= ~(ICANON | ECHO);
		raw.c_cc[VMIN] = 1;
		raw.c_cc[VTIME] = 0;
		tcsetattr(STDIN_FILENO, TCSANOW, &raw);
	}
	char buf[1024];
	bool stdin_open = true;
	for(;;) {
		struct pollfd pfds[2] = {{fd, POLLIN, 0}, {STDIN_FILENO, POLLIN, 0}};
		if(poll(pfds, stdin_open ? 2 : 1, -1) < 0) {
			break;
		}
		if(pfds[0].revents & (POLLIN | POLLHUP)) {
			ssize_t n = read(fd, buf, sizeof(buf));
			if(n <= 0) {
				break;	// エミュレーターが閉じた
			}
			ssize_t off = 0;
			while(off < n) {
				ssize_t w = write(STDOUT_FILENO, buf + off, n - off);
				if(w <= 0) break;
				off += w;
			}
		}
		if(stdin_open && (pfds[1].revents & (POLLIN | POLLHUP))) {
			ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
			if(n <= 0) {
				stdin_open = false;
			} else if(write(fd, buf, n) <= 0) {
				break;
			}
		}
	}
	if(tty) {
		tcsetattr(STDIN_FILENO, TCSANOW, &saved);
	}
	close(fd);
	return 0;
}

struct console_state_t {
	struct termios saved;
	bool tty;
};

void OSD::open_console(int width, int height, const _TCHAR* title)
{
	if(console_open) {
		return;
	}
	if(ext_active()) {
		console_open = true;
		console_closed = false;
#ifdef _WIN32
		fprintf(stdout, "\n[%s]\n", title);
		fflush(stdout);
#else
		std::string t = std::string("[") + title + "]\n";
		ext_send(t.c_str(), t.size());
#endif
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
	if(g_vcon && !ext_active()) {
		console_open = false;
		return;
	}
#ifndef _WIN32
	if(g_ext_fd >= 0) {
		close(g_ext_fd);	// 中継プロセスが終わり、ターミナルのウィンドウも閉じる
		g_ext_fd = -1;
		console_open = false;
		return;
	}
#endif
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
	if(g_ext_fd >= 0) {
		struct pollfd pfd = {g_ext_fd, POLLIN, 0};
		if(poll(&pfd, 1, 0) <= 0) {
			return 0;
		}
		char tmp[16];
		ssize_t n = read(g_ext_fd, tmp, length < sizeof(tmp) ? length : sizeof(tmp));
		if(n == 0) {
			console_closed = true;	// ターミナルのウィンドウが閉じられた
			return 0;
		}
		if(n < 0) {
			return 0;
		}
		for(ssize_t i = 0; i < n; i++) {
			buffer[i] = (tmp[i] == 0x7f) ? 0x08 : tmp[i];
		}
		return (int)n;
	}
	if(g_vcon && !ext_active()) {
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
	if(g_ext_fd >= 0) {
		if(vk != VK_ESCAPE) {
			return false;
		}
		// 単独のESCだけを押下とみなす(矢印キーのESC [ A のような列は残す)
		char c[3];
		ssize_t n = recv(g_ext_fd, c, sizeof(c), MSG_PEEK | MSG_DONTWAIT);
		if(n == 1 && c[0] == 0x1b) {
			recv(g_ext_fd, c, 1, MSG_DONTWAIT);
			return true;
		}
		return false;
	}
	if(g_vcon && !ext_active()) {
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
#ifndef _WIN32
	if(g_ext_fd >= 0) {
		int idx = ((attr & OSD_CONSOLE_RED) ? 1 : 0) | ((attr & OSD_CONSOLE_GREEN) ? 2 : 0) | ((attr & OSD_CONSOLE_BLUE) ? 4 : 0);
		int base = (attr & OSD_CONSOLE_INTENSITY) ? 90 : 30;
		if(idx == 0 && !(attr & OSD_CONSOLE_INTENSITY)) {
			idx = 7;
		}
		char esc[16];
		int n = snprintf(esc, sizeof(esc), "\x1b[%dm", base + idx);
		ext_send(esc, (size_t)n);
		return;
	}
#endif
	if(g_vcon && !ext_active()) {
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
#ifndef _WIN32
	if(g_ext_fd >= 0) {
		ext_send(buffer, length);
		return;
	}
#endif
	if(g_vcon && !ext_active()) {
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
