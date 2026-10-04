// コアの煙テスト: ROM無しでも生成・駆動・描画・サウンド取得が動くこと
#include <stdio.h>
#include <stdlib.h>
#include <vector>
#include "../bubiz_core.h"

int main(int argc, char **argv)
{
	bubiz_set_data_dir(argc > 1 ? argv[1] : ".");
	if(!bubiz_create()) {
		fprintf(stderr, "create failed\n");
		return 1;
	}
	printf("device: %s fps=%.2f rate=%d\n", bubiz_device_name(), bubiz_frame_rate(), bubiz_sound_rate());
	size_t pulled = 0;
	std::vector<int16_t> snd(4096 * 2);
	for(int i = 0; i < 300; i++) {
		bubiz_run();
		bubiz_draw_screen();
		pulled += bubiz_pull_sound(snd.data(), 800);
	}
	int w, h, aw, ah;
	bubiz_screen_size(&w, &h);
	bubiz_screen_aspect(&aw, &ah);
	std::vector<uint8_t> px((size_t)w * h * 4);
	bubiz_read_screen_rgba(px.data());
	printf("screen %dx%d aspect %dx%d, sound frames pulled=%zu\n", w, h, aw, ah, pulled);
	bubiz_destroy();
	return (w > 0 && h > 0) ? 0 : 1;
}
