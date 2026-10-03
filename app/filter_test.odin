package bubiz

import "core:testing"

// 単色の画面にRGBフィルタを掛けたときの、1画素ぶん(3x3)の出力を、元の計算式と突き合わせる
@(test)
test_rgb_filter_uniform :: proc(t: ^testing.T) {
	// 3x3の白(255,255,255)の画面。中央の画素は両隣の1/8を足す
	w, h := 3, 3
	src := make([]u8, w * h * 4)
	defer delete(src)
	for i in 0 ..< w * h {
		src[i * 4], src[i * 4 + 1], src[i * 4 + 2], src[i * 4 + 3] = 255, 255, 255, 255
	}
	dst := make([]u8, w * 3 * h * 3 * 4)
	defer delete(dst)
	apply_rgb_filter(src, w, h, false, 3, dst)

	out_w := w * 3
	px :: proc(dst: []u8, out_w, x, y: int) -> [3]u8 {
		o := (y * out_w + x) * 4
		return {dst[o], dst[o + 1], dst[o + 2]}
	}
	// 中央の画素(x=1)は r = 31 + 255 + 31 = 317 → 32 + (317*180>>8) = 254
	// 明るい行(行0,1)はRの縞が254, 暗い行(行2)は (317*3>>3)*180>>8 = 82 → 32 + 82 = 114
	testing.expect_value(t, px(dst, out_w, 3, 3), [3]u8{254, 0, 0})
	testing.expect_value(t, px(dst, out_w, 4, 3), [3]u8{0, 254, 0})
	testing.expect_value(t, px(dst, out_w, 5, 3), [3]u8{0, 0, 254})
	testing.expect_value(t, px(dst, out_w, 3, 4), [3]u8{254, 0, 0})
	testing.expect_value(t, px(dst, out_w, 3, 5), [3]u8{114, 0, 0})
	// 左端の画素(外側は0扱い) r = 0 + 255 + 31 = 286 → 32 + (286*180>>8) = 233
	testing.expect_value(t, px(dst, out_w, 0, 0), [3]u8{233, 0, 0})
}

// 1行おきの表示(skip_line)では、出力は元の2行ごとに6行になり、奇数行の元データは使われない
@(test)
test_rgb_filter_skip_line :: proc(t: ^testing.T) {
	w, h := 2, 4
	src := make([]u8, w * h * 4)
	defer delete(src)
	for y in 0 ..< h {
		for x in 0 ..< w {
			o := (y * w + x) * 4
			v: u8 = 200 if y % 2 == 0 else 7 // 偶数行は有効、奇数行は使われない
			src[o], src[o + 1], src[o + 2], src[o + 3] = v, v, v, 255
		}
	}
	dst := make([]u8, w * 3 * h * 3 * 4)
	defer delete(dst)
	apply_rgb_filter(src, w, h, true, 3, dst)
	// 出力の全ての画素が、値7の影響を受けていない(偶数行の値200から作られる)こと
	out_w := w * 3
	for y in 0 ..< h * 3 {
		o := (y * out_w + 0) * 4
		testing.expect(t, dst[o] > 50, "奇数行(値7)が混ざっている")
	}
}

// 2倍・1倍: 単色の白で、明るい列/暗い列と行ごとの値を確認する
@(test)
test_rgb_filter_scale_2_and_1 :: proc(t: ^testing.T) {
	w, h := 3, 2
	src := make([]u8, w * h * 4)
	defer delete(src)
	for i in 0 ..< w * h {
		src[i * 4], src[i * 4 + 1], src[i * 4 + 2], src[i * 4 + 3] = 255, 255, 255, 255
	}
	// 中央の画素: 混ぜた値 317 → 明: 32+(317*180>>8)=254, 暗: 32+82=114, 暗い列: 16+82=98
	dst2 := make([]u8, w * 2 * h * 2 * 4)
	defer delete(dst2)
	apply_rgb_filter(src, w, h, false, 2, dst2)
	out_w := w * 2
	px :: proc(dst: []u8, out_w, x, y: int) -> [3]u8 {
		o := (y * out_w + x) * 4
		return {dst[o], dst[o + 1], dst[o + 2]}
	}
	testing.expect_value(t, px(dst2, out_w, 2, 0), [3]u8{254, 254, 254}) // 明るい行の明るい列
	testing.expect_value(t, px(dst2, out_w, 3, 0), [3]u8{98, 98, 98}) // 明るい行の暗い列
	testing.expect_value(t, px(dst2, out_w, 2, 1), [3]u8{114, 114, 114}) // 暗い行の明るい列
	testing.expect_value(t, px(dst2, out_w, 3, 1), [3]u8{98, 98, 98}) // 暗い行の暗い列

	dst1 := make([]u8, w * h * 4)
	defer delete(dst1)
	apply_rgb_filter(src, w, h, false, 1, dst1)
	testing.expect_value(t, px(dst1, w, 1, 0), [3]u8{254, 254, 254})
	// 1行おき(1倍)では、2行ごとに(明,暗)の2行になる
	dst1s := make([]u8, w * h * 4)
	defer delete(dst1s)
	apply_rgb_filter(src, w, h, true, 1, dst1s)
	testing.expect_value(t, px(dst1s, w, 1, 0), [3]u8{254, 254, 254})
	testing.expect_value(t, px(dst1s, w, 1, 1), [3]u8{114, 114, 114})
}

@(test)
test_filter_scale_for :: proc(t: ^testing.T) {
	testing.expect_value(t, filter_scale_for(1.0), 1)
	testing.expect_value(t, filter_scale_for(1.5), 2)
	testing.expect_value(t, filter_scale_for(2.4), 2)
	testing.expect_value(t, filter_scale_for(3.0), 3)
}
