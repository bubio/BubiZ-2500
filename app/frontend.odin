package bubiz

// Sokolによるウィンドウ・描画・音声出力

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "core:image/png"

import sapp "sokol:app"
import saudio "sokol:audio"
import sg "sokol:gfx"
import sgl "sokol:gl"
import sglue "sokol:glue"
import slog "sokol:log"

SOUND_RATES := [8]int{2000, 4000, 8000, 11025, 22050, 44100, 48000, 96000}

Frontend :: struct {
	opt:        Options,
	// 描画
	image:      sg.Image,
	view:       sg.View,
	sampler:    sg.Sampler, // 最近傍
	sampler_linear: sg.Sampler, // 線形補間
	src:        []u8, // コアから受け取った生のフレーム(RGBA8)
	filter_scale: int, // 現在のフィルタの倍率(1〜3)
	tex_w:      i32,
	tex_h:      i32,
	pixels:     []u8,
	pass:       sg.Pass_Action,
	// エミュレーションスレッド(デバッガーでCPUが止まってもウィンドウが固まらないよう、描画と分ける)
	emu_thread: ^thread.Thread,
	running:    bool, // atomic: falseにするとエミュレーションスレッドが終わる
	paused:     bool, // atomic
	audio_rate: i32, // 現在開いている音声出力の周波数
	emu_frames: int, // atomic: FPS表示用の、エミュレーションを進めたフレーム数
	last_seq:   u64, // 最後にテクスチャへ反映したフレームの番号
	// 時間
	fps_time:   f64,
	fps_frames: int,
	title:      cstring,
	// マウス
	mouse_grab: bool, // マウスをキャプチャ中か
	mouse_dx:   i32,
	mouse_dy:   i32,
	mouse_btn:  i32, // b0=左 b1=右 b2=中
	// キーボードによるジョイスティック(どのポートかは設定keyboard_joystick: 1=#1, 2=#2)
	joy_status: u32, // bit0-3: 上下左右, bit4-: ボタン
}

fe: Frontend

// ウィンドウのアイコン(packaging/icons/bubiz.png を実行ファイルに埋め込む)。
// macOSは、アプリのバンドルに入れたアイコンをDockが使う。ここで指定するとsokolの既定アイコンで上書きされるため、何も指定しない
ICON_PNG := #load("../packaging/icons/bubiz.png")

window_icon :: proc() -> sapp.Icon_Desc {
	icon: sapp.Icon_Desc
	when ODIN_OS != .Darwin {
		img, err := png.load_from_bytes(ICON_PNG, {.alpha_add_if_missing}, context.allocator)
		if err == nil && img != nil && img.channels == 4 && img.depth == 8 && len(img.pixels.buf) >= img.width * img.height * 4 {
			// 大きい画像はX11などで受け付けられないことがあるため、128・64・32に縮小して渡す。
			// 画素はsokolが初期化時に使うため、解放せずに残す
			src := img.pixels.buf[:]
			sizes := [3]int{128, 64, 32}
			for size, n in sizes {
				px := make([]u8, size * size * 4)
				factor := img.width / size
				for y in 0 ..< size {
					for x in 0 ..< size {
						sum: [4]int
						for yy in 0 ..< factor {
							for xx in 0 ..< factor {
								o := ((y * factor + yy) * img.width + (x * factor + xx)) * 4
								for c in 0 ..< 4 {
									sum[c] += int(src[o + c])
								}
							}
						}
						for c in 0 ..< 4 {
							px[(y * size + x) * 4 + c] = u8(sum[c] / (factor * factor))
						}
					}
				}
				icon.images[n] = {width = i32(size), height = i32(size), pixels = {ptr = raw_data(px), size = uint(len(px))}}
			}
			return icon
		}
		icon.sokol_default = true
	}
	return icon
}

run_frontend :: proc(opt: Options) {
	fe.opt = opt

	// 設定の倍率(window_mode)でウィンドウの大きさを決める。-half / -double は上書き
	mode := clamp(int(get_option("window_mode")), 0, len(WINDOW_SCALES) - 1)
	w, h := window_size_for_scale(WINDOW_SCALES[mode])
	switch opt.window_size {
	case .Full:
	case .Half:
		w, h = window_size_for_scale(1.0)
		w, h = w / 2, (h - MENU_HEIGHT_LOGICAL - STATUS_HEIGHT_LOGICAL) / 2 + MENU_HEIGHT_LOGICAL + STATUS_HEIGHT_LOGICAL
	case .Double:
		w, h = window_size_for_scale(2.0)
	}
	if opt.width > 0 {w = i32(opt.width)}
	if opt.height > 0 {h = i32(opt.height)}

	sapp.run(
		{
			init_cb = init,
			frame_cb = frame,
			cleanup_cb = cleanup,
			event_cb = event,
			width = w,
			height = h,
			window_title = "BubiZ-2500",
			fullscreen = opt.fullscreen,
			swap_interval = 1 if get_option("wait_vsync") != 0 else 0,
			enable_clipboard = true,
			clipboard_size = 8192,
			enable_dragndrop = true,
			max_dropped_files = 4,
			logger = {func = slog.func},
			icon = window_icon(),
		},
	)
}

@(private = "file")
init :: proc "c" () {
	context = runtime.default_context()

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})
	sgl.setup({logger = {func = slog.func}})

	gui_init()
	fe.sampler = sg.make_sampler({min_filter = .NEAREST, mag_filter = .NEAREST, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE})
	fe.sampler_linear = sg.make_sampler({min_filter = .LINEAR, mag_filter = .LINEAR, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE})
	if fe.opt.mouse {
		enable_mouse(true)
	}
	if fe.opt.debug {
		action_open_debugger()
	}

	sync.atomic_store(&fe.running, true)
	fe.emu_thread = thread.create_and_start(emu_thread_proc)
	fe.pass = {
		colors = {0 = {load_action = .CLEAR, clear_value = {0, 0, 0, 1}}},
	}

	if fe.opt.sound {
		setup_audio()
	}
}

// コアのサンプリング周波数に合わせて出力を開く(周波数はリセットで変わるので、変わったら開き直す)
@(private = "file")
setup_audio :: proc() {
	fe.audio_rate = sound_rate()
	saudio.setup(
		{
			sample_rate = fe.audio_rate,
			num_channels = 2,
			buffer_frames = 2048,
			stream_cb = audio_stream,
			logger = {func = slog.func},
		},
	)
}

// オーディオスレッドから呼ばれる: コアが生成した音を取り出してfloatに変換する
@(private = "file")
audio_stream :: proc "c" (buf: ^f32, num_frames, num_channels: i32) {
	buffer := ([^]f32)(buf)
	tmp: [4096 * 2]i16
	remaining := int(num_frames)
	offset := 0
	for remaining > 0 {
		n := min(remaining, 4096)
		pull_sound(&tmp[0], uint(n))
		for i in 0 ..< n * 2 {
			buffer[offset * 2 + i] = f32(tmp[i]) / 32768.0
		}
		offset += n
		remaining -= n
	}
}

// コアの画面サイズに合わせてテクスチャを作り直す
@(private = "file")
ensure_texture :: proc(w, h: i32) -> (recreated: bool) {
	if fe.tex_w == w && fe.tex_h == h {
		return false
	}
	if fe.tex_w != 0 {
		sg.destroy_view(fe.view)
		sg.destroy_image(fe.image)
		delete(fe.pixels)
	}
	fe.tex_w, fe.tex_h = w, h
	fe.pixels = make([]u8, int(w * h * 4))
	fe.image = sg.make_image({width = w, height = h, pixel_format = .RGBA8, usage = {dynamic_update = true}})
	fe.view = sg.make_view({texture = {image = fe.image}})
	return true
}

@(private = "file")
frame :: proc "c" () {
	context = runtime.default_context()

	dt := sapp.frame_duration()
	if dt > 0.25 {
		dt = 0.25
	}

	if fe.opt.mouse {
		// 1フレーム分の移動量とボタン状態をコアへ渡す
		set_mouse(fe.mouse_dx, fe.mouse_dy, fe.mouse_btn)
		fe.mouse_dx, fe.mouse_dy = 0, 0
	}

	// エミュレーションスレッドが公開した最新のフレームを取り込む(画面フィルタがあればここで掛ける)
	w, h: i32
	screen_size(&w, &h)
	if w > 0 && h > 0 {
		tw, th := w, h
		if cur_filter() == .RGB {
			// 表示の大きさに合わせて倍率を選ぶ(元の実装と同じ考え方)。倍率が変わったら作り直す
			_, _, qw, qh := quad_rect()
			disp := qh if is_rotated() else qw
			scale := filter_scale_for(disp / f32(w))
			if scale != fe.filter_scale {
				fe.filter_scale = scale
				fe.last_seq = 0
			}
			tw, th = w * i32(scale), h * i32(scale)
		}
		if len(fe.src) != int(w * h * 4) {
			delete(fe.src)
			fe.src = make([]u8, int(w * h * 4))
			fe.last_seq = 0
		}
		if ensure_texture(tw, th) {
			fe.last_seq = 0
		}
		seq: u64
		if copy_frame(raw_data(fe.src), w, h, &seq) && seq != fe.last_seq {
			fe.last_seq = seq
			if cur_filter() == .RGB {
				apply_rgb_filter(fe.src, int(w), int(h), frame_skip_line(), fe.filter_scale, fe.pixels)
			} else {
				copy(fe.pixels, fe.src)
			}
			sg.update_image(fe.image, {mip_levels = {0 = {ptr = raw_data(fe.pixels), size = uint(len(fe.pixels))}}})
		}
	}

	gui_new_frame()
	sg.begin_pass({action = fe.pass, swapchain = sglue.swapchain()})
	draw_quad()
	sgl.draw()
	gui_render()
	sg.end_pass()
	sg.commit()

	if fe.opt.sound && sound_rate() != fe.audio_rate {
		saudio.shutdown()
		setup_audio()
	}
	if power_off_requested() {
		sapp.request_quit()
	}

	// FPS表示
	fe.fps_time += dt
	fe.fps_frames += 1
	if fe.fps_time >= 1.0 {
		emu_frames := sync.atomic_exchange(&fe.emu_frames, 0)
		gui.fps = f64(emu_frames) / fe.fps_time
		if fe.opt.show_fps {
			sapp.set_window_title(
				strings.clone_to_cstring(
					fmt.tprintf("BubiZ-2500 - %.1f fps (表示 %.1f fps)", f64(emu_frames) / fe.fps_time, f64(fe.fps_frames) / fe.fps_time),
					context.temp_allocator,
				),
			)
		}
		fe.fps_time = 0
		fe.fps_frames = 0
	}
	free_all(context.temp_allocator)
}

// 現在の画面フィルタ(RFは未実装のためなし扱い)
@(private = "file")
cur_filter :: proc() -> Screen_Filter {
	return .RGB if get_option("filter_type") == 1 else .None
}

// 画面を90度/270度回している(縦横が入れ替わる)か
@(private = "file")
is_rotated :: proc() -> bool {
	r := get_option("rotate_type")
	return r == 1 || r == 3
}

// キーボードジョイスティックのポート(0始まり)。使わないときは-1
kb_joystick_port :: proc() -> int {
	return int(get_option("keyboard_joystick")) - 1
}

// エミュレーション画面を描く矩形(x, y, 幅, 高さ)。メニューバーとステータスバーを除いた領域に、
// 元の実装(osd_screen.cpp)と同じ考え方で収める。
//   ウィンドウ: window_stretch_type 0=640x400比率 1=640x480比率
//   フルスクリーン: fullscreen_stretch_type 0=ドットバイドット 1=640x400比率 2=640x480比率 3=全面
@(private = "file")
quad_rect :: proc() -> (x0, y0, qw, qh: f32) {
	top := gui_top_offset()
	area_w := f32(sapp.width())
	area_h := f32(sapp.height()) - top - gui_bottom_offset()
	if area_w <= 0 || area_h <= 0 {
		return 0, 0, 0, 0
	}
	// 比率の基準(回転すると縦横が入れ替わる)
	w400, h400, w480, h480 := f32(640), f32(400), f32(640), f32(480)
	if is_rotated() {
		w400, h400 = h400, w400
		w480, h480 = h480, w480
	}
	fit :: proc(aw, ah, area_w, area_h: f32) -> (f32, f32) {
		s := min(area_w / aw, area_h / ah)
		return aw * s, ah * s
	}
	if !sapp.is_fullscreen() {
		if get_option("window_stretch_type") == 1 {
			qw, qh = fit(w480, h480, area_w, area_h)
		} else {
			qw, qh = fit(w400, h400, area_w, area_h)
		}
	} else {
		switch get_option("fullscreen_stretch_type") {
		case 0:
			// ドットバイドット: 整数倍で収まる最大の倍率(1倍未満にはしない)
			px := int(area_w / w400)
			py := int(area_h / h400)
			pow := 1
			if py >= px && px > 1 {
				pow = px
			} else if px >= py && py > 1 {
				pow = py
			}
			qw, qh = w400 * f32(pow), h400 * f32(pow)
		case 2:
			qw, qh = fit(w480, h480, area_w, area_h)
		case 3:
			qw, qh = area_w, area_h
		case:
			qw, qh = fit(w400, h400, area_w, area_h)
		}
	}
	return (area_w - qw) * 0.5, top + (area_h - qh) * 0.5, qw, qh
}

// 回転と比率を反映して、画面を描く
@(private = "file")
draw_quad :: proc() {
	if fe.tex_w == 0 {
		return
	}
	x0, y0, qw, qh := quad_rect()
	ww, wh := f32(sapp.width()), f32(sapp.height())

	sgl.defaults()
	sgl.viewport(0, 0, sapp.width(), sapp.height(), true)
	sgl.matrix_mode_projection()
	sgl.ortho(0, ww, wh, 0, -1, 1)
	sgl.enable_texture()
	sgl.texture(fe.view, fe.sampler_linear if (fe.opt.interp || cur_filter() != .None) else fe.sampler)
	// 画面の四隅(左上・右上・右下・左下)に対応するテクスチャ座標。回転ごとに巡回させる
	uv := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	shift := 0
	switch get_option("rotate_type") {
	case 1: shift = 3 // +90度(時計回り)
	case 2: shift = 2
	case 3: shift = 1 // -90度
	}
	sgl.begin_quads()
	sgl.c3f(1, 1, 1)
	sgl.v2f_t2f(x0, y0, uv[shift % 4][0], uv[shift % 4][1])
	sgl.v2f_t2f(x0 + qw, y0, uv[(1 + shift) % 4][0], uv[(1 + shift) % 4][1])
	sgl.v2f_t2f(x0 + qw, y0 + qh, uv[(2 + shift) % 4][0], uv[(2 + shift) % 4][1])
	sgl.v2f_t2f(x0, y0 + qh, uv[(3 + shift) % 4][0], uv[(3 + shift) % 4][1])
	sgl.end()
}

@(private = "file")
event :: proc "c" (e: ^sapp.Event) {
	context = runtime.default_context()

	// macOS: Command+Qで終了する(sokolはアプリケーションメニューを作らないため、自前で扱う)
	when ODIN_OS == .Darwin {
		if e.type == .KEY_DOWN && e.key_code == .Q && (e.modifiers & sapp.MODIFIER_SUPER) != 0 {
			sapp.request_quit()
			return
		}
	}
	// メニューなどGUIが使うイベントはエミュレーションへ渡さない
	if gui_event(e) {
		return
	}
	#partial switch e.type {
	case .KEY_DOWN:
		if handle_hotkey(e) {
			return
		}
		if kb_joystick_port() >= 0 && joy_key(e.key_code, true) {
			return
		}
		vk := to_vk(e.key_code)
		if vk != 0 {
			key_down(i32(vk), e.key_repeat)
		}
	case .KEY_UP:
		if kb_joystick_port() >= 0 && joy_key(e.key_code, false) {
			return
		}
		vk := to_vk(e.key_code)
		if vk != 0 {
			key_up(i32(vk))
		}
	case .UNFOCUSED:
		key_lost_focus()
		set_mouse_grab(false)
	case .MOUSE_MOVE:
		if fe.mouse_grab {
			fe.mouse_dx += i32(e.mouse_dx)
			fe.mouse_dy += i32(e.mouse_dy)
		}
	case .MOUSE_DOWN:
		if fe.opt.mouse && !fe.mouse_grab {
			set_mouse_grab(true) // 最初のクリックでキャプチャを開始
		} else if fe.mouse_grab {
			fe.mouse_btn |= mouse_button_bit(e.mouse_button)
		}
	case .MOUSE_UP:
		fe.mouse_btn &= ~mouse_button_bit(e.mouse_button)
	case .FILES_DROPPED:
		n := sapp.get_num_dropped_files()
		for i in 0 ..< n {
			path := string(sapp.get_dropped_file_path(i32(i)))
			insert_image(path, int(i))
		}
	}
}

// ホットキー: F11=フルスクリーン, F12=リセット(Ctrl併用でスペシャルリセット), Ctrl+P=一時停止, Ctrl+S=スクリーンショット
@(private = "file")
handle_hotkey :: proc(e: ^sapp.Event) -> bool {
	ctrl := (e.modifiers & sapp.MODIFIER_CTRL) != 0
	#partial switch e.key_code {
	case .F1 ..= .F4:
		// Ctrl+F1〜F4: ステート保存 / Ctrl+Shift+F1〜F4: ステート復元(スロット1〜4)
		if ctrl {
			slot := i32(int(e.key_code) - int(sapp.Keycode.F1)) + 1
			if (e.modifiers & sapp.MODIFIER_SHIFT) != 0 {
				load_state_slot(slot)
			} else {
				save_state_slot(slot)
			}
			return true
		}
	case .F11:
		sapp.toggle_fullscreen()
		return true
	case .F12:
		if ctrl {
			special_reset()
		} else {
			reset()
		}
		return true
	case .P:
		if ctrl {
			action_toggle_pause()
			return true
		}
	case .S:
		if ctrl {
			action_screenshot()
			return true
		}
	case .M:
		if ctrl {
			set_mouse_grab(!fe.mouse_grab)
			return true
		}
	case .F:
		if ctrl {
			set_option("filter_type", 0 if cur_filter() == .RGB else 1)
			fe.last_seq = 0
			return true
		}
	case .D:
		if ctrl {
			action_open_debugger()
			return true
		}
	case .J:
		if ctrl {
			action_toggle_joystick()
			return true
		}
	}
	return false
}

action_toggle_pause :: proc() {
	sync.atomic_store(&fe.paused, !sync.atomic_load(&fe.paused))
}

action_screenshot :: proc() {
	ensure_dir(fe.opt.snap_dir if fe.opt.snap_dir != "" else default_snap_dir())
	capture_screen()
}

action_toggle_joystick :: proc() {
	port := kb_joystick_port()
	if port >= 0 {
		set_joystick(i32(port), 0)
	}
	set_option("keyboard_joystick", 0 if port >= 0 else 1)
	fe.joy_status = 0
}

// キーボードをジョイスティックとして扱う。対象のキーならtrueを返す
@(private = "file")
joy_key :: proc(k: sapp.Keycode, down: bool) -> bool {
	bit: u32
	#partial switch k {
	case .UP: bit = 1 << 0
	case .DOWN: bit = 1 << 1
	case .LEFT: bit = 1 << 2
	case .RIGHT: bit = 1 << 3
	case .Z: bit = 1 << 4
	case .X: bit = 1 << 5
	case:
		return false
	}
	if down {
		fe.joy_status |= bit
	} else {
		fe.joy_status &= ~bit
	}
	set_joystick(i32(max(0, kb_joystick_port())), fe.joy_status)
	return true
}

@(private = "file")
mouse_button_bit :: proc(b: sapp.Mousebutton) -> i32 {
	#partial switch b {
	case .LEFT: return 1
	case .RIGHT: return 2
	case .MIDDLE: return 4
	}
	return 0
}

// マウスのキャプチャを開始/終了し、コアのマウスエミュレーションと同期させる
set_mouse_grab :: proc(on: bool) {
	if fe.mouse_grab == on {
		return
	}
	fe.mouse_grab = on
	fe.mouse_dx, fe.mouse_dy, fe.mouse_btn = 0, 0, 0
	sapp.lock_mouse(on)
	enable_mouse(on)
	// ゲストがマウスを使う場合に備え、キャプチャ中だけ有効にする
	fe.opt.mouse = true
}

// ドロップされたファイルをメディアとして挿入する
@(private = "file")
insert_image :: proc(path: string, index: int) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	switch image_kind_of(path) {
	case .Floppy:
		open_floppy(i32(index % FLOPPY_DRIVES), cpath, 0)
	case .Hard_Disk:
		open_hard_disk(0, cpath)
	case .Tape:
		play_tape(0, cpath)
	}
}

@(private = "file")
cleanup :: proc "c" () {
	context = runtime.default_context()
	// エミュレーションスレッドを止める。デバッガーでCPUが止まっていても外せるよう、先にデバッガーを閉じる
	sync.atomic_store(&fe.running, false)
	close_debugger()
	if fe.emu_thread != nil {
		thread.join(fe.emu_thread)
		thread.destroy(fe.emu_thread)
	}
	if fe.opt.sound {
		saudio.shutdown()
	}
	gui_shutdown()
	sgl.shutdown()
	sg.shutdown()
}

// エミュレーションを一定の速さで進めるスレッド
@(private = "file")
emu_thread_proc :: proc() {
	next := time.tick_now()
	for sync.atomic_load(&fe.running) {
		if sync.atomic_load(&fe.paused) {
			time.sleep(5 * time.Millisecond)
			next = time.tick_now()
			continue
		}
		run()
		sync.atomic_add(&fe.emu_frames, 1)

		if !fe.opt.wait || get_option("full_speed") != 0 {
			continue // 全速
		}
		// 速度比(%)を考慮した1フレームの時間
		step := time.Duration(f64(time.Second) / frame_rate() * 100.0 / f64(fe.opt.speed))
		next = time.tick_add(next, step)
		now := time.tick_now()
		behind := time.tick_diff(next, now) // nowがnextより進んでいれば正
		if behind > 250 * time.Millisecond {
			next = now // 遅れすぎたら追いつくのをあきらめる
		} else if behind < 0 {
			time.accurate_sleep(-behind)
		}
	}
}
