class_name Kasha
extends NpcBase
## 火車。04:00 以降の終盤だけ出る、猫のような妖怪。湯灌室から出てプレイヤーを追う。
##
## 速さ: プレイヤーの視界(FOV 100°・遮蔽なし)に入っている間は 3.0 m/s(プレイヤーは 2.5)。
## 視界から外れている間は 1.2 m/s に落ちるので、L 字廊下の角で見失う画になる。
##
## director からの使い方:
##     var k := NpcInstaller.find(&"kasha") as Kasha
##     k.caught.connect(func(): ... )            # 掴まれた(演出は director)
##     k.activate()                              # 湯灌室から出現 → 追跡開始(chase_started)
##     k.set_ceiling_mode(true)                  # 廊下だけ天井を這う
##     k.retreat()                               # 灯し直し成功で一度退く(relight_success でも自動)
##     k.resume()                                # また追う
##     k.stop_chase()                            # 完全停止(chase_ended)
##     k.took_target.connect(...); k.go_to_and_take(son)   # 真エンド

signal caught                                   ## プレイヤーを捕まえた
signal took_target(target: Node3D)               ## go_to_and_take の到着

@export_group("火車")
@export var chase_speed: float = 3.0             ## 見られている間
@export var unseen_speed: float = 1.2            ## 見失われている間
@export var retreat_speed: float = 4.0
@export var catch_distance: float = 1.2
@export var catch_freeze: float = 1.0
## 一度掴んだあと、プレイヤーがこの距離まで離れるまで掴み直さない。
@export var catch_rearm_distance: float = 2.4
@export var sight_fov_deg: float = 100.0
@export var sight_range: float = 26.0
@export var retreat_idle_seconds: float = 10.0
@export var eye_energy: float = 5.0
@export var eye_color: Color = Color(1.0, 0.06, 0.03)
@export var anim_crawl: StringName = &"crawl"
@export var crawl_sound_interval: float = 3.1
@export var ceiling_height: float = 2.5          ## 廊下の天井高

var is_chasing: bool = false
var is_retreating: bool = false
var ceiling_mode: bool = false
var player_sees_me: bool = false

var _gen: int = 0
var _crawl_t: float = 0.0
var _repath_t: float = 0.0
var _caught_armed: bool = true
var _free_anim: bool = false


func _init() -> void:
	model_name = "kasha"
	npc_id = &"kasha"
	move_speed = 3.0
	agent_radius = 0.45
	body_radius = 0.33
	body_height = 0.90
	head_height = 0.62
	arrive_distance = 0.6
	turn_speed = 5.0
	accel = 12.0
	can_open_doors = true
	look_at_player_when_near = false
	talkable = false
	start_active = false
	loop_anims = [&"idle", &"crawl"]
	anim_sit = &""
	anim_sit_floor = &""
	anim_sleep = &""
	anim_walk = &"crawl"
	# Spawn_Kasha (7.3, -11.0) は湯灌室のステンレス台(x 6.25〜8.35, z -10.38〜-9.43)と
	# 棚(x 5.45〜5.85)に挟まれている。ナビメッシュは家具を見ていないので、台の東を回って出る。
	spawn_exit_route = [Vector3(8.82, 0.0, -10.9), Vector3(8.82, 0.0, -8.6)]


func _ready() -> void:
	super._ready()
	add_to_group(&"kasha")
	if talk:
		talk.enabled = false
		talk.monitorable = false
	set_eye_glow(eye_energy)
	Events.on(&"relight_success", func(_d: Dictionary) -> void:
		if is_active and is_chasing:
			retreat())


func _locomotion_anim_enabled() -> bool:
	return not _free_anim and super._locomotion_anim_enabled()


# ============================================================ 公開 API

## 湯灌室から出現して追跡を始める。
func activate() -> void:
	var b := NpcUtil.building()
	var spawn: Vector3 = Vector3(7.3, 0.0, -11.0)
	if b:
		var a := b.get_anchor(&"Spawn_Kasha")
		if a:
			spawn = a.global_position
	set_active(true)
	teleport_to(NpcUtil.snap(get_world_3d(), spawn), 180.0)
	_caught_armed = true
	set_eye_glow(eye_energy)
	play_anim(anim_crawl)
	# 湯灌室の戸を開けて出る
	if b:
		var d := b.get_door(&"Door_Yukan")
		if d:
			d.set_locked(false)
			d.open()
	Audio.play_at(&"kasha_screech", global_position, 0.0, 1.0, 30.0)
	# 台の東を回って湯灌室を出てから追跡に入る
	await walk_spawn_exit_route()
	if not is_active:
		return
	start_chase()


func start_chase() -> void:
	if is_chasing:
		return
	is_chasing = true
	is_retreating = false
	_gen += 1
	set_speed_override(unseen_speed)
	Events.emit_event(&"chase_started", {})


## 完全に止める。
func stop_chase() -> void:
	if not is_chasing and not is_retreating:
		return
	is_chasing = false
	is_retreating = false
	_gen += 1
	stop()
	_free_anim = true
	play_anim(anim_idle)
	Events.emit_event(&"chase_ended", {})


## 一度退く。最寄りの暗がりへ逃げ、10 秒 idle してからまた追う。
func retreat() -> void:
	if is_retreating or not is_active:
		return
	is_retreating = true
	is_chasing = false
	_gen += 1
	_run_retreat(_gen)


## retreat のあと、手動でまた追わせる。
func resume() -> void:
	is_retreating = false
	_gen += 1
	start_chase()


## 天井を這う(廊下でのみ使う演出)。body の Y を天井高 - 0.9 に固定し、モデルを上下反転する。
func set_ceiling_mode(on: bool) -> void:
	if ceiling_mode == on:
		return
	ceiling_mode = on
	set_flying(on)
	if model:
		model.rotation_degrees.z = 180.0 if on else 0.0
		model.position.y = body_height if on else 0.0
	if on:
		global_position.y = ceiling_height - body_height


## 真エンド: 控室の息子のところへ行って連れて行く。
func go_to_and_take(target: Node3D) -> void:
	if target == null:
		return
	is_chasing = false
	is_retreating = false
	_gen += 1
	set_speed_override(chase_speed)
	await go_to(target.global_position)
	face(target)
	Audio.play_at(&"kasha_growl", global_position, 0.0, 0.9, 24.0)
	took_target.emit(target)


func set_eye_glow(f: float) -> void:
	NpcUtil.set_emission(model, "Eyes", maxf(f, 0.0), eye_color)


func distance_to_player() -> float:
	var p := Game.player
	return global_position.distance_to(p.global_position) if p else INF


# ============================================================ 毎フレーム

func _process(delta: float) -> void:
	super._process(delta)
	if not is_active:
		return
	_update_sight()
	_update_eyes()
	_update_crawl_sound(delta)
	if ceiling_mode:
		global_position.y = ceiling_height - body_height
	if is_chasing:
		_tick_chase(delta)


func _tick_chase(delta: float) -> void:
	var p := Game.player
	if p == null:
		return
	set_speed_override(chase_speed if player_sees_me else unseen_speed)
	_repath_t -= delta
	if _repath_t <= 0.0:
		_repath_t = 0.3
		retarget(p.global_position)
	if _caught_armed and distance_to_player() <= catch_distance:
		_catch()
	elif not _caught_armed and distance_to_player() > catch_rearm_distance:
		_caught_armed = true


func _catch() -> void:
	_caught_armed = false
	stop()
	set_scripted(true)
	_free_anim = true
	play_anim(anim_idle)
	face_now(Game.player)
	Audio.play_at(&"kasha_screech", global_position, 0.0, 1.0, 30.0)
	caught.emit()
	await get_tree().create_timer(catch_freeze).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	set_scripted(false)
	_free_anim = false


## プレイヤーの視界(FOV 100°・遮蔽なし)に入っているか。
func _update_sight() -> void:
	var was := player_sees_me
	player_sees_me = _player_sees_me()
	if player_sees_me and not was:
		Audio.play_at(&"kasha_growl", global_position, 0.0, 1.0, 26.0)


func _player_sees_me() -> bool:
	var p := Game.player
	if p == null:
		return false
	var cam: Camera3D = null
	if p.has_method("get_camera"):
		cam = p.get_camera()
	var eye: Vector3 = cam.global_position if cam else p.global_position + Vector3(0, 1.6, 0)
	var to := head_position() - eye
	if to.length() > sight_range:
		return false
	if cam:
		var fwd := -cam.global_transform.basis.z
		if rad_to_deg(fwd.angle_to(to.normalized())) > sight_fov_deg * 0.5:
			return false
	return NpcUtil.clear_line(get_world_3d(), eye, head_position(), [get_rid(), p.get_rid()])


## 距離が近いほど目が強く光る。
func _update_eyes() -> void:
	var d := distance_to_player()
	if is_inf(d):
		return
	var f: float = clampf(remap(d, 14.0, 2.0, 1.0, 2.6), 1.0, 2.6)
	set_eye_glow(eye_energy * f)


func _update_crawl_sound(delta: float) -> void:
	_crawl_t -= delta
	if _crawl_t > 0.0:
		return
	if Vector2(velocity.x, velocity.z).length() < 0.25:
		_crawl_t = 0.4
		return
	_crawl_t = crawl_sound_interval
	Audio.play_at(&"kasha_crawl", global_position, 0.0, 1.0, 18.0)


# ============================================================ 退却

func _run_retreat(g: int) -> void:
	Audio.play_at(&"kasha_screech", global_position, 0.0, 1.0, 30.0)
	set_speed_override(retreat_speed)
	var spot: Vector3 = NpcUtil.DARK_SPOTS[0]
	var best := INF
	for s in NpcUtil.DARK_SPOTS:
		var d: float = global_position.distance_to(s)
		if d < best:
			best = d
			spot = s
	await go_to(spot)
	if not _alive(g):
		return
	_free_anim = true
	play_anim(anim_idle)
	await get_tree().create_timer(retreat_idle_seconds).timeout
	if not _alive(g):
		return
	_free_anim = false
	is_retreating = false
	start_chase()


func _alive(g: int) -> bool:
	return is_instance_valid(self) and is_inside_tree() and is_active and _gen == g
