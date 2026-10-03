package bubiz

// 画面フィルタ(CRTの発光を模した、RGBのサブピクセル表示)
// 元のEmuZ-2500のRGBフィルタ(osd_screen.cpp)と同じ計算を移植したもの。
//   隣の画素の明るさを1/8だけ混ぜ、1画素を横x縦に広げる。
//   3倍: 横にR・G・Bの縞を作る / 2倍: 明るい列と暗い列 / 1倍: 混ぜるだけ
//   各画素の最後の1行は暗くして、走査線の隙間を表す。
// RFフィルタは、元の実装でも未実装(FIXME)のため、ここにもない。

Screen_Filter :: enum {
	None,
	RGB,
}

// 表示の大きさ(元の画面の何倍か)から、フィルタの倍率(1〜3)を選ぶ
filter_scale_for :: proc(display_over_source: f32) -> int {
	if display_over_source >= 2.5 {
		return 3
	}
	if display_over_source >= 1.5 {
		return 2
	}
	return 1
}

// 明るさの変換: 3/8に落としてから180/256を掛ける、または180/256だけ掛ける
@(private = "file")
dim :: #force_inline proc(v: u32) -> u32 {
	return (((v * 3) >> 3) * 180) >> 8
}

@(private = "file")
full :: #force_inline proc(v: u32) -> u32 {
	return (v * 180) >> 8
}

// RGBA8のsrc(w x h)を、RGBフィルタをかけた(w*scale x h*scale)のRGBA8へ変換してdstに書く。
// skip_lineは200ライン表示(1行おきに有効なデータ)のとき真。scaleは1〜3。
apply_rgb_filter :: proc(src: []u8, w, h: int, skip_line: bool, scale: int, dst: []u8) {
	assert(scale >= 1 && scale <= 3)
	assert(len(src) >= w * h * 4)
	assert(len(dst) >= w * scale * h * scale * 4)
	out_w := w * scale

	// 1行ぶんの横方向の混ぜ合わせ(両端の外側は0として扱う)
	r0 := make([]u32, w + 2, context.temp_allocator)
	g0 := make([]u32, w + 2, context.temp_allocator)
	b0 := make([]u32, w + 2, context.temp_allocator)

	// 出力の1行(RGBA8)を書く。bright=falseなら暗い行
	write_row :: proc(dst: []u8, y, out_w, scale: int, vr, vg, vb: []u32, w: int, bright: bool) {
		row := dst[y * out_w * 4:(y + 1) * out_w * 4]
		put :: proc(row: []u8, o: int, r, g, b: u32) {
			row[o], row[o + 1], row[o + 2], row[o + 3] = u8(r), u8(g), u8(b), 255
		}
		for x in 0 ..< w {
			// 隣の画素の1/8を混ぜる
			r := (vr[x] >> 3) + vr[x + 1] + (vr[x + 2] >> 3)
			g := (vg[x] >> 3) + vg[x + 1] + (vg[x + 2] >> 3)
			b := (vb[x] >> 3) + vb[x + 1] + (vb[x + 2] >> 3)
			switch scale {
			case 3:
				// R・G・Bの縞: 1列目はRのみ、2列目はGのみ、3列目はBのみ
				cr := 32 + (full(r) if bright else dim(r))
				cg := 32 + (full(g) if bright else dim(g))
				cb := 32 + (full(b) if bright else dim(b))
				o := x * 3 * 4
				put(row, o, cr, 0, 0)
				put(row, o + 4, 0, cg, 0)
				put(row, o + 8, 0, 0, cb)
			case 2:
				// 明るい列と、少し暗い列
				o := x * 2 * 4
				if bright {
					put(row, o, 32 + full(r), 32 + full(g), 32 + full(b))
				} else {
					put(row, o, 32 + dim(r), 32 + dim(g), 32 + dim(b))
				}
				put(row, o + 4, 16 + dim(r), 16 + dim(g), 16 + dim(b))
			case:
				if bright {
					put(row, x * 4, 32 + full(r), 32 + full(g), 32 + full(b))
				} else {
					put(row, x * 4, 32 + dim(r), 32 + dim(g), 32 + dim(b))
				}
			}
		}
	}

	step := 2 if skip_line else 1
	// 1つの元の行から作る出力の行数と、そのうち明るい行の数
	// 3倍: 通常3行(明2,暗1) / 1行おき6行(明4,暗2)
	// 2倍: 通常2行(明1,暗1) / 1行おき4行(明3,暗1)
	// 1倍: 通常1行(明1)     / 1行おき2行(明1,暗1)
	rows_per_src, bright_rows: int
	switch scale {
	case 3:
		rows_per_src, bright_rows = (6 if skip_line else 3), (4 if skip_line else 2)
	case 2:
		rows_per_src, bright_rows = (4 if skip_line else 2), (3 if skip_line else 1)
	case:
		rows_per_src, bright_rows = (2 if skip_line else 1), 1
	}

	yy := 0
	for y := 0; y < h; y += step {
		line := src[y * w * 4:(y + 1) * w * 4]
		for x in 0 ..< w {
			r0[x + 1] = u32(line[x * 4 + 0])
			g0[x + 1] = u32(line[x * 4 + 1])
			b0[x + 1] = u32(line[x * 4 + 2])
		}
		for k in 0 ..< rows_per_src {
			write_row(dst, yy + k, out_w, scale, r0, g0, b0, w, k < bright_rows)
		}
		yy += rows_per_src
	}
}
