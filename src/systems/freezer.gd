class_name Freezer
extends Interactable
## バックヤードの冷凍庫。ドライアイスを取る。03:40 以降は空。
##
## director からの使い方:
##     var fz := SystemsInstaller.find(&"freezer") as Freezer
##     fz.set_empty(true)     # 2回目の交換ができなくなる

signal taken
signal found_empty

@export var is_empty: bool = false
@export var item_name: StringName = &"dry_ice"
@export var carried: bool = true          # 運搬中は両手が塞がる
@export var take_prompt: String = "ドライアイスを取る"
@export var empty_line: String = "……空だ。もう無い。"
@export var open_seconds: float = 2.2
@export var keep_open: bool = false       # 確認用: 蓋を開けっぱなしにする
## freezer_chest.glb の "Lid"(原点 (0, 0.785, -0.342)、X 回転の - で開く)
@export var lid_open_degrees: float = -74.0
## 庫内のドライアイス箱の位置(庫内は Y 0.285..0.785)
@export var ice_offset: Vector3 = Vector3(0.0, 0.30, 0.0)
@export var chest_size: Vector3 = Vector3(1.244, 0.86, 0.717)   # freezer_chest.glb の実寸

var is_lid_open: bool = false

var _lid_pivot: Node3D
var _lid_node: Node3D
var _ice: Prop
var _fog: GPUParticles3D
var _prop: Prop
var _busy: bool = false

func _ready() -> void:
	super._ready()
	prompt = take_prompt
	_prop = get_node_or_null(^"Prop") as Prop
	_build()
	if keep_open:
		call_deferred(&"_set_lid", true)

func _build() -> void:
	# 蓋。freezer_chest.glb の "Lid" は原点が奥側の蝶番になっている。
	_lid_node = _find_lid_in_model()
	if _lid_node == null:
		_lid_pivot = Node3D.new()
		_lid_pivot.name = "LidPivot"
		_lid_pivot.position = Vector3(0, chest_size.y, -chest_size.z * 0.5)
		add_child(_lid_pivot)
		var mi := MeshInstance3D.new()
		mi.name = "Lid"
		var bm := BoxMesh.new()
		bm.size = Vector3(chest_size.x + 0.04, 0.07, chest_size.z + 0.04)
		mi.mesh = bm
		mi.position = Vector3(0, 0.035, chest_size.z * 0.5)
		mi.material_override = SystemUtil.flat_material(Color(0.78, 0.78, 0.76))
		mi.visible = not SystemUtil.has_model("freezer_chest")
		_lid_pivot.add_child(mi)
		lid_open_degrees = -72.0
	else:
		_lid_pivot = _lid_node

	# 庫内のドライアイス(空にすると消える)
	if SystemUtil.has_model("dry_ice_box"):
		_ice = Prop.new()
		_ice.name = "DryIce"
		_ice.add_collision = false
		_ice.position = ice_offset
		_ice.model_name = "dry_ice_box"
		add_child(_ice)
		_ice.visible = not is_empty

	# 中の白い霧
	_fog = SystemUtil.make_fog(130, 3.0, chest_size.x * 0.42)
	_fog.name = "Fog"
	# 庫内の口のあたりから湧かせ、縁を越えて側面を伝い落ちるようにする。
	_fog.position = Vector3(0, chest_size.y - 0.04, 0)
	_fog.emitting = false
	add_child(_fog)

func _find_lid_in_model() -> Node3D:
	if _prop == null:
		return null
	var inst := _prop.get_instance()
	if inst == null:
		return null
	for n in inst.find_children("*", "Node3D", true, false):
		if String(n.name).to_lower().contains("lid"):
			return n as Node3D
	return null

func _set_lid(open: bool) -> void:
	is_lid_open = open
	if _lid_pivot:
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(_lid_pivot, "rotation_degrees:x", lid_open_degrees if open else 0.0, 0.5)
	if _fog:
		_fog.emitting = open

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

## 蓋の開閉(確認用・台本用)。
func set_lid_open(open: bool) -> void:
	_set_lid(open)

func set_empty(empty: bool) -> void:
	is_empty = empty
	if _ice:
		_ice.visible = not empty

## 蓋を開けてドライアイスを取る。
func take(player: Node3D) -> void:
	if _busy:
		return
	_busy = true
	Audio.play_at(&"freezer_open", global_position)
	_set_lid(true)
	await get_tree().create_timer(0.55).timeout
	if is_empty:
		Dialogue.monologue(empty_line)
		found_empty.emit()
	else:
		SystemUtil.give_item(player, item_name, carried)
		taken.emit()
	if not keep_open:
		await get_tree().create_timer(open_seconds).timeout
		_set_lid(false)
		Audio.play_at(&"freezer_close", global_position)
	_busy = false

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func _can_interact(player: Node3D) -> bool:
	if _busy:
		return false
	# もう持っているなら取れない
	return not SystemUtil.has_item(player, item_name)

func _interact(player: Node3D) -> void:
	take(player)
