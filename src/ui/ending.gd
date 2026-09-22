extends CanvasLayer
## エンディング画面。director が instantiate して play(...) を await する。
##   var e := load("res://src/ui/ending.tscn").instantiate()
##   add_child(e)
##   e.show_portrait(tex)                      # 遺影エンド用(任意)
##   await e.play(Game.ENDING_MORNING, "朝", ["空が白んだ。", "社長の車の音がする。"])
##   await e.finished                           # 「タイトルへ」が押されるまで

signal finished(ending_id: StringName)

@export var to_title_text: String = "タイトルへ"
@export var line_fade: float = 1.4          ## 1行がフェードインする秒数
@export var line_gap: float = 1.1           ## 行と行の間

var _root: Control
var _lines_box: VBoxContainer
var _title: Label
var _portrait: TextureRect
var _portrait_frame: Panel
var _hint: Label
var _fade: ColorRect
var _ending_id: StringName = &""
var _waiting: bool = false
var _latch: Dictionary = {}

func _ready() -> void:
	add_to_group(&"ending")
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	_root = Control.new()
	UiTheme.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var bg := ColorRect.new()
	UiTheme.full_rect(bg)
	bg.color = Color(0, 0, 0, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# 遺影(任意)
	_portrait_frame = Panel.new()
	_portrait_frame.anchor_left = 0.5
	_portrait_frame.anchor_right = 0.5
	_portrait_frame.offset_left = -52.0
	_portrait_frame.offset_right = 52.0
	_portrait_frame.offset_top = 32.0
	_portrait_frame.offset_bottom = 156.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.045)
	sb.border_color = Color(0.14, 0.13, 0.12)
	sb.set_border_width_all(3)
	_portrait_frame.add_theme_stylebox_override("panel", sb)
	_portrait_frame.visible = false
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_portrait_frame)

	_portrait = TextureRect.new()
	UiTheme.full_rect(_portrait)
	_portrait.offset_left = 4.0
	_portrait.offset_top = 4.0
	_portrait.offset_right = -4.0
	_portrait.offset_bottom = -4.0
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.modulate = Color(0.76, 0.75, 0.78)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_frame.add_child(_portrait)

	# 本文
	_lines_box = VBoxContainer.new()
	_lines_box.anchor_left = 0.5
	_lines_box.anchor_right = 0.5
	_lines_box.anchor_top = 0.5
	_lines_box.anchor_bottom = 0.5
	_lines_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lines_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_lines_box.custom_minimum_size = Vector2(440, 0)
	_lines_box.add_theme_constant_override("separation", 8)
	_lines_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lines_box)

	# エンディング名
	_title = UiTheme.mincho_label("", 38, Color(0.91, 0.90, 0.86))
	_title.anchor_right = 1.0
	_title.offset_top = 150.0
	_title.offset_bottom = 210.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.modulate.a = 0.0
	_root.add_child(_title)

	_hint = UiTheme.gothic_label("", 15, UiTheme.TEXT)
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -44.0
	_hint.offset_bottom = -22.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate.a = 0.0
	_root.add_child(_hint)

	_fade = ColorRect.new()
	UiTheme.full_rect(_fade)
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)

## 遺影エンド用。暗い写真を上に出す。
func show_portrait(texture: Texture2D) -> void:
	_portrait.texture = texture
	_portrait_frame.visible = texture != null
	if texture != null:
		_lines_box.offset_top = 40.0
		_lines_box.offset_bottom = 40.0
		_title.offset_top = 186.0
		_title.offset_bottom = 240.0

## 黒画面に1行ずつフェードインさせ、最後にエンディング名を出す。
## 「タイトルへ」が押されると finished を出して戻る。
func play(ending_id: StringName, title: String, lines: Array) -> void:
	_ending_id = ending_id
	for c in _lines_box.get_children():
		c.queue_free()
	_title.text = title
	_title.modulate.a = 0.0
	_hint.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.2)
	await get_tree().create_timer(1.6).timeout

	for line in lines:
		var l := UiTheme.mincho_label(String(line), 19, Color(0.89, 0.88, 0.84))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(440, 0)
		l.modulate.a = 0.0
		_lines_box.add_child(l)
		var t2 := create_tween()
		t2.tween_property(l, "modulate:a", 1.0, line_fade)
		await get_tree().create_timer(line_fade + line_gap).timeout

	await get_tree().create_timer(0.8).timeout
	var t3 := create_tween()
	t3.tween_property(_lines_box, "modulate:a", 0.0, 1.0)
	await t3.finished

	var t4 := create_tween()
	t4.tween_property(_title, "modulate:a", 1.0, 1.6)
	await get_tree().create_timer(2.2).timeout

	_hint.text = "[%s] %s" % [_key_for(&"advance"), to_title_text]
	var t5 := create_tween()
	t5.tween_property(_hint, "modulate:a", 1.0, 0.8)

	_latch[&"advance"] = true
	_waiting = true
	while _waiting and is_inside_tree():
		await get_tree().process_frame
	var t6 := create_tween()
	t6.tween_property(_fade, "color:a", 1.0, 0.8)
	await t6.finished
	finished.emit(_ending_id)

func _key_for(action: StringName) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var kc: int = (e as InputEventKey).physical_keycode
			if kc == 0:
				kc = (e as InputEventKey).keycode
			if kc != 0:
				return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(kc))
	return "Space"

func _process(_delta: float) -> void:
	if not _waiting:
		return
	var p := Input.is_action_pressed(&"advance")
	var was: bool = bool(_latch.get(&"advance", true))
	_latch[&"advance"] = p
	if p and not was:
		_waiting = false
