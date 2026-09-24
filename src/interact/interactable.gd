class_name Interactable
extends Area3D
## すべての「調べる/使う」対象の基底。collision_layer = 2 (interact)。
## プレイヤーは正面のレイキャストで Area3D を拾い、Interactable なら get_prompt() を表示し、
## interact 入力で interact(player) を呼ぶ。hold_time > 0 なら長押し。
##
## 派生側は _can_interact / _interact をオーバーライドする。
## 持ち物が必要なら required_item を設定する(例: &"dry_ice")。

signal interacted(player: Node3D)
signal focused
signal unfocused

@export var prompt: String = "調べる"
@export var hold_time: float = 0.0
@export var enabled: bool = true
@export var required_item: StringName = &""
@export var one_shot: bool = false
@export var interact_distance: float = 2.2
## 押しても何も起きないとき(can_interact が false)に HUD へ出す短い文。空なら共通の文。
@export var blocked_text: String = ""

var _used: bool = false

## 導入などで操作を絞るゲート。Game.get_flag(&"interact_gate") が true の間は、
## group "gate_allowed" に入っている Interactable 以外は押せず、gate_text を返す。
const GATE_FLAG := &"interact_gate"
const GATE_GROUP := &"gate_allowed"
static var gate_text: String = "先に社長に話さないと。"

func _gated() -> bool:
	return bool(Game.get_flag(GATE_FLAG, false)) and not is_in_group(GATE_GROUP)

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group(&"interactable")

func get_prompt() -> String:
	if required_item != &"" and not _player_has(required_item):
		return _missing_item_prompt()
	return prompt

func _missing_item_prompt() -> String:
	return prompt

## HUD が表示に使う理由文。ゲート中は派生の上書きより優先してゲートの文を返す。
func blocked_text_for_hud() -> String:
	if _gated():
		return gate_text
	return get_blocked_text()

## 押しても反応しない理由の文。派生は状況に応じて上書きしてよい(例: 「鍵がかかっている。」「空だ。」)。
func get_blocked_text() -> String:
	if _gated():
		return gate_text
	if required_item != &"" and not _player_has(required_item):
		return blocked_text if blocked_text != "" else "何かが要る。"
	return blocked_text

func can_interact(player: Node3D) -> bool:
	if not enabled or (one_shot and _used):
		return false
	if _gated():
		return false
	if required_item != &"" and not _player_has(required_item):
		return false
	return _can_interact(player)

func interact(player: Node3D) -> void:
	if not can_interact(player):
		return
	if one_shot:
		_used = true
	_interact(player)
	interacted.emit(player)

func _can_interact(_player: Node3D) -> bool:
	return true

func _interact(_player: Node3D) -> void:
	pass

func _player_has(item: StringName) -> bool:
	var p := Game.player
	if p == null:
		return false
	if p.has_method("has_item"):
		return p.has_item(item)
	return false

func reset_one_shot() -> void:
	_used = false

func on_focus() -> void:
	focused.emit()

func on_unfocus() -> void:
	unfocused.emit()
