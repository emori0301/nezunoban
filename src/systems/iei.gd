class_name Iei
extends Interactable
## 遺影。伏せる・目線が追う・写真を差し替える(遺影エンド)。
##
## director からの使い方:
##     var iei := SystemsInstaller.find(&"iei") as Iei
##     iei.set_face_down(true)                 # 00:00 復旧して戻ると伏せてある
##     iei.set_follow_player(true)             # 異変度>=3: どこにいても目線が追う
##     iei.set_portrait(load("res://assets/textures/portrait_player.png"))  # 遺影エンド

signal fixed

@export var fix_prompt: String = "遺影を直す"
@export var idle_prompt: String = "遺影"
@export var upright_text: String = "そのままでいい。"
@export var photo_size: Vector2 = Vector2(0.22, 0.30)
## モデルは +Z が正面。
@export var photo_offset: Vector3 = Vector3(0, 0.33, 0.058)
@export var stand_height: float = 0.07
@export var follow_max_degrees: float = 16.0
@export var follow_speed: float = 1.8

var is_face_down: bool = false
var follow_player: bool = false

var _pivot: Node3D
var _photo: MeshInstance3D
var _prop: Prop
var _yaw: float = 0.0
var _use_model: bool = false

func _ready() -> void:
	super._ready()
	prompt = idle_prompt
	_prop = get_node_or_null(^"Prop") as Prop
	_use_model = SystemUtil.has_model("iei_frame") and _prop != null
	_build()
	if _use_model and _photo:
		# iei_frame.glb は写真("Photo" サーフェス)を持っているので自前の板は出さない
		_photo.visible = false
	set_process(true)

func _build() -> void:
	# 額縁ごと傾ける/回すためのピボット。Prop も中に入れ直す。
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.position = Vector3(0, stand_height, 0)
	add_child(_pivot)
	if _prop:
		_prop.reparent(_pivot, false)
		_prop.position = Vector3.ZERO

	_photo = MeshInstance3D.new()
	_photo.name = "Photo"
	var q := QuadMesh.new()
	q.size = photo_size
	_photo.mesh = q
	_photo.position = photo_offset
	_photo.rotation_degrees = Vector3.ZERO          # 手前(+Z)を向く
	_photo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_photo.material_override = _default_portrait_material()
	_pivot.add_child(_photo)

func _default_portrait_material() -> StandardMaterial3D:
	var tex := SystemUtil.load_texture("iei_portrait")
	if tex == null:
		tex = SystemUtil.face_texture(0, 96)
	var m := SystemUtil.alpha_material(tex, Color(0.82, 0.80, 0.78, 1.0), false, false)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	return m

func _process(delta: float) -> void:
	if not follow_player or is_face_down or _pivot == null:
		return
	var p := Game.player
	if p == null or not (p is Node3D):
		return
	# 額縁をプレイヤーの方向へ少しだけ回す(目線が追う)
	var to := (p as Node3D).global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var want := atan2(to.x, to.z)          # 写真は +Z を向いている
	var here := global_rotation.y
	var diff := wrapf(want - here, -PI, PI)
	var target := clampf(rad_to_deg(diff), -follow_max_degrees, follow_max_degrees)
	_yaw = lerpf(_yaw, target, clampf(delta * follow_speed, 0.0, 1.0))
	_pivot.rotation_degrees.y = _yaw

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

func set_face_down(down: bool) -> void:
	if is_face_down == down:
		return
	is_face_down = down
	prompt = fix_prompt if down else idle_prompt
	if _pivot:
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(_pivot, "rotation_degrees:x", -82.0 if down else 0.0, 0.5)
	if down:
		Audio.play_at(&"chair_drag", global_position, -12.0, 1.4)

func set_follow_player(on: bool) -> void:
	follow_player = on
	if not on and _pivot:
		var tw := create_tween()
		tw.tween_property(_pivot, "rotation_degrees:y", 0.0, 0.6)
		_yaw = 0.0

## 遺影エンド用。写真を差し替える。
## 例: iei.set_portrait(load("res://assets/textures/iei_photo_player.png"))
func set_portrait(texture: Texture2D) -> void:
	if texture == null:
		return
	if _use_model and SystemUtil.set_surface_texture(_prop.get_instance(), "Photo", texture) > 0:
		return
	if _photo == null:
		return
	_photo.visible = true
	var m := SystemUtil.alpha_material(texture, Color(1, 1, 1, 1), false, false)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_photo.material_override = m

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func get_prompt() -> String:
	return fix_prompt if is_face_down else idle_prompt

func get_blocked_text() -> String:
	if not is_face_down:
		return upright_text
	return super.get_blocked_text()

func _can_interact(_player: Node3D) -> bool:
	return is_face_down

func _interact(_player: Node3D) -> void:
	set_face_down(false)
	Audio.play_at(&"paper_rustle", global_position, -8.0)
	fixed.emit()
