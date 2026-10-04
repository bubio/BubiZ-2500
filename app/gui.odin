package bubiz

// GUI: メニューバー・ファイル選択・バージョン情報(Dear ImGui)

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"

import sapp "sokol:app"
import simgui "sokol:imgui"
import slog "sokol:log"

MENU_HEIGHT_LOGICAL :: 22 // ImGuiの既定(フォント14px + 余白)でのメニューバーの高さ

File_Purpose :: enum {
	Floppy,
	Hard_Disk,
	Tape,
}

Gui_Entry :: struct {
	name:   cstring,
	is_dir: bool,
}

Gui :: struct {
	ja:            bool, // 日本語フォントを読み込めたか
	mouse_y:       f32, // フルスクリーン時にメニューを出すための位置(論理座標)
	menu_open:     bool, // いずれかのメニューが開いている
	// ファイル選択
	dialog_open:   bool,
	purpose:       File_Purpose,
	drive:         int,
	cwd:           string,
	entries:       [dynamic]Gui_Entry,
	path_buf:      [1024]u8,
	last_dir:      string,
	// バージョン情報
	about_open:    bool,
}

gui: Gui

// 日本語を表示できるシステムフォントの候補
FONT_CANDIDATES :: [?]cstring {
	// macOS
	"/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
	"/System/Library/Fonts/Hiragino Sans GB.ttc",
	"/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
	// Windows
	"C:\\Windows\\Fonts\\YuGothM.ttc",
	"C:\\Windows\\Fonts\\meiryo.ttc",
	"C:\\Windows\\Fonts\\msgothic.ttc",
	// Linux
	"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
	"/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
	"/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc",
	"/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf",
	"/usr/share/fonts/truetype/fonts-japanese-gothic.ttf",
	"/usr/share/fonts/truetype/takao-gothic/TakaoPGothic.ttf",
	"/usr/share/fonts/ipa-gothic/ipag.ttf",
}

gui_init :: proc() {
	simgui.setup({no_default_font = true, logger = {func = slog.func}})
	bubiz_gui_disable_ini()
	for path in FONT_CANDIDATES {
		if os.exists(string(path)) && bubiz_gui_load_font(path, 14) {
			gui.ja = true
			break
		}
	}
	if !gui.ja {
		bubiz_gui_load_font("", 14) // 内蔵フォントにする
	}
	start := fe.opt.disk_dir
	if start == "" {
		start = os.get_env("HOME", context.allocator)
	}
	gui.last_dir = strings.clone(start if start != "" else ".")
}

gui_shutdown :: proc() {
	simgui.shutdown()
}

// イベントをGUIへ渡す。GUIが処理したらtrue
gui_event :: proc(e: ^sapp.Event) -> bool {
	if e.type == .MOUSE_MOVE {
		gui.mouse_y = e.mouse_y / sapp.dpi_scale()
	}
	return simgui.handle_event(e^)
}

// GUIがキーボード・マウスを使っているか(エミュレーション側へ渡さない)
gui_wants_input :: proc() -> bool {
	return gui.menu_open || gui.dialog_open || gui.about_open
}

// メニューバーを表示するか(フルスクリーンでは、マウスを上端へ寄せたときだけ)
gui_menu_visible :: proc() -> bool {
	return !sapp.is_fullscreen() || gui.mouse_y < f32(MENU_HEIGHT_LOGICAL) || gui.menu_open
}

// エミュレーション画面が使える領域の上端(フレームバッファのピクセル)。ウィンドウ表示ではメニューの下
gui_top_offset :: proc() -> f32 {
	if sapp.is_fullscreen() {
		return 0
	}
	return f32(MENU_HEIGHT_LOGICAL) * sapp.dpi_scale()
}

tr :: proc(ja, en: cstring) -> cstring {
	return ja if gui.ja else en
}

// 書式文字列用
trf :: proc(ja, en: string) -> string {
	return ja if gui.ja else en
}

gui_new_frame :: proc() {
	simgui.new_frame({width = sapp.width(), height = sapp.height(), delta_time = sapp.frame_duration(), dpi_scale = sapp.dpi_scale()})
	gui.menu_open = false
	if gui_menu_visible() {
		draw_menu_bar()
	}
	draw_file_dialog()
	draw_about()
}

gui_render :: proc() {
	simgui.render()
}

@(private = "file")
menu :: proc(label: cstring) -> bool {
	open := igBeginMenuEx(label, true)
	if open {
		gui.menu_open = true
	}
	return open
}

@(private = "file")
item :: proc(label: cstring, shortcut: cstring = nil, selected := false, enabled := true) -> bool {
	return igMenuItemEx(label, shortcut, selected, enabled)
}

@(private = "file")
draw_menu_bar :: proc() {
	if !igBeginMainMenuBar() {
		return
	}
	defer igEndMainMenuBar()

	if menu(tr("ファイル", "File")) {
		defer igEndMenu()
		for d in 0 ..< FLOPPY_DRIVES {
			if menu(fmt.ctprintf(trf("フロッピー%d", "Floppy %d"), d + 1)) {
				if item(tr("開く...", "Open...")) {
					open_file_dialog(.Floppy, d)
				}
				if item(tr("取り出し", "Eject"), nil, false, floppy_inserted(i32(d))) {
					close_floppy(i32(d))
				}
				igEndMenu()
			}
		}
		if menu(tr("ハードディスク", "Hard disk")) {
			if item(tr("開く...", "Open...")) {
				open_file_dialog(.Hard_Disk, 0)
			}
			if item(tr("取り外し", "Remove")) {
				close_hard_disk(0)
			}
			igEndMenu()
		}
		if menu(tr("テープ", "Tape")) {
			if item(tr("再生...", "Play...")) {
				open_file_dialog(.Tape, 0)
			}
			if item(tr("取り出し", "Eject")) {
				close_tape(0)
			}
			igEndMenu()
		}
		igSeparator()
		if menu(tr("ステートを保存", "Save state")) {
			for s in 1 ..= 4 {
				if item(fmt.ctprintf(trf("スロット%d", "Slot %d"), s), fmt.ctprintf("Ctrl+F%d", s)) {
					save_state_slot(i32(s))
				}
			}
			igEndMenu()
		}
		if menu(tr("ステートを読み込み", "Load state")) {
			for s in 1 ..= 4 {
				if item(fmt.ctprintf(trf("スロット%d", "Slot %d"), s), fmt.ctprintf("Ctrl+Shift+F%d", s)) {
					load_state_slot(i32(s))
				}
			}
			igEndMenu()
		}
		igSeparator()
		if item(tr("スクリーンショット", "Screenshot"), "Ctrl+S") {
			action_screenshot()
		}
		igSeparator()
		if item(tr("終了", "Quit")) {
			sapp.request_quit()
		}
	}

	if menu(tr("制御", "Control")) {
		defer igEndMenu()
		if item(tr("リセット", "Reset"), "F12") {
			reset()
		}
		if item(tr("スペシャルリセット", "Special reset"), "Ctrl+F12") {
			special_reset()
		}
		igSeparator()
		if item(tr("一時停止", "Pause"), "Ctrl+P", sync.atomic_load(&fe.paused)) {
			action_toggle_pause()
		}
		if menu(tr("速度", "Speed")) {
			for pct in ([]int{25, 50, 100, 200, 400}) {
				if item(fmt.ctprintf("%d%%", pct), nil, fe.opt.wait && fe.opt.speed == pct) {
					fe.opt.wait = true
					fe.opt.speed = pct
				}
			}
			if item(tr("全速", "Full speed"), nil, !fe.opt.wait) {
				fe.opt.wait = false
			}
			igEndMenu()
		}
	}

	if menu(tr("画面", "Screen")) {
		defer igEndMenu()
		if item(tr("フルスクリーン", "Fullscreen"), "F11", sapp.is_fullscreen()) {
			sapp.toggle_fullscreen()
		}
		if menu(tr("縦横比", "Aspect")) {
			if item("640x400", nil, !fe.opt.aspect_480) {
				fe.opt.aspect_480 = false
			}
			if item("640x480", nil, fe.opt.aspect_480) {
				fe.opt.aspect_480 = true
			}
			igEndMenu()
		}
		if menu(tr("フィルタ", "Filter")) {
			if item(tr("なし", "None"), nil, fe.filter == .None) {
				fe.filter = .None
				fe.last_seq = 0
			}
			if item("RGB", "Ctrl+F", fe.filter == .RGB) {
				fe.filter = .RGB
				fe.last_seq = 0
			}
			igEndMenu()
		}
		if item(tr("スキャンライン", "Scanline"), nil, fe.opt.scan_line != 0) {
			fe.opt.scan_line = 1 - fe.opt.scan_line
			set_config("scan_line", i32(fe.opt.scan_line))
		}
	}

	if menu(tr("デバイス", "Device")) {
		defer igEndMenu()
		if item(tr("キーボードをジョイスティックにする", "Keyboard as joystick"), "Ctrl+J", fe.joy_mode) {
			action_toggle_joystick()
		}
		if item(tr("マウスをキャプチャ", "Capture mouse"), "Ctrl+M", fe.mouse_grab) {
			set_mouse_grab(!fe.mouse_grab)
		}
	}

	if menu(tr("デバッグ", "Debug")) {
		defer igEndMenu()
		if item(tr("デバッガーを開く(端末)", "Open debugger (terminal)"), "Ctrl+D", debugger_active()) {
			open_debugger(0)
		}
	}

	if menu(tr("ヘルプ", "Help")) {
		defer igEndMenu()
		if item(tr("バージョン情報", "About")) {
			gui.about_open = true
		}
	}
}

@(private = "file")
draw_about :: proc() {
	if gui.about_open {
		igOpenPopup("About##bubiz", 0)
		gui.about_open = false
	}
	if igBeginPopupModal("About##bubiz", nil, WINDOW_ALWAYS_AUTO_RESIZE | WINDOW_NO_RESIZE) {
		gui.menu_open = true
		igTextUnformatted(fmt.ctprintf("BubiZ-2500 %s", VERSION))
		igTextUnformatted(tr("SHARP MZ-2500 エミュレーター", "SHARP MZ-2500 emulator"))
		igSeparator()
		igTextUnformatted(tr("エミュレーションコア: Common Source Code Project (EmuZ-2500)", "Core: Common Source Code Project (EmuZ-2500)"))
		igTextUnformatted("Odin / Sokol / Dear ImGui")
		igSeparator()
		if igButton("OK") {
			igCloseCurrentPopup()
		}
		igEndPopup()
	}
}

// ---------------------------------------------------------------------------
// ファイル選択
// ---------------------------------------------------------------------------

@(private = "file")
open_file_dialog :: proc(purpose: File_Purpose, drive: int) {
	gui.purpose = purpose
	gui.drive = drive
	gui.dialog_open = true
	set_dir(gui.last_dir)
}

@(private = "file")
FLOPPY_EXTS := []string{".d88", ".d77", ".2d", ".2hd", ".dsk", ".img", ".fdi", ".xdf"}
@(private = "file")
HDD_EXTS := []string{".hdd", ".hdi", ".nhd", ".thd", ".dat"}
@(private = "file")
TAPE_EXTS := []string{".wav", ".mzt", ".m12", ".mti", ".cas", ".cmt", ".t88"}

@(private = "file")
dialog_extensions :: proc(p: File_Purpose) -> []string {
	switch p {
	case .Floppy: return FLOPPY_EXTS
	case .Hard_Disk: return HDD_EXTS
	case .Tape: return TAPE_EXTS
	}
	return nil
}

@(private = "file")
clear_entries :: proc() {
	for e in gui.entries {
		delete(e.name)
	}
	clear(&gui.entries)
}

// ディレクトリを読み直す。Windowsで空の場合はドライブ一覧を出す
@(private = "file")
set_dir :: proc(dir: string) {
	clear_entries()
	delete(gui.cwd)
	gui.cwd = strings.clone(dir)
	copy_to_path_buf(gui.cwd)

	when ODIN_OS == .Windows {
		if dir == "" {
			for l in 'C' ..= 'Z' {
				root := fmt.tprintf("%c:\\", l)
				if os.exists(root) {
					append(&gui.entries, Gui_Entry{name = strings.clone_to_cstring(root), is_dir = true})
				}
			}
			return
		}
	}
	infos, err := os.read_directory_by_path(dir, -1, context.allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(infos, context.allocator)

	exts := dialog_extensions(gui.purpose)
	dirs: [dynamic]string
	files: [dynamic]string
	defer delete(dirs)
	defer delete(files)
	for fi in infos {
		if strings.has_prefix(fi.name, ".") {
			continue
		}
		if fi.type == .Directory {
			append(&dirs, fi.name)
		} else {
			lower := strings.to_lower(fi.name, context.temp_allocator)
			for ext in exts {
				if strings.has_suffix(lower, ext) {
					append(&files, fi.name)
					break
				}
			}
		}
	}
	less :: proc(a, b: string) -> bool {
		return strings.compare(strings.to_lower(a, context.temp_allocator), strings.to_lower(b, context.temp_allocator)) < 0
	}
	slice.sort_by(dirs[:], less)
	slice.sort_by(files[:], less)
	for d in dirs {
		append(&gui.entries, Gui_Entry{name = strings.clone_to_cstring(d), is_dir = true})
	}
	for f in files {
		append(&gui.entries, Gui_Entry{name = strings.clone_to_cstring(f), is_dir = false})
	}
}

@(private = "file")
copy_to_path_buf :: proc(s: string) {
	n := min(len(s), len(gui.path_buf) - 1)
	copy(gui.path_buf[:n], s[:n])
	gui.path_buf[n] = 0
}

@(private = "file")
parent_dir :: proc(dir: string) -> string {
	sep := byte('\\') if ODIN_OS == .Windows else byte('/')
	d := dir
	for len(d) > 1 && d[len(d) - 1] == sep {
		d = d[:len(d) - 1]
	}
	i := strings.last_index_byte(d, sep)
	when ODIN_OS == .Windows {
		if i <= 2 && len(d) <= 3 {
			return "" // ドライブ一覧へ
		}
		if i == 2 {
			return d[:3]
		}
	}
	if i <= 0 {
		return "/" if ODIN_OS != .Windows else ""
	}
	return d[:i]
}

@(private = "file")
join_path :: proc(dir, name: string) -> string {
	sep := "\\" when ODIN_OS == .Windows else "/"
	if strings.has_suffix(dir, sep) || dir == "" {
		return fmt.tprintf("%s%s", dir, name)
	}
	return fmt.tprintf("%s%s%s", dir, sep, name)
}

@(private = "file")
choose_file :: proc(path: string) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	switch gui.purpose {
	case .Floppy: open_floppy(i32(gui.drive), cpath, 0)
	case .Hard_Disk: open_hard_disk(0, cpath)
	case .Tape: play_tape(0, cpath)
	}
	delete(gui.last_dir)
	gui.last_dir = strings.clone(gui.cwd if gui.cwd != "" else ".")
	gui.dialog_open = false
}

@(private = "file")
draw_file_dialog :: proc() {
	if !gui.dialog_open {
		return
	}
	vw, vh := f32(sapp.width()) / sapp.dpi_scale(), f32(sapp.height()) / sapp.dpi_scale()
	w, h := min(vw - 20, 560), min(vh - 40, 420)
	igSetNextWindowPos({(vw - w) * 0.5, MENU_HEIGHT_LOGICAL + 8}, COND_APPEARING)
	igSetNextWindowSize({w, h}, COND_APPEARING)
	title: cstring
	switch gui.purpose {
	case .Floppy: title = fmt.ctprintf("%s %d##filedialog", tr("フロッピーを開く: ドライブ", "Open floppy: drive"), gui.drive + 1)
	case .Hard_Disk: title = fmt.ctprintf("%s##filedialog", tr("ハードディスクを開く", "Open hard disk"))
	case .Tape: title = fmt.ctprintf("%s##filedialog", tr("テープを再生", "Play tape"))
	}
	open := true
	if igBegin(title, &open, WINDOW_NO_COLLAPSE | WINDOW_NO_SAVED_SETTINGS) {
		if igButton(tr("上へ", "Up")) {
			set_dir(parent_dir(gui.cwd))
		}
		igSameLine()
		igSetNextItemWidth(igGetContentRegionAvail().x)
		if igInputText("##path", raw_data(gui.path_buf[:]), len(gui.path_buf), INPUT_ENTER_RETURNS_TRUE) {
			typed := string(cstring(raw_data(gui.path_buf[:])))
			if os.is_dir(typed) {
				set_dir(typed)
			} else if os.exists(typed) {
				gui.cwd = strings.clone(parent_dir(typed))
				choose_file(typed)
			}
		}
		igSeparator()
		if igBeginChild("##list", {0, 0}, 0, 0) {
			for e, i in gui.entries {
				label := fmt.ctprintf("%s%s##%d", "[D] " if e.is_dir else "    ", e.name, i)
				if igSelectableEx(label, false, 0, {0, 0}) {
					full := join_path(gui.cwd, string(e.name))
					if e.is_dir {
						set_dir(full)
						break // entriesが入れ替わるので、この回の描画はここまで
					} else {
						choose_file(full)
						break
					}
				}
			}
		}
		igEndChild()
	}
	igEnd()
	if !open {
		gui.dialog_open = false
	}
}
