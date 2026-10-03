package bubiz

// Sokolによるウィンドウ・描画・音声出力

import "base:runtime"
import "core:fmt"
import "core:strings"

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
	sampler:    sg.Sampler,
	tex_w:      i32,
	tex_h:      i32,
	pixels:     []u8,
	pass:       sg.Pass_Action,
	// 時間
	acc:        f64, // 未消化のエミュレーション時間(秒)
	fps_time:   f64,
	fps_frames: int,
	title:      cstring,
	paused:     bool,
}

@(private = "file")
fe: Frontend

run_frontend :: proc(opt: Options) {
	fe.opt = opt

	w, h := i32(640), i32(480)
	switch opt.window_size {
	case .Full:
	case .Half:
		w, h = 320, 240
	case .Double:
		w, h = 1280, 960
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
			enable_dragndrop = true,
			max_dropped_files = 4,
			logger = {func = slog.func},
			icon = {sokol_default = true},
		},
	)
}

@(private = "file")
init :: proc "c" () {
	context = runtime.default_context()

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})
	sgl.setup({logger = {func = slog.func}})

	fe.sampler = sg.make_sampler({min_filter = .NEAREST, mag_filter = .NEAREST, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE})
	fe.pass = {
		colors = {0 = {load_action = .CLEAR, clear_value = {0, 0, 0, 1}}},
	}

	if fe.opt.sound {
		saudio.setup(
			{
				sample_rate = i32(bubiz_sound_rate_value()),
				num_channels = 2,
				buffer_frames = 2048,
				stream_cb = audio_stream,
				logger = {func = slog.func},
			},
		)
	}
}

@(private = "file")
bubiz_sound_rate_value :: proc() -> int {
	return int(sound_rate())
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
ensure_texture :: proc(w, h: i32) {
	if fe.tex_w == w && fe.tex_h == h {
		return
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
}

@(private = "file")
frame :: proc "c" () {
	context = runtime.default_context()

	dt := sapp.frame_duration()
	if dt > 0.25 {
		dt = 0.25
	}

	if !fe.paused {
		interval := 1.0 / frame_rate()
		if fe.opt.wait {
			// 速度比を考慮して消化すべきエミュレーション時間を積む
			fe.acc += dt * f64(fe.opt.speed) / 100.0
			for fe.acc >= interval {
				run()
				fe.acc -= interval
			}
		} else {
			// 全速: 1フレーム分の時間で数フレーム進める
			for _ in 0 ..< 8 {
				run()
			}
			fe.acc = 0
		}
	}

	draw_screen()
	w, h: i32
	screen_size(&w, &h)
	if w > 0 && h > 0 {
		ensure_texture(w, h)
		read_screen_rgba(raw_data(fe.pixels))
		sg.update_image(fe.image, {mip_levels = {0 = {ptr = raw_data(fe.pixels), size = uint(len(fe.pixels))}}})
	}

	sg.begin_pass({action = fe.pass, swapchain = sglue.swapchain()})
	draw_quad()
	sgl.draw()
	sg.end_pass()
	sg.commit()

	if power_off_requested() {
		sapp.request_quit()
	}

	// FPS表示
	fe.fps_time += dt
	fe.fps_frames += 1
	if fe.opt.show_fps && fe.fps_time >= 1.0 {
		sapp.set_window_title(strings.clone_to_cstring(fmt.tprintf("BubiZ-2500 - %.1f fps", f64(fe.fps_frames) / fe.fps_time), context.temp_allocator))
		fe.fps_time = 0
		fe.fps_frames = 0
	}
	free_all(context.temp_allocator)
}

// アスペクト比を保ってウィンドウ内に描く
@(private = "file")
draw_quad :: proc() {
	if fe.tex_w == 0 {
		return
	}
	aw, ah: i32
	screen_aspect(&aw, &ah)
	if aw <= 0 || ah <= 0 {
		aw, ah = fe.tex_w, fe.tex_h
	}
	ww, wh := f32(sapp.width()), f32(sapp.height())
	scale := min(ww / f32(aw), wh / f32(ah))
	qw, qh := f32(aw) * scale, f32(ah) * scale
	x0, y0 := (ww - qw) * 0.5, (wh - qh) * 0.5

	sgl.defaults()
	sgl.viewport(0, 0, sapp.width(), sapp.height(), true)
	sgl.matrix_mode_projection()
	sgl.ortho(0, ww, wh, 0, -1, 1)
	sgl.enable_texture()
	sgl.texture(fe.view, fe.sampler)
	sgl.begin_quads()
	sgl.c3f(1, 1, 1)
	sgl.v2f_t2f(x0, y0, 0, 0)
	sgl.v2f_t2f(x0 + qw, y0, 1, 0)
	sgl.v2f_t2f(x0 + qw, y0 + qh, 1, 1)
	sgl.v2f_t2f(x0, y0 + qh, 0, 1)
	sgl.end()
}

@(private = "file")
event :: proc "c" (e: ^sapp.Event) {
	context = runtime.default_context()

	#partial switch e.type {
	case .KEY_DOWN:
		if handle_hotkey(e) {
			return
		}
		vk := to_vk(e.key_code)
		if vk != 0 {
			key_down(i32(vk), e.key_repeat)
		}
	case .KEY_UP:
		vk := to_vk(e.key_code)
		if vk != 0 {
			key_up(i32(vk))
		}
	case .UNFOCUSED:
		key_lost_focus()
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
			fe.paused = !fe.paused
			return true
		}
	case .S:
		if ctrl {
			capture_screen()
			return true
		}
	}
	return false
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
	if fe.opt.sound {
		saudio.shutdown()
	}
	sgl.shutdown()
	sg.shutdown()
}
