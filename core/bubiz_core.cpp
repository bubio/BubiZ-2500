/*
	BubiZ-2500 コアC API 実装
*/

#include <string>
#include "bubiz_core.h"
#include "csp/emu.h"
#include "csp/config.h"
#include "csp/common.h"

extern std::string cpp_homedir;

static EMU *g_emu = NULL;
static bool g_config_loaded = false;

void bubiz_set_data_dir(const char *dir)
{
	std::string d = dir;
	if(!d.empty() && d.back() != '/' && d.back() != '\\') {
		d += '/';
	}
	cpp_homedir = d;
}

bool bubiz_create(void)
{
	if(g_emu != NULL) {
		return true;
	}
	if(!g_config_loaded) {
		bubiz_load_config(CONFIG_NAME ".ini");
	}
	g_emu = new EMU();
	return true;
}

void bubiz_destroy(void)
{
	delete g_emu;
	g_emu = NULL;
}

void bubiz_load_config(const char *name)
{
	// 設定ファイルが無ければ既定値で初期化される
	load_config(create_local_path(_T("%s"), name));
	g_config_loaded = true;
}

bool bubiz_set_config(const char *key, int value)
{
	if(!g_config_loaded) {
		bubiz_load_config(CONFIG_NAME ".ini");
	}
	std::string k = key;
	if(k == "boot_mode") config.boot_mode = value;
	else if(k == "monitor_type") config.monitor_type = value;
	else if(k == "option_switch") config.option_switch = value;
	else if(k == "sound_frequency") config.sound_frequency = value;
	else if(k == "sound_latency") config.sound_latency = value;
	else if(k == "scan_line") config.scan_line = (value != 0);
	else if(k == "printer_type") config.printer_type = value;
	else return false;
	return true;
}

void bubiz_save_config(const char *name)
{
	save_config(create_local_path(_T("%s"), name));
}

int bubiz_run(void)
{
	return g_emu ? g_emu->run() : 0;
}

double bubiz_frame_rate(void)
{
	return g_emu ? g_emu->get_frame_rate() : 55.49;
}

const char *bubiz_device_name(void)
{
	return g_emu ? g_emu->device_name() : "";
}

void bubiz_draw_screen(void)
{
	if(g_emu) {
		g_emu->draw_screen();
	}
}

void bubiz_screen_size(int *width, int *height)
{
	const bitmap_t *b = g_emu ? g_emu->get_osd()->get_draw_buffer() : NULL;
	*width = b ? b->width : 0;
	*height = b ? b->height : 0;
}

void bubiz_screen_aspect(int *width, int *height)
{
	OSD *osd = g_emu ? g_emu->get_osd() : NULL;
	*width = osd ? osd->get_vm_window_width_aspect() : 0;
	*height = osd ? osd->get_vm_window_height_aspect() : 0;
}

void bubiz_read_screen_rgba(uint8_t *out_pixels)
{
	const bitmap_t *b = g_emu ? g_emu->get_osd()->get_draw_buffer() : NULL;
	if(b == NULL) {
		return;
	}
	size_t n = (size_t)b->width * b->height;
	for(size_t i = 0; i < n; i++) {
		scrntype_t c = b->pixels[i];
		out_pixels[i * 4    ] = R_OF_COLOR(c);
		out_pixels[i * 4 + 1] = G_OF_COLOR(c);
		out_pixels[i * 4 + 2] = B_OF_COLOR(c);
		out_pixels[i * 4 + 3] = 0xff;
	}
}

int bubiz_sound_rate(void)
{
	return g_emu ? g_emu->get_sound_rate() : 48000;
}

size_t bubiz_pull_sound(int16_t *dest, size_t frames)
{
	if(g_emu == NULL) {
		for(size_t i = 0; i < frames * 2; i++) {
			dest[i] = 0;
		}
		return 0;
	}
	return g_emu->get_osd()->pull_sound(dest, frames);
}

void bubiz_key_down(int vk, bool repeat)
{
	if(g_emu) {
		g_emu->key_down(vk, false, repeat);
	}
}

void bubiz_key_up(int vk)
{
	if(g_emu) {
		g_emu->key_up(vk, false);
	}
}

void bubiz_key_lost_focus(void)
{
	if(g_emu) {
		g_emu->key_lost_focus();
	}
}

void bubiz_set_joystick(int index, uint32_t status)
{
#ifdef USE_JOYSTICK
	if(g_emu && 0 <= index && index < 4) {
		g_emu->get_osd()->get_joy_buffer()[index] = status;
	}
#endif
}

void bubiz_set_mouse(int dx, int dy, int buttons)
{
#ifdef USE_MOUSE
	if(g_emu) {
		g_emu->get_osd()->set_mouse_state(dx, dy, buttons);
	}
#endif
}

void bubiz_enable_mouse(bool enable)
{
#ifdef USE_MOUSE
	if(g_emu) {
		if(enable) {
			g_emu->enable_mouse();
		} else {
			g_emu->disable_mouse();
		}
	}
#endif
}

void bubiz_reset(void)
{
	if(g_emu) {
		g_emu->reset();
	}
}

void bubiz_special_reset(void)
{
	if(g_emu) {
		g_emu->special_reset();
	}
}

void bubiz_open_floppy(int drive, const char *path, int bank)
{
	if(g_emu) {
		g_emu->open_floppy_disk(drive, path, bank);
	}
}

void bubiz_close_floppy(int drive)
{
	if(g_emu) {
		g_emu->close_floppy_disk(drive);
	}
}

bool bubiz_floppy_inserted(int drive)
{
	return g_emu && g_emu->is_floppy_disk_inserted(drive);
}

void bubiz_open_hard_disk(int drive, const char *path)
{
	if(g_emu) {
		g_emu->open_hard_disk(drive, path);
	}
}

void bubiz_close_hard_disk(int drive)
{
	if(g_emu) {
		g_emu->close_hard_disk(drive);
	}
}

void bubiz_play_tape(int drive, const char *path)
{
	if(g_emu) {
		g_emu->play_tape(drive, path);
	}
}

void bubiz_rec_tape(int drive, const char *path)
{
	if(g_emu) {
		g_emu->rec_tape(drive, path);
	}
}

void bubiz_close_tape(int drive)
{
	if(g_emu) {
		g_emu->close_tape(drive);
	}
}

void bubiz_save_state(const char *path)
{
	if(g_emu) {
		g_emu->save_state(path);
	}
}

void bubiz_load_state(const char *path)
{
	if(g_emu) {
		g_emu->load_state(path);
	}
}

void bubiz_capture_screen(void)
{
	if(g_emu) {
		g_emu->capture_screen();
	}
}

bool bubiz_write_screenshot(const char *path)
{
	if(g_emu == NULL) {
		return false;
	}
	OSD *osd = g_emu->get_osd();
	osd->write_bitmap_to_file(const_cast<bitmap_t *>(osd->get_draw_buffer()), path);
	return true;
}

void bubiz_start_record_sound(void)
{
	if(g_emu) {
		g_emu->start_record_sound();
	}
}

void bubiz_stop_record_sound(void)
{
	if(g_emu) {
		g_emu->stop_record_sound();
	}
}

bool bubiz_power_off_requested(void)
{
	return g_emu && g_emu->get_osd()->power_off_requested;
}
