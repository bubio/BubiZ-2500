package bubiz

// GUI: メニューバー・ステータスバー・ファイル選択・各種ダイアログ(Dear ImGui)
// 構成と項目名は、元のEmuZ-2500(Win32版 res/mz2500.rc)のメニューに合わせている

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"

import sapp "sokol:app"
import simgui "sokol:imgui"
import slog "sokol:log"

MENU_HEIGHT_LOGICAL :: 22 // ImGuiの既定(フォント14px + 余白)でのメニューバーの高さ
STATUS_HEIGHT_LOGICAL :: 24 // ステータスバーの高さ

// 履歴・初期ディレクトリの種別(コアのkindと同じ)
KIND_FLOPPY :: 0
KIND_HARD_DISK :: 1
KIND_TAPE :: 2

Dialog_Kind :: enum {
	Floppy,
	Hard_Disk,
	Tape_Play,
	Tape_Rec,
	Blank_2D,
	Blank_2DD,
	Blank_HD,
}

Gui_Entry :: struct {
	name:   cstring,
	is_dir: bool,
}

// フロッピーを開いた直後に、2つ目のイメージを次のドライブへ入れるかを調べるための保留
Pending_Bank :: struct {
	frames: int,
	drive:  int,
	path:   string,
}

Gui :: struct {
	ja:            bool, // 日本語フォントを読み込めたか
	mouse_y:       f32, // フルスクリーン時にメニューを出すための位置(論理座標)
	menu_open:     bool, // いずれかのメニューが開いている(このフレームで描いた結果)
	menu_was_open: bool, // 前のフレームでメニューが開いていた(フルスクリーンでバーを出し続ける判定に使う)
	// ファイル選択
	dialog_open:   bool,
	kind:          Dialog_Kind,
	drive:         int,
	show_all:      bool,
	cwd:           string,
	entries:       [dynamic]Gui_Entry,
	path_buf:      [1024]u8,
	name_buf:      [256]u8,
	pending:       Pending_Bank,
	// ダイアログ
	about_open:    bool,
	volume_open:   bool,
	volume_saved:  [2][16]int, // 開いた時点の値(キャンセル用)
	// ステータスバー
	fps:           f64,
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
	// デバッガーは端末ではなくこのウィンドウの中で使う(端末の無い起動でも使えるように)
	set_virtual_console(true)
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

// メニューバーを表示するか(フルスクリーンでは、マウスを上端へ寄せたときだけ)
gui_menu_visible :: proc() -> bool {
	return !sapp.is_fullscreen() || gui.mouse_y < f32(MENU_HEIGHT_LOGICAL) || gui.menu_was_open
}

// エミュレーション画面が使える領域の上端と下端の余白(フレームバッファのピクセル)
gui_top_offset :: proc() -> f32 {
	if sapp.is_fullscreen() {
		return 0
	}
	return f32(MENU_HEIGHT_LOGICAL) * sapp.dpi_scale()
}

gui_bottom_offset :: proc() -> f32 {
	if sapp.is_fullscreen() || get_option("show_status_bar") == 0 {
		return 0
	}
	return f32(STATUS_HEIGHT_LOGICAL) * sapp.dpi_scale()
}

tr :: proc(ja, en: cstring) -> cstring {
	return ja if gui.ja else en
}

gui_new_frame :: proc() {
	simgui.new_frame({width = sapp.width(), height = sapp.height(), delta_time = sapp.frame_duration(), dpi_scale = sapp.dpi_scale()})
	gui.menu_was_open = gui.menu_open
	gui.menu_open = false
	check_pending_bank()
	if gui_menu_visible() {
		draw_menu_bar()
	}
	if get_option("show_status_bar") != 0 && !sapp.is_fullscreen() {
		draw_status_bar()
	}
	draw_debugger_window()
	draw_state_dialog()
	draw_file_dialog()
	draw_volume_dialog()
	draw_about()
}

gui_render :: proc() {
	simgui.render()
}

// ---------------------------------------------------------------------------
// メニューの部品
// ---------------------------------------------------------------------------

@(private = "file")
menu :: proc(label: cstring, enabled := true) -> bool {
	open := igBeginMenuEx(label, enabled)
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
opt_get :: proc(key: cstring) -> int {
	return int(get_option(key))
}

@(private = "file")
opt_set :: proc(key: cstring, value: int) {
	set_option(key, i32(value))
}

// 選択肢の1つ(ラジオ)
@(private = "file")
radio :: proc(label: cstring, key: cstring, value: int, enabled := true) {
	if item(label, nil, opt_get(key) == value, enabled) {
		opt_set(key, value)
	}
}

// オン/オフ
@(private = "file")
check :: proc(label: cstring, key: cstring, enabled := true) {
	on := opt_get(key) != 0
	if item(label, nil, on, enabled) {
		opt_set(key, 0 if on else 1)
	}
}

// option_switch の1ビット
@(private = "file")
switch_bit :: proc(label: cstring, bit: uint) {
	v := opt_get("option_switch")
	on := (v & (1 << bit)) != 0
	if item(label, nil, on) {
		opt_set("option_switch", v ~ (1 << bit))
	}
}

// ---------------------------------------------------------------------------
// メニューバー
// ---------------------------------------------------------------------------

@(private = "file")
draw_menu_bar :: proc() {
	if !igBeginMainMenuBar() {
		return
	}
	defer igEndMainMenuBar()

	draw_control_menu()
	for d in 0 ..< FLOPPY_DRIVES {
		draw_floppy_menu(d)
	}
	draw_tape_menu()
	for d in 0 ..< 2 {
		draw_hard_disk_menu(d)
	}
	draw_device_menu()
	draw_host_menu()
}

@(private = "file")
draw_control_menu :: proc() {
	if !menu("Control") {
		return
	}
	defer igEndMenu()
	if item("IPL Reset", "F12") {
		reset()
	}
	if item("Reset", "Ctrl+F12") {
		special_reset()
	}
	igSeparator()
	for p in 0 ..< 5 {
		radio(fmt.ctprintf("CPU x%d", 1 << uint(p)), "cpu_power", p)
	}
	if item("Full Speed", nil, opt_get("full_speed") != 0) {
		opt_set("full_speed", 1 - opt_get("full_speed"))
	}
	check("Drive VM in M1/R/W Cycle", "drive_vm_in_opecode")
	igSeparator()
	if item("Paste") {
		action_paste()
	}
	if item("Stop") {
		stop_auto_key()
	}
	if item("Romaji to Kana", nil, opt_get("romaji_to_kana") != 0) {
		set_romaji_to_kana(opt_get("romaji_to_kana") == 0)
	}
	igSeparator()
	if item("Save / Load State...") {
		action_open_state_dialog()
	}
	igSeparator()
	if item("Debug Main CPU", "Ctrl+D") {
		action_open_debugger()
	}
	if item("Close Debugger") {
		action_close_debugger()
	}
	igSeparator()
	if item("Exit") {
		sapp.request_quit()
	}
}

// ステートスロットの表示。保存済みなら "ファイル名  日時"、未保存なら "(empty)"
@(private = "file")
state_slot_label :: proc(slot: int) -> (label: string, saved: bool) {
	buf: [160]u8
	if state_slot_info(i32(slot), raw_data(buf[:]), len(buf)) {
		return strings.clone(string(cstring(raw_data(buf[:]))), context.temp_allocator), true
	}
	return "(empty)", false
}

@(private = "file")
draw_floppy_menu :: proc(d: int) {
	if !menu(fmt.ctprintf("FD%d", d + 1)) {
		return
	}
	defer igEndMenu()
	inserted := floppy_inserted(i32(d))
	if item("Insert") {
		open_dialog(.Floppy, d)
	}
	if item("Eject") {
		close_floppy(i32(d))
	}
	if item("Insert Blank 2D Disk") {
		open_dialog(.Blank_2D, d)
	}
	if item("Insert Blank 2DD Disk") {
		open_dialog(.Blank_2DD, d)
	}
	igSeparator()
	protected := floppy_protected(i32(d))
	if item("Write Protected", nil, protected, inserted) {
		set_floppy_protected(i32(d), !protected)
	}
	check(fmt.ctprintf("Correct Timing##%d", d), fmt.ctprintf("correct_disk_timing:%d", d))
	check(fmt.ctprintf("Ignore CRC Errors##%d", d), fmt.ctprintf("ignore_disk_crc:%d", d))
	// 複数のイメージを含むD88は、バンクを選べる
	banks := int(floppy_bank_count(i32(d)))
	if banks > 1 {
		igSeparator()
		cur := int(floppy_cur_bank(i32(d)))
		for b in 0 ..< banks {
			name := floppy_bank_name(i32(d), i32(b))
			if item(fmt.ctprintf("%d: %s##bank%d", b + 1, name, b), nil, b == cur) {
				select_floppy_bank(i32(d), i32(b))
			}
		}
	}
	draw_recent(KIND_FLOPPY, d)
}

@(private = "file")
draw_tape_menu :: proc() {
	if !menu("CMT") {
		return
	}
	defer igEndMenu()
	if item("Play") {
		open_dialog(.Tape_Play, 0)
	}
	if item("Rec") {
		open_dialog(.Tape_Rec, 0)
	}
	if item("Eject") {
		close_tape(0)
	}
	igSeparator()
	has := tape_inserted(0)
	if item("Play Button", nil, tape_playing(0), has) {
		tape_button(0, 0)
	}
	if item("Stop Button", nil, false, has) {
		tape_button(0, 1)
	}
	if item("Fast Forward", nil, false, has) {
		tape_button(0, 2)
	}
	if item("Fast Rewind", nil, false, has) {
		tape_button(0, 3)
	}
	igSeparator()
	check("Waveform Shaper", "wave_shaper:0")
	draw_recent(KIND_TAPE, 0)
}

@(private = "file")
draw_hard_disk_menu :: proc(d: int) {
	if !menu(fmt.ctprintf("HD%d", d + 1)) {
		return
	}
	defer igEndMenu()
	if item("Mount") {
		open_dialog(.Hard_Disk, d)
	}
	if item("Unmount") {
		close_hard_disk(i32(d))
	}
	if item("Mount Blank 20MB Disk") {
		open_dialog(.Blank_HD, d)
	}
	draw_recent(KIND_HARD_DISK, d)
}

// 履歴(最大8件)。選ぶとそのファイルを開き、先頭へ移す
@(private = "file")
draw_recent :: proc(kind, drive: int) {
	any_recent := false
	for i in 0 ..< 8 {
		if string(recent_path(i32(kind), i32(drive), i32(i))) != "" {
			any_recent = true
			break
		}
	}
	if !any_recent {
		return
	}
	igSeparator()
	for i in 0 ..< 8 {
		path := recent_path(i32(kind), i32(drive), i32(i))
		if string(path) == "" {
			continue
		}
		if item(fmt.ctprintf("%d  %s##recent%d", i + 1, path, i)) {
			open_media(kind, drive, string(path), false)
			break // 履歴の並びが変わるので、この回はここまで
		}
	}
}

@(private = "file")
draw_device_menu :: proc() {
	if !menu("Device") {
		return
	}
	defer igEndMenu()
	if menu("Boot") {
		radio("MZ-2500", "boot_mode", 0)
		radio("MZ-2000", "boot_mode", 1)
		radio("MZ-80B", "boot_mode", 2)
		igEndMenu()
	}
	if menu("Option") {
		switch_bit("MZ-1E26 (Voice Comm.)", 8)
		switch_bit("MZ-1E30 (SASI I/F)", 9)
		switch_bit("MZ-1E32 (Parallel I/F)", 10)
		switch_bit("MZ-1R12 (CMOS RAM)", 11)
		switch_bit("MZ-1R13 (Kanji ROM)", 12)
		switch_bit("MZ-1R37 (EMM)", 13)
		switch_bit("WIZnet W3100A (NIC)", 14)
		igEndMenu()
	}
	if menu("Sound") {
		switch_bit("CMU-800", 0)
		switch_bit("CMU-800 Tempo +10", 1)
		switch_bit("CMU-800 Tempo -10", 2)
		switch_bit("CMU-800 Tempo +5", 3)
		switch_bit("CMU-800 Tempo -5", 4)
		switch_bit("CMU-800 Tempo +1", 5)
		switch_bit("CMU-800 Tempo -1", 6)
		switch_bit("CMU-800 Tempo 160", 7)
		igSeparator()
		check("Play FDD Noise", "sound_noise_fdd")
		check("Play CMT Noise", "sound_noise_cmt")
		check("Play CMT Signal", "sound_tape_signal")
		check("Play CMT Voice", "sound_tape_voice")
		igEndMenu()
	}
	if menu("Display") {
		radio("400 Lines, Analog", "monitor_type", 0)
		radio("400 Lines, Digital", "monitor_type", 1)
		radio("200 Lines, Analog", "monitor_type", 2)
		radio("200 Lines, Digital", "monitor_type", 3)
		igSeparator()
		check("Scanline", "scan_line")
		igEndMenu()
	}
	if menu("Printer") {
		radio("Write Printer to File", "printer_type", 0)
		radio("MZ-1P17", "printer_type", 1)
		radio("PC-PR201", "printer_type", 2, false)
		radio("None", "printer_type", 3)
		igEndMenu()
	}
}

@(private = "file")
draw_host_menu :: proc() {
	if !menu("Host") {
		return
	}
	defer igEndMenu()
	// 動画の録画は未実装
	item("Rec Movie 60fps", nil, false, false)
	item("Rec Movie 30fps", nil, false, false)
	item("Rec Movie 15fps", nil, false, false)
	if item("Rec Sound") {
		ensure_dir(fe.opt.sound_dir if fe.opt.sound_dir != "" else default_sound_dir())
		start_record_sound()
	}
	if item("Stop") {
		stop_record_sound()
	}
	if item("Capture Screen", "Ctrl+S") {
		action_screenshot()
	}
	igSeparator()
	if menu("Screen") {
		// 元の実装と同じ並びと表記
		for scale, idx in WINDOW_SCALES {
			label := fmt.ctprintf("Window x%s", scale_label(scale))
			if item(label, nil, !sapp.is_fullscreen() && opt_get("window_mode") == idx) {
				set_window_scale(idx)
			}
		}
		if item("Fullscreen", "F11", false) {
			sapp.toggle_fullscreen()
		}
		igSeparator()
		radio("Window: Aspect Ratio 640:400", "window_stretch_type", 0)
		radio("Window: Aspect Ratio 640:480", "window_stretch_type", 1)
		igSeparator()
		radio("Fullscreen: Dot By Dot", "fullscreen_stretch_type", 0)
		radio("Fullscreen: Stretch (Aspect Ratio 640:400)", "fullscreen_stretch_type", 1)
		radio("Fullscreen: Stretch (Aspect Ratio 640:480)", "fullscreen_stretch_type", 2)
		radio("Fullscreen: Stretch (Fill)", "fullscreen_stretch_type", 3)
		igSeparator()
		radio("Rotate 0deg", "rotate_type", 0)
		radio("Rotate +90deg", "rotate_type", 1)
		radio("Rotate 180deg", "rotate_type", 2)
		radio("Rotate -90deg", "rotate_type", 3)
		igEndMenu()
	}
	if menu("Filter") {
		radio("RGB Filter", "filter_type", 1)
		radio("None", "filter_type", 0)
		igEndMenu()
	}
	if menu("Sound") {
		for hz, i in SOUND_RATES {
			radio(fmt.ctprintf("%dHz", hz), "sound_frequency", i)
		}
		igSeparator()
		for ms, i in ([]int{50, 100, 200, 300, 400}) {
			radio(fmt.ctprintf("%dmsec", ms), "sound_latency", i)
		}
		igSeparator()
		if item("Realtime Mix", nil, opt_get("sound_strict_rendering") != 0) {
			opt_set("sound_strict_rendering", 1)
		}
		if item("Light Weight Mix", nil, opt_get("sound_strict_rendering") == 0) {
			opt_set("sound_strict_rendering", 0)
		}
		igSeparator()
		if item("Volume") {
			open_volume_dialog()
		}
		igEndMenu()
	}
	if menu("Input") {
		// ホストのジョイスティックは未対応のため、キーボードで代用する
		radio("Joystick #1 (Keyboard)", "keyboard_joystick", 1)
		radio("Joystick #2 (Keyboard)", "keyboard_joystick", 2)
		item("Joystick To Keyboard", nil, false, false)
		igSeparator()
		if item("Joystick Off", nil, opt_get("keyboard_joystick") == 0) {
			opt_set("keyboard_joystick", 0)
		}
		igEndMenu()
	}
	igSeparator()
	check("Wait Vsync", "wait_vsync")
	check("Show Status Bar", "show_status_bar")
	igSeparator()
	if item("About BubiZ-2500") {
		gui.about_open = true
	}
}

// ---------------------------------------------------------------------------
// 貼り付け(自動キー入力)
// ---------------------------------------------------------------------------

// クリップボードの文字列を、ASCIIと半角カナのバイト列にして送る
@(private = "file")
action_paste :: proc() {
	text := string(sapp.get_clipboard_string())
	if text == "" {
		return
	}
	buf: [dynamic]u8
	defer delete(buf)
	for r in text {
		switch {
		case r < 0x80:
			append(&buf, u8(r))
		case r >= 0xFF61 && r <= 0xFF9F: // 半角カナ → Shift_JISの0xA1〜0xDF
			append(&buf, u8(r - 0xFF61 + 0xA1))
		}
	}
	if len(buf) > 0 {
		paste_text(raw_data(buf), i32(len(buf)))
	}
}

// ---------------------------------------------------------------------------
// ステータスバー
// ---------------------------------------------------------------------------

@(private = "file")
base_name :: proc(path: string) -> string {
	i := max(strings.last_index_byte(path, '/'), strings.last_index_byte(path, '\\'))
	return path[i + 1:]
}

// ImGuiColの番号
COL_TEXT :: c_int(0)
COL_WINDOW_BG :: c_int(2)
COL_BORDER :: c_int(5)

// ABGRの色(ImU32)
rgb :: proc(r, g, b: u32) -> u32 {
	return 0xFF000000 | (b << 16) | (g << 8) | r
}

// アクセスランプ(元の実装のビットマップと同じ 14x12 の角丸)。0:消灯 1:点灯(赤) 2:点灯(緑)
@(private = "file")
draw_led :: proc(state: int) {
	size := Im_Vec2{14, 12}
	pos := igGetCursorScreenPos()
	list := igGetWindowDrawList()
	fill: u32
	switch state {
	case 1: fill = rgb(255, 0, 0)
	case 2: fill = rgb(65, 216, 77)
	case: fill = rgb(96, 0, 0)
	}
	ImDrawList_AddRectFilledEx(list, pos, {pos.x + size.x, pos.y + size.y}, rgb(64, 0, 0), 3, 0)
	ImDrawList_AddRectFilledEx(list, {pos.x + 1, pos.y + 1}, {pos.x + size.x - 1, pos.y + size.y - 1}, fill, 2, 0)
	igDummy(size)
}

// 元のEmuZ-2500のステータスバーと同じ表示: "FD:"と4つのランプ、"HD:"と2つのランプ、"CMT:"とテープの状態
@(private = "file")
draw_status_bar :: proc() {
	vw, vh := f32(sapp.width()) / sapp.dpi_scale(), f32(sapp.height()) / sapp.dpi_scale()
	igSetNextWindowPos({0, vh - STATUS_HEIGHT_LOGICAL}, 0)
	igSetNextWindowSize({vw, STATUS_HEIGHT_LOGICAL}, 0)
	flags := WINDOW_NO_TITLE_BAR | WINDOW_NO_RESIZE | WINDOW_NO_MOVE | WINDOW_NO_SCROLLBAR | WINDOW_NO_SAVED_SETTINGS | WINDOW_NO_BRING_TO_FRONT | WINDOW_NO_NAV
	// Windowsの標準のステータスバーに合わせた、明るい灰色の背景と黒い文字
	igPushStyleColor(COL_WINDOW_BG, rgb(240, 240, 240))
	igPushStyleColor(COL_TEXT, rgb(0, 0, 0))
	igPushStyleColor(COL_BORDER, rgb(160, 160, 160))
	defer igPopStyleColorEx(3)
	if igBegin("##statusbar", nil, flags) {
		fd_access := floppy_accessed()
		fd_color := floppy_indicator_color()
		igTextUnformatted("FD:")
		for d in 0 ..< FLOPPY_DRIVES {
			igSameLine()
			state := 0
			if (fd_access >> uint(d)) & 1 != 0 {
				state = 2 if (fd_color >> uint(d)) & 1 != 0 else 1
			}
			draw_led(state)
		}
		igSameLine()
		igTextUnformatted("  HD:")
		hd_access := hard_disk_accessed()
		for d in 0 ..< 2 {
			igSameLine()
			draw_led(1 if (hd_access >> uint(d)) & 1 != 0 else 0)
		}
		igSameLine()
		igTextUnformatted(fmt.ctprintf("  CMT: %s", tape_message(0)))
	}
	igEnd()
}

// ---------------------------------------------------------------------------
// ウィンドウサイズ
// ---------------------------------------------------------------------------

// ウィンドウの倍率の選択肢(Window x1 / x1.5 / x2 / x3)。設定window_modeはこの添字
WINDOW_SCALES := [4]f32{1, 1.5, 2, 3}

@(private = "file")
scale_label :: proc(scale: f32) -> string {
	if scale == f32(int(scale)) {
		return fmt.tprintf("%d", int(scale))
	}
	return fmt.tprintf("%.1f", scale)
}

// 倍率の選択肢idxになるようにウィンドウの大きさを変える
@(private = "file")
set_window_scale :: proc(idx: int) {
	if sapp.is_fullscreen() {
		return
	}
	set_option("window_mode", i32(idx))
	w, h := window_size_for_scale(WINDOW_SCALES[idx])
	native_resize_window(w, h)
}

// 倍率nのときのウィンドウの内側の大きさ(論理座標)
window_size_for_scale :: proc(n: f32) -> (w, h: i32) {
	base_h := 480 if opt_get("window_stretch_type") == 1 else 400
	sw, sh := 640, base_h
	if opt_get("rotate_type") == 1 || opt_get("rotate_type") == 3 {
		sw, sh = sh, sw
	}
	status := 0
	if get_option("show_status_bar") != 0 {
		status = STATUS_HEIGHT_LOGICAL
	}
	return i32(f32(sw) * n), i32(f32(sh) * n) + MENU_HEIGHT_LOGICAL + i32(status)
}

// ---------------------------------------------------------------------------
// メディアを開く
// ---------------------------------------------------------------------------

// 履歴に加えて開く。fromRecent=trueのときは、履歴の並び替えだけ(開くのは同じ)
@(private = "file")
open_media :: proc(kind, drive: int, path: string, new_media: bool) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	add_recent(i32(kind), i32(drive), cpath)
	switch kind {
	case KIND_FLOPPY:
		open_floppy(i32(drive), cpath, 0)
		// 複数のイメージを含むD88は、偶数ドライブなら次のドライブへ2つ目を入れる(元の実装と同じ)
		if drive % 2 == 0 && drive + 1 < FLOPPY_DRIVES {
			delete(gui.pending.path)
			gui.pending = Pending_Bank{frames = 3, drive = drive, path = strings.clone(path)}
		}
	case KIND_HARD_DISK:
		open_hard_disk(i32(drive), cpath)
	case KIND_TAPE:
		play_tape(0, cpath)
	}
	remember_dir(kind, path)
}

@(private = "file")
remember_dir :: proc(kind: int, path: string) {
	sep := max(strings.last_index_byte(path, '/'), strings.last_index_byte(path, '\\'))
	if sep > 0 {
		set_initial_dir(i32(kind), strings.clone_to_cstring(path[:sep], context.temp_allocator))
	}
}

// open_floppyは非同期のため、バンク数が分かるまで数フレーム待ってから次のドライブへ入れる
@(private = "file")
check_pending_bank :: proc() {
	if gui.pending.frames <= 0 {
		return
	}
	gui.pending.frames -= 1
	if gui.pending.frames == 0 {
		d := gui.pending.drive
		if floppy_bank_count(i32(d)) > 1 {
			open_floppy(i32(d + 1), strings.clone_to_cstring(gui.pending.path, context.temp_allocator), 1)
		}
		delete(gui.pending.path)
		gui.pending.path = ""
	}
}

// ---------------------------------------------------------------------------
// ボリューム
// ---------------------------------------------------------------------------

@(private = "file")
open_volume_dialog :: proc() {
	n := min(int(sound_device_count()), 16)
	for i in 0 ..< n {
		gui.volume_saved[0][i] = opt_get(fmt.ctprintf("sound_volume_l:%d", i))
		gui.volume_saved[1][i] = opt_get(fmt.ctprintf("sound_volume_r:%d", i))
	}
	gui.volume_open = true
}

@(private = "file")
draw_volume_dialog :: proc() {
	if !gui.volume_open {
		return
	}
	igSetNextWindowPos({20, MENU_HEIGHT_LOGICAL + 8}, COND_APPEARING)
	igSetNextWindowSize({420, 0}, COND_APPEARING)
	open := true
	if igBegin("Volume##volume", &open, WINDOW_NO_COLLAPSE | WINDOW_NO_SAVED_SETTINGS | WINDOW_ALWAYS_AUTO_RESIZE) {
		n := min(int(sound_device_count()), 16)
		igSeparatorText("Left / Right (dB)")
		for i in 0 ..< n {
			for ch in 0 ..< 2 {
				key := fmt.ctprintf("sound_volume_%s:%d", "l" if ch == 0 else "r", i)
				v := c_int(opt_get(key))
				igSetNextItemWidth(150)
				if igSliderInt(fmt.ctprintf("##v%d_%d", i, ch), &v, -40, 0) {
					opt_set(key, int(v))
				}
				igSameLine()
			}
			igTextUnformatted(sound_device_name(i32(i)))
		}
		igSeparator()
		if igButton("OK") {
			gui.volume_open = false
		}
		igSameLine()
		if igButton("Cancel") {
			for i in 0 ..< n {
				opt_set(fmt.ctprintf("sound_volume_l:%d", i), gui.volume_saved[0][i])
				opt_set(fmt.ctprintf("sound_volume_r:%d", i), gui.volume_saved[1][i])
			}
			gui.volume_open = false
		}
		igSameLine()
		if igButton("Reset") {
			for i in 0 ..< n {
				opt_set(fmt.ctprintf("sound_volume_l:%d", i), 0)
				opt_set(fmt.ctprintf("sound_volume_r:%d", i), 0)
			}
		}
	}
	igEnd()
	if !open {
		gui.volume_open = false
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
		igTextUnformatted("SHARP MZ-2500 emulator")
		igSeparator()
		igTextUnformatted("Core: Common Source Code Project (EmuZ-2500)")
		igTextUnformatted("Odin / Sokol / Dear ImGui")
		igSeparator()
		if igButton("OK") {
			igCloseCurrentPopup()
		}
		igEndPopup()
	}
}

// ---------------------------------------------------------------------------
// ファイル選択(開く / 保存)
// ---------------------------------------------------------------------------

@(private = "file")
c_int :: i32

@(private = "file")
is_save_dialog :: proc(k: Dialog_Kind) -> bool {
	return k == .Tape_Rec || k == .Blank_2D || k == .Blank_2DD || k == .Blank_HD
}

@(private = "file")
dialog_kind_index :: proc(k: Dialog_Kind) -> int {
	switch k {
	case .Floppy, .Blank_2D, .Blank_2DD: return KIND_FLOPPY
	case .Hard_Disk, .Blank_HD: return KIND_HARD_DISK
	case .Tape_Play, .Tape_Rec: return KIND_TAPE
	}
	return KIND_FLOPPY
}

@(private = "file")
FLOPPY_EXTS := []string{".d88", ".d8e", ".d77", ".1dd", ".td0", ".imd", ".dsk", ".nfd", ".fdi", ".hdm", ".hd5", ".hd4", ".hdb", ".dd9", ".dd6", ".tfd", ".xdf", ".2d", ".sf7", ".img", ".ima", ".vfd"}
@(private = "file")
BLANK_FLOPPY_EXTS := []string{".d88", ".d77"}
@(private = "file")
HDD_EXTS := []string{".hdd", ".hdi", ".nhd", ".thd", ".dat"}
@(private = "file")
TAPE_PLAY_EXTS := []string{".wav", ".cas", ".mzt", ".mzf", ".m12", ".gz"}
@(private = "file")
TAPE_REC_EXTS := []string{".wav", ".cas"}

@(private = "file")
dialog_extensions :: proc(k: Dialog_Kind) -> []string {
	switch k {
	case .Floppy: return FLOPPY_EXTS
	case .Blank_2D, .Blank_2DD: return BLANK_FLOPPY_EXTS
	case .Hard_Disk, .Blank_HD: return HDD_EXTS
	case .Tape_Play: return TAPE_PLAY_EXTS
	case .Tape_Rec: return TAPE_REC_EXTS
	}
	return nil
}

@(private = "file")
open_dialog :: proc(kind: Dialog_Kind, drive: int) {
	gui.kind = kind
	gui.drive = drive
	gui.dialog_open = true
	start := string(initial_dir(i32(dialog_kind_index(kind))))
	if start == "" || !os.is_dir(start) {
		start = os.get_env("HOME", context.temp_allocator)
		when ODIN_OS == .Windows {
			if start == "" {start = os.get_env("USERPROFILE", context.temp_allocator)}
		}
	}
	set_dir(start if start != "" else ".")
	// 保存の既定のファイル名(日時)
	if is_save_dialog(kind) {
		ext := ".d88"
		#partial switch kind {
		case .Blank_HD: ext = ".hdi"
		case .Tape_Rec: ext = ".wav"
		}
		stamp := fmt.tprintf("%s%s", date_stamp(), ext)
		n := min(len(stamp), len(gui.name_buf) - 1)
		copy(gui.name_buf[:n], stamp[:n])
		gui.name_buf[n] = 0
	}
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
	// dirは古いgui.cwdの一部を指していることがある(「上へ」など)ので、解放する前に複製する
	new_cwd := strings.clone(dir)
	clear_entries()
	delete(gui.cwd)
	gui.cwd = new_cwd
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

	exts := dialog_extensions(gui.kind)
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
		} else if gui.show_all {
			append(&files, fi.name)
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

// 選んだファイルに対する処理
@(private = "file")
choose_file :: proc(path: string) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	switch gui.kind {
	case .Floppy:
		open_media(KIND_FLOPPY, gui.drive, path, false)
	case .Hard_Disk:
		open_media(KIND_HARD_DISK, gui.drive, path, false)
	case .Tape_Play:
		open_media(KIND_TAPE, 0, path, false)
	case .Tape_Rec:
		add_recent(KIND_TAPE, 0, cpath)
		rec_tape(0, cpath)
		remember_dir(KIND_TAPE, path)
	case .Blank_2D, .Blank_2DD:
		if create_blank_floppy(cpath, 0 if gui.kind == .Blank_2D else 1) {
			open_media(KIND_FLOPPY, gui.drive, path, true)
		}
	case .Blank_HD:
		if create_blank_hard_disk(cpath) {
			open_media(KIND_HARD_DISK, gui.drive, path, true)
		}
	}
	gui.dialog_open = false
}

// 拡張子が無ければ足す
@(private = "file")
with_default_ext :: proc(name: string) -> string {
	if strings.contains_rune(name, '.') {
		return name
	}
	ext := ".d88"
	#partial switch gui.kind {
	case .Blank_HD: ext = ".hdi"
	case .Tape_Rec: ext = ".wav"
	}
	return fmt.tprintf("%s%s", name, ext)
}

@(private = "file")
dialog_title :: proc() -> cstring {
	switch gui.kind {
	case .Floppy: return fmt.ctprintf("Floppy Disk: FD%d##filedialog", gui.drive + 1)
	case .Hard_Disk: return fmt.ctprintf("Hard Disk: HD%d##filedialog", gui.drive + 1)
	case .Tape_Play: return "Play Tape##filedialog"
	case .Tape_Rec: return "Record Tape##filedialog"
	case .Blank_2D: return fmt.ctprintf("New Blank 2D Disk: FD%d##filedialog", gui.drive + 1)
	case .Blank_2DD: return fmt.ctprintf("New Blank 2DD Disk: FD%d##filedialog", gui.drive + 1)
	case .Blank_HD: return fmt.ctprintf("New Blank 20MB Disk: HD%d##filedialog", gui.drive + 1)
	}
	return "File##filedialog"
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
	open := true
	save := is_save_dialog(gui.kind)
	if igBegin(dialog_title(), &open, WINDOW_NO_COLLAPSE | WINDOW_NO_SAVED_SETTINGS) {
		if igButton("Up") {
			set_dir(parent_dir(gui.cwd))
		}
		igSameLine()
		igSetNextItemWidth(igGetContentRegionAvail().x)
		if igInputText("##path", raw_data(gui.path_buf[:]), len(gui.path_buf), INPUT_ENTER_RETURNS_TRUE) {
			typed := string(cstring(raw_data(gui.path_buf[:])))
			if os.is_dir(typed) {
				set_dir(typed)
			} else if !save && os.exists(typed) {
				choose_file(typed)
			}
		}
		// 一覧に出す拡張子の絞り込み
		all := gui.show_all
		igTextUnformatted("Show all files:")
		igSameLine()
		if igButton("Off" if all else "On") {
			gui.show_all = !gui.show_all
			set_dir(gui.cwd)
		}
		igSeparator()
		list_h := f32(-34) if save else f32(-4)
		if igBeginChild("##list", {0, list_h}, 0, 0) {
			for e, i in gui.entries {
				label := fmt.ctprintf("%s%s##%d", "[D] " if e.is_dir else "    ", e.name, i)
				if igSelectableEx(label, false, 0, {0, 0}) {
					full := join_path(gui.cwd, string(e.name))
					if e.is_dir {
						set_dir(full)
					} else if save {
						n := min(len(e.name), len(gui.name_buf) - 1)
						copy(gui.name_buf[:n], string(e.name)[:n])
						gui.name_buf[n] = 0
					} else {
						choose_file(full)
					}
					break // entriesが入れ替わるので、この回の描画はここまで
				}
			}
		}
		igEndChild()
		if save {
			igSetNextItemWidth(igGetContentRegionAvail().x - 70)
			igInputText("##name", raw_data(gui.name_buf[:]), len(gui.name_buf), 0)
			igSameLine()
			if igButton("Save") {
				name := string(cstring(raw_data(gui.name_buf[:])))
				if name != "" {
					choose_file(join_path(gui.cwd, with_default_ext(name)))
				}
			}
		}
	}
	igEnd()
	if !open {
		gui.dialog_open = false
	}
}
