class_name GuestBook
extends Interactable
## 受付の芳名帳。00:00 以降、最後の行に自分の名前が書かれている(director が set_lines で足す)。
##
## director からの使い方:
##     var gb := SystemsInstaller.find(&"guest_book") as GuestBook
##     gb.set_lines(["春日 誠", "春日 ひかり", "……", "(プレイヤーの名前)"])
##     gb.rustle()     # 受話器を置いた直後にページがめくれる音

signal viewed

@export var book_title: String = "芳名帳"
@export var view_prompt: String = "芳名帳を見る"
@export var lines: PackedStringArray = PackedStringArray()
@export var reading_text: String = "……見ている。"

var _viewing: bool = false

func _ready() -> void:
	super._ready()
	prompt = view_prompt

func set_lines(new_lines: Array) -> void:
	lines = PackedStringArray()
	for l in new_lines:
		lines.append(String(l))

func add_line(text: String) -> void:
	lines.append(text)

func body_text() -> String:
	return "\n".join(lines)

## ページが独りでにめくれる音(誰も居ないのに)。
func rustle() -> void:
	Audio.play_at(&"page_turn", global_position)

func view() -> void:
	if _viewing:
		return
	_viewing = true
	Audio.play_at(&"paper_rustle", global_position)
	await Dialogue.note(book_title, body_text())
	Audio.play_at(&"book_close", global_position, -6.0)
	_viewing = false
	viewed.emit()

func get_blocked_text() -> String:
	if _viewing:
		return reading_text
	return super.get_blocked_text()

func _can_interact(_player: Node3D) -> bool:
	return not _viewing

func _interact(_player: Node3D) -> void:
	view()
