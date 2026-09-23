class_name BossDesk
extends Interactable
## 社長の机。03:20 に director が enable_key(true) を呼ぶと金庫の鍵が見つかる。
##
## director からの使い方:
##     var desk := SystemsInstaller.find(&"boss_desk") as BossDesk
##     desk.enable_key(true)

signal key_taken

@export var key_item: StringName = &"safe_key"
@export var search_prompt: String = "机を調べる"
@export var key_prompt: String = "鍵を探す"
@export var nothing_line: String = "めぼしいものは無い。"
@export var key_line: String = "引き出しの奥に鍵があった。"
@export var has_key: bool = false
@export var papers_text: String = "書類ばかりだ。"

var key_given: bool = false

func _ready() -> void:
	super._ready()
	prompt = key_prompt if has_key else search_prompt

## 鍵が見つかる状態にする。
func enable_key(on: bool = true) -> void:
	has_key = on
	key_given = false
	prompt = key_prompt if on else search_prompt

func get_blocked_text() -> String:
	if not has_key or key_given:
		return papers_text
	return super.get_blocked_text()

func get_prompt() -> String:
	return key_prompt if (has_key and not key_given) else search_prompt

func _interact(player: Node3D) -> void:
	Audio.play_at(&"paper_rustle", global_position)
	if has_key and not key_given:
		key_given = true
		SystemUtil.give_item(player, key_item, false)
		prompt = search_prompt
		Dialogue.monologue(key_line)
		key_taken.emit()
	else:
		Dialogue.monologue(nothing_line)
