extends CanvasLayer
## エンディング画面。director が instantiate して play(...) を await する。
##   var e := load("res://src/ui/ending.tscn").instantiate()
##   add_child(e)
##   e.show_portrait(tex)                      # 遺影エンド用(任意)
##   await e.play(Game.ENDING_MORNING, "朝", ["空が白んだ。", "社長の車の音がする。"])
##   await e.finished                           # 「タイトルへ」が押されるまで

signal finished(ending_id: StringName)

@export var to_title_text: String = "タイトルへ"
## 回想の静止画 1 枚あたりの表示秒数(advance で早送りできる)
@export var recap_seconds: float = 4.0
## 画面が 640x360 なので、下の 1 行ぶんを空けた 16:9 の枠に収める
## (素材は 512x288 程度で作ってよい。ここには合わせて縮む)
@export var recap_image_size: Vector2 = Vector2(464, 261)
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
var _recap: Control
var _recap_image: TextureRect
var _recap_frame: Panel
var _recap_line: Label
var _recap_skip: bool = false

func _ready() -> void:
	add_to_group(&"ending")
	layer = 20
	# ポーズ中に台詞が進まないように PAUSABLE。ポーズメニュー自体は HUD(ALWAYS)が持つので操作は効く。
	process_mode = Node.PROCESS_MODE_PAUSABLE
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

	# 真相の回想(エンディング文の前)。静止画 1 枚とその下に明朝 1 行。
	_recap = Control.new()
	_recap.name = "Recap"
	UiTheme.full_rect(_recap)
	_recap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap.visible = false
	_root.add_child(_recap)

	_recap_frame = Panel.new()
	_recap_frame.anchor_left = 0.5
	_recap_frame.anchor_right = 0.5
	_recap_frame.anchor_top = 0.5
	_recap_frame.anchor_bottom = 0.5
	_recap_frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_recap_frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	# 下の文のぶんだけ上に寄せる(中心 y = 180 - 32 = 148)
	_recap_frame.offset_top = -32.0
	_recap_frame.offset_bottom = -32.0
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.02, 0.02, 0.025)
	rsb.border_color = Color(0.10, 0.10, 0.11)
	rsb.set_border_width_all(1)
	_recap_frame.add_theme_stylebox_override("panel", rsb)
	_recap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap.add_child(_recap_frame)

	_recap_image = TextureRect.new()
	UiTheme.full_rect(_recap_image)
	_recap_image.offset_left = 1.0
	_recap_image.offset_top = 1.0
	_recap_image.offset_right = -1.0
	_recap_image.offset_bottom = -1.0
	_recap_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_recap_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# VHS 越しに見るので少し暗く落とす
	_recap_image.modulate = Color(0.60, 0.60, 0.63)
	_recap_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap_frame.add_child(_recap_image)

	_recap_line = UiTheme.mincho_label("", 19, Color(0.89, 0.88, 0.84))
	_recap_line.anchor_right = 1.0
	_recap_line.anchor_top = 1.0
	_recap_line.anchor_bottom = 1.0
	_recap_line.offset_left = 60.0
	_recap_line.offset_right = -60.0
	_recap_line.offset_top = -74.0
	_recap_line.offset_bottom = -24.0
	_recap_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recap_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_recap_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recap_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap.add_child(_recap_line)

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

## エンディング文の前に流す「真相」の回想。
## images は Texture2D の配列(null や足りない分は黒画面に文だけ)、lines は同じ長さの文。
## 1 枚 recap_seconds 秒。advance を押すと次へ。await 可。
func show_recap(images: Array, lines: Array) -> void:
	var n: int = maxi(images.size(), lines.size())
	if n == 0:
		return
	_recap_frame.custom_minimum_size = recap_image_size
	_recap.visible = true
	_recap.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.0)
	await get_tree().create_timer(1.0, false).timeout

	for i in n:
		var tex: Texture2D = images[i] if i < images.size() and images[i] is Texture2D else null
		var line: String = String(lines[i]) if i < lines.size() else ""
		_recap_image.texture = tex
		_recap_frame.visible = tex != null
		# 画像が無いときは文を画面中央に置く(下端に張り付くと据わりが悪い)
		if tex != null:
			_recap_line.offset_top = -74.0
			_recap_line.offset_bottom = -24.0
		else:
			_recap_line.offset_top = -205.0
			_recap_line.offset_bottom = -155.0
		_recap_line.text = line
		var fade_in := create_tween()
		fade_in.tween_property(_recap, "modulate:a", 1.0, 0.7)
		await _wait_recap(recap_seconds)
		var fade_out := create_tween()
		fade_out.tween_property(_recap, "modulate:a", 0.0, 0.6)
		await fade_out.finished
		await get_tree().create_timer(0.3, false).timeout

	_recap.visible = false
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 1.0, 0.6)
	await tw2.finished

## 指定秒待つ。途中で advance を押したら切り上げる。
func _wait_recap(seconds: float) -> void:
	_recap_skip = false
	_latch[&"advance"] = true
	var t := 0.0
	while t < seconds and is_inside_tree():
		await get_tree().process_frame
		t += get_process_delta_time()
		if _recap_skip:
			_recap_skip = false
			return

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
	await get_tree().create_timer(1.6, false).timeout

	for line in lines:
		var l := UiTheme.mincho_label(String(line), 19, Color(0.89, 0.88, 0.84))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(440, 0)
		l.modulate.a = 0.0
		_lines_box.add_child(l)
		var t2 := create_tween()
		t2.tween_property(l, "modulate:a", 1.0, line_fade)
		await get_tree().create_timer(line_fade + line_gap, false).timeout

	await get_tree().create_timer(0.8, false).timeout
	var t3 := create_tween()
	t3.tween_property(_lines_box, "modulate:a", 0.0, 1.0)
	await t3.finished

	var t4 := create_tween()
	t4.tween_property(_title, "modulate:a", 1.0, 1.6)
	await get_tree().create_timer(2.2, false).timeout

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
	return UiTheme.key_name(action, "Space")

func _process(_delta: float) -> void:
	if not _waiting and not _recap.visible:
		return
	var p := Input.is_action_pressed(&"advance")
	var was: bool = bool(_latch.get(&"advance", true))
	_latch[&"advance"] = p
	if p and not was:
		if _waiting:
			_waiting = false
		else:
			_recap_skip = true
