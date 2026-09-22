class_name Cat
extends NpcBase
## 黒猫。外周をうろつき、開いた開口部から侵入して棺を目指す。
## 棺の上に乗ると systems 側の CatZone が拾って `cat_crossed_coffin`(異変度 +3)が出る。
##
## 状態:
##   OUTSIDE_IDLE  スポーン付近で座る/寝そべる。20〜40 秒おきに鳴く。窓越しにプレイヤーを見る
##   APPROACH      set_target_entry() の開口部の外側へ歩く。開いていれば ENTERING、閉まっていれば引っ掻く
##   ENTERING      開口部をまたいで中へ。`cat_entered`
##   INSIDE_WANDER 廊下をうろつく
##   TO_COFFIN     棺へ向かう → ON_COFFIN で蓋の上へ飛び乗って座る
##   SHOOED        「追い払う」で最寄りの開いた開口部へ走って出る。`cat_shooed`
##   HIDING        出口が全部閉まっていたら室内の隅に隠れ、20 秒後にまた棺を目指す
##
## director からの使い方:
##     var c := NpcInstaller.find(&"cat", 0) as Cat
##     c.activate()                              # 外に出す
##     c.set_target_entry(&"Door_Backyard")      # 勝手口へ寄せる(開いていれば入る)
##     Events.on(&"cat_entered", func(_d): ...)
##     c.sit_at(Vector3(-19.0, 0, -5.0), Game.player)   # 駐車場でこちらを見ている
##     c.flee()                                  # 演出で外へ逃がす

enum State { OUTSIDE_IDLE, APPROACH, ENTERING, INSIDE_WANDER, TO_COFFIN, ON_COFFIN, SHOOED, HIDING, POSED }

@export_group("猫")
@export var run_speed: float = 3.0
@export var eye_energy: float = 3.2
@export var eye_color: Color = Color(1.0, 0.92, 0.35)
@export var meow_interval: Vector2 = Vector2(20.0, 40.0)
@export var see_player_distance: float = 16.0
@export var hide_seconds: float = 20.0

var state: State = State.OUTSIDE_IDLE
var is_inside: bool = false
var target_entry: StringName = &"Door_Backyard"

var _gen: int = 0
var _free_anim: bool = false      ## true の間は idle/walk の自動切り替えをしない
var _shoo_hiss: bool = false
var _cross_marker: Area3D = null
var _on_perch: bool = false       ## 棺の蓋の上に乗っているか


## 既定値は _init で入れる(.tscn の @export がこの後に適用されるので上書きできる)。
func _init() -> void:
	model_name = "cat"
	npc_id = &"cat"
	move_speed = 1.6
	agent_radius = 0.20
	body_radius = 0.13
	body_height = 0.36
	head_height = 0.30
	arrive_distance = 0.40
	can_open_doors = false
	talk_prompt = "追い払う"
	look_at_player_when_near = false
	start_active = false
	loop_anims = [&"idle", &"walk", &"sit"]
	anim_sit = &"sit"
	# cat.glb は頭が +Z 側。ほかのキャラ(-Z 正面)と揃えるため見た目だけ 180 度回す。
	model_yaw_offset_deg = 180.0


func _ready() -> void:
	super._ready()
	add_to_group(&"cat")
	_build_cross_marker()
	set_eye_glow(eye_energy)
	talked.connect(_on_talked)


## 棺の CatZone(mask 12)に確実に拾わせるための当たり。猫の体の中心に置く。
func _build_cross_marker() -> void:
	_cross_marker = Area3D.new()
	_cross_marker.name = "CrossMarker"
	_cross_marker.collision_layer = 8     # layer 4 = npc
	_cross_marker.collision_mask = 0
	_cross_marker.monitoring = false
	_cross_marker.monitorable = true
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.20
	cs.shape = sp
	cs.position = Vector3(0, 0.22, 0)
	_cross_marker.add_child(cs)
	add_child(_cross_marker)


func _locomotion_anim_enabled() -> bool:
	return not _free_anim and super._locomotion_anim_enabled()


func _process(delta: float) -> void:
	super._process(delta)


# ============================================================ 公開 API

## 外に出して動き始める。
func activate() -> void:
	set_active(true)
	is_inside = false
	set_talkable(false)
	set_speed_override(-1.0)
	_set_state(State.OUTSIDE_IDLE)


## 指定の開口部の外側へ寄る。開いていれば入る。
func set_target_entry(opening: StringName) -> void:
	if not NpcUtil.OPENINGS.has(opening):
		push_warning("Cat.set_target_entry: 知らない開口部 %s" % opening)
		return
	target_entry = opening
	if not is_active:
		set_active(true)
	_set_state(State.APPROACH)


## デバッグ/演出用の瞬間侵入。開いているかを問わず中に居る状態にする。
func go_inside_now(opening: StringName = &"") -> void:
	var o: StringName = opening if opening != &"" else target_entry
	if not NpcUtil.OPENINGS.has(o):
		o = &"Door_Backyard"
	target_entry = o
	set_active(true)
	teleport_to(NpcUtil.snap(get_world_3d(), NpcUtil.OPENINGS[o]["inside"]))
	is_inside = true
	set_talkable(true)
	Events.emit_event(&"cat_entered", {"entry": o, "instant": true})
	_set_state(State.INSIDE_WANDER)


## 外へ逃げる(プレイヤーに追い払われたわけではない演出用)。
func flee() -> void:
	_shoo_hiss = false
	_set_state(State.SHOOED)


## プレイヤーに追い払われた。
func shoo() -> void:
	_shoo_hiss = true
	_set_state(State.SHOOED)


## 決めた場所に座らせる(自販機の前に並ぶ、駐車場でこちらを見ている)。
## face_target は Node3D でも Vector3 でもよい。
func sit_at(pos: Vector3, face_target: Variant = null) -> void:
	set_active(true)
	_set_state(State.POSED)
	teleport_to(NpcUtil.snap(get_world_3d(), pos))
	if face_target != null:
		face_now(face_target)
	_free_anim = true
	play_anim(anim_sit)


## 目の発光の強さ。異変度が上がったら director が上げる。
func set_eye_glow(f: float) -> void:
	NpcUtil.set_emission(model, "Eyes", maxf(f, 0.0), eye_color)


func meow() -> void:
	Audio.play_at(StringName("cat_meow_%d" % _rng.randi_range(1, 3)),
		global_position + Vector3(0, 0.25, 0), 0.0, _rng.randf_range(0.94, 1.06), 26.0)


func purr() -> void:
	Audio.play_at(&"cat_purr", global_position + Vector3(0, 0.25, 0), 0.0, 1.0, 8.0)


func state_name() -> String:
	return State.keys()[state]


# ============================================================ 状態遷移

func _set_state(s: State) -> void:
	state = s
	_gen += 1
	_free_anim = false
	set_flying(false)
	if Game.debug:
		print("[cat] %s -> %s" % [name, state_name()])
	_run_state(s, _gen)


func _alive(g: int) -> bool:
	return is_instance_valid(self) and is_inside_tree() and is_active and _gen == g


func _run_state(s: State, g: int) -> void:
	# 棺の上から別の行動に移るときは、まず床へ飛び降りる。
	# 蓋のトライメッシュにカプセルがめり込んだままだと move_and_slide が動かなくなる。
	if _on_perch and s != State.ON_COFFIN:
		_on_perch = false
		await _hop_down(g)
		if not _alive(g):
			return
	match s:
		State.OUTSIDE_IDLE:
			await _state_outside_idle(g)
		State.APPROACH:
			await _state_approach(g)
		State.ENTERING:
			await _state_entering(g)
		State.INSIDE_WANDER:
			await _state_inside_wander(g)
		State.TO_COFFIN:
			await _state_to_coffin(g)
		State.ON_COFFIN:
			await _state_on_coffin(g)
		State.SHOOED:
			await _state_shooed(g)
		State.HIDING:
			await _state_hiding(g)
		State.POSED:
			pass


func _state_outside_idle(g: int) -> void:
	stop()
	set_speed_override(-1.0)
	set_talkable(false)
	_free_anim = true
	play_anim(anim_sit if _rng.randf() < 0.6 else anim_idle)
	while _alive(g):
		var wait := _rng.randf_range(meow_interval.x, meow_interval.y)
		var t := 0.0
		while t < wait and _alive(g):
			await get_tree().create_timer(0.3).timeout
			t += 0.3
			_watch_player()
		if not _alive(g):
			return
		meow()


func _state_approach(g: int) -> void:
	set_talkable(false)
	set_speed_override(-1.0)
	var o: Dictionary = NpcUtil.OPENINGS[target_entry]
	await go_to(o["outside"])
	if not _alive(g):
		return
	face(NpcUtil.opening_center(target_entry))
	await get_tree().create_timer(0.5).timeout
	if not _alive(g):
		return
	if NpcUtil.is_opening_open(target_entry):
		_set_state(State.ENTERING)
		return

	# 閉まっている: 3 回引っ掻いて、窓を叩いて、しばらくしたら諦める
	_free_anim = true
	play_anim(anim_idle)
	for i in 3:
		if not _alive(g):
			return
		if NpcUtil.is_opening_open(target_entry):
			_set_state(State.ENTERING)
			return
		Audio.play_at(StringName("cat_scratch_%d" % (i + 1)),
			NpcUtil.opening_center(target_entry), 0.0, _rng.randf_range(0.95, 1.05), 22.0)
		await get_tree().create_timer(1.6).timeout
	if not _alive(g):
		return
	Audio.play_at(&"window_tap", NpcUtil.opening_center(target_entry), 0.0, 1.0, 22.0)
	await get_tree().create_timer(3.0).timeout
	if not _alive(g):
		return
	if NpcUtil.is_opening_open(target_entry):
		_set_state(State.ENTERING)
	else:
		_set_state(State.OUTSIDE_IDLE)


func _state_entering(g: int) -> void:
	var o: Dictionary = NpcUtil.OPENINGS[target_entry]
	await _traverse(o["inside"], float(o["sill"]))
	if not _alive(g):
		return
	is_inside = true
	set_talkable(true)
	Events.emit_event(&"cat_entered", {"entry": target_entry})
	_set_state(State.INSIDE_WANDER)


func _state_inside_wander(g: int) -> void:
	set_talkable(true)
	set_speed_override(-1.0)
	var n := _rng.randi_range(2, 4)
	for _i in n:
		if not _alive(g):
			return
		var p: Vector3 = NpcUtil.WANDER_POINTS[_rng.randi_range(0, NpcUtil.WANDER_POINTS.size() - 1)]
		await go_to(p)
		if not _alive(g):
			return
		_free_anim = true
		play_anim(anim_idle)
		await get_tree().create_timer(_rng.randf_range(0.8, 2.2)).timeout
		_free_anim = false
	if not _alive(g):
		return
	_set_state(State.TO_COFFIN)


func _state_to_coffin(g: int) -> void:
	set_talkable(true)
	for p in NpcUtil.COFFIN_ROUTE:
		if not _alive(g):
			return
		await go_to(p)
		if not _alive(g):
			return
		# 式場の戸が閉まっていると猫は開けられない。引っ掻いて、うろつきに戻る。
		if last_move_blocked:
			await _scratch_at_blocked_door(g)
			if not _alive(g):
				return
			_set_state(State.INSIDE_WANDER)
			return
	_set_state(State.ON_COFFIN)


## 閉まっていて開けられなかった扉を引っ掻く。
func _scratch_at_blocked_door(g: int) -> void:
	var at := global_position + Vector3(0, 0.4, 0)
	var b := NpcUtil.building()
	if b and blocked_door_name != &"":
		var d := b.get_door(blocked_door_name)
		if d:
			at = d.global_position + Vector3(0, 0.5, 0)
	_free_anim = true
	play_anim(anim_idle)
	for i in 3:
		if not _alive(g):
			return
		Audio.play_at(StringName("cat_scratch_%d" % (i + 1)), at, 0.0,
			_rng.randf_range(0.95, 1.05), 22.0)
		await get_tree().create_timer(1.6).timeout
	if not _alive(g):
		return
	await get_tree().create_timer(2.0).timeout


## 蓋の上へ 0.4 秒で飛び乗って座る。
func _state_on_coffin(g: int) -> void:
	var base := coffin_position()
	var land := Vector3(base.x, coffin_top_y() + 0.02, base.z)
	face_now(Vector3(base.x - 1.0, land.y, base.z))
	set_scripted(true)
	_free_anim = true
	play_anim(anim_walk, 1.8)
	var from := global_position
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(t: float) -> void:
		var p := from.lerp(land, t)
		p.y = lerpf(from.y, land.y, t) + sin(t * PI) * 0.28
		global_position = p, 0.0, 1.0, 0.4)
	await tw.finished
	if not _alive(g):
		set_scripted(false)
		return
	global_position = land
	set_scripted(false)
	set_flying(true)        # 蓋の上から滑り落ちないように Y を固定する
	_on_perch = true
	play_anim(anim_sit)
	Audio.play_at(&"cat_purr", global_position, 0.0, 1.0, 8.0)


## 棺の蓋から床へ飛び降りる。
func _hop_down(g: int) -> void:
	set_flying(false)
	if global_position.y < 0.25:
		return
	var base := coffin_position()
	var land := Vector3(base.x, 0.02, base.z - 1.35)
	var from := global_position
	face_now(land)
	set_scripted(true)
	_free_anim = true
	play_anim(anim_walk, 1.6)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(t: float) -> void:
		var p := from.lerp(land, t)
		p.y = lerpf(from.y, land.y, t) + sin(t * PI) * 0.12
		global_position = p, 0.0, 1.0, 0.35)
	await tw.finished
	if not _alive(g):
		set_scripted(false)
		return
	global_position = land
	set_scripted(false)
	_free_anim = false


func _state_shooed(g: int) -> void:
	set_talkable(false)
	if _shoo_hiss:
		Audio.play_at(&"cat_hiss", global_position + Vector3(0, 0.25, 0), 0.0, 1.0, 20.0)
	set_speed_override(run_speed)
	var exit_name := NpcUtil.nearest_open_opening(global_position)
	if exit_name == &"":
		_set_state(State.HIDING)
		return
	var o: Dictionary = NpcUtil.OPENINGS[exit_name]
	await go_to(o["inside"])
	if not _alive(g):
		return
	if last_move_blocked:
		_set_state(State.HIDING)
		return
	await _traverse(o["outside"], float(o["sill"]))
	if not _alive(g):
		return
	is_inside = false
	set_speed_override(-1.0)
	Events.emit_event(&"cat_shooed", {"exit": exit_name})
	_set_state(State.OUTSIDE_IDLE)


func _state_hiding(g: int) -> void:
	set_talkable(true)
	set_speed_override(run_speed)
	var spot: Vector3 = NpcUtil.HIDE_SPOTS[0]
	var best := INF
	for s in NpcUtil.HIDE_SPOTS:
		var d: float = global_position.distance_to(s)
		if d < best:
			best = d
			spot = s
	await go_to(spot)
	if not _alive(g):
		return
	set_speed_override(-1.0)
	_free_anim = true
	play_anim(anim_sit)
	await get_tree().create_timer(hide_seconds).timeout
	if not _alive(g):
		return
	_set_state(State.TO_COFFIN)


# ============================================================ 小道具

## 開口部をまたぐ。扉(sill がほぼ 0)はナビで普通に通り、窓は弧を描いて飛び越える。
func _traverse(to: Vector3, sill: float) -> void:
	if sill < 0.3:
		await go_to(to)
		return
	var from := global_position
	var land := NpcUtil.snap(get_world_3d(), to)
	face_now(land)
	set_scripted(true)
	_free_anim = true
	play_anim(anim_walk, 1.6)
	var peak: float = sill + 0.35
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(t: float) -> void:
		var p := from.lerp(land, t)
		p.y = lerpf(from.y, land.y, t) + sin(t * PI) * peak
		global_position = p, 0.0, 1.0, 1.0)
	await tw.finished
	set_scripted(false)
	_free_anim = false
	global_position = land


func coffin_position() -> Vector3:
	var cof := SystemsInstaller.find(&"coffin")
	if cof and cof is Node3D:
		return (cof as Node3D).global_position
	var b := NpcUtil.building()
	if b:
		var a := b.get_anchor(&"Anchor_Coffin")
		if a:
			return a.global_position
	return Vector3(16.9, 0.44, -0.5)


## 蓋の上面のワールド Y。
func coffin_top_y() -> float:
	var cof := SystemsInstaller.find(&"coffin")
	if cof and cof is Node3D:
		var lid: float = float(cof.get(&"lid_top_y")) if cof.get(&"lid_top_y") != null else 0.444
		return (cof as Node3D).global_position.y + lid
	return 0.884


## 窓越しにプレイヤーが見えていれば、そちらを向いて目を光らせる。
func _watch_player() -> void:
	var p := Game.player
	if p == null:
		return
	var eye: Vector3 = p.global_position + Vector3(0, 1.6, 0)
	if p.has_method("get_camera"):
		var c: Camera3D = p.get_camera()
		if c:
			eye = c.global_position
	if global_position.distance_to(p.global_position) > see_player_distance:
		set_eye_glow(eye_energy)
		return
	if NpcUtil.visible_through_openings(get_world_3d(), head_position(), eye, [get_rid()]):
		face(p)
		set_eye_glow(eye_energy * 1.6)
	else:
		set_eye_glow(eye_energy)


func _on_talked(_player: Node3D) -> void:
	shoo()
