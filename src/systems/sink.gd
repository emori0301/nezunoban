class_name Sink
extends Interactable
## バックヤードの水道。供花の水替え用に水を汲む。

signal filled

@export var item_name: StringName = &"water"
@export var carried: bool = true
@export var fill_prompt: String = "水を汲む"
@export var already_line: String = "もう汲んである。"

func _ready() -> void:
	super._ready()
	prompt = fill_prompt

func fill(player: Node3D) -> void:
	if SystemUtil.has_item(player, item_name):
		Dialogue.monologue(already_line)
		return
	Audio.play_at(&"water_pour", global_position)
	SystemUtil.give_item(player, item_name, carried)
	filled.emit()

func _interact(player: Node3D) -> void:
	fill(player)
