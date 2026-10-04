package bubiz

// コマンドラインの解釈（書式はQUASI88に準じる）
//   BubiZ-2500 [-option] [image-file [image-No]] ...

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

FLOPPY_DRIVES :: 4

Image_Kind :: enum {
	Floppy,
	Hard_Disk,
	Tape,
}

Image_Arg :: struct {
	path: string,
	bank: int, // 0始まりのイメージ番号
	kind: Image_Kind,
}

// ヘッドレス実行時に指定フレームで押すキー(検証用)
Key_Event :: struct {
	frame: int, // 押し始めるフレーム
	vk:    int, // Windows仮想キーコード
	hold:  int, // 押し続けるフレーム数
}

// ヘッドレス実行時に指定フレームでステートを保存/復元する(検証用)
State_Event :: struct {
	frame: int,
	slot:  int,
	load:  bool, // falseなら保存
}

// ヘッドレス実行時に指定フレームで画面を保存する(検証用)
Shot_Event :: struct {
	frame: int,
	path:  string,
}

Window_Size :: enum {
	Full, // 標準(640x400)
	Half,
	Double,
}

Options :: struct {
	// 実行制御
	help:          bool,
	version:       bool,
	verbose:       int,
	no_config:     bool,
	save_config:   bool,
	headless:      int, // >0ならウィンドウ無しでそのフレーム数だけ実行
	screenshot:    string, // headless終了時に保存するPNG
	wav:           string, // headless中の音声を録音するWAV
	keys:          [dynamic]Key_Event,
	shots:         [dynamic]Shot_Event,
	states:        [dynamic]State_Event,
	// ディレクトリ
	rom_dir:       string,
	disk_dir:      string,
	tape_dir:      string,
	snap_dir:      string,
	sound_dir:     string, // 録音(WAV)の保存先(空ならOS標準のミュージック)
	state_dir:     string,
	// イメージ
	floppies:      [FLOPPY_DRIVES]Image_Arg,
	floppy_count:  int,
	hard_disks:    [2]string,
	tape_load:     string,
	tape_save:     string,
	// エミュレーション
	boot_mode:     int, // -1=未指定
	monitor_type:  int,
	scan_line:     int, // -1=未指定
	option_switch: int,
	// 画面・音・入力
	fullscreen:    bool,
	window_size:   Window_Size,
	aspect_480:    bool, // true: 640x480(4:3)比率、false: 640x400比率
	aspect_set:    bool, // -aspectが指定されたか(未指定なら設定ファイルの値)
	width:         int,
	height:        int,
	wait:          bool, // false=ウェイト無し(全速)
	speed:         int, // 実時間との比率(%)
	sound:         bool,
	sample_freq:   int,
	mouse:         bool,
	joystick:      bool,
	joystick_set:  bool, // -joystick / -nojoystickが指定されたか
	show_fps:      bool,
	debug:         bool, // 起動時にデバッガーを開く
	filter:        Screen_Filter, // 画面フィルタ
	filter_set:    bool, // -filterが指定されたか
	interp:        bool, // 拡大時に補間する(既定は最近傍)
	resume:        bool,
	resume_file:   string,
}

default_options :: proc() -> Options {
	return Options{
		boot_mode = -1,
		monitor_type = -1,
		scan_line = -1,
		option_switch = -1,
		wait = true,
		speed = 100,
		sound = true,
		save_config = true, // 元の実装と同じく、終了時に設定を保存する
		window_size = .Full,
	}
}

Parse_Error :: struct {
	message: string,
}

// イメージ種別を拡張子から判定する
image_kind_of :: proc(path: string) -> Image_Kind {
	lower := strings.to_lower(path, context.temp_allocator)
	for ext in ([]string{".hdd", ".hdi", ".nhd", ".thd", ".dat"}) {
		if strings.has_suffix(lower, ext) {
			return .Hard_Disk
		}
	}
	for ext in ([]string{".wav", ".mzt", ".m12", ".mti", ".cas", ".cmt", ".t88"}) {
		if strings.has_suffix(lower, ext) {
			return .Tape
		}
	}
	return .Floppy
}

// "<frame>:<key>[:<hold>]" を解釈する
parse_key_event :: proc(s: string) -> (ev: Key_Event, err: string) {
	parts := strings.split(s, ":", context.temp_allocator)
	if len(parts) < 2 || len(parts) > 3 {
		return ev, fmt.aprintf("オプション -key の書式は <frame>:<key>[:<hold>] です: %s", s)
	}
	frame, ok := strconv.parse_int(parts[0])
	if !ok || frame < 0 {
		return ev, fmt.aprintf("オプション -key のフレーム指定が不正です: %s", parts[0])
	}
	vk := vk_from_name(parts[1])
	if vk == 0 {
		return ev, fmt.aprintf("オプション -key のキー名が不明です: %s", parts[1])
	}
	hold := 3
	if len(parts) == 3 {
		hold, ok = strconv.parse_int(parts[2])
		if !ok || hold < 1 {
			return ev, fmt.aprintf("オプション -key の押下フレーム数が不正です: %s", parts[2])
		}
	}
	return Key_Event{frame = frame, vk = vk, hold = hold}, ""
}

// 次の引数が値として存在するか確認して取り出す
@(private = "file")
take_value :: proc(args: []string, i: ^int, name: string) -> (value: string, ok: bool) {
	if i^ + 1 >= len(args) {
		return "", false
	}
	i^ += 1
	return args[i^], true
}

@(private = "file")
take_int :: proc(args: []string, i: ^int, name: string) -> (value: int, err: string) {
	s, ok := take_value(args, i, name)
	if !ok {
		return 0, fmt.aprintf("オプション %s には値が必要です", name)
	}
	v, parsed := strconv.parse_int(s)
	if !parsed {
		return 0, fmt.aprintf("オプション %s の値が整数ではありません: %s", name, s)
	}
	return v, ""
}

@(private = "file")
all_digits :: proc(s: string) -> bool {
	if len(s) == 0 {
		return false
	}
	for c in s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// 引数列を解釈する。errorが空でなければ不正。
parse_args :: proc(args: []string) -> (opt: Options, err: string) {
	opt = default_options()
	last_floppy := -1 // 直近のフロッピー引数(イメージ番号の受け取り先)
	numbered := -1 // 番号を受け取ったフロッピー(同一ファイルの2台目指定に使う)

	for i := 0; i < len(args); i += 1 {
		a := args[i]
		if len(a) == 0 {
			continue
		}
		if a[0] != '-' {
			// イメージ番号: 直前のフロッピーに続く数字
			if last_floppy >= 0 && all_digits(a) {
				n, _ := strconv.parse_int(a)
				if n < 1 {
					return opt, fmt.aprintf("イメージ番号は1以上です: %s", a)
				}
				opt.floppies[last_floppy].bank = n - 1
				numbered = last_floppy
				last_floppy = -1
				continue
			}
			// ファイルが1つだけのとき、続けて番号を指定すると同じファイルを2台目にも割り当てる
			if numbered == 0 && opt.floppy_count == 1 && all_digits(a) {
				n, _ := strconv.parse_int(a)
				if n < 1 {
					return opt, fmt.aprintf("イメージ番号は1以上です: %s", a)
				}
				opt.floppies[1] = Image_Arg{path = opt.floppies[0].path, bank = n - 1, kind = .Floppy}
				opt.floppy_count = 2
				numbered = -1
				continue
			}
			numbered = -1
			kind := image_kind_of(a)
			switch kind {
			case .Floppy:
				if opt.floppy_count < FLOPPY_DRIVES {
					opt.floppies[opt.floppy_count] = Image_Arg{path = a, kind = .Floppy}
					last_floppy = opt.floppy_count
					opt.floppy_count += 1
				} // 超過分は無視（QUASI88と同様）
			case .Hard_Disk:
				if opt.hard_disks[0] == "" {
					opt.hard_disks[0] = a
				} else {
					opt.hard_disks[1] = a
				}
				last_floppy = -1
			case .Tape:
				opt.tape_load = a
				last_floppy = -1
			}
			continue
		}

		last_floppy = -1
		numbered = -1
		name := a
		// "--option" も "-option" として扱う
		if strings.has_prefix(name, "--") {
			name = name[1:]
		}
		msg: string
		switch name {
		case "-help", "-h", "-?":
			opt.help = true
		case "-version":
			opt.version = true
		case "-verbose":
			opt.verbose, msg = take_int(args, &i, name)
		case "-noconfig":
			opt.no_config = true
		case "-saveconfig":
			opt.save_config = true
		case "-nosaveconfig":
			opt.save_config = false
		case "-romdir":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -romdir には値が必要です"}
			opt.rom_dir = v
		case "-diskdir":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -diskdir には値が必要です"}
			opt.disk_dir = v
		case "-tapedir":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -tapedir には値が必要です"}
			opt.tape_dir = v
		case "-sounddir":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -sounddir には値が必要です"}
			opt.sound_dir = v
		case "-snapdir":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -snapdir には値が必要です"}
			opt.snap_dir = v
		case "-statedir":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -statedir には値が必要です"}
			opt.state_dir = v
		case "-diskimage":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -diskimage には値が必要です"}
			if opt.floppy_count < FLOPPY_DRIVES {
				opt.floppies[opt.floppy_count] = Image_Arg{path = v, kind = .Floppy}
				last_floppy = opt.floppy_count
				opt.floppy_count += 1
			}
		case "-hd1", "-hd2":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, fmt.aprintf("オプション %s には値が必要です", name)}
			opt.hard_disks[0 if name == "-hd1" else 1] = v
		case "-tapeload":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -tapeload には値が必要です"}
			opt.tape_load = v
		case "-tapesave":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -tapesave には値が必要です"}
			opt.tape_save = v
		case "-mz2500":
			opt.boot_mode = 0
		case "-mz2000":
			opt.boot_mode = 1
		case "-mz80b":
			opt.boot_mode = 2
		case "-monitor":
			opt.monitor_type, msg = take_int(args, &i, name)
		case "-optsw":
			opt.option_switch, msg = take_int(args, &i, name)
		case "-skipline", "-interlace":
			opt.scan_line = 0
		case "-nointerlace", "-scanline":
			opt.scan_line = 1
		case "-full":
			opt.window_size = .Full
		case "-half":
			opt.window_size = .Half
		case "-double":
			opt.window_size = .Double
		case "-aspect":
			v: int
			v, msg = take_int(args, &i, name)
			if msg == "" {
				switch v {
				case 400: opt.aspect_480, opt.aspect_set = false, true
				case 480: opt.aspect_480, opt.aspect_set = true, true
				case: msg = "-aspect には 400 か 480 を指定してください"
				}
			}
		case "-fullscreen":
			opt.fullscreen = true
		case "-window":
			opt.fullscreen = false
		case "-width":
			opt.width, msg = take_int(args, &i, name)
		case "-height":
			opt.height, msg = take_int(args, &i, name)
		case "-wait":
			opt.wait = true
		case "-nowait":
			opt.wait = false
		case "-speed":
			opt.speed, msg = take_int(args, &i, name)
			if msg == "" && opt.speed <= 0 {
				msg = "オプション -speed の値は1以上です"
			}
		case "-sound", "-snd":
			opt.sound = true
		case "-nosound", "-nosnd":
			opt.sound = false
		case "-samplefreq", "-sf":
			opt.sample_freq, msg = take_int(args, &i, name)
		case "-mouse":
			opt.mouse = true
		case "-nomouse":
			opt.mouse = false
		case "-joystick", "-use_joy":
			opt.joystick, opt.joystick_set = true, true
		case "-nojoystick", "-nouse_joy":
			opt.joystick, opt.joystick_set = false, true
		case "-debug", "-monitor_mode":
			opt.debug = true
		case "-filter":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -filter には値が必要です"}
			switch strings.to_lower(v, context.temp_allocator) {
			case "none": opt.filter, opt.filter_set = .None, true
			case "rgb": opt.filter, opt.filter_set = .RGB, true
			case: return opt, fmt.aprintf("オプション -filter の値は none か rgb です: %s", v)
			}
		case "-interp":
			opt.interp = true
		case "-nointerp":
			opt.interp = false
		case "-show_fps":
			opt.show_fps = true
		case "-hide_fps":
			opt.show_fps = false
		case "-resume":
			opt.resume = true
		case "-resumefile":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -resumefile には値が必要です"}
			opt.resume = true
			opt.resume_file = v
		case "-headless":
			opt.headless, msg = take_int(args, &i, name)
		case "-wav":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -wav には値が必要です"}
			opt.wav = v
		case "-key":
			// -key <frame>:<key>[:<hold>]  例: -key 3000:1  -key 3200:RETURN:5
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -key には値が必要です"}
			ev, kerr := parse_key_event(v)
			if kerr != "" {return opt, kerr}
			append(&opt.keys, ev)
		case "-savestate", "-loadstate":
			// -savestate <frame>:<slot>  -loadstate <frame>:<slot>  (-headless中)
			v, ok := take_value(args, &i, name)
			if !ok {return opt, fmt.aprintf("オプション %s には値が必要です", name)}
			parts := strings.split(v, ":", context.temp_allocator)
			frame, slot := 0, 0
			ok1, ok2 := false, false
			if len(parts) == 2 {
				frame, ok1 = strconv.parse_int(parts[0])
				slot, ok2 = strconv.parse_int(parts[1])
			}
			if !ok1 || !ok2 || frame < 0 || slot < 0 {
				return opt, fmt.aprintf("オプション %s の書式は <frame>:<slot> です: %s", name, v)
			}
			append(&opt.states, State_Event{frame = frame, slot = slot, load = name == "-loadstate"})
		case "-shotat":
			// -shotat <frame>:<file>  指定フレームで画面をPNG保存
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -shotat には値が必要です"}
			idx := strings.index_byte(v, ':')
			frame, parsed := 0, false
			if idx > 0 {
				frame, parsed = strconv.parse_int(v[:idx])
			}
			if !parsed || frame < 0 || idx + 1 >= len(v) {
				return opt, fmt.aprintf("オプション -shotat の書式は <frame>:<file> です: %s", v)
			}
			append(&opt.shots, Shot_Event{frame = frame, path = v[idx + 1:]})
		case "-screenshot":
			v, ok := take_value(args, &i, name)
			if !ok {return opt, "オプション -screenshot には値が必要です"}
			opt.screenshot = v
		case:
			return opt, fmt.aprintf("不明なオプションです: %s", a)
		}
		if msg != "" {
			return opt, msg
		}
	}
	return opt, ""
}

usage :: proc() {
	fmt.println("使い方: BubiZ-2500 [-option] [image-file [image-No]] [image-file [image-No]] ...")
	fmt.println()
	fmt.println("  イメージファイルは拡張子で判定します。フロッピーは最大4台(ドライブ1:〜4:)に")
	fmt.println("  先頭から順に割り当てます。直後の数字は複数イメージ内の番号(1始まり)です。")
	fmt.println()
	fmt.println("  -help               このヘルプを表示して終了")
	fmt.println("  -version            バージョンを表示して終了")
	fmt.println("  -verbose <n>        冗長レベル")
	fmt.println("  -romdir <path>      BIOS ROM・設定・ステートのディレクトリ")
	fmt.println("  -diskdir <path>     ディスクイメージのディレクトリ")
	fmt.println("  -tapedir <path>     テープイメージのディレクトリ")
	fmt.println("  -sounddir <path>    録音(WAV)の保存先(既定: ミュージック/BubiZ-2500)")
	fmt.println("  -snapdir <path>     スクリーンショットの保存先(既定: ピクチャ/BubiZ-2500)")
	fmt.println("  -statedir <path>    ステート保存先")
	fmt.println("  -noconfig           設定ファイルを読み込まない")
	fmt.println("  -saveconfig         終了時に設定ファイルを更新する")
	fmt.println("  -nosaveconfig       終了時に設定ファイルを更新しない")
	fmt.println("  -hd1 <file>         ハードディスク1を接続")
	fmt.println("  -hd2 <file>         ハードディスク2を接続")
	fmt.println("  -tapeload <file>    ロード用テープイメージ")
	fmt.println("  -tapesave <file>    セーブ用テープイメージ")
	fmt.println("  -mz2500 | -mz2000 | -mz80b   起動モード")
	fmt.println("  -monitor <n>        モニタータイプ")
	fmt.println("  -optsw <n>          オプションスイッチ(拡張ボード構成)")
	fmt.println("  -skipline | -interlace   走査線を描画しない")
	fmt.println("  -nointerlace | -scanline 走査線を描画する")
	fmt.println("  -full | -half | -double  画面サイズ(標準 / 半分 / 2倍)")
	fmt.println("  -aspect <400|480>        画面の縦横比(640x400 / 640x480、既定は400)")
	fmt.println("  -fullscreen | -window    フルスクリーン / ウィンドウ")
	fmt.println("  -width <x> -height <y>   ウィンドウサイズ")
	fmt.println("  -wait | -nowait     ウェイトあり / なし(全速)")
	fmt.println("  -speed <rate>       実時間との比率(%)")
	fmt.println("  -sound | -nosound   サウンドの有無")
	fmt.println("  -samplefreq <hz>    サンプリング周波数")
	fmt.println("  -mouse | -nomouse   マウスのエミュレート")
	fmt.println("  -joystick | -nojoystick   キーボードによるジョイスティックで起動する / しない(既定: しない)")
	fmt.println("  -filter <none|rgb>        画面フィルタ(rgb: CRTのRGBサブピクセル表示。既定: none)")
	fmt.println("  -interp | -nointerp       画面の拡大時に補間する / しない(既定: しない)")
	fmt.println("  -show_fps | -hide_fps     ウィンドウタイトルにFPS(エミュレーション速度)を表示")
	fmt.println("  -debug              起動時にデバッガーを開く(ウィンドウ内のデバッガー画面。-headlessでは端末を使う。'?'でコマンド一覧)")
	fmt.println("  -resume             起動時にステートをロード")
	fmt.println("  -resumefile <file>  起動時に指定ステートをロード")
	fmt.println()
	fmt.println("  ウィンドウ上のホットキー:")
	fmt.println("    F11          フルスクリーンの切り替え")
	fmt.println("    F12          リセット (Ctrl+F12: スペシャルリセット)")
	fmt.println("    Ctrl+P       一時停止 / 再開")
	fmt.println("    Ctrl+S       スクリーンショットを保存(ピクチャ/BubiZ-2500へPNG)")
	fmt.println("    Ctrl+F1〜F4        ステートを保存(スロット1〜4)")
	fmt.println("    Ctrl+Shift+F1〜F4  ステートを復元(スロット1〜4)")
	fmt.println("    Ctrl+F       画面フィルタ(RGB)の切り替え")
	fmt.println("    Ctrl+J       キーボードによるジョイスティックの切り替え(矢印キー=方向, Z=ボタン1, X=ボタン2)")
	fmt.println("    Ctrl+D       デバッガーを開く(端末の標準入出力を使う)")
	fmt.println("    Ctrl+M       マウスのキャプチャ切り替え(-mouse指定時は最初のクリックでも開始)")
	fmt.println("    ドラッグ&ドロップ  ディスクイメージ・テープ・ハードディスクを挿入")
	fmt.println()
	fmt.println("  -headless <frames>  ウィンドウ無しで指定フレーム数実行して終了(検証用)")
	fmt.println("  -screenshot <file>  -headless終了時の画面をPNGで保存")
	fmt.println("  -key <frame>:<key>[:<hold>]  -headless中、指定フレームでキーを押す(複数指定可)")
	fmt.println("                      key: 英数字1文字 / RETURN SPACE ESC TAB BS UP DOWN LEFT RIGHT F1-F12 SHIFT CTRL ...")
	fmt.println("                      hold: 押し続けるフレーム数(既定3)")
	fmt.println("  -wav <file>         -headless中の音声をWAVで録音(-nosoundと併用不可)")
	fmt.println("  -savestate <frame>:<slot>  -headless中、指定フレームでステートを保存(スロット番号は0から)")
	fmt.println("  -loadstate <frame>:<slot>  -headless中、指定フレームでステートを復元")
	fmt.println("  -shotat <frame>:<file>  -headless中、指定フレームの画面をBMPで保存(複数指定可)")
}

print_version :: proc() {
	fmt.printfln("BubiZ-2500 %s", VERSION)
}

exit_with_error :: proc(msg: string) -> ! {
	fmt.eprintfln("BubiZ-2500: %s", msg)
	fmt.eprintln("ヘルプは BubiZ-2500 -help を参照してください。")
	os.exit(2)
}
