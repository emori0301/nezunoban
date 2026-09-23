class_name NpcBase
extends CharacterBody3D
## NPC(社長/息子/孫娘)・猫・火車の共通の土台。
##
## 当たり判定: layer 4 (npc) / mask 1 (world)。正面は -Z(models_notes.md)。
## (キャラ 6 体は models の ea8bd75 で -Z 正面に統一済み。ずれたモデルが来たときだけ
##  model_yaw_offset_deg で見た目を回す。当たり判定とナビはノード本体のまま。)
##
## glb は子の Prop が読み、その中の AnimationPlayer で idle / walk を速度に応じて切り替える。
## walk はその場歩きなので、移動は NavigationAgent3D + move_and_slide() で自前で行う。
## 人物は idle / walk / sit / sit_floor / sleep の 5 種を持つ(sit_on_chair / sit_on_floor / lie_down)。
##
## ナビメッシュは扉を障害物にしていないので、**閉まった扉は自前で判定して止まる**。
## 人間(can_open_doors = true)は止まった扉を開けて進む。猫は開けられないので引き返す。
## 家具に引っかかったら横へ舵を切って回り込み、stuck_give_up 秒で諦めて arrived を出す
## (そのとき last_move_failed / last_move_blocked が true になる)。
##
## director からの使い方:
##     var gd := NpcInstaller.find(&"granddaughter") as NpcBase
##     gd.set_talkable(true)
##     gd.talked.connect(func(_p): ...)          # 話しかけられた
##     await gd.go_to(Vector3(12.0, 0.0, 0.5))   # 歩いて到着まで待つ
##     gd.face_player()
##     gd.sit_on_chair(Vector3(10.9, 0.0, 1.1), -90.0)   # パイプ椅子に座る
##     await gd.leave_via_genkan()               # 玄関から出て npc_left を出す

signal arrived                                   ## walk_to / go_to の到着
signal talked(player: Node3D)                    ## 話しかけられた(中身は director)
signal despawned
signal door_blocked(door_name: StringName)       ## 閉まった扉の前で止まった
## 移動が外から中断された(stop / set_active(false) / teleport_to)。
## await go_to() を返すため、このとき arrived も出る。
signal move_cancelled

@export_group("見た目")
@export var model_name: String = ""
@export var npc_id: StringName = &""             ## npc_left イベントなどで使う名前
@export var anim_idle: StringName = &"idle"
@export var anim_walk: StringName = &"walk"
@export var anim_sit: StringName = &"sit"            ## 椅子に座る
@export var anim_sit_floor: StringName = &"sit_floor" ## 座布団にあぐら
@export var anim_sleep: StringName = &"sleep"        ## 横になる
@export var loop_anims: Array[StringName] = [&"idle", &"walk", &"sit", &"sit_floor", &"sleep"]
## モデルの正面が -Z でないときの補正(度)。cat.glb だけ +Z が正面なので 180。
## 当たり判定とナビはノード本体のまま、見た目だけ回す。
@export var model_yaw_offset_deg: float = 0.0

@export_group("体")
@export var body_radius: float = 0.28
@export var body_height: float = 1.70
@export var head_height: float = 1.55
## 人物リグに head ボーンがあるとき、そこに Head を追従させる。
## 高さはレストポーズを測って head_height に合わせるので、この値は微調整ぶん。
@export var head_bone: StringName = &"head"
@export var head_bone_offset: float = 0.0
@export var gravity: float = 9.8

@export_group("移動")
@export var move_speed: float = 1.2              ## 歩速(m/s)
@export var agent_radius: float = 0.30
@export var arrive_distance: float = 0.45
@export var turn_speed: float = 7.0              ## rad/s
@export var accel: float = 9.0
@export var can_open_doors: bool = true
## 開けられない扉の前で待つ秒数。これを過ぎたら諦めて arrived を出す(0 で永久に待つ)。
@export var blocked_give_up: float = 6.0
## 家具などに引っかかって目標に近づけないまま粘る秒数。これを過ぎたら到着扱いにする。
@export var stuck_give_up: float = 9.0
@export var drunk: bool = false                  ## 歩行がわずかに蛇行する

@export_group("会話")
@export var talkable: bool = false
@export var talk_prompt: String = "話す"
@export var look_at_player_when_near: bool = true
@export var look_near_distance: float = 3.5

@export_group("起動")
@export var start_active: bool = true
## スポーン地点が家具で囲われているとき(社長は受付台の内側)、そこから出るための経由点。
## leave_via() が最初に通る。まだスポーン付近に居るときだけ使う。
@export var spawn_exit_route: Array[Vector3] = []

var model: Prop = null
var anim: AnimationPlayer = null
var agent: NavigationAgent3D = null
var head: Marker3D = null
var talk: NpcTalk = null

var is_active: bool = true
var is_moving: bool = false
## stand / sit / sit_floor / sleep。stand 以外の間は idle/walk の自動切り替えを止める。
var posture: StringName = &"stand"
## 直前の walk_to / go_to が「閉まった扉に阻まれて」終わったか。
var last_move_blocked: bool = false
## 直前の移動が詰まって打ち切られたか(家具に引っかかった等)。
var last_move_failed: bool = false
## 直前の移動が外から中断されたか(stop / set_active(false) / teleport_to)。
var last_move_cancelled: bool = false
var blocked_door_name: StringName = &""

var _shape: CollisionShape3D = null
var _target_yaw: float = 0.0
var _nav_target: Vector3 = Vector3.ZERO
var _move_t: float = 0.0
## 詰まったときに舵を切る角度(度)。順に試して抜け道を探す。
const NUDGE_ANGLES := [78.0, -78.0, 118.0, -118.0]
## stuck_give_up に対するこの割合で、経路上へ押し出す(何度か試す)。
const UNSTICK_AT := [0.35, 0.6, 0.85]

var _stuck_t: float = 0.0
var _blocked_t: float = 0.0
var _nudge_angle: float = 78.0
var _best_progress: float = INF
var _unstuck_count: int = 0
var _head_attach: BoneAttachment3D = null
var _repath_t2: float = 0.0
var _steer_cache: Vector3 = Vector3.INF
var _arrive_dist: float = 0.45
var _last_pos: Vector3 = Vector3.ZERO
var _cur_anim: StringName = &""
var _anim_speed: float = 1.0
var _scripted: bool = false                      ## tween が位置を握っている間は物理を止める
var _flying: bool = false                        ## 天井這い(重力と接地を無視)
var _blocked_door: StringName = &""
var _speed_override: float = -1.0
var _doors: Array[Door] = []
var _rng := RandomNumberGenerator.new()
## デバッグ用: 直近の _steer の結果と理由
var last_desired: Vector3 = Vector3.ZERO
var last_steer_reason: String = ""



func _ready() -> void:
	add_to_group(&"npc")
	collision_layer = 8          # layer 4 = npc
	collision_mask = 1           # layer 1 = world
	_rng.randomize()
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_max_angle = deg_to_rad(50.0)
	_build_shape()
	_build_model()
	_build_agent()
	_build_head()
	_build_talk()
	_target_yaw = rotation.y
	_last_pos = global_position
	set_active(start_active)
	play_anim(anim_idle)


# ============================================================ 組み立て

func _build_shape() -> void:
	_shape = CollisionShape3D.new()
	_shape.name = "Body"
	var cap := CapsuleShape3D.new()
	cap.radius = body_radius
	cap.height = maxf(body_height, body_radius * 2.0 + 0.02)
	_shape.shape = cap
	_shape.position = Vector3(0, cap.height * 0.5, 0)
	add_child(_shape)


func _build_model() -> void:
	model = Prop.new()
	model.name = "Model"
	model.add_collision = false
	model.cast_shadow = true
	model.placeholder_size = Vector3(body_radius * 2.0, body_height, body_radius * 2.0)
	model.placeholder_color = Color(0.36, 0.32, 0.30)
	model.model_name = model_name
	model.rotation_degrees.y = model_yaw_offset_deg
	add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
		anim.playback_default_blend_time = 0.15
		NpcUtil.force_loop(anim, loop_anims)
	elif model_name != "":
		push_warning("NpcBase: %s に AnimationPlayer が無い" % model_name)


func _build_agent() -> void:
	agent = NavigationAgent3D.new()
	agent.name = "Agent"
	agent.radius = agent_radius
	agent.height = body_height
	# 経路の後処理は既定(CORRIDORFUNNEL)のまま。EDGECENTERED は戸口の真ん中を通るが、
	# 外周のような広いポリゴンでは経由点が大きく脇へ飛んで遠回りになる(実測で打ち切り 11 件)。
	# 角で壁を突っ切る問題は _steer() 側で「経由点との間に壁があれば引き直す」で対処する。
	agent.path_desired_distance = 0.25
	agent.target_desired_distance = 0.25
	agent.path_max_distance = 3.0
	agent.avoidance_enabled = false
	agent.debug_enabled = false
	add_child(agent)


func _build_head() -> void:
	head = Marker3D.new()
	head.name = "Head"
	# 人物リグ(MPFB2)には head ボーンがあるので、そこに追従させる。
	# 座る/寝るアニメでも頭の位置が正しく出るので、director の look_at_point が合う。
	var skel := _find_skeleton()
	var bone := skel.find_bone(head_bone) if (skel != null and head_bone != &"") else -1
	if bone >= 0:
		_head_attach = BoneAttachment3D.new()
		_head_attach.name = "HeadBone"
		_head_attach.bone_name = String(head_bone)
		skel.add_child(_head_attach)
		# 素体によって head ボーンの高さが違う(頭頂寄り / 首寄り)ので、
		# レストポーズを測って「立ったときに head_height に来る」ぶんだけ上下させる。
		var rest_y: float = (skel.global_transform * skel.get_bone_global_pose(bone)).origin.y \
			- global_position.y
		head.position = Vector3(0, head_height - rest_y + head_bone_offset, 0)
		_head_attach.add_child(head)
		return
	head.position = Vector3(0, head_height, 0)
	add_child(head)


func _find_skeleton() -> Skeleton3D:
	if model == null:
		return null
	var list := model.find_children("*", "Skeleton3D", true, false)
	return list[0] as Skeleton3D if not list.is_empty() else null


func _build_talk() -> void:
	talk = NpcTalk.new()
	talk.name = "Talk"
	talk.prompt = talk_prompt
	talk.radius = maxf(body_radius + 0.35, 0.5)
	talk.height = maxf(body_height, 0.9)
	talk.talk_requested.connect(_on_talk_requested)
	add_child(talk)
	set_talkable(talkable)


func _on_talk_requested(player: Node3D) -> void:
	if look_at_player_when_near:
		face_player()
	talked.emit(player)


# ============================================================ 公開 API

## 目的地まで歩き出す。到着は `arrived`。
##     npc.walk_to(p)          … 撃ちっぱなし
##     await npc.walk_to(p)    … 返り値の Signal をそのまま待てる
## tolerance を指定すると、その距離まで近づいたら到着扱いにする(狭い通路の経由点用)。
func walk_to(pos: Vector3, tolerance: float = -1.0) -> Signal:
	if not is_active:
		return arrived
	_arrive_dist = tolerance if tolerance > 0.0 else arrive_distance
	agent.target_desired_distance = clampf(_arrive_dist - 0.15, 0.15, 0.4)
	_nav_target = NpcUtil.snap(get_world_3d(), pos)
	agent.target_position = _nav_target
	is_moving = true
	_move_t = 0.0
	_stuck_t = 0.0
	_blocked_t = 0.0
	_blocked_door = &""
	last_move_blocked = false
	last_move_failed = false
	last_move_cancelled = false
	_nudge_angle = NUDGE_ANGLES[0]
	_best_progress = INF
	_unstuck_count = 0
	_reset_steer_cache()
	return arrived


## 追跡中に目標だけ差し替える。walk_to と違って詰まり判定をリセットしないので、
## 毎フレーム呼んでも「家具に引っかかったまま」を検知できる。
func retarget(pos: Vector3) -> void:
	if not is_active:
		return
	_nav_target = NpcUtil.snap(get_world_3d(), pos)
	agent.target_position = _nav_target
	_best_progress = _flat_distance(global_position, _nav_target)
	_reset_steer_cache()
	if not is_moving:
		is_moving = true
		_move_t = 0.0
		_blocked_door = &""
		last_move_blocked = false
		last_move_failed = false
		last_move_cancelled = false


## 到着まで待つコルーチン。`await npc.go_to(pos)`
## 起動 1 フレーム目に呼ばれても NavigationServer がエラーを出さないよう、
## マップが同期されるまで待ってから経路を引く。
func go_to(pos: Vector3, tolerance: float = -1.0) -> void:
	if not is_active:
		return
	await wait_for_nav()
	if not is_active or not is_inside_tree():
		return
	walk_to(pos, tolerance)
	if not is_moving:
		return
	await arrived


## NavigationServer のマップが同期されるまで待つ(最大 60 物理フレーム)。
func wait_for_nav() -> void:
	var guard := 0
	while not NpcUtil.is_nav_ready(get_world_3d()) and guard < 60:
		guard += 1
		await get_tree().physics_frame
		if not is_inside_tree():
			return


## その場で止まる。移動中だったら待っている go_to() を返すために arrived も出す。
func stop() -> void:
	_blocked_door = &""
	if is_moving:
		_cancel_move()
	else:
		velocity.x = 0.0
		velocity.z = 0.0


## 移動の外からの中断。await go_to() が永久に返らなくなるのを防ぐ。
func _cancel_move() -> void:
	if not is_moving:
		return
	is_moving = false
	velocity.x = 0.0
	velocity.z = 0.0
	last_move_cancelled = true
	move_cancelled.emit()
	arrived.emit()


## Node3D か Vector3 の方を向く(ゆっくり回る)。
func face(target: Variant) -> void:
	var p: Vector3 = Vector3.ZERO
	if target is Node3D:
		p = (target as Node3D).global_position
	elif target is Vector3:
		p = target
	else:
		return
	var to := p - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_target_yaw = atan2(-to.x, -to.z)     # 正面は -Z


## 今すぐその向きにする(tween しない)。
func face_now(target: Variant) -> void:
	face(target)
	rotation.y = _target_yaw


func face_player() -> void:
	if Game.player:
		face(Game.player)


func set_talkable(on: bool) -> void:
	talkable = on
	if talk:
		talk.enabled = on and is_active
		talk.monitorable = on and is_active
		talk.prompt = talk_prompt


## 表示・処理・当たり判定をまとめて入/切。
func set_active(on: bool) -> void:
	is_active = on
	visible = on
	set_process(on)
	set_physics_process(on)
	if _shape:
		_shape.disabled = not on
	if talk:
		talk.enabled = on and talkable
		talk.monitorable = on and talkable
	if not on:
		_cancel_move()
		velocity = Vector3.ZERO
	else:
		NpcUtil.set_transparency(model, 0.0)


## 消える。fade = true なら 0.6 秒かけて透過してから非表示にする。
## ノード自体は残すので、director があとから set_active(true) で戻せる。
func despawn(fade: bool = true) -> void:
	stop()
	set_talkable(false)
	if fade and model:
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			NpcUtil.set_transparency(model, v), 0.0, 1.0, 0.6)
		await tw.finished
		if not is_instance_valid(self) or not is_inside_tree():
			return
	set_active(false)
	despawned.emit()


## アニメを指定して再生する。無ければ何もしない。
func play_anim(name: StringName, speed: float = 1.0) -> void:
	if anim == null or name == &"":
		return
	if not anim.has_animation(String(name)):
		return
	_cur_anim = name
	_anim_speed = speed
	anim.speed_scale = speed
	if anim.current_animation != String(name):
		anim.play(String(name))


func current_anim() -> StringName:
	return _cur_anim


## 移動速度を一時的に上書きする(猫が走る、火車が視界外で遅くなる)。負で解除。
func set_speed_override(v: float) -> void:
	_speed_override = v


func current_speed() -> float:
	return _speed_override if _speed_override >= 0.0 else move_speed


## 位置を直接動かす(演出・デバッグ)。
## 既定でナビメッシュ上の最寄り点へ寄せる。寄せないと、祭壇の前などナビの外に降りた NPC が
## 以後どこへも歩けなくなる(review_1.md M4)。高さは呼び出し側の値を保つ。
func teleport_to(pos: Vector3, yaw_deg: float = NAN, snap_to_nav: bool = true) -> void:
	if snap_to_nav:
		var p := NpcUtil.snap(get_world_3d(), pos)
		global_position = Vector3(p.x, pos.y, p.z)
	else:
		global_position = pos
	if not is_nan(yaw_deg):
		rotation.y = deg_to_rad(yaw_deg)
		_target_yaw = rotation.y
	_cancel_move()
	velocity = Vector3.ZERO
	if agent:
		agent.target_position = global_position


func head_position() -> Vector3:
	return head.global_position if head else global_position + Vector3(0, head_height, 0)


## 当たり判定のカプセルを差し替える(寝転がる・這うなど姿勢が変わるとき)。
func set_body_size(radius: float, height: float) -> void:
	if _shape == null:
		return
	var cap := _shape.shape as CapsuleShape3D
	if cap == null:
		return
	cap.radius = radius
	cap.height = maxf(height, radius * 2.0 + 0.02)
	_shape.position = Vector3(0, cap.height * 0.5, 0)


## Head マーカーの位置を動かす(director の look_at_point 用)。
## head ボーンに追従させているときは、アニメが頭を動かすので何もしない。
func set_head_offset(offset: Vector3) -> void:
	if head and _head_attach == null:
		head.position = offset


# ------------------------------------------------------------ 姿勢
# 人物モデルには idle / walk / sit / sit_floor / sleep の 5 種が入っている。
# sit は椅子の高さ、sit_floor と sleep は座布団(厚み 0.065m)の上に置く前提。

## パイプ椅子・事務椅子に座る。pos / yaw を省くと今の位置と向きのまま。
func sit_on_chair(pos: Vector3 = Vector3.INF, yaw_deg: float = NAN) -> void:
	_set_posture(&"sit", anim_sit, pos, yaw_deg, 1.30, 1.15)


## 座布団にあぐらで座る(息子が控室で飲んでいる場面)。
func sit_on_floor(pos: Vector3 = Vector3.INF, yaw_deg: float = NAN) -> void:
	_set_posture(&"sit_floor", anim_sit_floor, pos, yaw_deg, 1.00, 0.85)


## 横になる。
func lie_down(pos: Vector3 = Vector3.INF, yaw_deg: float = NAN, speed: float = 1.0) -> void:
	_set_posture(&"sleep", anim_sleep, pos, yaw_deg, 0.60, 0.35, speed)


## 立ち上がる。
func stand_up() -> void:
	posture = &"stand"
	set_body_size(body_radius, body_height)
	set_head_offset(Vector3(0, head_height, 0))
	play_anim(anim_idle, 1.0)


func _set_posture(name: StringName, anim_name: StringName, pos: Vector3, yaw_deg: float,
		shape_height: float, head_y: float, speed: float = 1.0) -> void:
	stop()
	if pos != Vector3.INF:
		global_position = Vector3(pos.x, global_position.y, pos.z)
	if not is_nan(yaw_deg):
		rotation.y = deg_to_rad(yaw_deg)
		_target_yaw = rotation.y
	posture = name
	set_body_size(minf(body_radius, 0.30), shape_height)
	set_head_offset(Vector3(0, head_y, 0))
	play_anim(anim_name, speed)


# ------------------------------------------------------------ 出入り

## 開口部から出ていく共通処理。扉なら開けて通り、通ったら閉める。
func leave_via(door_name: StringName = &"Door_Genkan", emit_left: bool = true) -> void:
	if not NpcUtil.OPENINGS.has(door_name):
		push_warning("NpcBase.leave_via: 知らない開口部 %s" % door_name)
		await despawn(true)
		return
	var o: Dictionary = NpcUtil.OPENINGS[door_name]
	var door := NpcUtil.opening_node(door_name)
	await walk_spawn_exit_route()
	await go_to(o["inside"])
	face(o["outside"])
	if door:
		if bool(door.get(&"locked")):
			door.call(&"set_locked", false)
		door.call(&"open")
		await get_tree().create_timer(0.8, false).timeout
	await go_to(o["outside"])
	if door and bool(door.get(&"is_open")):
		door.call(&"close")
	await despawn(true)
	if emit_left:
		Events.emit_event(&"npc_left", {"name": npc_id})


func leave_via_genkan() -> void:
	await leave_via(&"Door_Genkan")


## 経由点を順に歩く。director が「まずここを通ってから」と指示するのにも使える。
func walk_route(points: Array, tolerance: float = -1.0) -> void:
	for p in points:
		if not is_active:
			return
		await go_to(p, tolerance)


## spawn_exit_route を、まだスポーン付近に居るときだけ歩く。
## 家具の隙間を抜けるので、到着判定は狭くする。
func walk_spawn_exit_route() -> void:
	if spawn_exit_route.is_empty():
		return
	if _flat_distance(global_position, spawn_exit_route[0]) > 2.5:
		return
	await walk_route(spawn_exit_route, 0.20)


## 玄関の外から入ってきて to_pos まで歩く。
func enter_from_genkan(to_pos: Vector3) -> void:
	var o: Dictionary = NpcUtil.OPENINGS[&"Door_Genkan"]
	teleport_to(o["outside"])
	set_active(true)
	face_now(o["inside"])
	play_anim(anim_idle)
	var door := NpcUtil.opening_node(&"Door_Genkan")
	if door:
		if bool(door.get(&"locked")):
			door.call(&"set_locked", false)
		door.call(&"open")
		await get_tree().create_timer(0.8, false).timeout
	await go_to(o["inside"])
	if door and bool(door.get(&"is_open")):
		door.call(&"close")
	await go_to(to_pos)


# ============================================================ 毎フレーム

func _physics_process(delta: float) -> void:
	if not is_active or _scripted:
		return

	if _flying:
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	var desired := Vector3.ZERO
	if is_moving:
		_move_t += delta
		desired = _steer(delta)
		last_desired = desired
	elif look_at_player_when_near and Game.player:
		var d := global_position.distance_to(Game.player.global_position)
		if d < look_near_distance:
			face(Game.player)

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat = flat.move_toward(desired, accel * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	rotation.y = rotate_toward(rotation.y, _target_yaw, turn_speed * delta)
	move_and_slide()
	_check_stuck(delta)


## 次の経路点へ向かう速度を返す。閉まった扉の前では止まる。
func _steer(delta: float) -> Vector3:
	if _move_t > 0.15 and (agent.is_navigation_finished() or _flat_distance(global_position, _nav_target) < _arrive_dist):
		last_steer_reason = "arrived"
		_finish_move()
		return Vector3.ZERO
	var next := _steer_point(delta)
	var to := next - global_position
	to.y = 0.0
	if to.length_squared() < 0.0004:
		last_steer_reason = "next==self"
		return Vector3.ZERO
	var dir := to.normalized()
	if drunk:
		dir = dir.rotated(Vector3.UP, sin(_move_t * 1.9) * 0.34)
	# 家具や壁に引っかかったら回り込む。当たっている面が分かるならその面に沿って滑り、
	# 分からないときだけ固定角で舵を切る。固定角だけだと壁へ押し付け続けることがある。
	if _stuck_t > 0.5:
		var wall := _touching_wall_normal()
		# その壁が本当に進路を塞いでいるときだけ滑る。塞いでいないのに滑ると、
		# 行きたい向きとは無関係な方へ舵を切ってしまう。
		if wall != Vector3.ZERO and wall.dot(dir) < -0.1:
			var t1 := Vector3(-wall.z, 0.0, wall.x).normalized()
			var t2 := -t1
			# 滑る向きは「目標に近づくほう」で選ぶ。dir で選ぶと壁と直交するときに
			# どちらを選んでも同点になり、目標と逆へ滑ることがある。
			var to_goal := Vector3(_nav_target.x - global_position.x, 0.0,
				_nav_target.z - global_position.z)
			if to_goal.length_squared() < 0.0001:
				to_goal = dir
			var along: Vector3 = t1 if t1.dot(to_goal) > t2.dot(to_goal) else t2
			# 壁から少し離れる成分を足して、角に吸い付かないようにする
			dir = (along + wall * 0.25).normalized()
		else:
			dir = dir.rotated(Vector3.UP, deg_to_rad(_nudge_angle))
	var speed := current_speed()
	var door := _closed_door_between(global_position, global_position + dir * (speed * delta + 0.45))
	if door != null:
		last_steer_reason = "door:" + String(door.name)
		return _handle_closed_door(door, delta)
	_blocked_door = &""
	_target_yaw = atan2(-dir.x, -dir.z)
	last_steer_reason = "move"
	return dir * speed


## 閉まった扉の前。開けられるなら開ける。開けられないなら少し待って諦める。
func _handle_closed_door(door: Door, delta: float) -> Vector3:
	if _blocked_door != door.name:
		_blocked_door = door.name
		blocked_door_name = door.name
		_blocked_t = 0.0
		face(door)
		door_blocked.emit(door.name)
	if can_open_doors and not door.locked:
		door.open()
		return Vector3.ZERO
	_blocked_t += delta
	if blocked_give_up > 0.0 and _blocked_t >= blocked_give_up:
		last_move_blocked = true
		_blocked_door = &""
		_finish_move()
	return Vector3.ZERO


func _finish_move() -> void:
	is_moving = false
	velocity.x = 0.0
	velocity.z = 0.0
	_settle_on_nav()
	arrived.emit()


## 「目標に近づけているか」で詰まりを測る。壁際で左右に揺れているだけの状態も詰まり扱いにする。
func _check_stuck(delta: float) -> void:
	if not is_moving or _blocked_door != &"":
		_last_pos = global_position
		return
	var d := _flat_distance(global_position, _nav_target)
	if d < _best_progress - 0.05:
		_best_progress = d
		_stuck_t = 0.0
		_last_pos = global_position
		return
	_stuck_t += delta
	# 一度舵を切ったら 3 秒は同じ向きで粘る(受付台のような長い家具を端まで伝うため)
	_nudge_angle = NUDGE_ANGLES[int(_stuck_t / 3.0) % NUDGE_ANGLES.size()]
	if _stuck_t > 2.4 and _stuck_t < 2.4 + delta * 1.5:
		agent.target_position = NpcUtil.snap(get_world_3d(), _nav_target)
	elif _unstuck_count < UNSTICK_AT.size() and _stuck_t > stuck_give_up * UNSTICK_AT[_unstuck_count]:
		_unstuck_count += 1
		_try_unstick()
	elif _stuck_t > stuck_give_up:
		if Game.debug:
			var reachable := agent.is_target_reachable() if agent else false
			var plen := NpcUtil.path_length(get_world_3d(), global_position, _nav_target, 1.2)
			print("[npc] %s が %v へ到達できないので打ち切り(残り %.2fm) pos=%v reason=%s next=%v nav_ready=%s reachable=%s path=%s" % [
				name, _nav_target, d, global_position, last_steer_reason,
				agent.get_next_path_position() if agent else Vector3.ZERO,
				NpcUtil.is_nav_ready(get_world_3d()), reachable,
				"INF" if is_inf(plen) else "%.1fm" % plen])
		_stuck_t = 0.0
		last_move_failed = true
		_finish_move()


## 次に向かう点。経路から外れて「経由点との間に壁がある」状態になったら、
## いまの位置から経路を引き直してその 1 点目を返す。
## (funnel 経路は角に吸い付くので、経路から外れた位置から次の経由点へ直進すると
##  戸口の脇の壁を突っ切ってしまう)
## 目標が変わったら、次に向かう点のキャッシュを捨てる。
## 残したままだと 0.25 秒のあいだ古い目標へ向かって歩く。
func _reset_steer_cache() -> void:
	_steer_cache = Vector3.INF
	_repath_t2 = 0.0


func _steer_point(delta: float) -> Vector3:
	var next := agent.get_next_path_position()
	_repath_t2 -= delta
	if _repath_t2 > 0.0:
		return _steer_cache if _steer_cache != Vector3.INF else next
	_repath_t2 = 0.25
	_steer_cache = Vector3.INF
	if not _wall_between(global_position, next):
		return next
	var world := get_world_3d()
	if world == null or not NpcUtil.is_nav_ready(world):
		return next
	var p := NavigationServer3D.map_get_path(world.navigation_map, global_position, _nav_target, true)
	if p.size() >= 2:
		_steer_cache = p[1]
		return p[1]
	return next


## a → b の間に world(layer 1)の壁があるか。腰の高さで見る。
func _wall_between(a: Vector3, b: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var up := Vector3(0, minf(body_height * 0.45, 0.6), 0)
	var q := PhysicsRayQueryParameters3D.create(a + up, Vector3(b.x, a.y, b.z) + up, 1)
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	return not world.direct_space_state.intersect_ray(q).is_empty()


## いま当たっている壁(垂直面)の法線。無ければ Vector3.ZERO。
func _touching_wall_normal() -> Vector3:
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if absf(n.y) < 0.5:
			return Vector3(n.x, 0.0, n.z).normalized()
	return Vector3.ZERO


## 家具の隙間に嵌まって動けないとき、経路上の次の点へ小さくワープして抜け出す。
## 式場の椅子は 0.54m 間隔で並んでいて、NPC(直径 0.52m)が入ると自力では出られない。
## ワープ先はナビメッシュ上の点なので、家具の中には出ない。
func _try_unstick() -> void:
	if agent == null:
		return
	var world := get_world_3d()
	# 経路上で 2.5m 以内の「一番先の点」へ出す。戸口では次の経由点が枠の真ん中に乗るので、
	# そこへ出すだけだと枠に挟まったままになる。その先まで抜ける。
	var np := Vector3.INF
	if world != null and NpcUtil.is_nav_ready(world):
		var path := NavigationServer3D.map_get_path(world.navigation_map,
			global_position, _nav_target, true)
		for i in range(1, path.size()):
			var q := path[i]
			q.y = global_position.y
			if _flat_distance(q, global_position) > 2.5:
				break
			np = q
	if np == Vector3.INF:
		np = NpcUtil.snap(world, agent.get_next_path_position())
		np.y = global_position.y
	var d := _flat_distance(np, global_position)
	if d < 0.05 or d > 2.5:
		np = NpcUtil.snap(world, global_position)
		np.y = global_position.y
		if _flat_distance(np, global_position) < 0.05:
			return
	if Game.debug:
		print("[npc] %s を %v から %v へ押し出した(家具に嵌まっていた)" % [name, global_position, np])
	global_position = np


## 到着したところが家具の中(ナビメッシュの外)なら、ナビ上へ寄せておく。
## そうしないと次に歩かせたときに経路が引けない。
func _settle_on_nav() -> void:
	var p := NpcUtil.snap(get_world_3d(), global_position)
	if _flat_distance(p, global_position) > 0.4:
		if Game.debug:
			print("[npc] %s の到着点がナビ外なので %v へ寄せた" % [name, p])
		global_position = Vector3(p.x, global_position.y, p.z)


## a → b の線分が「閉まっている扉」の開口面を横切るなら、その扉を返す。
func _closed_door_between(a: Vector3, b: Vector3) -> Door:
	for d in _cached_doors():
		if d.is_open:
			continue
		var inv := d.global_transform.affine_inverse()
		var l0 := inv * a
		var l1 := inv * b
		if l0.z * l1.z > 0.0:
			continue
		if is_equal_approx(l0.z, l1.z):
			continue
		var t := l0.z / (l0.z - l1.z)
		var x := lerpf(l0.x, l1.x, t)
		var y := lerpf(l0.y, l1.y, t)
		if absf(x) <= d.door_width * 0.5 + 0.25 and y >= -0.4 and y <= d.door_height:
			return d
	return null


## Building.all_doors() は毎回 duplicate を返すので、扉の参照だけ持っておく。
func _cached_doors() -> Array[Door]:
	if not _doors.is_empty() and is_instance_valid(_doors[0]):
		return _doors
	_doors.clear()
	var bld := NpcUtil.building()
	if bld == null:
		return _doors
	for v in bld.all_doors().values():
		var d := v as Door
		if d != null:
			_doors.append(d)
	return _doors


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _process(_delta: float) -> void:
	if not is_active or anim == null:
		return
	_update_locomotion_anim()


## 速度で idle / walk を自動で切り替える。派生が別の姿勢(sit / crawl)を出している間は触らない。
func _update_locomotion_anim() -> void:
	if not _locomotion_anim_enabled():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.15:
		var s: float = clampf(speed / maxf(move_speed, 0.1), 0.55, 2.2)
		if _cur_anim != anim_walk:
			play_anim(anim_walk, s)
		else:
			_anim_speed = s
			anim.speed_scale = s
	elif _cur_anim != anim_idle:
		play_anim(anim_idle, 1.0)


## 派生クラスが「今は自動切り替えをしないでほしい」ときに false を返す。
func _locomotion_anim_enabled() -> bool:
	return posture == &"stand"


# ------------------------------------------------------------ 演出用

## tween などで位置を直接動かす間、物理更新を止める。
func set_scripted(on: bool) -> void:
	_scripted = on
	if on:
		is_moving = false
		velocity = Vector3.ZERO


func set_flying(on: bool) -> void:
	_flying = on


func is_scripted() -> bool:
	return _scripted


func is_flying() -> bool:
	return _flying
