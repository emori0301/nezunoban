class_name BodyRisen
extends Node3D
## 起き上がった故人。演出専用なので当たり判定もナビも持たない。
## director が棺の位置に置いて rise() を呼ぶ。
##
##     var br := load("res://src/npc/body_risen.tscn").instantiate()
##     world.add_child(br)
##     br.global_position = coffin.global_position
##     br.rotation.y = coffin.rotation.y     # 棺の頭側 +X に合わせる
##     await br.rise()

signal risen

@export var start_hidden: bool = true
@export var anim_rise: StringName = &"rise"
@export var sound: StringName = &"body_rise"

var model: Prop = null
var anim: AnimationPlayer = null


func _ready() -> void:
	add_to_group(&"npc")
	add_to_group(&"body_risen")
	model = Prop.new()
	model.name = "Model"
	model.add_collision = false
	model.placeholder_size = Vector3(0.52, 0.25, 1.74)
	model.placeholder_color = Color(0.78, 0.76, 0.72)
	model.model_name = "body_risen"
	add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
	visible = not start_hidden


## 寝た姿勢(rest ポーズ)から上体を起こす。1 回だけ再生する。
func rise() -> void:
	visible = true
	Audio.play_at(sound, global_position + Vector3(0, 0.4, 0), 0.0, 1.0, 26.0)
	if anim == null or not anim.has_animation(String(anim_rise)):
		push_warning("BodyRisen: %s アニメが無い" % anim_rise)
		risen.emit()
		return
	anim.speed_scale = 1.0
	anim.play(String(anim_rise))
	await anim.animation_finished
	risen.emit()


## 寝た姿勢に戻す。
func reset_pose() -> void:
	if anim and anim.has_animation(String(anim_rise)):
		anim.play(String(anim_rise))
		anim.seek(0.0, true)
		anim.stop()
