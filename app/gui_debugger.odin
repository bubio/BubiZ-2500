package bubiz

// デバッガーの画面(アプリ内のコンソール)
// 端末が無い起動(ファイルブラウザやFinderから)でも使えるよう、CSPのデバッガーの入出力を
// 仮想コンソール経由でこのウィンドウとやり取りする。画面は簡易な端末として、
// 復帰(\r)・後退(\b)・改行(\n)と文字色を扱う。

import "core:fmt"
import "core:strings"

import sapp "sokol:app"

DBG_MAX_LINES :: 600
KEY_UP_ARROW :: i32(515)
KEY_DOWN_ARROW :: i32(516)
KEY_ESCAPE :: i32(526)

Dbg_Line :: struct {
	chars: [dynamic]u8,
	attrs: [dynamic]u16,
}

Debugger_Window :: struct {
	open:       bool,
	idle_frames: int, // デバッガーが動いていない状態が続いたフレーム数(終了したらウィンドウを閉じる)
	lines:      [dynamic]Dbg_Line,
	cursor:     int,
	input:      [256]u8,
	history:    [dynamic]string,
	hist_pos:   int,
	refocus:    bool,
	stick:      bool, // 新しい出力があれば一番下へ追従する
}

dbgw: Debugger_Window

// デバッガーを開き、ウィンドウを出す
action_open_debugger :: proc() {
	open_debugger(0)
	dbgw.open = true
	dbgw.idle_frames = 0
	dbgw.refocus = true
	dbgw.stick = true
}

action_close_debugger :: proc() {
	close_debugger()
	dbgw.open = false
}

@(private = "file")
dbg_new_line :: proc() {
	append(&dbgw.lines, Dbg_Line{})
	if len(dbgw.lines) > DBG_MAX_LINES {
		delete(dbgw.lines[0].chars)
		delete(dbgw.lines[0].attrs)
		ordered_remove(&dbgw.lines, 0)
	}
	dbgw.cursor = 0
}

// コアから届いた出力を、簡易端末の画面へ反映する
@(private = "file")
dbg_feed :: proc(attr: u16, text: []u8) {
	if len(dbgw.lines) == 0 {
		dbg_new_line()
	}
	for ch in text {
		line := &dbgw.lines[len(dbgw.lines) - 1]
		switch ch {
		case '\n':
			dbg_new_line()
		case '\r':
			dbgw.cursor = 0
		case '\b':
			if dbgw.cursor > 0 {
				dbgw.cursor -= 1
			}
		case 0x1b:
		// 制御列は使わない(色は属性で受け取る)
		case:
			if ch < 0x20 && ch != '\t' {
				continue
			}
			if dbgw.cursor < len(line.chars) {
				line.chars[dbgw.cursor] = ch
				line.attrs[dbgw.cursor] = attr
			} else {
				append(&line.chars, ch)
				append(&line.attrs, attr)
			}
			dbgw.cursor += 1
		}
	}
}

// 文字属性(青=1 緑=2 赤=4 強調=8)を色にする
@(private = "file")
attr_color :: proc(attr: u16) -> u32 {
	bright := (attr & 8) != 0
	if (attr & 7) == 0 {
		return rgb(230, 230, 230) if bright else rgb(204, 204, 204)
	}
	level := u32(255) if bright else u32(170)
	r := level if (attr & 4) != 0 else 0
	g := level if (attr & 2) != 0 else 0
	b := level if (attr & 1) != 0 else 0
	return rgb(r, g, b)
}

@(private = "file")
send_to_debugger :: proc(s: string) {
	if len(s) > 0 {
		console_write_input(raw_data(transmute([]u8)s), i32(len(s)))
	}
}

draw_debugger_window :: proc() {
	// 出力を取り込む
	got := false
	buf: [4096]u8
	for {
		attr: u16
		n := console_read(&attr, raw_data(buf[:]), len(buf))
		if n <= 0 {
			break
		}
		dbg_feed(attr, buf[:n])
		got = true
	}
	if !dbgw.open {
		return
	}
	// デバッガーが終わったらウィンドウも閉じる(起動直後の数フレームは待つ)
	if debugger_active() {
		dbgw.idle_frames = 0
	} else {
		dbgw.idle_frames += 1
		if dbgw.idle_frames > 60 {
			dbgw.open = false
			return
		}
	}

	vw, vh := f32(sapp.width()) / sapp.dpi_scale(), f32(sapp.height()) / sapp.dpi_scale()
	w, h := min(vw - 20, 640), min(vh - 40, 360)
	igSetNextWindowPos({(vw - w) * 0.5, MENU_HEIGHT_LOGICAL + 16}, COND_APPEARING)
	igSetNextWindowSize({w, h}, COND_APPEARING)
	open := true
	if igBegin("Debugger##debugger", &open, WINDOW_NO_COLLAPSE | WINDOW_NO_SAVED_SETTINGS) {
		focused := igIsWindowFocused(0)
		input_h := f32(-30)
		if igBeginChild("##dbgout", {0, input_h}, 0, 0) {
			for line in dbgw.lines {
				i := 0
				if len(line.chars) == 0 {
					igTextUnformatted("")
				}
				for i < len(line.chars) {
					j := i
					for j < len(line.chars) && line.attrs[j] == line.attrs[i] {
						j += 1
					}
					igPushStyleColor(COL_TEXT, attr_color(line.attrs[i]))
					igTextUnformatted(strings.clone_to_cstring(string(line.chars[i:j]), context.temp_allocator))
					igPopStyleColorEx(1)
					if j < len(line.chars) {
						igSameLineEx(0, 0)
					}
					i = j
				}
			}
			// 末尾を見ているか、新しい出力があれば追従する
			if got && dbgw.stick || igGetScrollY() >= igGetScrollMaxY() - 1 {
				igSetScrollHereY(1.0)
			}
		}
		igEndChild()

		// 入力欄。Enterで1行をデバッガーへ送る
		if dbgw.refocus {
			igSetKeyboardFocusHereEx(0)
			dbgw.refocus = false
		}
		igSetNextItemWidth(f32(w) - 150)
		if igInputText("##dbgin", raw_data(dbgw.input[:]), len(dbgw.input), INPUT_ENTER_RETURNS_TRUE) {
			cmd := string(cstring(raw_data(dbgw.input[:])))
			if cmd != "" && (len(dbgw.history) == 0 || dbgw.history[len(dbgw.history) - 1] != cmd) {
				append(&dbgw.history, strings.clone(cmd))
			}
			dbgw.hist_pos = len(dbgw.history)
			send_to_debugger(cmd)
			send_to_debugger("\r")
			dbgw.input[0] = 0
			dbgw.refocus = true
			dbgw.stick = true
		}
		// 上下キーで履歴をたどる
		if focused && len(dbgw.history) > 0 {
			move := 0
			if igIsKeyPressedEx(KEY_UP_ARROW, true) {move = -1}
			if igIsKeyPressedEx(KEY_DOWN_ARROW, true) {move = 1}
			if move != 0 {
				dbgw.hist_pos = clamp(dbgw.hist_pos + move, 0, len(dbgw.history))
				text := "" if dbgw.hist_pos == len(dbgw.history) else dbgw.history[dbgw.hist_pos]
				n := min(len(text), len(dbgw.input) - 1)
				copy(dbgw.input[:n], text[:n])
				dbgw.input[n] = 0
				dbgw.refocus = true
			}
		}
		igSameLine()
		if igButton("Break") || (focused && igIsKeyPressedEx(KEY_ESCAPE, false)) {
			console_break() // 実行中のCPUを止める(ESC)
		}
		igSameLine()
		if igButton("Close") {
			open = false
		}
	}
	igEnd()
	if !open {
		action_close_debugger()
	}
}
