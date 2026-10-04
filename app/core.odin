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
	set_snap_dir :: proc(dir: cstring) ---
	set_sound_dir :: proc(dir: cstring) ---
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
	create_blank_floppy :: proc(path: cstring, type: c.int) -> bool ---
	create_blank_hard_disk :: proc(path: cstring) -> bool ---
	floppy_protected :: proc(drive: c.int) -> bool ---
	set_floppy_protected :: proc(drive: c.int, protect: bool) ---
	floppy_bank_count :: proc(drive: c.int) -> c.int ---
	floppy_bank_name :: proc(drive: c.int, bank: c.int) -> cstring ---
	floppy_cur_bank :: proc(drive: c.int) -> c.int ---
	select_floppy_bank :: proc(drive: c.int, bank: c.int) ---
	hard_disk_inserted :: proc(drive: c.int) -> bool ---
	floppy_path :: proc(drive: c.int) -> cstring ---
	tape_message :: proc(drive: c.int) -> cstring ---
	tape_inserted :: proc(drive: c.int) -> bool ---
	tape_playing :: proc(drive: c.int) -> bool ---
	tape_recording :: proc(drive: c.int) -> bool ---
	tape_button :: proc(drive: c.int, button: c.int) ---
	recent_path :: proc(kind: c.int, drive: c.int, index: c.int) -> cstring ---
	add_recent :: proc(kind: c.int, drive: c.int, path: cstring) ---
	initial_dir :: proc(kind: c.int) -> cstring ---
	set_initial_dir :: proc(kind: c.int, dir: cstring) ---
	paste_text :: proc(text: [^]u8, size: c.int) ---
	stop_auto_key :: proc() ---
	set_romaji_to_kana :: proc(enable: bool) ---
	floppy_accessed :: proc() -> u32 ---
	floppy_indicator_color :: proc() -> u32 ---
	hard_disk_accessed :: proc() -> u32 ---
	tape_accessed :: proc() -> u32 ---
	set_option :: proc(key: cstring, value: c.int) -> bool ---
	get_option :: proc(key: cstring) -> c.int ---
	sound_device_count :: proc() -> c.int ---
	sound_device_name :: proc(index: c.int) -> cstring ---

	save_state :: proc(path: cstring) ---
	load_state :: proc(path: cstring) ---
	state_slot_info :: proc(slot: c.int, buf: [^]u8, cap: c.int) -> bool ---
	save_state_slot :: proc(slot: c.int) ---
	load_state_slot :: proc(slot: c.int) ---

	capture_screen :: proc() ---
	write_screenshot :: proc(path: cstring) -> bool ---
	start_record_sound :: proc() ---
	start_record_sound_to :: proc(path: cstring) -> bool ---
	stop_record_sound :: proc() ---

	set_virtual_console :: proc(on: bool) ---
	console_read :: proc(attr: ^u16, buf: [^]u8, cap: c.int) -> c.int ---
	console_write_input :: proc(s: [^]u8, n: c.int) ---
	console_break :: proc() ---
	open_debugger :: proc(cpu_index: c.int) ---
	close_debugger :: proc() ---
	debugger_active :: proc() -> bool ---

	power_off_requested :: proc() -> bool ---
}
