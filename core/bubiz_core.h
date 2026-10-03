/*
	BubiZ-2500 コアC API
	エミュレーションコア(CSP EmuZ-2500)をアプリケーション層(Odin)から使うための薄い層。
	コアは1プロセスに1インスタンスのみ。
*/

#ifndef BUBIZ_CORE_H
#define BUBIZ_CORE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// データディレクトリ(設定ファイル・BIOS ROM・ステートの置き場)を設定する。末尾の区切り文字は自動補完。
// bubiz_create より前に呼ぶこと。
void bubiz_set_data_dir(const char *dir);

// 設定ファイル(データディレクトリ内の相対名)を読む。無ければ既定値。bubiz_createより前に呼べる。
void bubiz_load_config(const char *name);
void bubiz_save_config(const char *name);

// 設定値の上書き(bubiz_createより前に呼ぶ)。未知のkeyはfalse。
// key: boot_mode, monitor_type, option_switch, sound_frequency, sound_latency,
//      scan_line, printer_type
bool bubiz_set_config(const char *key, int value);

// 生成・破棄(設定が未読込なら既定の設定ファイルを読む)
bool bubiz_create(void);
void bubiz_destroy(void);

// エミュレーション駆動: 1フレーム進める。返り値は実行したフレーム数
int bubiz_run(void);
double bubiz_frame_rate(void);
const char *bubiz_device_name(void);

// 画面: 描画してRGBA8(メモリ上R,G,B,Aの順)に変換した画素を返す。
// out_pixelsはbubiz_screen_size()で得た幅*高さ*4バイト以上の領域。
void bubiz_draw_screen(void);
void bubiz_screen_size(int *width, int *height);
void bubiz_screen_aspect(int *width, int *height);
void bubiz_read_screen_rgba(uint8_t *out_pixels);

// サウンド: ステレオ16bitのframes個を取り出す。返り値は実データのあったフレーム数(不足分は無音)
int bubiz_sound_rate(void);
size_t bubiz_pull_sound(int16_t *dest, size_t frames);

// 入力(Windows仮想キーコード)
void bubiz_key_down(int vk, bool repeat);
void bubiz_key_up(int vk);
void bubiz_key_lost_focus(void);
void bubiz_set_joystick(int index, uint32_t status);	// bit0-3:上下左右 bit4-:ボタン
void bubiz_set_mouse(int dx, int dy, int buttons);
void bubiz_enable_mouse(bool enable);

// 操作
void bubiz_reset(void);
void bubiz_special_reset(void);

// メディア
void bubiz_open_floppy(int drive, const char *path, int bank);
void bubiz_close_floppy(int drive);
bool bubiz_floppy_inserted(int drive);
void bubiz_open_hard_disk(int drive, const char *path);
void bubiz_close_hard_disk(int drive);
void bubiz_play_tape(int drive, const char *path);
void bubiz_rec_tape(int drive, const char *path);
void bubiz_close_tape(int drive);

// ステート
void bubiz_save_state(const char *path);
void bubiz_load_state(const char *path);

// 録画・キャプチャ
void bubiz_capture_screen(void);
bool bubiz_write_screenshot(const char *path);	// 現在の画面をBMPで保存
void bubiz_start_record_sound(void);
bool bubiz_start_record_sound_to(const char *path);	// 指定パスへWAV録音を開始
void bubiz_stop_record_sound(void);

// 電源オフ要求(ゲストが要求した場合)の有無
bool bubiz_power_off_requested(void);

#ifdef __cplusplus
}
#endif

#endif
