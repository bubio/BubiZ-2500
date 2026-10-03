package bubiz

// エミュレーションコア(core/bubiz_core.h)のC APIバインディング

import "core:c"

when ODIN_OS == .Darwin {
	foreign import core {
		"system:bubiz_core",
		"system:c++",
	}
} else when ODIN_OS == .Windows {
	// 拡張子を付けないとlink.exeが.objとして探してしまう
	foreign import core {
		"system:bubiz_core.lib",
	}
} else {
	foreign import core {
		"system:bubiz_core",
		"system:stdc++",
		"system:pthread",
		"system:m",
	}
}

@(default_calling_convention = "c", link_prefix = "bubiz_")
foreign core {
	set_data_dir :: proc(dir: cstring) ---
	load_config :: proc(name: cstring) ---
	save_config :: proc(name: cstring) ---
	set_config :: proc(key: cstring, value: c.int) -> bool ---
	create :: proc() -> bool ---
	destroy :: proc() ---

	run :: proc() -> c.int ---
	frame_rate :: proc() -> f64 ---
	device_name :: proc() -> cstring ---

	draw_screen :: proc() ---
	screen_size :: proc(width, height: ^c.int) ---
	screen_aspect :: proc(width, height: ^c.int) ---
	read_screen_rgba :: proc(out_pixels: [^]u8) ---
	frame_skip_line :: proc() -> bool ---
	copy_frame :: proc(out_pixels: [^]u8, width, height: c.int, seq: ^u64) -> bool ---

	sound_rate :: proc() -> c.int ---
	pull_sound :: proc(dest: [^]i16, frames: c.size_t) -> c.size_t ---

	key_down :: proc(vk: c.int, repeat: bool) ---
	key_up :: proc(vk: c.int) ---
	key_lost_focus :: proc() ---
	set_joystick :: proc(index: c.int, status: u32) ---
	set_mouse :: proc(dx, dy, buttons: c.int) ---
	enable_mouse :: proc(enable: bool) ---

	reset :: proc() ---
	special_reset :: proc() ---

	open_floppy :: proc(drive: c.int, path: cstring, bank: c.int) ---
	close_floppy :: proc(drive: c.int) ---
	floppy_inserted :: proc(drive: c.int) -> bool ---
	open_hard_disk :: proc(drive: c.int, path: cstring) ---
	close_hard_disk :: proc(drive: c.int) ---
	play_tape :: proc(drive: c.int, path: cstring) ---
	rec_tape :: proc(drive: c.int, path: cstring) ---
	close_tape :: proc(drive: c.int) ---

	save_state :: proc(path: cstring) ---
	load_state :: proc(path: cstring) ---
	save_state_slot :: proc(slot: c.int) ---
	load_state_slot :: proc(slot: c.int) ---

	capture_screen :: proc() ---
	write_screenshot :: proc(path: cstring) -> bool ---
	start_record_sound :: proc() ---
	start_record_sound_to :: proc(path: cstring) -> bool ---
	stop_record_sound :: proc() ---

	open_debugger :: proc(cpu_index: c.int) ---
	close_debugger :: proc() ---
	debugger_active :: proc() -> bool ---

	power_off_requested :: proc() -> bool ---
}
