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
