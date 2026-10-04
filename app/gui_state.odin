package bubiz

// ステートの保存・復元ダイアログ(BubiC-8801MAと同じ構成)
// 10個のスロットを、サムネイルと保存日時つきの一覧にして、Save / Load / Delete を選べる。
// ダブルクリックで、そのスロットを復元する。

import "core:fmt"
import "core:image/png"
import "core:os"
import "core:strings"

import sapp "sokol:app"
import sg "sokol:gfx"
import simgui "sokol:imgui"

STATE_SLOTS :: 10
THUMB_W :: 256
THUMB_H :: 160

State_Dialog :: struct {
	open:       bool,
	selected:   int,
	refresh_in: int, // 保存は非同期のため、数フレーム待ってからサムネイルを読み直す
	refresh_again: bool, // 書き込みが遅れた場合に備えて、もう一度読み直す
	images:     [STATE_SLOTS]sg.Image,
	views:      [STATE_SLOTS]sg.View,
	loaded:     [STATE_SLOTS]bool,
}

state_dlg: State_Dialog

action_open_state_dialog :: proc() {
	state_dlg.open = true
	state_dlg.selected = 0
	state_refresh_thumbnails()
}

@(private = "file")
state_release_thumbnails :: proc() {
	for i in 0 ..< STATE_SLOTS {
		if state_dlg.loaded[i] {
			sg.destroy_view(state_dlg.views[i])
			sg.destroy_image(state_dlg.images[i])
			state_dlg.loaded[i] = false
		}
	}
}

@(private = "file")
state_close :: proc() {
	state_dlg.open = false
	state_release_thumbnails()
}

// 各スロットのサムネイル(ステートのパス + ".png")を読み直す
@(private = "file")
state_refresh_thumbnails :: proc() {
	state_release_thumbnails()
	for i in 0 ..< STATE_SLOTS {
		path := fmt.tprintf("%s.png", state_slot_path(i32(i)))
		if !os.exists(path) {
			continue
		}
		img, err := png.load_from_file(path, {.alpha_add_if_missing}, context.temp_allocator)
		if err != nil || img == nil {
			continue
		}
		pixels := img.pixels.buf[:]
		if len(pixels) < img.width * img.height * 4 {
			continue
		}
		state_dlg.images[i] = sg.make_image(
			{
				width = i32(img.width),
				height = i32(img.height),
				pixel_format = .RGBA8,
				data = {mip_levels = {0 = {ptr = raw_data(pixels), size = uint(img.width * img.height * 4)}}},
			},
		)
		state_dlg.views[i] = sg.make_view({texture = {image = state_dlg.images[i]}})
		state_dlg.loaded[i] = true
	}
}

// "mz2500.sta1  2026-10-04 06:54:57" から日時を取り出して "2026/10/04 06:54:57" にする
@(private = "file")
state_time_label :: proc(slot: int) -> (label: string, exists: bool) {
	buf: [160]u8
	if !state_slot_info(i32(slot), raw_data(buf[:]), len(buf)) {
		return "(No Data)", false
	}
	s := string(cstring(raw_data(buf[:])))
	if len(s) < 19 {
		return s, true
	}
	t, _ := strings.replace_all(s[len(s) - 19:], "-", "/", context.temp_allocator)
	return t, true
}

draw_state_dialog :: proc() {
	if !state_dlg.open {
		return
	}
	if state_dlg.refresh_in > 0 {
		state_dlg.refresh_in -= 1
		if state_dlg.refresh_in == 0 {
			state_refresh_thumbnails()
			if state_dlg.refresh_again {
				state_dlg.refresh_again = false
				state_dlg.refresh_in = 90
			}
		}
	}
	vw, vh := f32(sapp.width()) / sapp.dpi_scale(), f32(sapp.height()) / sapp.dpi_scale()
	dlg_w, dlg_h := f32(480), f32(360)
	igSetNextWindowPosEx({vw * 0.5, vh * 0.5}, COND_APPEARING, {0.5, 0.5})
	igSetNextWindowSize({dlg_w, dlg_h}, COND_APPEARING)
	igSetNextWindowSizeConstraints({dlg_w, dlg_h}, {1e9, 1e9}, nil, nil)
	open := true
	if !igBegin("Save / Load State##statedlg", &open, WINDOW_NO_COLLAPSE | WINDOW_NO_SAVED_SETTINGS) {
		igEnd()
		if !open {
			state_close()
		}
		return
	}
	gui.menu_open = true // ダイアログ中はエミュレーターへキー入力を渡さない

	btn_w := f32(100)
	avail := igGetContentRegionAvail()
	list_w := avail.x - btn_w - 12
	list_h := avail.y - igGetFrameHeightWithSpacing()
	row_h := f32(THUMB_H + 6)

	exists: [STATE_SLOTS]bool
	times: [STATE_SLOTS]string
	for i in 0 ..< STATE_SLOTS {
		times[i], exists[i] = state_time_label(i)
	}

	// 左: スロットの一覧
	loaded_now := false
	if igBeginChild("##state_list", {list_w, list_h}, 1, 0) {
		for i in 0 ..< STATE_SLOTS {
			igPushIDInt(i32(i))
			row_pos := igGetCursorScreenPos()
			if igSelectableEx("##row", state_dlg.selected == i, 1 << 4, {0, row_h}) {
				state_dlg.selected = i
			}
			if igIsItemHovered(0) && igIsMouseDoubleClicked(0) {
				state_dlg.selected = i
				if exists[i] {
					load_state_slot(i32(i))
					loaded_now = true
				}
			}
			list := igGetWindowDrawList()
			tmin := Im_Vec2{row_pos.x + 4, row_pos.y + 3}
			tmax := Im_Vec2{tmin.x + THUMB_W, tmin.y + THUMB_H}
			if state_dlg.loaded[i] {
				ImDrawList_AddImage(list, {nil, simgui.imtextureid(state_dlg.views[i])}, tmin, tmax)
			} else {
				ImDrawList_AddRectFilled(list, tmin, tmax, rgb(40, 40, 40))
			}
			ImDrawList_AddRect(list, tmin, tmax, rgb(160, 160, 160))

			// 左上にスロット番号
			slot_label := strings.clone_to_cstring(fmt.tprintf("Slot %d", i), context.temp_allocator)
			ls := igCalcTextSize(slot_label)
			ImDrawList_AddRectFilled(list, tmin, {tmin.x + ls.x + 12, tmin.y + ls.y + 6}, 0xB4000000)
			ImDrawList_AddText(list, {tmin.x + 6, tmin.y + 3}, rgb(255, 255, 255), slot_label)

			// 下の帯に保存日時
			time_text := strings.clone_to_cstring(times[i], context.temp_allocator)
			ts := igCalcTextSize(time_text)
			strip_h := ts.y + 6
			ImDrawList_AddRectFilled(list, {tmin.x, tmax.y - strip_h}, tmax, 0xB4000000)
			ImDrawList_AddText(list, {tmax.x - ts.x - 6, tmax.y - strip_h + 3}, rgb(255, 255, 255), time_text)
			igPopID()
		}
	}
	igEndChild()

	// 右: 操作ボタン
	igSameLine()
	if igBeginChild("##state_actions", {btn_w, list_h}, 0, 0) {
		sel := state_dlg.selected
		if igButtonEx("Save", {-1, 0}) {
			save_state_slot(i32(sel))
			state_dlg.refresh_in = 30
			state_dlg.refresh_again = true
		}
		igBeginDisabled(!exists[sel])
		if igButtonEx("Load", {-1, 0}) {
			load_state_slot(i32(sel))
			loaded_now = true
		}
		if igButtonEx("Delete", {-1, 0}) {
			delete_state_slot(i32(sel))
			state_refresh_thumbnails()
		}
		igEndDisabled()
	}
	igEndChild()

	igSeparator()
	if igButtonEx("Close", {100, 0}) {
		open = false
	}
	igEnd()
	if !open || loaded_now {
		state_close()
	}
}
