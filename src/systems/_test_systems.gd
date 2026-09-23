extends Node3D
## systems の単体確認シーン。全プレハブを並べて、火・煙・画面が「そう見えるか」を目で見る。
##
##   godot --path . res://src/systems/_test_systems.tscn
##   godot --path . res://src/systems/_test_systems.tscn -- --look=candle --shot=out/systems/candle.png
##   godot --path . res://src/systems/_test_systems.tscn -- --list        # ステーション名を出す
##
## 引数:
##   --look=<name>   そのステーションの正面にカメラを置く
##   --shot=<path>   --wait 秒後に撮影して終了
##   --wait=<sec>    既定 1.6
##   --pos=x,y,z --yaw=deg --pitch=deg   カメラを直接置く
##   --bright        環境光を上げる(形を確かめたいとき)
##   --fast          線香2秒/ロウソク4秒にして燃え尽きを確認する
##   --lit           起動時に火を点ける(既定で on)
##   --face=<0..3>   棺の顔の状態
##   --faceview      起動直後に棺の顔ビューを出す
##   --open          金庫を開け、ブレーカーを落とし、棺の蓋を開ける
##   --hud           src/ui/hud.tscn を載せる(ダイヤル UI や字幕の確認用)
##   --dial          金庫のダイヤルを開く(--hud と併用)
##
## 手動操作: WASD 移動 / マウス視点 / Shift 速く / Esc でマウス解放 / P でスクショ

const COLS := 5
const SPACING_X := 3.0
const SPACING_Z := 3.6

const STATIONS := [
	# [group 名, シーン, 台の高さ]
	["coffin", "res://src/systems/coffin.tscn", 0.0],
	["altar", "res://src/systems/altar.tscn", 0.0],
	["incense_stand", "res://src/systems/incense_stand.tscn", 0.80],
	["candle", "res://src/systems/candle.tscn", 0.80],
	["iei", "res://src/systems/iei.tscn", 0.90],
	["flower_stand", "res://src/systems/flower_stand.tscn", 0.0],
	["phone", "res://src/systems/phone.tscn", 0.80],
	["monitor", "res://src/systems/monitor.tscn", 0.85],
	["tv", "res://src/systems/tv.tscn", 0.55],
	["freezer", "res://src/systems/freezer.tscn", 0.0],
	["breaker", "res://src/systems/breaker.tscn", 1.10],
	["safe", "res://src/systems/safe.tscn", 0.0],
	["boss_desk", "res://src/systems/boss_desk.tscn", 0.0],
	["futon", "res://src/systems/futon.tscn", 0.0],
	["sink", "res://src/systems/sink.tscn", 0.0],
	["guest_book", "res://src/systems/guest_book.tscn", 0.0],
	["note", "res://src/systems/note.tscn", 0.85],
	["incense_box", "res://src/systems/incense_box.tscn", 0.85],
	["matches", "res://src/systems/matches.tscn", 0.85],
]

var args: Dictionary = {}
var nodes: Dictionary = {}          # name -> Node3D
var station_pos: Dictionary = {}    # name -> Vector3
var cam: Camera3D
var rig: Node3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _free_look: bool = true

func _ready() -> void:
	args = _parse_args()
	Game.level = self
	_build_room()
	_build_stations()
	_build_camera()
	_build_cctv_anchors()
	if args.has("hud") and ResourceLoader.exists("res://src/ui/hud.tscn"):
		add_child(load("res://src/ui/hud.tscn").instantiate())
	if args.has("list"):
		for k in station_pos.keys():
			print("%s  %s" % [k, station_pos[k]])
	call_deferred(&"_setup_state")

# --------------------------------------------------------------------------
# 部屋
# --------------------------------------------------------------------------

func _build_room() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.015, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.46, 0.55)
	e.ambient_light_energy = 0.9 if args.has("bright") else 0.22
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = false
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 35, 0)
	key.light_energy = 0.55 if args.has("bright") else 0.12
	key.light_color = Color(0.7, 0.75, 0.9)
	key.shadow_enabled = true
	add_child(key)

	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "Floor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	floor_mi.material_override = SystemUtil.flat_material(Color(0.20, 0.19, 0.18))
	add_child(floor_mi)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 0.2, 60)
	cs.shape = bs
	cs.position.y = -0.1
	body.add_child(cs)
	add_child(body)

	# 奥の壁(背景が真っ黒だと形が見えないので)
	var wall := MeshInstance3D.new()
	wall.name = "BackWall"
	var wm := BoxMesh.new()
	wm.size = Vector3(40, 4, 0.2)
	wall.mesh = wm
	wall.position = Vector3(0, 2, 4.5 * SPACING_Z)
	wall.material_override = SystemUtil.flat_material(Color(0.24, 0.23, 0.21))
	add_child(wall)

func _build_stations() -> void:
	for i in STATIONS.size():
		var entry: Array = STATIONS[i]
		var sname: String = entry[0]
		var path: String = entry[1]
		var plinth: float = entry[2]
		var col := i % COLS
		var row: int = i / COLS
		var pos := Vector3((float(col) - (COLS - 1) * 0.5) * SPACING_X, 0.0, float(row) * SPACING_Z)
		station_pos[sname] = pos + Vector3(0, plinth, 0)

		if plinth > 0.0:
			var mi := MeshInstance3D.new()
			mi.name = "Plinth_%s" % sname
			var bm := BoxMesh.new()
			bm.size = Vector3(0.7, plinth, 0.7)
			mi.mesh = bm
			mi.position = pos + Vector3(0, plinth * 0.5, 0)
			mi.material_override = SystemUtil.flat_material(Color(0.30, 0.28, 0.26))
			add_child(mi)

		if not ResourceLoader.exists(path):
			push_warning("_test_systems: %s が無い" % path)
			continue
		var n: Node3D = load(path).instantiate()
		n.name = sname
		add_child(n)
		n.position = pos + Vector3(0, plinth, 0)
		n.add_to_group(StringName("system_" + sname))
		n.add_to_group(&"system")
		nodes[sname] = n

		var label := Label3D.new()
		label.text = sname
		label.font_size = 48
		label.pixel_size = 0.0022
		label.position = pos + Vector3(0, plinth + 1.75, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.9, 0.9, 0.7)
		label.no_depth_test = true
		add_child(label)

func _build_cctv_anchors() -> void:
	# モニターの映像の中身。棺のあたりと、並びの全景を映す。
	var a := Node3D.new()
	a.name = "Anchor_Cam_Shikijo"
	a.position = station_pos.get("coffin", Vector3.ZERO) + Vector3(0, 2.2, -3.2)
	add_child(a)
	a.look_at(station_pos.get("coffin", Vector3.ZERO) + Vector3(0, 0.5, 0), Vector3.UP)

	var b := Node3D.new()
	b.name = "Anchor_Cam_Genkan"
	b.position = Vector3(0, 2.6, -5.0)
	add_child(b)
	b.look_at(Vector3(0, 0.8, SPACING_Z), Vector3.UP)

func _build_camera() -> void:
	var player_path := "res://src/player/player.tscn"
	if ResourceLoader.exists(player_path) and not args.has("freecam"):
		var p: Node3D = load(player_path).instantiate()
		add_child(p)
		p.global_position = Vector3(0, 0.1, -4.0)
		Game.register_player(p)
		_free_look = false
		cam = p.find_child("Camera3D", true, false) as Camera3D
		if cam == null:
			cam = _make_free_camera()
		return
	cam = _make_free_camera()

func _make_free_camera() -> Camera3D:
	rig = Node3D.new()
	rig.name = "CamRig"
	rig.position = Vector3(0, 1.55, -4.2)
	add_child(rig)
	var c := Camera3D.new()
	c.name = "TestCamera"
	c.fov = 70.0
	c.near = 0.05
	c.far = 120.0
	rig.add_child(c)
	c.current = true
	return c

# --------------------------------------------------------------------------
# 起動時の状態
# --------------------------------------------------------------------------

func _setup_state() -> void:
	Game.set_flag(&"incense_sticks", 10)

	var fast := args.has("fast")
	var inc := nodes.get("incense_stand") as IncenseStand
	if inc:
		if fast:
			inc.burn_seconds = 2.0
		if not args.has("unlit"):
			inc.light()
	var cnd := nodes.get("candle") as Candle
	if cnd:
		if fast:
			cnd.burn_seconds = 4.0
		if not args.has("unlit"):
			cnd.light()
	var tv := nodes.get("tv") as TV
	if tv and not args.has("unlit"):
		tv.turn_on()
		if args.has("tvface"):
			await get_tree().create_timer(0.6, false).timeout
			tv.set_overlay(SystemUtil.tv_face_texture(), 0.9)
	var fz := nodes.get("freezer") as Freezer
	if fz:
		fz.keep_open = true
		fz._set_lid(true)
	var cof := nodes.get("coffin") as Coffin
	if cof:
		cof.set_face_state(int(args.get("face", "0")))
		cof.set_handprint(args.has("handprint"))
		if args.has("ajar"):
			cof.set_lid_ajar(true)
	var iei := nodes.get("iei") as Iei
	if iei and args.has("facedown"):
		iei.set_face_down(true)
	var fl := nodes.get("flower_stand") as FlowerStand
	if fl and args.has("fresh"):
		fl.set_wilted(false)
	if args.has("dial"):
		var sf3 := nodes.get("safe") as Safe
		if sf3:
			Game.set_flag(&"safe_code", "1009")
			sf3.try_code()
	if args.has("open"):
		var sf := nodes.get("safe") as Safe
		if sf:
			sf.open()
		var br := nodes.get("breaker") as Breaker
		if br:
			br.trip()
		var cof2 := nodes.get("coffin") as Coffin
		if cof2:
			cof2.set_open(true)
	var nt := nodes.get("note") as Note
	if nt:
		nt.title = "日記 1"
		nt.body = "おばあちゃんは猫を二十匹ほど飼っていた。"
		nt.page_number = 1

	_place_camera()
	if args.has("faceview") and cof:
		await get_tree().create_timer(0.3, false).timeout
		cof.show_face(60.0, "test")
	if args.has("shot"):
		_do_shot(String(args["shot"]))

func _place_camera() -> void:
	if args.has("look"):
		var key := String(args["look"])
		if station_pos.has(key):
			var target: Vector3 = station_pos[key]
			var dist := float(args.get("dist", "1.5"))
			var height := float(args.get("height", "1.35"))
			var eye := target + Vector3(0, height, dist)   # モデルは +Z が正面
			var at := target + Vector3(0, float(args.get("at", "0.45")), 0)
			_aim(eye, at)
			return
	if args.has("pos"):
		var v := String(args["pos"]).split(",")
		if v.size() == 3:
			var pos := Vector3(float(v[0]), float(v[1]), float(v[2]))
			if rig:
				rig.global_position = pos
				_yaw = deg_to_rad(float(args.get("yaw", "0")))
				_pitch = deg_to_rad(float(args.get("pitch", "0")))
				rig.rotation.y = _yaw
				cam.rotation.x = _pitch
			elif Game.player and Game.player.has_method("teleport"):
				Game.player.teleport(pos, float(args.get("yaw", "0")), float(args.get("pitch", "0")))

## eye からat を見る向きにカメラを置く。
func _aim(eye: Vector3, at: Vector3) -> void:
	var dir := (at - eye).normalized()
	_yaw = atan2(-dir.x, -dir.z)
	_pitch = asin(clampf(dir.y, -1.0, 1.0))
	if rig:
		rig.global_position = eye
		rig.rotation = Vector3(0, _yaw, 0)
		cam.position = Vector3.ZERO
		cam.rotation = Vector3(_pitch, 0, 0)
	elif Game.player and Game.player.has_method("teleport"):
		Game.player.teleport(eye - Vector3(0, 1.5, 0), rad_to_deg(_yaw), rad_to_deg(_pitch))

func _do_shot(path: String) -> void:
	var wait := float(args.get("wait", "1.6"))
	await get_tree().create_timer(wait, false).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("shot: %s" % path)
	get_tree().quit()

# --------------------------------------------------------------------------
# 手動操作
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _free_look:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.003
		_pitch = clampf(_pitch - mm.relative.y * 0.003, -1.4, 1.4)
		rig.rotation.y = _yaw
		cam.rotation.x = _pitch
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_P:
				var img := get_viewport().get_texture().get_image()
				DirAccess.make_dir_recursive_absolute("res://out/systems")
				var p := "res://out/systems/manual_%d.png" % Time.get_ticks_msec()
				img.save_png(ProjectSettings.globalize_path(p))
				print("shot: %s" % p)

func _process(delta: float) -> void:
	if not _free_look or rig == null:
		return
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= rig.global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += rig.global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= rig.global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += rig.global_transform.basis.x
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	var speed := 6.0 if Input.is_key_pressed(KEY_SHIFT) else 2.4
	rig.global_position += dir.normalized() * speed * delta

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out
