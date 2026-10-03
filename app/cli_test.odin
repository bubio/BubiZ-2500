package bubiz

import "core:testing"

@(test)
test_floppy_assignment :: proc(t: ^testing.T) {
	// 番号付きの2台指定
	opt, err := parse_args({"x.d88", "3", "y.d88", "2"})
	testing.expect_value(t, err, "")
	testing.expect_value(t, opt.floppy_count, 2)
	testing.expect_value(t, opt.floppies[0].bank, 2)
	testing.expect_value(t, opt.floppies[1].path, "y.d88")
	testing.expect_value(t, opt.floppies[1].bank, 1)

	// 1ファイルに番号を2つ: 同じファイルが2台に入る
	opt, err = parse_args({"x.d88", "2", "4"})
	testing.expect_value(t, err, "")
	testing.expect_value(t, opt.floppy_count, 2)
	testing.expect_value(t, opt.floppies[0].bank, 1)
	testing.expect_value(t, opt.floppies[1].path, "x.d88")
	testing.expect_value(t, opt.floppies[1].bank, 3)
}

@(test)
test_kind_by_extension :: proc(t: ^testing.T) {
	testing.expect_value(t, image_kind_of("a.D88"), Image_Kind.Floppy)
	testing.expect_value(t, image_kind_of("hd.hdi"), Image_Kind.Hard_Disk)
	testing.expect_value(t, image_kind_of("game.mzt"), Image_Kind.Tape)
}

@(test)
test_options :: proc(t: ^testing.T) {
	opt, err := parse_args({"-nosound", "-double", "-speed", "200", "-boot", "x"})
	testing.expect(t, err != "", "不明なオプションはエラー")
	opt, err = parse_args({"-nosound", "-double", "-speed", "200", "-mz2000"})
	testing.expect_value(t, err, "")
	testing.expect_value(t, opt.sound, false)
	testing.expect_value(t, opt.window_size, Window_Size.Double)
	testing.expect_value(t, opt.speed, 200)
	testing.expect_value(t, opt.boot_mode, 1)
}

@(test)
test_missing_value :: proc(t: ^testing.T) {
	_, err := parse_args({"-romdir"})
	testing.expect(t, err != "", "値が無い場合はエラー")
}

@(test)
test_key_event :: proc(t: ^testing.T) {
	opt, err := parse_args({"-key", "3000:1", "-key", "3200:return:5", "-shotat", "100:/tmp/a.bmp"})
	testing.expect_value(t, err, "")
	testing.expect_value(t, len(opt.keys), 2)
	testing.expect_value(t, opt.keys[0], Key_Event{frame = 3000, vk = '1', hold = 3})
	testing.expect_value(t, opt.keys[1], Key_Event{frame = 3200, vk = 0x0D, hold = 5})
	testing.expect_value(t, opt.shots[0].path, "/tmp/a.bmp")
	delete(opt.keys)
	delete(opt.shots)

	_, err = parse_args({"-key", "10:nokey"})
	testing.expect(t, err != "", "不明なキー名はエラー")
	_, err = parse_args({"-key", "x:1"})
	testing.expect(t, err != "", "フレームが数値でなければエラー")
	testing.expect_value(t, vk_from_name("f10"), 0x79)
	testing.expect_value(t, vk_from_name("a"), 'A')
}

@(test)
test_debug_and_state_options :: proc(t: ^testing.T) {
	opt, err := parse_args({"-debug", "-savestate", "100:2", "-loadstate", "200:2", "-joystick"})
	testing.expect_value(t, err, "")
	testing.expect_value(t, opt.debug, true)
	testing.expect_value(t, opt.joystick, true)
	testing.expect_value(t, len(opt.states), 2)
	testing.expect_value(t, opt.states[0], State_Event{frame = 100, slot = 2, load = false})
	testing.expect_value(t, opt.states[1], State_Event{frame = 200, slot = 2, load = true})
	delete(opt.states)

	_, err = parse_args({"-savestate", "abc"})
	testing.expect(t, err != "", "書式が不正ならエラー")
	opt2, _ := parse_args({})
	testing.expect_value(t, opt2.joystick, false)
}

@(test)
test_filter_option :: proc(t: ^testing.T) {
	opt, err := parse_args({"-filter", "RGB"})
	testing.expect_value(t, err, "")
	testing.expect_value(t, opt.filter, Screen_Filter.RGB)
	_, err = parse_args({"-filter", "rf"})
	testing.expect(t, err != "", "未対応のフィルタ名はエラー")
	opt2, _ := parse_args({})
	testing.expect_value(t, opt2.filter, Screen_Filter.None)
}
