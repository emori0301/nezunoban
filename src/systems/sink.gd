class_name Sink
extends Interactable
## バックヤードの水道。供花の水替え用に水を汲む。

signal filled

@export var item_name: StringName = &"water"
@export var carried: bool = true
@export var fill_prompt: String = "水を汲む"
@export var already_line: String = "もう汲んである。"
@export var hands_full_prompt: String = "両手が塞がっている"
@export var hands_full_text: String = "両手が塞がっている。"

func _ready() -> void:
	super._ready()
	prompt = fill_prompt

func get_prompt() -> String:
	if _blocked_by_other_item(Game.player):
		return hands_full_prompt
	return fill_prompt

## 別の運搬物で両手が塞がっているときだけ止める。
## 水そのものを持っているときは通して「もう汲んである。」を出す。
func _can_interact(player: Node3D) -> bool:
	return not _blocked_by_other_item(player)

func _blocked_by_other_item(p: Node) -> bool:
	return SystemUtil.is_carrying(p) and not SystemUtil.has_item(p, item_name)

func get_blocked_text() -> String:
	if _blocked_by_other_item(Game.player):
		return hands_full_text
	return super.get_blocked_text()

func fill(player: Node3D) -> void:
	if SystemUtil.has_item(player, item_name):
		Dialogue.monologue(already_line)
		return
	Audio.play_at(&"water_pour", global_position)
	SystemUtil.give_item(player, item_name, carried)
	filled.emit()

func _interact(player: Node3D) -> void:
	fill(player)
