package bubiz

// ホストのキーコード(sokol_app)からWindows仮想キーコード(CSPが使う体系)への変換

import sapp "sokol:app"

to_vk :: proc(k: sapp.Keycode) -> int {
	#partial switch k {
	case .SPACE: return 0x20
	case .APOSTROPHE: return 0xDE
	case .COMMA: return 0xBC
	case .MINUS: return 0xBD
	case .PERIOD: return 0xBE
	case .SLASH: return 0xBF
	case ._0 ..= ._9: return 0x30 + int(k) - int(sapp.Keycode._0)
	case .SEMICOLON: return 0xBA
	case .EQUAL: return 0xBB
	case .A ..= .Z: return 0x41 + int(k) - int(sapp.Keycode.A)
	case .LEFT_BRACKET: return 0xDB
	case .BACKSLASH: return 0xDC
	case .RIGHT_BRACKET: return 0xDD
	case .GRAVE_ACCENT: return 0xC0
	case .WORLD_1, .WORLD_2: return 0xE2
	case .ESCAPE: return 0x1B
	case .ENTER: return 0x0D
	case .TAB: return 0x09
	case .BACKSPACE: return 0x08
	case .INSERT: return 0x2D
	case .DELETE: return 0x2E
	case .RIGHT: return 0x27
	case .LEFT: return 0x25
	case .DOWN: return 0x28
	case .UP: return 0x26
	case .PAGE_UP: return 0x21
	case .PAGE_DOWN: return 0x22
	case .HOME: return 0x24
	case .END: return 0x23
	case .CAPS_LOCK: return 0x14
	case .SCROLL_LOCK: return 0x91
	case .NUM_LOCK: return 0x90
	case .PRINT_SCREEN: return 0x2C
	case .PAUSE: return 0x13
	case .F1 ..= .F12: return 0x70 + int(k) - int(sapp.Keycode.F1)
	case .KP_0 ..= .KP_9: return 0x60 + int(k) - int(sapp.Keycode.KP_0)
	case .KP_DECIMAL: return 0x6E
	case .KP_DIVIDE: return 0x6F
	case .KP_MULTIPLY: return 0x6A
	case .KP_SUBTRACT: return 0x6D
	case .KP_ADD: return 0x6B
	case .KP_ENTER: return 0x0D
	case .LEFT_SHIFT: return 0xA0
	case .LEFT_CONTROL: return 0xA2
	case .LEFT_ALT: return 0xA4
	case .RIGHT_SHIFT: return 0xA1
	case .RIGHT_CONTROL: return 0xA3
	case .RIGHT_ALT: return 0xA5
	}
	return 0
}
