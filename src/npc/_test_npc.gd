extends Node3D
## NPC / 猫 / 火車 の動作確認シーン。建物 + systems + player + NpcInstaller を組んで、
## シナリオを 1 本走らせ、状態遷移を print しながら out/npc/ にスクリーンショットを残す。
##
##   godot --path . res://src/npc/_test_npc.tscn -- --no-capture --scenario=cat_enter
##   godot --path . res://src/npc/_test_npc.tscn -- --no-capture --scenario=cat_shoo
##   godot --path . res://src/npc/_test_npc.tscn -- --no-capture --scenario=boss_leave
##   godot --path . res://src/npc/_test_npc.tscn -- --no-capture --scenario=kasha_chase
##   godot --path . res://src/npc/_test_npc.tscn -- --no-capture --scenario=son_sleep
##   godot --path . res://src/npc/_test_npc.tscn -- --no-capture --scenario=api      # API だけ叩く
##
## --out=out/npc で出力先を変えられる。--free で自由に見回す(カメラは WASD + マウス)。

const OUT_DEFAULT := "out/npc"

var args: Dictionary = {}
var out_dir: String = OUT_DEFAULT
var building: Building = null
var player: Node3D = null
var cam: Camera3D = null
var shot_index: int = 0
var events_seen: Array[String] = []


func _ready() -> void:
	args = _parse_args()
	out_dir = String(args.get("out", OUT_DEFAULT))
	Game.debug = true
	Game.reset()
	Game.debug = true

	building = load("res://src/level/building.tscn").instantiate() as Building
	add_child(building)
	Game.level = building

	for p in ["res://src/systems/installer.tscn", "res://src/npc/installer.tscn"]:
		if ResourceLoader.exists(p):
			add_child(load(p).instantiate())

	player = load("res://src/player/player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector3(-9.5, 0.0, 0.0)
	Game.register_player(player)

	cam = Camera3D.new()
	cam.name = "ShotCam"
	cam.fov = 70.0
	cam.far = 220.0
	add_child(cam)

	Events.event.connect(func(n: StringName, d: Dictionary) -> void:
		events_seen.append(String(n))
		print("   [event] %s %s" % [n, d]))

	Game.start_night()
	# ナビマップの同期を待つ
	for i in 4:
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout

	var scenario := String(args.get("scenario", "api"))
	print("=== scenario: %s ===" % scenario)
	match scenario:
		"cat_enter": await _cat_enter()
		"cat_shoo": await _cat_shoo()
		"boss_leave": await _boss_leave()
		"kasha_chase": await _kasha_chase()
		"son_sleep": await _son_sleep()
		"api": await _api()
		"free":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		_:
			push_error("知らない scenario: %s" % scenario)
	print("=== done: %s  events=%s ===" % [scenario, events_seen])
	get_tree().quit()


# ==================================================================== シナリオ

## 勝手口を開けて猫を入れ、棺の上まで行かせる。
func _cat_enter() -> void:
	var cat := NpcInstaller.find(&"cat", 2) as Cat      # Spawn_Cat3 = 勝手口のそば
	assert(cat != null, "cat が置かれていない")
	var door := building.get_door(&"Door_Backyard")
	door.open()
	building.get_door(&"Door_Shikijo").open()   # 式場の戸。猫は扉を開けられない
	print("勝手口 is_open=%s / 式場 is_open=%s" % [door.is_open, building.get_door(&"Door_Shikijo").is_open])
	cat.activate()
	await get_tree().create_timer(0.5).timeout
	await _shot("cat_01_outside", cat.global_position + Vector3(1.3, 0.85, -1.9),
		cat.global_position + Vector3(0, 0.2, 0))

	cat.set_target_entry(&"Door_Backyard")
	await _wait_state(cat, Cat.State.INSIDE_WANDER, 25.0)
	print("猫の状態=%s  pos=%v  is_inside=%s" % [cat.state_name(), cat.global_position, cat.is_inside])
	await _shot("cat_02_inside", Vector3(3.2, 1.55, -3.2), cat.global_position + Vector3(0, 0.2, 0))

	# うろつきを飛ばして棺へ
	cat._set_state(Cat.State.TO_COFFIN)
	await _wait_state(cat, Cat.State.ON_COFFIN, 40.0)
	await get_tree().create_timer(1.5).timeout
	print("猫の状態=%s  pos=%v  棺の上面 y=%.3f" % [cat.state_name(), cat.global_position, cat.coffin_top_y()])
	await _shot("cat_03_on_coffin", Vector3(14.4, 1.35, -2.4), cat.global_position)
	await _shot("cat_04_coffin_wide", Vector3(11.0, 2.2, -2.8), Vector3(16.9, 0.8, -0.5))
	print("cat_crossed_coffin が出たか: %s" % events_seen.has("cat_crossed_coffin"))


## 室内の猫を「追い払う」。開いている勝手口から外へ走って出る。
func _cat_shoo() -> void:
	var cat := NpcInstaller.find(&"cat", 2) as Cat
	building.get_door(&"Door_Backyard").open()
	building.get_door(&"Door_Shikijo").open()
	cat.activate()
	cat.go_inside_now(&"Door_Backyard")
	await get_tree().create_timer(1.0).timeout
	cat._set_state(Cat.State.TO_COFFIN)
	await _wait_state(cat, Cat.State.ON_COFFIN, 40.0)
	await get_tree().create_timer(1.0).timeout
	await _shot("shoo_01_before", Vector3(14.4, 1.35, -2.4), cat.global_position)

	print("追い払う prompt=%s enabled=%s" % [cat.talk.get_prompt(), cat.talk.enabled])
	cat.shoo()
	print("猫の状態=%s" % cat.state_name())
	await get_tree().create_timer(2.5).timeout
	await _shot("shoo_02_running", cat.global_position + Vector3(0.0, 2.4, -3.2), cat.global_position)
	await _wait_state(cat, Cat.State.OUTSIDE_IDLE, 40.0)
	print("猫の状態=%s  pos=%v  is_inside=%s" % [cat.state_name(), cat.global_position, cat.is_inside])
	await _shot("shoo_03_outside", cat.global_position + Vector3(2.0, 2.4, -3.0), cat.global_position)
	print("cat_shooed が出たか: %s" % events_seen.has("cat_shooed"))


## 社長が玄関から帰る。
func _boss_leave() -> void:
	var boss := NpcInstaller.find(&"boss") as NpcBoss
	assert(boss != null, "boss が置かれていない")
	boss.set_talkable(true)
	print("社長 pos=%v talk=%s" % [boss.global_position, boss.talk.get_prompt()])
	await _shot("boss_01_start", Vector3(-6.0, 1.7, -1.0), boss.global_position + Vector3(0, 1.2, 0))
	var t0 := Time.get_ticks_msec()
	boss.leave_via_genkan()
	await get_tree().create_timer(3.5).timeout
	await _shot("boss_02_walking", Vector3(-7.5, 1.7, 2.6), boss.global_position + Vector3(0, 1.2, 0))
	await _wait_until(func() -> bool: return not boss.is_active, 30.0)
	print("社長 despawn 済み  pos=%v  所要 %.1f 秒" % [boss.global_position, (Time.get_ticks_msec() - t0) / 1000.0])
	await _shot("boss_03_gone", Vector3(-8.0, 1.7, 1.2), Vector3(-11.5, 1.0, 0.0))
	print("npc_left が出たか: %s" % events_seen.has("npc_left"))


## プレイヤーを式場に置き、火車を湯灌室から出して追わせる。
func _kasha_chase() -> void:
	var kasha := NpcInstaller.find(&"kasha") as Kasha
	assert(kasha != null, "kasha が置かれていない")
	player.global_position = Vector3(9.5, 0.0, -0.5)
	if player.has_method("teleport"):
		player.teleport(Vector3(9.5, 0.0, -0.5), 90.0, 0.0)
	building.set_all_lights(false)
	building.set_room_lights(&"Room_Hall", true)
	await get_tree().create_timer(0.3).timeout

	kasha.activate()
	print("火車 pos=%v is_chasing=%s" % [kasha.global_position, kasha.is_chasing])
	await get_tree().create_timer(2.0).timeout
	await _shot("kasha_01_yukan", Vector3(6.4, 1.5, -4.0), kasha.global_position + Vector3(0, 0.5, 0))

	await get_tree().create_timer(3.0).timeout
	print("火車 pos=%v 見られている=%s 速度=%.2f" % [kasha.global_position, kasha.player_sees_me,
		Vector2(kasha.velocity.x, kasha.velocity.z).length()])
	await _shot("kasha_02_hall", Vector3(6.4, 1.6, 1.4), kasha.global_position + Vector3(0, 0.5, 0))

	kasha.set_ceiling_mode(true)
	await get_tree().create_timer(2.0).timeout
	print("天井モード y=%.2f" % kasha.global_position.y)
	await _shot("kasha_03_ceiling", kasha.global_position + Vector3(0, -0.3, 4.0),
		kasha.global_position + Vector3(0, 0.3, 0))
	kasha.set_ceiling_mode(false)

	# 捕まるまで待つ
	var caught := false
	kasha.caught.connect(func() -> void: caught = true)
	await _wait_until(func() -> bool: return caught, 25.0)
	print("捕まえた=%s  距離=%.2f" % [caught, kasha.distance_to_player()])
	await _shot("kasha_04_caught", player.global_position + Vector3(0, 1.6, 0) - Vector3(2.5, 0, 0),
		kasha.global_position + Vector3(0, 0.5, 0))

	# 灯し直し成功 → 退却 → 再追跡
	Events.emit_event(&"relight_success", {"n": 1})
	await get_tree().create_timer(3.0).timeout
	print("退却中 is_retreating=%s pos=%v" % [kasha.is_retreating, kasha.global_position])
	await _shot("kasha_05_retreat", Vector3(6.4, 1.6, -3.0), kasha.global_position + Vector3(0, 0.5, 0))
	kasha.stop_chase()
	print("stop_chase 後 is_chasing=%s" % kasha.is_chasing)


## 息子が控室の座布団で寝る。
func _son_sleep() -> void:
	var son := NpcInstaller.find(&"son") as NpcSon
	assert(son != null, "son が置かれていない")
	son.set_active(true)
	son.teleport_to(Vector3(-1.35, 0.0, 1.5), 180.0)
	print("息子 drunk=%s pos=%v" % [son.drunk, son.global_position])
	await son.go_to_hikaeshitsu()
	print("控室に到着 pos=%v" % son.global_position)
	await _shot("son_01_walk", Vector3(-3.2, 1.6, 1.4), son.global_position + Vector3(0, 1.2, 0))
	son.sleep()
	await get_tree().create_timer(2.0).timeout
	print("is_sleeping=%s anim=%s speed=%.2f フラグ=%s" % [son.is_sleeping, son.current_anim(),
		son.anim.speed_scale, Game.get_flag(&"son_asleep")])
	await _shot("son_02_sleeping", Vector3(-2.6, 1.3, 1.1), son.global_position + Vector3(0, 0.9, 0))
	await get_tree().create_timer(5.0).timeout
	print("5 秒後も寝ている=%s" % son.is_sleeping)


## API が一通り生きているかだけ確認する(スクショなし)。
func _api() -> void:
	print("NpcInstaller.all() = %d" % NpcInstaller.all().size())
	for key in [&"boss", &"granddaughter", &"son", &"cat", &"kasha"]:
		var list := NpcInstaller.find_all(key)
		var names := PackedStringArray()
		for n in list:
			names.append("%s@%v" % [n.name, (n as Node3D).global_position])
		print("  %-14s %d  %s" % [key, list.size(), ", ".join(names)])
	var cat := NpcInstaller.find(&"cat", 0) as Cat
	print("  cat.state=%s layer=%d mask=%d agent.radius=%.2f" % [cat.state_name(),
		cat.collision_layer, cat.collision_mask, cat.agent.radius])
	print("  cat.head=%v coffin=%v top_y=%.3f" % [cat.head_position(), cat.coffin_position(), cat.coffin_top_y()])
	var k := NpcInstaller.find(&"kasha") as Kasha
	print("  kasha agent.radius=%.2f anim=%s" % [k.agent.radius, k.anim.get_animation_list()])
	for o in NpcUtil.OPENINGS:
		print("  開口部 %-16s open=%s center=%v" % [o, NpcUtil.is_opening_open(o), NpcUtil.opening_center(o)])
	var br: BodyRisen = load("res://src/npc/body_risen.tscn").instantiate()
	add_child(br)
	br.global_position = Vector3(16.9, 0.9, -0.5)
	await br.rise()
	print("  body_risen.rise() 完了")


# ==================================================================== 補助

func _wait_state(cat: Cat, want: int, timeout: float) -> void:
	await _wait_until(func() -> bool: return cat.state == want, timeout)


func _wait_until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		if bool(cond.call()):
			return
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	print("!! タイムアウト(%.1f 秒)" % timeout)


func _shot(name: String, pos: Vector3, look_at: Vector3) -> void:
	shot_index += 1
	cam.global_position = pos
	var to := look_at - pos
	if to.length_squared() > 0.0001:
		cam.look_at(look_at, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [out_dir, shot_index, name]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("   saved %s" % path)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out
