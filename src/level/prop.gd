@tool
class_name Prop
extends Node3D
## 3Dモデルの配置ノード。assets/models/<model_name>.glb があればそれを、無ければ placeholder_size の箱を出す。
## モデル担当とレベル担当が並列で作業できるようにするための緩衝。
## 読み込んだマテリアルは PSX 風にするため texture_filter を NEAREST に統一する。

@export var model_name: String = "":
	set(v):
		model_name = v
		if is_inside_tree():
			_rebuild()
@export var placeholder_size: Vector3 = Vector3(1, 1, 1)
@export var placeholder_color: Color = Color(0.5, 0.3, 0.6)
@export var cast_shadow: bool = true
@export var add_collision: bool = true   # 箱コリジョン(StaticBody3D, layer 1)を付ける

var _instance: Node3D = null

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		if c.owner == null or Engine.is_editor_hint():
			c.queue_free()
	_instance = null
	var path := "res://assets/models/%s.glb" % model_name
	if model_name != "" and ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		if scene:
			_instance = scene.instantiate()
			add_child(_instance)
			_apply_psx(_instance)
			return
	_build_placeholder()

func _build_placeholder() -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = placeholder_size
	mi.mesh = box
	mi.position.y = placeholder_size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = placeholder_color
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)
	_instance = mi
	if add_collision and not Engine.is_editor_hint():
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = placeholder_size
		cs.shape = shape
		cs.position.y = placeholder_size.y * 0.5
		sb.add_child(cs)
		add_child(sb)

func _apply_psx(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D:
				var dup := (m as BaseMaterial3D).duplicate()
				dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				dup.roughness = maxf(dup.roughness, 0.85)
				dup.metallic = 0.0
				dup.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mi.set_surface_override_material(i, dup)
	if add_collision and not Engine.is_editor_hint():
		var has_body := root.find_children("*", "CollisionObject3D", true, false).size() > 0
		if not has_body:
			for n in root.find_children("*", "MeshInstance3D", true, false):
				(n as MeshInstance3D).create_trimesh_collision()
				for b in n.get_children():
					if b is StaticBody3D:
						b.collision_layer = 1
						b.collision_mask = 0

func get_instance() -> Node3D:
	return _instance
