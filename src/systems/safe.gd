class_name Safe
extends Interactable
## 事務所の金庫。鍵は社長の机(BossDesk)。中に台帳(Note)が入っている。
##
## director からの使い方:
##     var sf := SystemsInstaller.find(&"safe") as Safe
##     sf.set_note("台帳", "春日 キヨ 検案なし 追加金 …", 4)
##     Events.on(&"page_read", func(d): if d["n"] == 4: ...)

signal opened
signal code_failed(count: int)

const NOTE_SCENE := "res://src/systems/note.tscn"

@export var open_prompt: String = "金庫を開ける"
@export var locked_prompt: String = "金庫"
## 4桁ダイヤル。正解は director が Game.set_flag(&"safe_code", "1009") で入れる。
## フラグが空のときだけ fallback_code を使う(QA で詰まないように)。
@export var code_title: String = "金庫"
@export var code_length: int = 4
@export var fallback_code: String = "1009"
@export var note_title: String = "台帳"
@export_multiline var note_body: String = ""
@export var note_page: int = 0
@export var door_size: Vector3 = Vector3(0.44, 0.50, 0.04)
## safe.glb の "Door"(原点 (-0.205, 0.050, 0.254)、Y 回転で開く)
@export var door_open_degrees: float = -108.0
@export var locked_text: String = "鍵がかかっている。社長の机か。"
@export var emptied_text: String = "もう何もない。"
@export var busy_text: String = "いま開けている。"

var is_open: bool = false
var wrong_count: int = 0

var _has_model: bool = false
var _door_node: Node3D
var _door_pivot: Node3D
var _note: Note
var _busy: bool = false
var _asking: bool = false

func _ready() -> void:
	super._ready()
	prompt = open_prompt
	_build()
	_spawn_note()

func _build() -> void:
	# safe.glb の "Door" があればそれを回す。無いときだけ自前の扉を作る。
	_has_model = SystemUtil.has_model("safe")
	var prop := get_node_or_null(^"Prop") as Prop
	if prop:
		var inst := prop.get_instance()
		if inst:
			_door_node = inst.find_child("Door", true, false) as Node3D
	if _door_node:
		return
	_door_pivot = Node3D.new()
	_door_pivot.name = "DoorPivot"
	_door_pivot.position = Vector3(-door_size.x * 0.5, 0.32, -0.24)
	add_child(_door_pivot)
	var mi := MeshInstance3D.new()
	mi.name = "Door"
	var bm := BoxMesh.new()
	bm.size = door_size
	mi.mesh = bm
	mi.position = Vector3(door_size.x * 0.5, 0, 0)
	mi.material_override = SystemUtil.flat_material(Color(0.22, 0.22, 0.24))
	_door_pivot.add_child(mi)
	var dial := MeshInstance3D.new()
	dial.name = "Dial"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.045
	cm.height = 0.02
	cm.radial_segments = 10
	dial.mesh = cm
	dial.rotation_degrees = Vector3(90, 0, 0)
	dial.position = Vector3(door_size.x * 0.62, 0, -0.03)
	dial.material_override = SystemUtil.flat_material(Color(0.62, 0.60, 0.56))
	_door_pivot.add_child(dial)
	_door_pivot.visible = not _has_model

func _spawn_note() -> void:
	if not ResourceLoader.exists(NOTE_SCENE):
		return
	var packed: PackedScene = load(NOTE_SCENE)
	_note = packed.instantiate() as Note
	_note.name = "Ledger"
	_note.title = note_title
	_note.body = note_body
	_note.page_number = note_page
	_note.paper_size = Vector2(0.16, 0.22)
	_note.position = Vector3(0, 0.315, 0.0)   # 庫内の棚板の上
	_note.enabled = false
	_note.visible = false
	add_child(_note)

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

## 中身を設定する。開ける前に director が呼ぶ。
func set_note(title: String, body: String, page: int = 0) -> void:
	note_title = title
	note_body = body
	note_page = page
	if _note:
		_note.set_text(title, body, page)

func get_note() -> Note:
	return _note

func open() -> void:
	if is_open or _busy:
		return
	_busy = true
	await get_tree().create_timer(0.5, false).timeout
	Audio.play_at(&"safe_open", global_position)
	is_open = true
	enabled = false
	var door: Node3D = _door_node if _door_node else _door_pivot
	if door:
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(door, "rotation_degrees:y", door_open_degrees, 0.9)
	if _note:
		_note.enabled = true
		_note.visible = true
	_busy = false
	opened.emit()

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func get_prompt() -> String:
	return locked_prompt if is_open else open_prompt

func get_blocked_text() -> String:
	if _busy or _asking:
		return busy_text
	if is_open:
		return emptied_text
	return super.get_blocked_text()

## 正解の番号。director がフラグで入れる。
func expected_code() -> String:
	var v := String(Game.get_flag(&"safe_code", ""))
	return v if v != "" else fallback_code

## ダイヤルを回す。空文字はキャンセル。
func try_code() -> void:
	if _asking or _busy or is_open:
		return
	_asking = true
	Audio.play_at(&"safe_dial", global_position)
	var code: String = await Dialogue.code_input(code_title, code_length)
	_asking = false
	if code == "":
		return
	if code == expected_code():
		open()
	else:
		wrong_count += 1
		Audio.play_at(&"safe_wrong", global_position)
		Events.emit_event(&"safe_wrong", {"count": wrong_count})
		code_failed.emit(wrong_count)

func _can_interact(_player: Node3D) -> bool:
	return not is_open and not _busy and not _asking

func _interact(_player: Node3D) -> void:
	try_code()
