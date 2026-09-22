extends Node
## エントリポイント。存在するものだけを組み立てる(各担当が並列で作れるように)。
##   World(SubViewport 内) に level → player の順で入れ、HUD/VHS があれば載せる。
## CLI フック(検証用):
##   godot --path . -- --screenshot=out/a.png [--pos=x,y,z] [--yaw=deg] [--pitch=deg] [--time=HH:MM] [--wait=1.5]
##   godot --path . -- --tour=out/dir            # docs/viewpoints.json の全視点を撮影
##   godot --path . -- --skip-title --time=HH:MM  # タイトルを飛ばして指定時刻から
##   godot --path . -- --debug                    # イベントログ出力 / Clock.speed 変更キー有効

const LEVEL_PATH := "res://src/level/building.tscn"
const PLAYER_PATH := "res://src/player/player.tscn"
const HUD_PATH := "res://src/ui/hud.tscn"
const VHS_PATH := "res://src/fx/vhs_layer.tscn"
const DIRECTOR_PATH := "res://src/director/director.tscn"
const INSTALLER_PATH := "res://src/systems/installer.tscn"   # Anchor_* に systems のプレハブを置く
const NPC_INSTALLER_PATH := "res://src/npc/installer.tscn"   # Spawn_* に NPC/猫を置く
const TITLE_PATH := "res://src/ui/title.tscn"

@onready var viewport: SubViewport = %GameViewport
@onready var world: Node3D = %World

var args: Dictionary = {}

var _vhs: Node = null

func _ready() -> void:
	args = _parse_args()
	Game.debug = args.has("debug")
	# VHS はタイトルにも乗せるので最初に付ける
	if ResourceLoader.exists(VHS_PATH):
		_vhs = load(VHS_PATH).instantiate()
		add_child(_vhs)
		if _vhs.has_method("attach"):
			_vhs.attach(%GameViewportContainer)
	if args.has("skip-title") or args.has("screenshot") or args.has("tour") or not ResourceLoader.exists(TITLE_PATH):
		start_game()
	else:
		_show_title()

func _show_title() -> void:
	var t: Node = load(TITLE_PATH).instantiate()
	viewport.add_child(t)
	if t.has_signal("start_requested"):
		t.start_requested.connect(func():
			t.queue_free()
			start_game())

func start_game() -> void:
	Game.reset()
	# level
	if ResourceLoader.exists(LEVEL_PATH):
		var lvl: Node3D = load(LEVEL_PATH).instantiate()
		world.add_child(lvl)
		Game.level = lvl
	else:
		_build_fallback_floor()
	# systems / npc のプレハブをアンカーに配置(存在すれば)
	for inst_path in [INSTALLER_PATH, NPC_INSTALLER_PATH]:
		if ResourceLoader.exists(inst_path):
			var inst: Node = load(inst_path).instantiate()
			world.add_child(inst)
	# player
	if ResourceLoader.exists(PLAYER_PATH):
		var p: Node3D = load(PLAYER_PATH).instantiate()
		world.add_child(p)
		var spawn := world.find_child("Spawn_Player", true, false)
		if spawn:
			p.global_transform = spawn.global_transform
		Game.register_player(p)
		# systems 側が先に Camera3D を足していても、描画は必ずプレイヤーのカメラで行う
		var pcam: Camera3D = p.get_camera() if p.has_method("get_camera") else p.find_child("Camera3D", true, false)
		if pcam:
			pcam.make_current()
	else:
		_add_debug_camera()
	# HUD (SubViewport 内に入れて VHS フィルタの下に置く)
	if ResourceLoader.exists(HUD_PATH):
		var hud: Node = load(HUD_PATH).instantiate()
		viewport.add_child(hud)
	# director (夜の進行台本)
	if ResourceLoader.exists(DIRECTOR_PATH):
		var d: Node = load(DIRECTOR_PATH).instantiate()
		add_child(d)
	# 時刻
	if args.has("time"):
		Clock.skip_to(Clock.minutes_from_hhmm(String(args["time"])))
	Game.start_night()
	if not ResourceLoader.exists(DIRECTOR_PATH):
		Clock.start()
	# CLI hooks
	if args.has("screenshot"):
		_do_screenshot(String(args["screenshot"]))
	elif args.has("tour"):
		_do_tour(String(args["tour"]))

func _build_fallback_floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	mi.mesh = pm
	world.add_child(mi)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.light_energy = 0.3
	world.add_child(light)

func _add_debug_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "DebugCamera"
	cam.position = Vector3(0, 1.6, 4)
	world.add_child(cam)
	cam.current = true

func _place_camera_from_args() -> void:
	var cam := viewport.get_camera_3d()
	if cam == null:
		return
	var target: Node3D = Game.player if Game.player else cam
	if args.has("pos"):
		var v := String(args["pos"]).split(",")
		if v.size() == 3:
			var pos := Vector3(float(v[0]), float(v[1]), float(v[2]))
			if Game.player and Game.player.has_method("teleport"):
				Game.player.teleport(pos, float(args.get("yaw", "0")), float(args.get("pitch", "0")))
			else:
				target.global_position = pos
	if not (Game.player and Game.player.has_method("teleport")):
		if args.has("yaw"):
			target.rotation_degrees.y = float(args["yaw"])
		if args.has("pitch"):
			cam.rotation_degrees.x = float(args["pitch"])

func _do_screenshot(path: String) -> void:
	await get_tree().process_frame
	_place_camera_from_args()
	var wait := float(args.get("wait", "1.5"))
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("screenshot saved: %s" % path)
	get_tree().quit()

func _do_tour(dir: String) -> void:
	var vp_path := "res://docs/viewpoints.json"
	if not FileAccess.file_exists(vp_path):
		push_error("docs/viewpoints.json がない")
		get_tree().quit(1)
		return
	var list: Array = JSON.parse_string(FileAccess.get_file_as_string(vp_path))
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	DirAccess.make_dir_recursive_absolute(dir)
	for vp in list:
		if vp.has("time"):
			Clock.skip_to(Clock.minutes_from_hhmm(String(vp["time"])))
		var pos: Array = vp["pos"]
		if Game.player and Game.player.has_method("teleport"):
			Game.player.teleport(Vector3(pos[0], pos[1], pos[2]), float(vp.get("yaw", 0)), float(vp.get("pitch", 0)))
		await get_tree().create_timer(float(vp.get("wait", 0.6))).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var out := "%s/%s.png" % [dir, vp["name"]]
		img.save_png(out)
		print("saved %s" % out)
	get_tree().quit()

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out

func _unhandled_input(event: InputEvent) -> void:
	if not Game.debug:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1: Clock.speed = 1.0
			KEY_F2: Clock.speed = 10.0
			KEY_F3: Clock.speed = 60.0
			KEY_F4: Clock.skip_to(int(Clock.game_minutes) + 60)
			KEY_F5:
				var img := get_viewport().get_texture().get_image()
				var p := "user://shot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
				img.save_png(p)
				print("saved ", ProjectSettings.globalize_path(p))
