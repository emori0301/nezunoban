class_name Note
extends Interactable
## 手紙・日記・メモ・台帳。読むと Dialogue.note で全文が出る。
## page_number > 0 のものは収集物。初回だけ Game.add_flag(&"pages") と page_read{n} が出る。
## 何度でも読める(one_shot ではない)。
##
## director からの使い方:
##     var n := Note.new()  # または note.tscn を instantiate
##     n.title = "日記 1"
##     n.body = "……"
##     n.page_number = 1
##     Events.on(&"page_read", func(d): print(d["n"]))

signal read_first_time(page_number: int)
signal read_again

@export var title: String = "メモ"
@export_multiline var body: String = ""
## 収集物なら 1..4。0 は普通の読み物。
@export var page_number: int = 0
@export var read_prompt: String = "読む"
@export var paper_size: Vector2 = Vector2(0.21, 0.29)
@export var show_paper: bool = true      # 紙の板ポリを出す(モデルが無いとき用)
@export var blank_text: String = "白紙だ。"
@export var reading_text: String = "……読んでいる。"

var has_been_read: bool = false

var _paper: MeshInstance3D
var _reading: bool = false

func _ready() -> void:
	super._ready()
	prompt = read_prompt
	one_shot = false
	if show_paper:
		_build_paper()

func _build_paper() -> void:
	_paper = MeshInstance3D.new()
	_paper.name = "Paper"
	var q := QuadMesh.new()
	q.size = paper_size
	_paper.mesh = q
	_paper.rotation_degrees = Vector3(-90, 0, 0)   # 寝かせて置く
	_paper.position = Vector3(0, 0.002, 0)
	_paper.material_override = SystemUtil.flat_material(Color(0.86, 0.84, 0.78))
	_paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_paper)

func set_text(new_title: String, new_body: String, page: int = 0) -> void:
	title = new_title
	body = new_body
	page_number = page

## 読む。UI が閉じるまで待つ。
func read() -> void:
	if _reading:
		return
	_reading = true
	Audio.play_at(&"paper_rustle", global_position)
	await Dialogue.note(title, body)
	if not has_been_read:
		has_been_read = true
		if page_number > 0:
			Game.add_flag(&"pages")
			Events.emit_event(&"page_read", {"n": page_number})
		read_first_time.emit(page_number)
	else:
		read_again.emit()
	Audio.play_at(&"book_close", global_position, -6.0)
	_reading = false

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func get_blocked_text() -> String:
	if _reading:
		return reading_text
	if not enabled or body == "":
		return blank_text
	return super.get_blocked_text()

func _can_interact(_player: Node3D) -> bool:
	return not _reading

func _interact(_player: Node3D) -> void:
	read()
