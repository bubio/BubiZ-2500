package bubiz

import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	opt, err := parse_args(os.args[1:])
	if err != "" {
		exit_with_error(err)
	}
	// デバッガーのターミナルウィンドウの中で動く中継(エミュレーターが自分自身を起動する)
	if opt.dbg_relay != "" {
		os.exit(int(run_console_relay(strings.clone_to_cstring(opt.dbg_relay))))
	}
	if opt.help {
		usage()
		return
	}
	if opt.version {
		print_version()
		return
	}

	// データディレクトリ（設定・ROM・ステート）
	data_dir := opt.rom_dir if opt.rom_dir != "" else default_data_dir()
	if !ensure_dir(data_dir) {
		exit_with_error(fmt.aprintf("ディレクトリを作成できません: %s", display_path(data_dir)))
	}
	if opt.verbose > 0 {
		fmt.printfln("データディレクトリ: %s", display_path(data_dir))
	}
	set_data_dir(strings.clone_to_cstring(data_dir))
	snap_dir := opt.snap_dir if opt.snap_dir != "" else default_snap_dir()
	set_snap_dir(strings.clone_to_cstring(snap_dir))
	sound_dir := opt.sound_dir if opt.sound_dir != "" else default_sound_dir()
	set_sound_dir(strings.clone_to_cstring(sound_dir))

	// 設定の読み込みとオプションによる上書き
	if !opt.no_config {
		load_config("mz2500.ini")
	}
	apply_options(opt)

	if !create() {
		exit_with_error("エミュレーションコアの初期化に失敗しました")
	}
	defer destroy()

	insert_media(opt)
	if opt.debug {
		open_debugger(0)
	}
	if opt.resume {
		path := opt.resume_file if opt.resume_file != "" else fmt.tprintf("%s/mz2500.sta0", data_dir)
		load_state(strings.clone_to_cstring(path, context.temp_allocator))
	}

	if opt.headless > 0 {
		run_headless(opt)
	} else {
		run_frontend(opt)
	}

	if opt.save_config {
		save_config("mz2500.ini")
	}
}

// CLIオプションをコア設定へ反映する
apply_options :: proc(opt: Options) {
	if opt.boot_mode >= 0 {set_config("boot_mode", i32(opt.boot_mode))}
	if opt.monitor_type >= 0 {set_config("monitor_type", i32(opt.monitor_type))}
	if opt.option_switch >= 0 {set_config("option_switch", i32(opt.option_switch))}
	if opt.scan_line >= 0 {set_config("scan_line", i32(opt.scan_line))}
	if opt.aspect_set {
		// 640x400比率 / 640x480(4:3)比率。ウィンドウとフルスクリーンの両方に適用する
		set_option("window_stretch_type", 1 if opt.aspect_480 else 0)
		set_option("fullscreen_stretch_type", 2 if opt.aspect_480 else 1)
	}
	if opt.filter_set {set_option("filter_type", i32(opt.filter))}
	if opt.joystick_set {set_option("keyboard_joystick", 1 if opt.joystick else 0)}
	if opt.sample_freq > 0 {
		for hz, idx in SOUND_RATES {
			if hz == opt.sample_freq {
				set_config("sound_frequency", i32(idx))
			}
		}
	}
}

// 指定されたイメージを各ドライブへ挿入する
insert_media :: proc(opt: Options) {
	for i in 0 ..< opt.floppy_count {
		img := opt.floppies[i]
		path := resolve_path(opt.disk_dir, img.path)
		open_floppy(i32(i), strings.clone_to_cstring(path, context.temp_allocator), i32(img.bank))
	}
	for hd, i in opt.hard_disks {
		if hd != "" {
			open_hard_disk(i32(i), strings.clone_to_cstring(resolve_path(opt.disk_dir, hd), context.temp_allocator))
		}
	}
	if opt.tape_load != "" {
		play_tape(0, strings.clone_to_cstring(resolve_path(opt.tape_dir, opt.tape_load), context.temp_allocator))
	}
	if opt.tape_save != "" {
		rec_tape(0, strings.clone_to_cstring(resolve_path(opt.tape_dir, opt.tape_save), context.temp_allocator))
	}
}

// 相対パスで、基準ディレクトリが指定されていればその下とみなす
resolve_path :: proc(base, path: string) -> string {
	if base == "" || os.exists(path) || strings.has_prefix(path, "/") {
		return path
	}
	return fmt.tprintf("%s/%s", base, path)
}

// ウィンドウ無しで指定フレーム数だけ実行する（CIでの動作確認用）
// -key / -shotat で指定されたキー入力と画面保存をフレームに合わせて行う
run_headless :: proc(opt: Options) {
	recording := false
	if opt.wav != "" {
		recording = start_record_sound_to(strings.clone_to_cstring(opt.wav, context.temp_allocator))
		if !recording {
			fmt.eprintfln("BubiZ-2500: WAV録音を開始できません: %s", opt.wav)
		}
	}
	// 録音時はウィンドウ版の音声スレッド相当として、1フレーム分の音を取り出し続ける
	pull_buf := make([]i16, 8192 * 2)
	defer delete(pull_buf)
	pull_acc := 0.0
	rate := f64(sound_rate())

	for frame in 0 ..< opt.headless {
		for k in opt.keys {
			if k.frame == frame {
				key_down(i32(k.vk), false)
			}
			if k.frame + k.hold == frame {
				key_up(i32(k.vk))
			}
		}
		for st in opt.states {
			if st.frame == frame {
				if st.load {
					load_state_slot(i32(st.slot))
				} else {
					save_state_slot(i32(st.slot))
				}
			}
		}
		run()
		draw_screen()
		if recording {
			pull_acc += rate / frame_rate()
			n := int(pull_acc)
			pull_acc -= f64(n)
			for n > 0 {
				c := min(n, 8192)
				pull_sound(&pull_buf[0], uint(c))
				n -= c
			}
		}
		for s in opt.shots {
			if s.frame == frame {
				write_screenshot(strings.clone_to_cstring(s.path, context.temp_allocator))
			}
		}
	}
	if recording {
		stop_record_sound()
	}
	w, h: i32
	screen_size(&w, &h)
	fmt.printfln("%s: %dx%d, %dフレーム実行", device_name(), w, h, opt.headless)
	if opt.screenshot != "" {
		write_screenshot(strings.clone_to_cstring(opt.screenshot, context.temp_allocator))
	}
}
