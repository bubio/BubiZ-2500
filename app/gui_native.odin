package bubiz

// ウィンドウの大きさの変更とその他の補助

import "core:fmt"
import "core:time"

import "core:c"

import sapp "sokol:app"

when ODIN_OS == .Windows {
	foreign import native "system:bubiz_imgui.lib"
	@(default_calling_convention = "c")
	foreign native {
		bubiz_native_resize :: proc(hwnd: rawptr, w, h: c.int) ---
	}
} else when ODIN_OS == .Darwin {
	foreign import native "system:bubiz_imgui"
	@(default_calling_convention = "c")
	foreign native {
		bubiz_native_resize :: proc(window: rawptr, w, h: c.int) ---
	}
} else {
	foreign import native {
		"system:bubiz_imgui",
		"system:X11",
	}
	@(default_calling_convention = "c")
	foreign native {
		bubiz_native_resize :: proc(display: rawptr, window: rawptr, w, h: c.int) ---
	}
}

// ウィンドウの内側の大きさ(論理座標)を変える
native_resize_window :: proc(w, h: i32) {
	when ODIN_OS == .Windows {
		scale := sapp.dpi_scale()
		bubiz_native_resize(sapp.win32_get_hwnd(), c.int(f32(w) * scale), c.int(f32(h) * scale))
	} else when ODIN_OS == .Darwin {
		bubiz_native_resize(sapp.macos_get_window(), c.int(w), c.int(h))
	} else {
		scale := sapp.dpi_scale()
		bubiz_native_resize(sapp.x11_get_display(), sapp.x11_get_window(), c.int(f32(w) * scale), c.int(f32(h) * scale))
	}
}

// ファイル名に使う日時(YYYY-MM-DD_hh-mm-ss)
date_stamp :: proc() -> string {
	y, mo, d := time.date(time.now())
	h, mi, s := time.clock_from_time(time.now())
	return fmt.tprintf("%04d-%02d-%02d_%02d-%02d-%02d", y, int(mo), d, h, mi, s)
}
