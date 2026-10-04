package bubiz

// 設定ファイルなどの置き場所（OSの習慣に従う）

import "core:fmt"
import "core:os"
import "core:strings"

APP_DIR_NAME :: "BubiZ-2500"

// 設定・BIOS ROM・ステートを置くデータディレクトリを返す
default_data_dir :: proc() -> string {
	when ODIN_OS == .Windows {
		base := os.get_env("APPDATA", context.temp_allocator)
		if base != "" {
			return fmt.aprintf("%s\\%s", base, APP_DIR_NAME)
		}
	} else when ODIN_OS == .Darwin {
		home := os.get_env("HOME", context.temp_allocator)
		if home != "" {
			return fmt.aprintf("%s/Library/Application Support/%s", home, APP_DIR_NAME)
		}
	} else {
		// 他のエミュレーターと同じく、XDGのデータディレクトリ(~/.local/share)に置く
		home := os.get_env("HOME", context.temp_allocator)
		data := os.get_env("XDG_DATA_HOME", context.temp_allocator)
		if data == "" && home != "" {
			data = fmt.tprintf("%s/.local/share", home)
		}
		if data != "" {
			dir := fmt.aprintf("%s/%s", data, APP_DIR_NAME)
			// 以前の版が使っていた ~/.config 側にだけデータがある場合は、そちらを引き続き使う
			if !os.exists(dir) && home != "" {
				cfg := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
				if cfg == "" {cfg = fmt.tprintf("%s/.config", home)}
				old := fmt.tprintf("%s/%s", cfg, APP_DIR_NAME)
				if os.exists(old) {
					delete(dir)
					return strings.clone(old)
				}
			}
			return dir
		}
	}
	return strings.clone(".")
}

// OS標準のユーザーフォルダ(ピクチャ・ミュージックなど)の下のBubiZ-2500。
// name は "Pictures" / "Music"、xdg_key は "PICTURES" / "MUSIC"
default_user_media_dir :: proc(name, xdg_key: string) -> string {
	when ODIN_OS == .Windows {
		base := os.get_env("USERPROFILE", context.temp_allocator)
		if base != "" {
			return fmt.aprintf("%s\\%s\\%s", base, name, APP_DIR_NAME)
		}
	} else {
		home := os.get_env("HOME", context.temp_allocator)
		if home != "" {
			folder := fmt.tprintf("%s/%s", home, name)
			when ODIN_OS != .Darwin {
				// XDGのユーザーディレクトリ設定があれば従う
				cfg := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
				if cfg == "" {cfg = fmt.tprintf("%s/.config", home)}
				if data, err := os.read_entire_file(fmt.tprintf("%s/user-dirs.dirs", cfg), context.temp_allocator); err == nil {
					prefix := fmt.tprintf("XDG_%s_DIR=", xdg_key)
					for line in strings.split_lines(string(data), context.temp_allocator) {
						if strings.has_prefix(line, prefix) {
							v := strings.trim(line[len(prefix):], "\"")
							folder, _ = strings.replace_all(v, "$HOME", home, context.temp_allocator)
						}
					}
				}
			}
			return fmt.aprintf("%s/%s", folder, APP_DIR_NAME)
		}
	}
	return strings.clone(".")
}

// スクリーンショットの既定の保存先(ピクチャ/BubiZ-2500)
default_snap_dir :: proc() -> string {
	return default_user_media_dir("Pictures", "PICTURES")
}

// 録音(WAV)の既定の保存先(ミュージック/BubiZ-2500)
default_sound_dir :: proc() -> string {
	return default_user_media_dir("Music", "MUSIC")
}

// ディレクトリを(親も含めて)作成する
ensure_dir :: proc(path: string) -> bool {
	if os.exists(path) {
		return true
	}
	// 親から順に作る
	sep := '\\' when ODIN_OS == .Windows else '/'
	for i in 1 ..< len(path) {
		if rune(path[i]) == sep {
			parent := path[:i]
			if !os.exists(parent) {
				os.make_directory(parent)
			}
		}
	}
	return os.make_directory(path) == nil
}

// 表示用にホームディレクトリを~に置き換える（ユーザー名を表示しないため）
display_path :: proc(path: string) -> string {
	home := os.get_env("HOME", context.temp_allocator)
	if home != "" && strings.has_prefix(path, home) {
		return fmt.tprintf("~%s", path[len(home):])
	}
	return path
}
