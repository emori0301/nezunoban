class_name NpcSon
extends NpcBase
## 息子(春日誠)。00:30 に玄関から泥酔して来館する。
## 「断る」を選ぶと控室で飲み続け、01:30 に座布団の上で寝る(真エンドの前提)。
##
## 酔っているので歩行がわずかに蛇行する(NpcBase.drunk)。
##
## director からの使い方:
##     var son := NpcInstaller.find(&"son") as NpcSon
##     await son.enter_from_genkan(Vector3(9.0, 0.0, -0.5))   # 玄関から入って式場へ
##     son.set_talkable(true)
##     await son.go_to_hikaeshitsu()
##     son.sleep()                                            # いびきをかいて寝る
##     if son.is_sleeping: 火車を控室へ通せる

signal fell_asleep

@export_group("息子")
## 座布団の上。furnish_a.gd の Zabuton_-13_22 の位置。
@export var sleep_position: Vector3 = Vector3(-1.35, 0.0, 2.2)
@export var sleep_yaw_deg: float = 180.0
@export var sleep_anim_speed: float = 0.32
## いびき。audio に専用の音が無いので breath_close を低いピッチで流している。
@export var snore_sound: StringName = &"breath_close"
@export var snore_interval: float = 4.0
@export var snore_pitch: float = 0.72

var is_sleeping: bool = false

var _snore_gen: int = 0


func _init() -> void:
	model_name = "npc_son"
	npc_id = &"son"
	move_speed = 1.1
	body_radius = 0.30
	body_height = 1.75
	head_height = 1.62
	agent_radius = 0.32
	talk_prompt = "話す"
	talkable = false
	drunk = true
	start_active = false


func _ready() -> void:
	super._ready()
	add_to_group(&"npc_human")


func _locomotion_anim_enabled() -> bool:
	return not is_sleeping


## 控室の座布団まで歩く。
func go_to_hikaeshitsu() -> void:
	await go_to(sleep_position + Vector3(0.0, 0.0, -0.9))


## 座布団の上で寝る。idle をごく遅く回し、4 秒周期でいびきを鳴らす。
func sleep() -> void:
	if is_sleeping:
		return
	stop()
	set_talkable(false)
	global_position = Vector3(sleep_position.x, global_position.y, sleep_position.z)
	rotation.y = deg_to_rad(sleep_yaw_deg)
	_target_yaw = rotation.y
	is_sleeping = true
	play_anim(anim_idle, sleep_anim_speed)
	Game.set_flag(&"son_asleep", true)
	fell_asleep.emit()
	_snore_gen += 1
	_snore_loop(_snore_gen)


func wake() -> void:
	if not is_sleeping:
		return
	is_sleeping = false
	_snore_gen += 1
	Game.set_flag(&"son_asleep", false)
	play_anim(anim_idle, 1.0)


func _snore_loop(g: int) -> void:
	while is_sleeping and _snore_gen == g and is_inside_tree() and is_active:
		Audio.play_at(snore_sound, head_position(), -4.0, snore_pitch, 9.0)
		await get_tree().create_timer(snore_interval).timeout
