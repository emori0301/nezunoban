class_name Futon
extends Interactable
## 控室の布団。「休む」を選ぶと遺影エンドへ(エンディングの処理は director)。

signal rested
signal declined

@export var lie_prompt: String = "横になる"
@export var question: String = "少し休むか"
@export var option_no: String = "休まない"
@export var option_yes: String = "休む"

var _asking: bool = false

func _ready() -> void:
	super._ready()
	prompt = lie_prompt

func ask() -> void:
	if _asking:
		return
	_asking = true
	Audio.play_at(&"tatami_creak", global_position, -6.0)
	var i: int = await Dialogue.choose(question, [option_no, option_yes])
	_asking = false
	if i == 1:
		Events.emit_event(&"futon_rest")
		rested.emit()
	else:
		declined.emit()

func _can_interact(_player: Node3D) -> bool:
	return not _asking

func _interact(_player: Node3D) -> void:
	ask()
