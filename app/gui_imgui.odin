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

Im_Vec2 :: struct {
	x, y: f32,
}

// ImGuiWindowFlags
WINDOW_NO_RESIZE :: c.int(1 << 1)
WINDOW_NO_COLLAPSE :: c.int(1 << 5)
WINDOW_ALWAYS_AUTO_RESIZE :: c.int(1 << 6)
WINDOW_NO_SAVED_SETTINGS :: c.int(1 << 8)

// ImGuiCond
COND_APPEARING :: c.int(1 << 3)

// ImGuiInputTextFlags
INPUT_ENTER_RETURNS_TRUE :: c.int(1 << 5)

@(default_calling_convention = "c")
foreign imgui_native {
	igBegin :: proc(name: cstring, p_open: ^bool, flags: c.int) -> bool ---
	igEnd :: proc() ---
	igBeginChild :: proc(str_id: cstring, size: Im_Vec2, child_flags: c.int, window_flags: c.int) -> bool ---
	igEndChild :: proc() ---
	igSetNextWindowPos :: proc(pos: Im_Vec2, cond: c.int) ---
	igSetNextWindowSize :: proc(size: Im_Vec2, cond: c.int) ---
	igSetNextItemWidth :: proc(w: f32) ---
	igSeparator :: proc() ---
	igSameLine :: proc() ---
	igPushID :: proc(id: cstring) ---
	igPushIDInt :: proc(id: c.int) ---
	igPopID :: proc() ---
	igTextUnformatted :: proc(text: cstring) ---
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

	// core/../gui/gui_shim.c
	bubiz_gui_load_font :: proc(path: cstring, size: f32) -> bool ---
	bubiz_gui_disable_ini :: proc() ---
	bubiz_gui_want_capture_mouse :: proc() -> bool ---
	bubiz_gui_want_capture_keyboard :: proc() -> bool ---
	bubiz_gui_frame_height :: proc() -> f32 ---
}
