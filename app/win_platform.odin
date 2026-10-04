#+build windows
package bubiz

// Windows固有の処理

import "core:os"
import "core:strings"
import win "core:sys/windows"

ATTACH_PARENT_PROCESS :: win.DWORD(0xFFFFFFFF)

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "system")
foreign kernel32 {
	SetStdHandle :: proc(nStdHandle: win.DWORD, hHandle: win.HANDLE) -> win.BOOL ---
}

// GUIアプリ(コンソールを持たない)でも、ターミナルから起動されたときはそのターミナルへ出力する。
// 標準出力がパイプやファイルに向けられている場合はそのまま使う
attach_parent_console :: proc() {
	out_ok := win.GetStdHandle(win.STD_OUTPUT_HANDLE) != nil && win.GetStdHandle(win.STD_OUTPUT_HANDLE) != win.INVALID_HANDLE
	if out_ok {
		return
	}
	if !win.AttachConsole(ATTACH_PARENT_PROCESS) {
		return
	}
	h_out := win.CreateFileW(win.utf8_to_wstring("CONOUT$"), win.GENERIC_READ | win.GENERIC_WRITE, win.FILE_SHARE_READ | win.FILE_SHARE_WRITE, nil, win.OPEN_EXISTING, 0, nil)
	if h_out != win.INVALID_HANDLE {
		os.stdout = os.new_file(uintptr(h_out), "CONOUT$")
		os.stderr = os.stdout
		SetStdHandle(win.STD_OUTPUT_HANDLE, h_out)
		SetStdHandle(win.STD_ERROR_HANDLE, h_out)
	}
	h_in := win.CreateFileW(win.utf8_to_wstring("CONIN$"), win.GENERIC_READ | win.GENERIC_WRITE, win.FILE_SHARE_READ | win.FILE_SHARE_WRITE, nil, win.OPEN_EXISTING, 0, nil)
	if h_in != win.INVALID_HANDLE {
		os.stdin = os.new_file(uintptr(h_in), "CONIN$")
		SetStdHandle(win.STD_INPUT_HANDLE, h_in)
	}
}

Known_Folder :: enum {
	Pictures,
	Music,
}

// Windowsが管理するユーザーフォルダ(OneDriveへ移している場合はその場所)を返す。取得できなければ空
known_folder :: proc(which: Known_Folder) -> string {
	id: win.GUID
	switch which {
	case .Pictures: id = win.FOLDERID_Pictures
	case .Music: id = win.FOLDERID_Music
	}
	path: win.LPWSTR
	if win.SHGetKnownFolderPath(&id, 0, nil, &path) != 0 || path == nil {
		return ""
	}
	defer win.CoTaskMemFree(rawptr(path))
	s, err := win.wstring_to_utf8(transmute(win.wstring)path, -1, context.allocator)
	if err != nil {
		return ""
	}
	return s
}
