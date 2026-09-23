class_name Sink
extends Interactable
## バックヤードの水道。供花の水替え用に水を汲む。

signal filled

@export var item_name: StringName = &"water"
@export var carried: bool = true
@export var fill_prompt: String = "水を汲む"
@export var already_line: String = "もう汲んである。"
@export var hands_full_prompt: String = "両手が塞がっている"

func _ready() -> void:
	super._ready()
	prompt = fill_prompt

func get_prompt() -> String:
	if SystemUtil.is_carrying(Game.player):
		return hands_full_prompt
	return fill_prompt

## 運搬物を持っているあいだは汲めない(持ち物が黙って消えるのを防ぐ)。
func _can_interact(player: Node3D) -> bool:
	return not SystemUtil.is_carrying(player)

func fill(player: Node3D) -> void:
	if SystemUtil.has_item(player, item_name):
		Dialogue.monologue(already_line)
		return
	Audio.play_at(&"water_pour", global_position)
	SystemUtil.give_item(player, item_name, carried)
	filled.emit()

func _interact(player: Node3D) -> void:
	fill(player)
