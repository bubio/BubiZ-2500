// Dear ImGuiの構造体に触る必要がある処理を、Cで包んでOdinから呼べるようにする
#include "cimgui.h"
#include <stdbool.h>

// 日本語を表示できるTTF/TTC/OTFを読み込む(1.92以降はグリフが必要になった時点で展開される)
bool bubiz_gui_load_font(const char *path, float size)
{
	ImGuiIO *io = igGetIO();
	if(ImFontAtlas_AddFontFromFileTTF(io->Fonts, path, size, NULL, NULL) != NULL) {
		return true;
	}
	// 読めなかった場合は内蔵フォント(日本語は出ない)にする
	ImFontAtlas_AddFontDefault(io->Fonts, NULL);
	return false;
}

// imgui.iniを作らない
void bubiz_gui_disable_ini(void)
{
	ImGuiIO *io = igGetIO();
	io->IniFilename = NULL;
}

bool bubiz_gui_want_capture_mouse(void)
{
	return igGetIO()->WantCaptureMouse;
}

bool bubiz_gui_want_capture_keyboard(void)
{
	return igGetIO()->WantCaptureKeyboard;
}

// メインメニューバーの高さ(ピクセル)
float bubiz_gui_frame_height(void)
{
	return igGetFrameHeight();
}
