class_name Breaker
extends Interactable
## バックヤードの分電盤。照明の実際の操作は director が Building に対して行う。
## ここは「落ちた/上げた」を音とイベントで伝えるだけ。
##
## director からの使い方:
##     var br := SystemsInstaller.find(&"breaker") as Breaker
##     br.trip()                                  # 00:00 廊下の照明が落ちる
##     Events.on(&"breaker_on", func(_d):
##         Building.set_all_lights(true))

signal tripped
signal restored

@export var is_on: bool = true
@export var restore_prompt: String = "ブレーカーを上げる"
@export var idle_prompt: String = "分電盤"
@export var restore_hold_time: float = 1.0
@export var panel_size: Vector3 = Vector3(0.30, 0.40, 0.12)
## レバーの位置(breaker_box.glb の前面に合わせてある)
## モデルの主幹ブレーカーのレバーを倒す角度(X 回転)
@export var lever_down_degrees: float = 38.0
@export var lever_offset: Vector3 = Vector3(-0.263, 0.188, 0.045)
@export var lever_size: Vector3 = Vector3(0.030, 0.050, 0.022)

var _model_lever: Node3D
var _lever: MeshInstance3D

func _ready() -> void:
	super._ready()
	prompt = restore_prompt
	hold_time = restore_hold_time
	_build()
	_apply()

func _build() -> void:
	# breaker_box.glb の "Lever"(原点 (-0.140, 0.210, 0.006)、X 回転で上下に倒れる)
	var prop := get_node_or_null(^"Prop") as Prop
	if prop:
		var inst := prop.get_instance()
		if inst:
			_model_lever = inst.find_child("Lever", true, false) as Node3D
	if _model_lever:
		return
	_lever = MeshInstance3D.new()
	_lever.name = "Lever"
	var bm := BoxMesh.new()
	bm.size = lever_size if SystemUtil.has_model("breaker_box") else Vector3(0.05, 0.09, 0.035)
	_lever.mesh = bm
	_lever.position = lever_offset if SystemUtil.has_model("breaker_box") else Vector3(0, panel_size.y * 0.55, panel_size.z * 0.5 + 0.02)
	_lever.material_override = SystemUtil.flat_material(Color(0.85, 0.83, 0.78))
	# breaker_box.glb は主幹ブレーカーとスイッチ列を持っているので、自前のレバーは出さない
	# (models に "Lever" ノードを切ってもらえたら、そこを回して見た目でも上下を出せる)。
	_lever.visible = not SystemUtil.has_model("breaker_box")
	add_child(_lever)

func _apply(animate: bool = false) -> void:
	if _model_lever:
		if animate:
			var tw := create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(_model_lever, "rotation_degrees:x", 0.0 if is_on else lever_down_degrees, 0.18)
		else:
			_model_lever.rotation_degrees.x = 0.0 if is_on else lever_down_degrees
		return
	if _lever:
		_lever.rotation_degrees.x = 0.0 if is_on else 34.0
		(_lever.material_override as StandardMaterial3D).albedo_color = (
			Color(0.85, 0.83, 0.78) if is_on else Color(0.55, 0.20, 0.16))

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

## ブレーカーを落とす(台本用)。
func trip() -> void:
	if not is_on:
		return
	is_on = false
	_apply(true)
	Audio.play_at(&"breaker_click", global_position)
	Audio.play_at(&"lights_off", global_position, -4.0)
	Events.emit_event(&"breaker_off")
	tripped.emit()

## 上げる。
func restore() -> void:
	if is_on:
		return
	is_on = true
	_apply(true)
	Audio.play_at(&"breaker_click", global_position)
	Audio.play_at(&"lights_on", global_position, -4.0)
	Events.emit_event(&"breaker_on")
	restored.emit()

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func get_prompt() -> String:
	return restore_prompt if not is_on else idle_prompt

func _can_interact(_player: Node3D) -> bool:
	return not is_on

func _interact(_player: Node3D) -> void:
	restore()
