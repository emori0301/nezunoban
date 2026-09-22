class_name FlowerStand
extends Interactable
## 供花スタンド。水を持っていると替えられる。しおれ ↔ 元気で見た目が変わる。
## 式場に2つある(Anchor_FlowerL / Anchor_FlowerR)ので、取り出しは find_all を使う:
##     for f in SystemsInstaller.find_all(&"flower_stand"):
##         (f as FlowerStand).set_wilted(true)

signal watered

@export var water_item: StringName = &"water"
@export var change_prompt: String = "水を替える"
@export var idle_prompt: String = "供花"
@export var change_hold_time: float = 1.5
@export var is_wilted: bool = true
@export var flower_count: int = 7
@export var stem_height: float = 0.34
@export var base_y: float = 0.78          # 花を挿す高さ(スタンドの上)

var _stems: Array[Node3D] = []
var _prop: Prop
var _use_model: bool = false

func _ready() -> void:
	super._ready()
	prompt = change_prompt
	hold_time = change_hold_time
	required_item = water_item
	_prop = get_node_or_null(^"Prop") as Prop
	# flower_stand.glb は花まで含んでいるので、モデルがあれば自前の花は作らず
	# "Flower" / "Leaf" サーフェスの色でしおれを表す。
	_use_model = SystemUtil.has_model("flower_stand") and _prop != null
	if not _use_model:
		_build_flowers()
	_apply()

func _build_flowers() -> void:
	var stem_mat := SystemUtil.flat_material(Color(0.22, 0.34, 0.18))
	for i in flower_count:
		var pivot := Node3D.new()
		pivot.name = "Stem%d" % i
		var a := TAU * float(i) / float(flower_count)
		var r := 0.055 + 0.02 * float(i % 3)
		pivot.position = Vector3(cos(a) * r, base_y, sin(a) * r)
		pivot.rotation_degrees.y = rad_to_deg(a)
		add_child(pivot)

		var stem := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0035
		cm.bottom_radius = 0.0045
		cm.height = stem_height
		cm.radial_segments = 5
		cm.rings = 1
		stem.mesh = cm
		stem.position = Vector3(0, stem_height * 0.5, 0)
		stem.material_override = stem_mat
		stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(stem)

		var head := MeshInstance3D.new()
		head.name = "Head"
		var sm := SphereMesh.new()
		sm.radius = 0.032
		sm.height = 0.050
		sm.radial_segments = 8
		sm.rings = 4
		head.mesh = sm
		head.position = Vector3(0, stem_height, 0)
		head.material_override = SystemUtil.flat_material(Color(0.95, 0.95, 0.92))
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(head)
		_stems.append(pivot)

func _apply() -> void:
	if _use_model:
		var inst := _prop.get_instance()
		SystemUtil.tint_surfaces(inst, "Flower", Color(0.74, 0.68, 0.52) if is_wilted else Color(1, 1, 1))
		SystemUtil.tint_surfaces(inst, "Leaf", Color(0.66, 0.62, 0.45) if is_wilted else Color(1, 1, 1))
		return
	for i in _stems.size():
		var pivot := _stems[i]
		var droop: float = 46.0 + float(i % 4) * 7.0 if is_wilted else float(i % 5) * 3.0
		pivot.rotation_degrees.x = droop
		var head := pivot.get_node_or_null(^"Head") as MeshInstance3D
		if head:
			var m := head.material_override as StandardMaterial3D
			m.albedo_color = Color(0.72, 0.66, 0.52) if is_wilted else Color(0.97, 0.97, 0.94)

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

func set_wilted(wilted: bool) -> void:
	is_wilted = wilted
	_apply()

func change_water(player: Node3D) -> void:
	SystemUtil.take_item(player, water_item)
	Audio.play_at(&"water_pour", global_position)
	set_wilted(false)
	Events.emit_event(&"flowers_watered")
	watered.emit()

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func get_prompt() -> String:
	if not SystemUtil.has_item(Game.player, water_item):
		return idle_prompt
	return change_prompt

func _interact(player: Node3D) -> void:
	change_water(player)
