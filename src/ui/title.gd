extends CanvasLayer
## タイトル画面。main.gd が SubViewport(640x360)の中に入れる。
## 起動時に短い「TRACKING」のカムコーダー演出 → 明朝の大タイトル → メニュー。
## 決定で start_requested を出す。main.gd がこれを受けてゲームを始める。

signal start_requested
signal quit_requested

@export var title_text: String = "寝ずの番"
@export var subtitle_text: String = "The Wake"
@export var menu_items: PackedStringArray = ["はじめる", "おわる"]
@export var tracking_text: String = "TRACKING"
## 到達エンディングの表示(右下)。並びは Settings.ENDING_IDS と同じ
@export var ending_names: PackedStringArray = ["朝", "火車", "代わり", "遺影"]
@export var ending_unknown_text: String = "？"
@export var ending_count_format: String = "終 %d/%d"
@export var intro_duration: float = 1.6
@export var skip_intro: bool = false

const OVERLAY_SHADER := "res://src/fx/vhs_overlay.gdshader"

var _root: Control
var _title: Label
var _sub: Label
var _menu: VBoxContainer
var _tracking: Label
var _stamp: Label
var _endings: Label
var _overlay: ColorRect
var _fade: ColorRect
var _index: int = 0
var _active: bool = false
var _latch: Dictionary = {}
var _t: float = 0.0

func _ready() -> void:
	add_to_group(&"title")
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Settings.load_all()
	_build()
	_ensure_vhs()
	Settings.apply()   # VhsLayer を作ったあとに反映する(VHS の強さも設定に従う)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.ambient(&"amb_drone_low", -12.0, 2.0)
	if skip_intro:
		_show_menu_now()
	else:
		_intro()

## main.gd は start_game() で初めて VhsLayer を付けるので、タイトルの間は自前で付ける。
## 既に誰かが付けていれば何もしない。
func _ensure_vhs() -> void:
	if not get_tree().get_nodes_in_group(&"vhs").is_empty():
		return
	var vp := get_viewport()
	if vp == null or not (vp is SubViewport):
		return
	var cont := vp.get_parent() as SubViewportContainer
	if cont == null or cont.material != null:
		return
	var path := "res://src/fx/vhs_layer.tscn"
	if not ResourceLoader.exists(path):
		return
	var v: Node = load(path).instantiate()
	add_child(v)
	v.attach(cont)
	v.set_intensity(0.42)

func _build() -> void:
	_root = Control.new()
	UiTheme.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var bg := ColorRect.new()
	UiTheme.full_rect(bg)
	bg.color = Color(0.008, 0.010, 0.014, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# 大タイトル(明朝)
	_title = UiTheme.mincho_label(title_text, 46, Color(0.86, 0.85, 0.80))
	_title.anchor_right = 1.0
	_title.offset_top = 96.0
	_title.offset_bottom = 156.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.label_settings.shadow_color = Color(0, 0, 0, 0.9)
	_title.label_settings.shadow_offset = Vector2(2, 2)
	_title.modulate.a = 0.0
	_root.add_child(_title)

	_sub = UiTheme.gothic_label(subtitle_text, 15, Color(0.58, 0.60, 0.60))
	_sub.anchor_right = 1.0
	_sub.offset_top = 160.0
	_sub.offset_bottom = 180.0
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.modulate.a = 0.0
	_root.add_child(_sub)

	# メニュー
	_menu = VBoxContainer.new()
	_menu.anchor_left = 0.5
	_menu.anchor_right = 0.5
	_menu.offset_left = 0.0
	_menu.offset_right = 0.0
	_menu.offset_top = 232.0
	_menu.offset_bottom = 232.0
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_END
	_menu.add_theme_constant_override("separation", 6)
	_menu.modulate.a = 0.0
	_root.add_child(_menu)
	for i in menu_items.size():
		var idx := i
		var l := UiTheme.gothic_label(String(menu_items[i]), 19, UiTheme.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.custom_minimum_size = Vector2(126, 0)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_entered.connect(func() -> void:
			if _active:
				_index = idx
				_refresh_menu())
		l.gui_input.connect(func(e: InputEvent) -> void:
			if _active and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_index = idx
				_activate())
		_menu.add_child(l)

	# カムコーダー表記
	_tracking = UiTheme.gothic_label(tracking_text, 15, Color(0.80, 0.82, 0.80))
	_tracking.offset_left = 18.0
	_tracking.offset_right = 260.0
	_tracking.offset_top = 300.0
	_tracking.offset_bottom = 320.0
	_root.add_child(_tracking)

	_stamp = UiTheme.gothic_label("PM 9:00", 15, Color(0.78, 0.80, 0.78))
	_stamp.anchor_left = 1.0
	_stamp.anchor_right = 1.0
	_stamp.offset_left = -130.0
	_stamp.offset_right = -14.0
	_stamp.offset_top = 10.0
	_stamp.offset_bottom = 30.0
	_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_stamp)

	# 右下: 到達したエンディング(director が user://progress.cfg に書いたもの)
	_endings = UiTheme.gothic_label(_endings_text(), 12, Color(0.62, 0.64, 0.62))
	_endings.anchor_left = 1.0
	_endings.anchor_right = 1.0
	_endings.anchor_top = 1.0
	_endings.anchor_bottom = 1.0
	_endings.offset_left = -260.0
	_endings.offset_right = -14.0
	_endings.offset_top = -54.0
	_endings.offset_bottom = -16.0
	_endings.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_endings.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_endings)

	# VHS ノイズ(タイトルには SubViewportContainer が無いので簡易版を重ねる)
	_overlay = ColorRect.new()
	UiTheme.full_rect(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(OVERLAY_SHADER):
		var m := ShaderMaterial.new()
		m.shader = load(OVERLAY_SHADER)
		m.set_shader_parameter("intensity", 1.0)
		m.set_shader_parameter("noise_amount", 0.42)
		m.set_shader_parameter("tracking_amount", 0.95)
		_overlay.material = m
	_root.add_child(_overlay)

	_fade = ColorRect.new()
	UiTheme.full_rect(_fade)
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)

## 「終 1/4」と、到達した名だけを並べた行。未到達は「？」。
func _endings_text() -> String:
	var reached := Settings.reached_endings()
	var n := 0
	var parts: PackedStringArray = []
	for i in reached.size():
		if reached[i]:
			n += 1
			parts.append(String(ending_names[i]) if i < ending_names.size() else "")
		else:
			parts.append(ending_unknown_text)
	var head := ending_count_format % [n, reached.size()]
	return "%s\n%s" % [head, "　".join(parts)]

func _intro() -> void:
	# 最初はテープの砂嵐。TRACKING の点滅だけが見えている状態から始める。
	var m: ShaderMaterial = _overlay.material as ShaderMaterial
	if m:
		m.set_shader_parameter("intensity", 1.0)
		m.set_shader_parameter("noise_amount", 0.42)
		m.set_shader_parameter("tracking_amount", 0.95)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.45)
	await get_tree().create_timer(intro_duration * 0.55, false).timeout
	if m:
		var tw2 := create_tween()
		tw2.tween_method(func(v: float) -> void:
			m.set_shader_parameter("noise_amount", v), 0.42, 0.13, 1.3)
		var tw3 := create_tween()
		tw3.tween_method(func(v: float) -> void:
			m.set_shader_parameter("intensity", v), 1.0, 0.50, 1.3)
		var tw4 := create_tween()
		tw4.tween_method(func(v: float) -> void:
			m.set_shader_parameter("tracking_amount", v), 0.95, 0.30, 1.3)
	var tt := create_tween()
	tt.tween_property(_title, "modulate:a", 1.0, 1.1)
	await get_tree().create_timer(0.5, false).timeout
	var ts := create_tween()
	ts.tween_property(_sub, "modulate:a", 1.0, 0.9)
	await get_tree().create_timer(0.6, false).timeout
	_show_menu_now()

func _show_menu_now() -> void:
	_title.modulate.a = 1.0
	_sub.modulate.a = 1.0
	_fade.color.a = 0.0
	if _overlay.material:
		var mm: ShaderMaterial = _overlay.material as ShaderMaterial
		mm.set_shader_parameter("intensity", 0.50)
		mm.set_shader_parameter("noise_amount", 0.13)
		mm.set_shader_parameter("tracking_amount", 0.30)
	var tm := create_tween()
	tm.tween_property(_menu, "modulate:a", 1.0, 0.6)
	_index = 0
	_refresh_menu()
	_latch[&"advance"] = true
	_active = true

func _refresh_menu() -> void:
	for i in _menu.get_child_count():
		var l := _menu.get_child(i) as Label
		var on := i == _index
		l.label_settings.font_color = UiTheme.SELECT if on else UiTheme.TEXT_DIM
		l.text = ("＞ " if on else "　 ") + String(l.text).lstrip("＞　 ")

func _input(event: InputEvent) -> void:
	UiTheme.note_input(event)

func _just(action: StringName) -> bool:
	var p := Input.is_action_pressed(action)
	var was: bool = bool(_latch.get(action, true))
	_latch[action] = p
	return p and not was

func _process(delta: float) -> void:
	_t += delta
	# TRACKING 表記とタイムスタンプの点滅(カムコーダーらしさ)
	_tracking.visible = fmod(_t, 0.8) < 0.55
	if not _active:
		_tracking.text = tracking_text + ".".repeat(int(_t * 3.0) % 4)
		return
	_tracking.text = tracking_text
	var adv := _just(&"advance")
	var u1 := _just(&"ui_up")
	var u2 := _just(&"move_forward")
	var d1 := _just(&"ui_down")
	var d2 := _just(&"move_back")
	var n := _menu.get_child_count()
	if n == 0:
		return
	if u1 or u2:
		_index = (_index - 1 + n) % n
		_refresh_menu()
		Audio.play(&"ui_select", -8.0)
	if d1 or d2:
		_index = (_index + 1) % n
		_refresh_menu()
		Audio.play(&"ui_select", -8.0)
	if adv:
		_activate()

func _activate() -> void:
	if not _active:
		return
	_active = false
	Audio.play(&"ui_confirm", -4.0)
	if _index == 0:
		var tw := create_tween()
		tw.tween_property(_fade, "color:a", 1.0, 0.6)
		await tw.finished
		Audio.stop_ambient(&"amb_drone_low", 0.5)
		start_requested.emit()
	else:
		quit_requested.emit()
		get_tree().quit()
