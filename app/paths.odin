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
		xdg := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
		if xdg != "" {
			return fmt.aprintf("%s/%s", xdg, APP_DIR_NAME)
		}
		home := os.get_env("HOME", context.temp_allocator)
		if home != "" {
			return fmt.aprintf("%s/.config/%s", home, APP_DIR_NAME)
		}
	}
	return strings.clone(".")
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
