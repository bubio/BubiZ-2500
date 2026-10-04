// ウィンドウの大きさを変える(sokol_appにはその機能が無いため、OSごとに直接操作する)
#if defined(_WIN32)
#include <windows.h>

// 内側(クライアント領域)の大きさをピクセルで指定する
void bubiz_native_resize(void *hwnd, int w, int h)
{
	RECT r = {0, 0, w, h};
	DWORD style = (DWORD)GetWindowLongPtr((HWND)hwnd, GWL_STYLE);
	DWORD ex_style = (DWORD)GetWindowLongPtr((HWND)hwnd, GWL_EXSTYLE);
	AdjustWindowRectEx(&r, style, FALSE, ex_style);
	SetWindowPos((HWND)hwnd, NULL, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
}
#elif defined(__linux__)
#include <X11/Xlib.h>

void bubiz_native_resize(void *display, void *window, int w, int h)
{
	XResizeWindow((Display *)display, (Window)(unsigned long)window, (unsigned int)w, (unsigned int)h);
	XFlush((Display *)display);
}
#endif
