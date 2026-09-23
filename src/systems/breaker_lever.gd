class_name BreakerLever
extends Interactable
## 分電盤の1本のレバー。Breaker が3本作って子にする(E-2)。
## 上げる順が正しければ上がったまま、違えば火花が出て落ちる。

@export var lever_name: StringName = &"Lever_Main"
@export var raise_prompt: String = "レバーを上げる"
@export var raise_hold_time: float = 0.6
@export var up_text: String = "もう上がっている。"
@export var down_degrees: float = 38.0

var is_up: bool = true

var _visual: Node3D
var _rest_rotation: Vector3 = Vector3.ZERO

func _ready() -> void:
	super._ready()
	prompt = raise_prompt
	hold_time = raise_hold_time

## Breaker が呼ぶ。動かす見た目(glb の Lever か、自前の箱)を渡す。
func setup(visual: Node3D) -> void:
	_visual = visual
	if _visual:
		_rest_rotation = _visual.rotation_degrees

func set_up(up: bool, animate: bool = true) -> void:
	is_up = up
	if _visual == null:
		return
	var target := _rest_rotation
	if not up:
		target.x += down_degrees
	if animate:
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(_visual, "rotation_degrees", target, 0.18)
	else:
		_visual.rotation_degrees = target

func get_blocked_text() -> String:
	if is_up:
		return up_text
	return super.get_blocked_text()

func _can_interact(_player: Node3D) -> bool:
	return not is_up

func _interact(_player: Node3D) -> void:
	var br := get_parent() as Breaker
	if br:
		br.raise_lever(lever_name)
