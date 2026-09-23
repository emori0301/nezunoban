class_name Pickup
extends Interactable
## 拾い物の共通クラス。incense_box(線香の箱)と matches(マッチ)がこれ。
## item_name を持ち物に足し、add_flag_key があれば在庫フラグも足す。
##
## incense_box: item_name = &"" / add_flag_key = &"incense_sticks" / add_flag_amount = 10
## matches:     item_name = &"matches"
##
## 在庫をバックヤードに追加で置きたいときは incense_box.tscn をもう1つ置けばよい。

signal picked_up(item: StringName)

@export var item_name: StringName = &""
@export var carried: bool = false
@export var add_flag_key: StringName = &""
@export var add_flag_amount: int = 0
@export var pickup_line: String = ""
@export var pickup_sound: StringName = &"paper_rustle"
@export var take_prompt: String = "拾う"
@export var disappear: bool = true          # 拾ったら消える
@export var hands_full_prompt: String = "両手が塞がっている"
@export var hands_full_text: String = "両手が塞がっている。"

func _ready() -> void:
	super._ready()
	prompt = take_prompt
	one_shot = true

func get_prompt() -> String:
	if carried and SystemUtil.is_carrying(Game.player):
		return hands_full_prompt
	return take_prompt

func get_blocked_text() -> String:
	if carried and SystemUtil.is_carrying(Game.player):
		return hands_full_text
	return super.get_blocked_text()

## 運搬物として持つ拾い物は、すでに両手が塞がっていたら拾えない。
func _can_interact(player: Node3D) -> bool:
	return not (carried and SystemUtil.is_carrying(player))

func take(player: Node3D) -> void:
	if pickup_sound != &"":
		Audio.play_at(pickup_sound, global_position)
	if item_name != &"":
		SystemUtil.give_item(player, item_name, carried)
	if add_flag_key != &"" and add_flag_amount != 0:
		Game.add_flag(add_flag_key, add_flag_amount)
	if pickup_line != "":
		Dialogue.monologue(pickup_line)
	picked_up.emit(item_name)
	if disappear:
		enabled = false
		visible = false
		queue_free()

func _interact(player: Node3D) -> void:
	take(player)
