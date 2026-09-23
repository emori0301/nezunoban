class_name Credits
extends CanvasLayer
## エンディング文のあとに流すクレジット。黒地に明朝、下から上へ 30 秒。
## `advance` で飛ばせる。文面は docs/script.md「クレジット(エンディング後)」から。
##
##     var c := Credits.new()
##     viewport.add_child(c)
##     await c.play()

signal finished

const W := 640.0
const H := 360.0
## 押しっぱなしのキーでいきなり飛ばないよう、これだけ経ってから入力を受ける
const INPUT_DELAY := 0.8

@export var duration: float = 30.0
@export var line_gap: int = 10

var _root: Control
var _box: VBoxContainer
var _hint: Label
var _done: bool = false
var _accept_input: bool = false


func _ready() -> void:
	layer = 25
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

	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", line_gap)
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.offset_left = -240.0
	_box.offset_right = 240.0
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_box)

	for row in ScriptText.CREDITS:
		var text := String(row[0])
		var size := int(row[1])
		if text == "":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, float(size))
			_box.add_child(spacer)
			continue
		var l := UiTheme.mincho_label(text, size, Color(0.86, 0.85, 0.81))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(480, 0)
		_box.add_child(l)

	_hint = UiTheme.gothic_label("", 13, Color(0.55, 0.54, 0.5))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -200.0
	_hint.offset_right = -14.0
	_hint.offset_top = -26.0
	_hint.offset_bottom = -8.0
	_hint.modulate.a = 0.0
	_root.add_child(_hint)


## 下から上へ流す。終わるか `advance` が押されるまで待つ。
func play() -> void:
	await get_tree().process_frame
	var box_h: float = maxf(_box.get_combined_minimum_size().y, 120.0)
	_box.offset_top = H + 20.0
	_box.offset_bottom = H + 20.0 + box_h
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(_box, "offset_top", -box_h - 20.0, maxf(duration, 1.0))
	tw.parallel().tween_property(_box, "offset_bottom", -20.0, maxf(duration, 1.0))
	tw.finished.connect(func(): _done = true)

	await Events.wait(INPUT_DELAY)
	_accept_input = true
	_hint.text = "[%s] とばす" % UiTheme.key_name(&"advance", "Space")
	var t2 := create_tween()
	t2.tween_property(_hint, "modulate:a", 1.0, 0.8)

	while not _done and is_inside_tree():
		await get_tree().process_frame
	_done = true
	var t3 := create_tween()
	t3.tween_property(_root, "modulate:a", 0.0, 0.6)
	await t3.finished
	finished.emit()


func _process(_delta: float) -> void:
	if _done or not _accept_input:
		return
	if InputMap.has_action(&"advance") and Input.is_action_just_pressed(&"advance"):
		_done = true
