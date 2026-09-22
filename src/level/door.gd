class_name Door
extends Interactable
## 建物の扉。開閉は 0.5 秒の tween、開いている間は板の当たり判定を外して通れるようにする。
## 種類は開き戸(SWING) / 片引き戸(SLIDE) / 引き分け戸(SLIDE_DOUBLE)。
##
## 置き方: ノードは開口部の中心・床面(y=0)に置く。
##   ローカル +X = 開口の幅方向、ローカル Z = 厚み方向。
##   壁が X 軸に沿っている(z 一定)なら yaw = 0、Z 軸に沿っている(x 一定)なら yaw = 90。
##
## Events: door_opened{door} / door_closed{door}
## director が独りでに閉める演出には slam() を使う。

enum Kind { SWING, SLIDE, SLIDE_DOUBLE }

const TWEEN_TIME := 0.5
const SLAM_TIME := 0.13

@export var kind: Kind = Kind.SWING
@export var door_width: float = 0.9
@export var door_height: float = 2.0
@export var door_thickness: float = 0.06
## SWING: +1 なら開口のローカル +X 側が蝶番。SLIDE: 引き込む向き。
@export var hinge_side: float = 1.0
## 開く角度。符号で開く向き(+ でローカル -Z 側へ開く)。
@export var swing_degrees: float = 95.0
@export var locked: bool = false
## >0 なら開いてからこの秒数で自動的に閉じる(玄関の自動ドアなど)。
@export var auto_close_after: float = 0.0
@export var steel: bool = false   ## 鉄扉。音が door_steel_*
@export var glass: bool = false   ## ガラス戸(玄関)
@export var start_open: bool = false
@export var build_frame: bool = true

@export var open_prompt: String = "開ける"
@export var close_prompt: String = "閉める"
@export var locked_prompt: String = "鍵がかかっている"

var is_open: bool = false

var _leaves: Array[Node3D] = []
var _props: Array[String] = []
var _closed_v: Array[float] = []
var _open_v: Array[float] = []
var _shapes: Array[CollisionShape3D] = []
var _tween: Tween = null
var _auto_id: int = 0


func _ready() -> void:
	super._ready()
	add_to_group(&"door")
	_build()
	if start_open:
		is_open = true
		for i in _leaves.size():
			_leaves[i].set(_props[i], _open_v[i])
		_set_solid(false)


func get_prompt() -> String:
	if locked and not is_open:
		return locked_prompt
	return close_prompt if is_open else open_prompt


func _can_interact(_player: Node3D) -> bool:
	return true


func _interact(_player: Node3D) -> void:
	toggle()


# ---------------------------------------------------------------- public API

func toggle(force: bool = false) -> void:
	if is_open:
		close()
	else:
		open(force)


## 開ける。locked なら鍵の音だけ鳴らす(force = true で強制的に開く)。
func open(force: bool = false) -> void:
	if is_open:
		return
	if locked and not force:
		Audio.play(&"door_locked")
		return
	is_open = true
	_set_solid(false)
	_animate(true, TWEEN_TIME)
	Audio.play(&"door_steel_open" if steel else &"door_open")
	Events.emit_event(&"door_opened", {"door": name})
	if auto_close_after > 0.0:
		_auto_id += 1
		var my := _auto_id
		await get_tree().create_timer(auto_close_after).timeout
		if my == _auto_id and is_open:
			close()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_auto_id += 1
	_animate(false, TWEEN_TIME)
	Audio.play(&"door_steel_close" if steel else &"door_close")
	Events.emit_event(&"door_closed", {"door": name})


## 独りでに、速く、大きな音で閉まる。
func slam() -> void:
	_auto_id += 1
	var was_open := is_open
	is_open = false
	_animate(false, SLAM_TIME)
	Audio.play(&"door_steel_close" if steel else &"door_close", 6.0, 0.88)
	if was_open:
		Events.emit_event(&"door_closed", {"door": name})


func set_locked(v: bool) -> void:
	locked = v


# ---------------------------------------------------------------- internals

func _animate(opening: bool, dur: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN_OUT if opening else Tween.EASE_OUT)
	for i in _leaves.size():
		var target: float = _open_v[i] if opening else _closed_v[i]
		_tween.tween_property(_leaves[i], _props[i], target, dur)
	if not opening:
		_tween.chain().tween_callback(func() -> void:
			if not is_open:
				_set_solid(true))


func _set_solid(solid: bool) -> void:
	for s in _shapes:
		s.disabled = not solid


func _panel_material() -> StandardMaterial3D:
	if glass:
		return LevelMaterials.translucent(Color(0.62, 0.70, 0.72), 0.30)
	if steel:
		return LevelMaterials.get_mat("steel", 1.0)
	return LevelMaterials.get_mat("wood_dark", 1.0)


func _build() -> void:
	# 視線インタラクト用の判定(開口部の位置に固定。開いていても閉められる)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(door_width + 0.1, door_height, 0.5)
	cs.shape = bs
	cs.position = Vector3(0, door_height * 0.5, 0)
	add_child(cs)

	if build_frame:
		var fm := LevelMaterials.get_mat("wood_dark", 1.0)
		var jamb := Vector3(0.05, door_height + 0.06, door_thickness + 0.14)
		LevelBuild.box(self, Vector3(-door_width * 0.5 - 0.025, door_height * 0.5, 0), jamb, fm, false, "", false)
		LevelBuild.box(self, Vector3(door_width * 0.5 + 0.025, door_height * 0.5, 0), jamb, fm, false, "", false)
		LevelBuild.box(self, Vector3(0, door_height + 0.03, 0),
			Vector3(door_width + 0.15, 0.06, door_thickness + 0.14), fm, false, "", false)

	match kind:
		Kind.SWING:
			_make_swing()
		Kind.SLIDE:
			_make_slide_single()
		Kind.SLIDE_DOUBLE:
			_make_slide_double()


func _make_swing() -> void:
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(hinge_side * door_width * 0.5, 0, 0)
	add_child(pivot)
	_panel(pivot, Vector3(-hinge_side * door_width * 0.5, door_height * 0.5, 0),
		Vector3(door_width, door_height, door_thickness))
	_leaves.append(pivot)
	_props.append("rotation_degrees:y")
	_closed_v.append(0.0)
	_open_v.append(swing_degrees * hinge_side)


func _make_slide_single() -> void:
	var leaf := Node3D.new()
	leaf.name = "Leaf"
	add_child(leaf)
	_panel(leaf, Vector3(0, door_height * 0.5, 0), Vector3(door_width, door_height, door_thickness))
	_leaves.append(leaf)
	_props.append("position:x")
	_closed_v.append(0.0)
	_open_v.append(door_width * hinge_side)


func _make_slide_double() -> void:
	var half := door_width * 0.5
	for s in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.name = "LeafL" if s < 0 else "LeafR"
		add_child(leaf)
		_panel(leaf, Vector3(s * half * 0.5, door_height * 0.5, 0),
			Vector3(half, door_height, door_thickness))
		_leaves.append(leaf)
		_props.append("position:x")
		_closed_v.append(0.0)
		_open_v.append(s * half)


func _panel(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var mat := _panel_material()
	var mi := LevelBuild.box(parent, center, size, mat, false, "", true)
	mi.name = "Panel"
	if glass:
		# ガラス戸の框(かまち)
		var fm := LevelMaterials.plain(Color(0.30, 0.30, 0.31))
		LevelBuild.box(parent, center + Vector3(0, size.y * 0.5 - 0.05, 0),
			Vector3(size.x, 0.1, size.z + 0.02), fm, false, "", false)
		LevelBuild.box(parent, center + Vector3(0, -size.y * 0.5 + 0.05, 0),
			Vector3(size.x, 0.1, size.z + 0.02), fm, false, "", false)
	elif not steel:
		# 取っ手
		var hm := LevelMaterials.plain(Color(0.45, 0.42, 0.34))
		var hx: float = center.x - signf(center.x if absf(center.x) > 0.001 else 1.0) * size.x * 0.34
		LevelBuild.box(parent, Vector3(hx, 1.02, size.z * 0.5 + 0.03),
			Vector3(0.05, 0.14, 0.06), hm, false, "", false)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	sb.add_child(cs)
	parent.add_child(sb)
	_shapes.append(cs)
