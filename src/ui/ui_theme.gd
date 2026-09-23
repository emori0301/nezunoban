class_name UiTheme
extends RefCounted
## HUD / タイトル / エンディングで共有するフォントと色。
## SubViewport 640x360 に描くので、既定サイズは 16px 前後。
## フォントはドット感を残すためアンチエイリアス無しで読み込み直す。

const GOTHIC_PATH := "res://assets/fonts/DotGothic16-Regular.ttf"
const MINCHO_PATH := "res://assets/fonts/ShipporiMincho-Regular.ttf"

## 画面上の色
const TEXT := Color(0.88, 0.88, 0.84)
const TEXT_DIM := Color(0.66, 0.67, 0.65)
const TEXT_WARN := Color(0.86, 0.74, 0.44)
const SPEAKER := Color(0.92, 0.84, 0.62)
const REC := Color(0.88, 0.18, 0.14)
const SHADOW := Color(0, 0, 0, 0.85)
const BOX_BG := Color(0.012, 0.014, 0.018, 0.80)
const BOX_LINE := Color(0.70, 0.76, 0.80, 0.22)
const DIM := Color(0, 0, 0, 0.62)
const PAPER := Color(0.690, 0.575, 0.445)
const PAPER_EDGE := Color(0.42, 0.35, 0.27)
const INK := Color(0.075, 0.068, 0.060)
const INK_DIM := Color(0.26, 0.24, 0.21)
const SELECT := Color(0.96, 0.93, 0.80)

static var _gothic: FontFile = null
static var _mincho: FontFile = null

static func gothic() -> FontFile:
	if _gothic == null:
		_gothic = _load(GOTHIC_PATH)
	return _gothic

static func mincho() -> FontFile:
	if _mincho == null:
		_mincho = _load(MINCHO_PATH)
	return _mincho

static func _load(path: String) -> FontFile:
	if not ResourceLoader.exists(path):
		push_warning("UiTheme: font missing %s" % path)
		return null
	var f: FontFile = load(path)
	if f:
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.generate_mipmaps = false
	return f

## 影付きの LabelSettings を作る(低解像度でも文字が背景に溶けないように)
static func settings(font: Font, size: int, color: Color = TEXT, shadow: bool = true) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = color
	if shadow:
		ls.shadow_size = 0
		ls.shadow_color = SHADOW
		ls.shadow_offset = Vector2(1, 1)
	return ls

static func gothic_label(text: String, size: int = 16, color: Color = TEXT, shadow: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = settings(gothic(), size, color, shadow)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func mincho_label(text: String, size: int = 18, color: Color = TEXT, shadow: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = settings(mincho(), size, color, shadow)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## 会話ボックスなどの黒半透明パネル
static func box_style(bg: Color = BOX_BG, line: Color = BOX_LINE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = line
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## 手紙・クリップボードの紙
static func paper_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = PAPER_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(2, 3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 12
	return sb

## ゲームパッドのボタン名。Godot に表示名を返す API が無いので自前で持つ。
const JOY_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
}

## 直前に使われた入力がゲームパッドかどうか。HUD / タイトルが note_input() で更新する。
static var using_joypad: bool = false

## 入力の種別を覚える。キーボード・マウスとパッドを行き来しても表記が追従するようにする。
static func note_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		using_joypad = true
	elif event is InputEventJoypadMotion:
		# スティックの揺り戻しで切り替わらないよう、しっかり倒したときだけ
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			using_joypad = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		using_joypad = false

## 入力アクションに割り当てられたキー名("E" / "Space" / パッドなら "A")。
## headless では DisplayServer.keyboard_get_keycode_from_physical() が
## 「Not supported by this display server」を出すので、物理キーコードのまま文字列にする。
static func key_name(action: StringName, fallback: String = "E") -> String:
	if using_joypad:
		var pad := joy_name(action)
		if pad != "":
			return pad
	var physical_ok := DisplayServer.get_name() != "headless"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var ev := e as InputEventKey
			var kc: int = ev.physical_keycode
			if kc == 0:
				kc = ev.keycode
			elif physical_ok:
				kc = DisplayServer.keyboard_get_keycode_from_physical(kc)
			if kc != 0:
				return OS.get_keycode_string(kc)
	return fallback

## アクションに割り当たっているパッドボタンの名前。無ければ空文字。
static func joy_name(action: StringName) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			var idx: int = (e as InputEventJoypadButton).button_index
			if JOY_BUTTON_NAMES.has(idx):
				return String(JOY_BUTTON_NAMES[idx])
	return ""

static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	return c
