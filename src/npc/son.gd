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
##     son.drink_on_zabuton()                                 # 座布団にあぐらで飲み続ける
##     son.sleep()                                            # 横になっていびきをかく
##     if son.is_sleeping: 火車を控室へ通せる

signal fell_asleep

@export_group("息子")
## 飲んでいる位置。座卓(x -1.93〜-0.78, z 2.64〜3.36)を挟んで TV 台(z 1.51〜1.99)の
## 反対側にある座布団 Zabuton_-13_38 (-1.35, 3.8)。向きは座卓のほう(-Z)。
## 座布団の厚みは 0.07m で、models の sit_floor / sleep はそれを見込んだ高さで作られている。
@export var drink_position: Vector3 = Vector3(-1.35, 0.0, 3.8)
@export var drink_yaw_deg: float = 0.0
## 寝る位置。座卓・布団・TV 台のどれにも当たらない畳の空き。
## sleep アニメは体が正面(-Z)側へ伸びるので、yaw 90 で頭が -X(西の壁側)を向く。
@export var sleep_position: Vector3 = Vector3(-2.05, 0.0, 2.05)
@export var sleep_yaw_deg: float = 90.0
## 寝息のアニメをゆっくり回す。
@export var sleep_anim_speed: float = 0.55
## いびき。audio の snore_1 / snore_2 を交互に鳴らす。
@export var snore_sounds: Array[StringName] = [&"snore_1", &"snore_2"]
@export var snore_interval: float = 4.0
@export var snore_pitch: float = 1.0

var is_sleeping: bool = false
var is_drinking: bool = false

var _snore_gen: int = 0


func _init() -> void:
	model_name = "npc_son"
	npc_id = &"son"
	move_speed = 1.1
	body_radius = 0.27
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


## 控室の座布団まで歩く。座卓を回り込めるよう、西(-X)側から寄る。
func go_to_hikaeshitsu() -> void:
	await go_to(Vector3(-2.45, 0.0, 3.8))


## 座布団にあぐらで座って飲み続ける(00:30 で「断る」を選んだあと)。
func drink_on_zabuton() -> void:
	is_drinking = true
	is_sleeping = false
	set_talkable(true)
	sit_on_floor(drink_position, drink_yaw_deg)


## 座布団の上で寝る。sleep アニメ(うつ伏せ寄りの寝姿)をゆっくり回し、
## 4 秒周期でいびきを鳴らす。
func sleep() -> void:
	if is_sleeping:
		return
	set_talkable(false)
	is_drinking = false
	is_sleeping = true
	lie_down(sleep_position, sleep_yaw_deg, sleep_anim_speed)
	Game.set_flag(&"son_asleep", true)
	fell_asleep.emit()
	_snore_gen += 1
	_snore_loop(_snore_gen)


func wake() -> void:
	if not is_sleeping and not is_drinking:
		return
	is_sleeping = false
	is_drinking = false
	_snore_gen += 1
	Game.set_flag(&"son_asleep", false)
	stand_up()


func _snore_loop(g: int) -> void:
	var i := 0
	while is_sleeping and _snore_gen == g and is_inside_tree() and is_active:
		if not snore_sounds.is_empty():
			Audio.play_at(snore_sounds[i % snore_sounds.size()], head_position(),
				-2.0, snore_pitch, 9.0)
			i += 1
		await get_tree().create_timer(snore_interval, false).timeout
