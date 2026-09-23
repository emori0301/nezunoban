class_name BossDesk
extends Interactable
## 社長の机。03:20 に director が enable_key(true) を呼ぶと金庫の鍵が見つかる。
##
## director からの使い方:
##     var desk := SystemsInstaller.find(&"boss_desk") as BossDesk
##     desk.enable_key(true)

signal memo_read

@export var search_prompt: String = "机を調べる"
@export var nothing_line: String = "めぼしいものは無い。"
@export var papers_text: String = "書類ばかりだ。"
## 21:00 から読めるメモ(E-1)。金庫の番号の手がかり。
@export var memo_title: String = "社長の机のメモ"
@export_multiline var memo_body: String = "金庫の番号は婆さんの命日。忘れるな。"
@export var memo_prompt: String = "メモを読む"

var _reading: bool = false

func _ready() -> void:
	super._ready()
	prompt = memo_prompt if memo_body != "" else search_prompt

## 旧仕様(金庫の鍵)。ダイヤル式になったので何もしない。director が呼んでも無害。
func enable_key(_on: bool = true) -> void:
	pass

func get_blocked_text() -> String:
	return papers_text

func get_prompt() -> String:
	return memo_prompt if memo_body != "" else search_prompt

func read_memo() -> void:
	if _reading:
		return
	_reading = true
	Audio.play_at(&"paper_rustle", global_position)
	if memo_body == "":
		Dialogue.monologue(nothing_line)
	else:
		await Dialogue.note(memo_title, memo_body)
		Audio.play_at(&"book_close", global_position, -6.0)
		memo_read.emit()
	_reading = false

func _can_interact(_player: Node3D) -> bool:
	return not _reading

func _interact(_player: Node3D) -> void:
	read_memo()
