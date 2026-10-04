package bubiz

// Dear ImGui(dcimgui)のうち、メニューとダイアログに使う関数の最小限のバインディング

import "core:c"

when ODIN_OS == .Windows {
	foreign import imgui_native {
		"system:bubiz_imgui.lib",
	}
} else when ODIN_OS == .Darwin {
	foreign import imgui_native {
		"system:bubiz_imgui",
		"system:c++",
	}
} else {
	foreign import imgui_native {
		"system:bubiz_imgui",
		"system:stdc++",
	}
}

// ImTextureRef(1.92以降のテクスチャ参照)。どちらか片方だけを使う
Im_Texture_Ref :: struct {
	tex_data: rawptr,
	tex_id:   u64,
}

Im_Vec2 :: struct {
	x, y: f32,
}

// ImGuiWindowFlags
WINDOW_NO_TITLE_BAR :: c.int(1 << 0)
WINDOW_NO_RESIZE :: c.int(1 << 1)
WINDOW_NO_MOVE :: c.int(1 << 2)
WINDOW_NO_SCROLLBAR :: c.int(1 << 3)
WINDOW_NO_BRING_TO_FRONT :: c.int(1 << 13)
WINDOW_NO_NAV :: c.int((1 << 16) | (1 << 17))
WINDOW_NO_COLLAPSE :: c.int(1 << 5)
WINDOW_ALWAYS_AUTO_RESIZE :: c.int(1 << 6)
WINDOW_NO_SAVED_SETTINGS :: c.int(1 << 8)

// ImGuiCond
COND_APPEARING :: c.int(1 << 3)

// ImGuiInputTextFlags
INPUT_ENTER_RETURNS_TRUE :: c.int(1 << 6)

@(default_calling_convention = "c")
foreign imgui_native {
	igBegin :: proc(name: cstring, p_open: ^bool, flags: c.int) -> bool ---
	igEnd :: proc() ---
	igBeginChild :: proc(str_id: cstring, size: Im_Vec2, child_flags: c.int, window_flags: c.int) -> bool ---
	igEndChild :: proc() ---
	igSetNextWindowPos :: proc(pos: Im_Vec2, cond: c.int) ---
	igSetNextWindowSize :: proc(size: Im_Vec2, cond: c.int) ---
	igSetNextWindowPosEx :: proc(pos: Im_Vec2, cond: c.int, pivot: Im_Vec2) ---
	igSetNextWindowSizeConstraints :: proc(size_min, size_max: Im_Vec2, custom_callback: rawptr, custom_callback_data: rawptr) ---
	igSetNextItemWidth :: proc(w: f32) ---
	igSeparator :: proc() ---
	igSameLine :: proc() ---
	igSameLineEx :: proc(offset_from_start_x: f32, spacing: f32) ---
	igIsKeyPressedEx :: proc(key: c.int, repeat: bool) -> bool ---
	igIsWindowFocused :: proc(flags: c.int) -> bool ---
	igSetScrollHereY :: proc(center_y_ratio: f32) ---
	igGetScrollY :: proc() -> f32 ---
	igGetScrollMaxY :: proc() -> f32 ---
	igSetKeyboardFocusHereEx :: proc(offset: c.int) ---
	igPushID :: proc(id: cstring) ---
	igPushIDInt :: proc(id: c.int) ---
	igPopID :: proc() ---
	igTextUnformatted :: proc(text: cstring) ---
	igSliderInt :: proc(label: cstring, v: ^c.int, v_min: c.int, v_max: c.int) -> bool ---
	igSeparatorText :: proc(label: cstring) ---
	igButton :: proc(label: cstring) -> bool ---
	igInputText :: proc(label: cstring, buf: [^]u8, buf_size: c.size_t, flags: c.int) -> bool ---
	igSelectableEx :: proc(label: cstring, selected: bool, flags: c.int, size: Im_Vec2) -> bool ---
	igBeginMainMenuBar :: proc() -> bool ---
	igEndMainMenuBar :: proc() ---
	igBeginMenuEx :: proc(label: cstring, enabled: bool) -> bool ---
	igEndMenu :: proc() ---
	igMenuItemEx :: proc(label: cstring, shortcut: cstring, selected: bool, enabled: bool) -> bool ---
	igBeginPopupModal :: proc(name: cstring, p_open: ^bool, flags: c.int) -> bool ---
	igEndPopup :: proc() ---
	igOpenPopup :: proc(id: cstring, flags: c.int) -> bool ---
	igCloseCurrentPopup :: proc() ---
	igBeginDisabled :: proc(disabled: bool) ---
	igEndDisabled :: proc() ---
	igSetKeyboardFocusHere :: proc() ---
	igGetContentRegionAvail :: proc() -> Im_Vec2 ---
	igGetWindowDrawList :: proc() -> rawptr ---
	igButtonEx :: proc(label: cstring, size: Im_Vec2) -> bool ---
	igGetFrameHeightWithSpacing :: proc() -> f32 ---
	igIsItemHovered :: proc(flags: c.int) -> bool ---
	igIsMouseDoubleClicked :: proc(button: c.int) -> bool ---
	igCalcTextSize :: proc(text: cstring) -> Im_Vec2 ---
	ImDrawList_AddImage :: proc(self: rawptr, tex: Im_Texture_Ref, p_min, p_max: Im_Vec2) ---
	ImDrawList_AddRect :: proc(self: rawptr, p_min, p_max: Im_Vec2, col: u32) ---
	ImDrawList_AddRectFilled :: proc(self: rawptr, p_min, p_max: Im_Vec2, col: u32) ---
	ImDrawList_AddText :: proc(self: rawptr, pos: Im_Vec2, col: u32, text: cstring) ---
	igGetCursorScreenPos :: proc() -> Im_Vec2 ---
	igDummy :: proc(size: Im_Vec2) ---
	igPushStyleColor :: proc(idx: c.int, col: u32) ---
	igPopStyleColorEx :: proc(count: c.int) ---
	ImDrawList_AddRectFilledEx :: proc(self: rawptr, p_min, p_max: Im_Vec2, col: u32, rounding: f32, flags: c.int) ---

	// core/../gui/gui_shim.c
	bubiz_gui_load_font :: proc(path: cstring, size: f32) -> bool ---
	bubiz_gui_disable_ini :: proc() ---
	bubiz_gui_want_capture_mouse :: proc() -> bool ---
	bubiz_gui_want_capture_keyboard :: proc() -> bool ---
	bubiz_gui_frame_height :: proc() -> f32 ---
}
