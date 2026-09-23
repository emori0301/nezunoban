extends Node3D
## レベル単体の確認・撮影用シーン。player.tscn がまだ無くても視点を回せる。
##   godot --path . res://src/level/_test_tour.tscn -- --tour=out/level
##   godot --path . res://src/level/_test_tour.tscn -- --shot=out/x.png --pos=0,1.6,0 --yaw=-90 --pitch=-3
##   godot --path . res://src/level/_test_tour.tscn                    # 自由に見回す(WASD + マウス)
##
## main.gd の --tour は player.tscn がある前提なので、それが揃うまではこちらを使う。

const VIEWPOINTS := "res://docs/viewpoints.json"

var cam: Camera3D
var args: Dictionary = {}
var free_look := false
var yaw := -90.0
var pitch := 0.0


func _ready() -> void:
	args = _parse_args()
	var b: Node3D = load("res://src/level/building.tscn").instantiate()
	add_child(b)
	Game.level = b
	# 本編と同じ条件で確かめたいとき: systems のプレハブを載せてからナビを焼き直す
	if args.has("systems") and ResourceLoader.exists("res://src/systems/installer.tscn"):
		add_child(load("res://src/systems/installer.tscn").instantiate())
		await get_tree().process_frame
		if b.has_method("rebake_navmesh"):
			b.rebake_navmesh()

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 220.0
	cam.position = Vector3(-9.5, 1.6, 0.0)
	cam.rotation_degrees = Vector3(0, -90, 0)
	add_child(cam)
	cam.current = true

	if args.has("api"):
		await _api(b)
		return
	if args.has("check"):
		await _check(b)
		return
	if args.has("dark"):
		b.set_all_lights(false)
	# CCTV の見え方確認: --camanchor=Anchor_Cam_Genkan でそのアンカーの視点から撮る
	if args.has("camanchor"):
		var an: Node3D = b.get_anchor(StringName(String(args["camanchor"])))
		if an:
			cam.global_transform = an.global_transform
			cam.fov = 70.0
	if args.has("emgoff"):
		b.set_emergency_lights(false)
	if args.has("roomoff"):
		b.set_room_lights(StringName(String(args["roomoff"])), false)
	if args.has("tour"):
		await _tour(String(args["tour"]))
	elif args.has("shot"):
		await _shot(String(args["shot"]))
	else:
		free_look = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _place(pos: Vector3, y: float, p: float) -> void:
	cam.position = pos
	cam.rotation_degrees = Vector3(p, y, 0)


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("saved %s (fps=%d, draw_calls=%d, objects=%d, prims=%d)" % [path,
		int(Engine.get_frames_per_second()),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _shot(path: String) -> void:
	if args.has("pos"):
		var v := String(args["pos"]).split(",")
		_place(Vector3(float(v[0]), float(v[1]), float(v[2])),
			float(args.get("yaw", "-90")), float(args.get("pitch", "0")))
	if args.has("time"):
		Clock.skip_to(Clock.minutes_from_hhmm(String(args["time"])))
	await get_tree().create_timer(float(args.get("wait", "1.2"))).timeout
	await _capture(path)
	get_tree().quit()


func _tour(dir: String) -> void:
	if not FileAccess.file_exists(VIEWPOINTS):
		push_error("docs/viewpoints.json がない")
		get_tree().quit(1)
		return
	var list: Array = JSON.parse_string(FileAccess.get_file_as_string(VIEWPOINTS))
	await get_tree().create_timer(1.2).timeout
	for vp in list:
		if vp.has("time"):
			Clock.skip_to(Clock.minutes_from_hhmm(String(vp["time"])))
		var p: Array = vp["pos"]
		_place(Vector3(p[0], p[1], p[2]), float(vp.get("yaw", 0)), float(vp.get("pitch", 0)))
		await get_tree().create_timer(float(vp.get("wait", 0.5))).timeout
		await _capture("%s/%s.png" % [dir, vp["name"]])
	get_tree().quit()


## 公開 API の動作確認(他担当が呼ぶ経路を一通り叩く)。
func _api(b: Node3D) -> void:
	await get_tree().process_frame
	var anchors := ["Spawn_Player", "Spawn_Boss", "Spawn_Granddaughter", "Spawn_Son",
		"Spawn_Cat1", "Spawn_Cat2", "Spawn_Cat3", "Spawn_Cat4", "Spawn_Cat5", "Spawn_Kasha",
		"Anchor_Coffin", "Anchor_Altar", "Anchor_Iei", "Anchor_IncenseStand", "Anchor_Candle",
		"Anchor_FlowerL", "Anchor_FlowerR", "Anchor_Sink", "Anchor_Phone", "Anchor_Monitor",
		"Anchor_Freezer", "Anchor_Breaker", "Anchor_Safe", "Anchor_Futon", "Anchor_TV",
		"Anchor_GuestBook", "Anchor_IncenseBox", "Anchor_Matches", "Anchor_BossDesk",
		"Anchor_Cam_Shikijo", "Anchor_Cam_Genkan"]
	var missing: Array[String] = []
	for a in anchors:
		if b.get_anchor(StringName(a)) == null:
			missing.append(a)
	print("anchors: %d / %d  missing=%s" % [anchors.size() - missing.size(), anchors.size(), missing])
	for a in anchors:
		var n: Node3D = b.get_anchor(StringName(a))
		if n:
			print("  %-22s pos=(%.2f, %.2f, %.2f) yaw=%.0f" % [a, n.global_position.x,
				n.global_position.y, n.global_position.z, rad_to_deg(n.global_rotation.y)])
	for d in ["Door_Genkan", "Door_Backyard", "Door_Shikijo", "Door_Office",
			"Door_Hikaeshitsu", "Door_Toilet", "Door_Yukan"]:
		var dr = b.get_door(StringName(d))
		print("  door %-18s %s locked=%s pos=(%.2f, %.2f)" % [d, "OK" if dr else "MISSING",
			dr.locked if dr else "-", dr.global_position.x if dr else 0.0, dr.global_position.z if dr else 0.0])
	for w in ["Window_Shikijo", "Window_Toilet", "Window_Office"]:
		var wp = b.get_window_pane(StringName(w))
		print("  window %-16s %s pos=(%.2f, %.2f, %.2f)" % [w, "OK" if wp else "MISSING",
			wp.global_position.x if wp else 0.0, wp.global_position.y if wp else 0.0,
			wp.global_position.z if wp else 0.0])
	for r in Building.ROOMS:
		print("  area %-20s %s  light=%s" % [r, "OK" if b.get_room_area(r) else "MISSING",
			b.get_light_state(r)])
	print("  area Room_Outside        %s" % ("OK" if b.get_room_area(&"Room_Outside") else "MISSING"))
	print("  Yukan_Robe: %s" % (b.find_child("Yukan_Robe", true, false) != null))
	print("  Anchor_Candle/Light: %s %s" % [b.get_anchor(&"Anchor_Candle").has_node("Light"),
		b.get_anchor(&"Anchor_Candle").has_node("Light2")])
	# 操作
	b.get_door(&"Door_Shikijo").open()
	b.get_window_pane(&"Window_Shikijo").open()
	b.set_room_lights(&"Room_Shikijo", false)
	print("  shikijo light after off = %s" % b.get_light_state(&"Room_Shikijo"))
	b.set_room_lights(&"Room_Shikijo", true)
	b.flicker(&"Room_Hall", 0.5)
	b.set_light_scale(0.8)
	b.set_light_scale(1.0)
	await get_tree().create_timer(1.0).timeout
	b.get_door(&"Door_Shikijo").slam()
	b.set_all_lights(false)
	b.set_all_lights(true)
	await get_tree().create_timer(0.8).timeout
	print("  API OK")
	get_tree().quit()


## 歩いて回れるかの検証。全扉を開けてから Spawn_Player → 各部屋の代表点へ
## ナビ経路を引き、経路上でプレイヤー相当のカプセルが壁や小物に当たらないか調べる。
const CHECK_TARGETS := {
	"Room_Genkan": Vector3(-8.0, 0.0, -1.6),
	"Room_Office": Vector3(-6.6, 0.0, 5.2),
	"Room_Hall": Vector3(3.0, 0.0, 0.0),
	"Room_Hall_L": Vector3(6.4, 0.0, -6.6),
	"Room_Hikaeshitsu": Vector3(-2.6, 0.0, 1.8),
	"Room_Toilet": Vector3(0.7, 0.0, 2.6),
	"Room_Shikijo_door": Vector3(9.0, 0.0, 0.0),
	"Room_Shikijo_incense": Vector3(14.3, 0.0, -0.5),
	"Room_Backyard_sink": Vector3(-2.6, 0.0, -3.2),
	"Room_Backyard_freezer": Vector3(3.6, 0.0, -5.3),
	"Room_Backyard_breaker": Vector3(4.3, 0.0, -5.6),
	"Room_Yukan": Vector3(7.3, 0.0, -9.0),
	"Outside_front": Vector3(-13.5, 0.0, 0.0),
	"Outside_back": Vector3(0.0, 0.0, -9.0),
}

func _check(b: Node3D) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	for d in get_tree().get_nodes_in_group(&"door"):
		d.open(true)
	await get_tree().create_timer(0.8).timeout
	await get_tree().physics_frame

	var spawn: Node3D = b.get_anchor(&"Spawn_Player")
	var from: Vector3 = spawn.global_position
	var map := get_world_3d().navigation_map
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.7   # プレイヤー相当
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1
	params.collide_with_areas = false

	# 経路自体は猫(nav agent r=0.2)の通り道なので、経路追従の判定は細めのカプセルで見る。
	# プレイヤーが通れるかは後段の「戸口の有効幅」が正。
	var navshape := CapsuleShape3D.new()
	# Recast は agent_radius をセル単位で侵食するので、実際に保証される余裕は
	# radius からセルの半分(0.05m)ほど甘い。判定はその分だけ細くする。
	navshape.radius = 0.25
	navshape.height = 1.7
	var navparams := PhysicsShapeQueryParameters3D.new()
	navparams.shape = navshape
	navparams.collision_mask = 1
	navparams.collide_with_areas = false
	print("--- walkability from Spawn_Player %s ---" % from)
	for key in CHECK_TARGETS:
		var to: Vector3 = CHECK_TARGETS[key]
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		if path.size() < 2:
			print("  [NG] %-24s 経路なし" % key)
			continue
		var dist := 0.0
		for i in range(1, path.size()):
			dist += path[i].distance_to(path[i - 1])
		var blocked := 0
		var worst := Vector3.ZERO
		var walked := 0.0
		for i in range(1, path.size()):
			var seg := path[i] - path[i - 1]
			var steps := maxi(1, int(seg.length() / 0.2))
			for k in steps + 1:
				var p: Vector3 = path[i - 1] + seg * (float(k) / steps)
				navparams.transform = Transform3D(Basis(), p + Vector3(0, 0.78, 0))
				if space.intersect_shape(navparams, 1).size() > 0:
					blocked += 1
					worst = p
			walked += seg.length()
		var tag := "OK " if blocked == 0 else "NG "
		print("  [%s] %-24s %5.1f m  %4.1f s  詰まり %d %s" % [tag, key, dist, dist / 2.5, blocked,
			("" if blocked == 0 else str(worst))])

	# 戸口の有効幅。開口の中心と左右 0.22m ずらした位置、前後 0.8m を通れるか。
	print("--- doorway clearance (player capsule r=0.32) ---")
	var doorways := [
		["Door_Genkan", Vector3(-11.0, 0, 0.0), true],
		["Hall_mouth", Vector3(-4.0, 0, 0.0), true],
		["Door_Office", Vector3(-8.0, 0, 4.0), false],
		["Door_Hikaeshitsu", Vector3(-2.2, 0, 1.1), false],
		["Door_Toilet", Vector3(0.7, 0, 1.1), false],
		["Hall_L_junction", Vector3(6.4, 0, -1.1), false],
		["Backyard_opening", Vector3(5.3, 0, -4.3), true],
		["Door_Shikijo", Vector3(7.5, 0, 0.0), true],
		["Door_Backyard", Vector3(0.0, 0, -7.5), false],
		["Door_Yukan", Vector3(6.4, 0, -7.5), false],
	]
	for dw in doorways:
		var c: Vector3 = dw[1]
		var along: Vector3 = Vector3(1, 0, 0) if dw[2] else Vector3(0, 0, 1)
		var side: Vector3 = Vector3(0, 0, 1) if dw[2] else Vector3(1, 0, 0)
		# 開口面で横にずらしながら、通れる幅を測る
		var left := 0.0
		var right := 0.0
		for i in 40:
			var o := i * 0.02
			params.transform = Transform3D(Basis(), c + side * o + Vector3(0, 0.92, 0))
			if space.intersect_shape(params, 1).size() > 0:
				break
			right = o
		for i in 40:
			var o := i * 0.02
			params.transform = Transform3D(Basis(), c - side * o + Vector3(0, 0.92, 0))
			if space.intersect_shape(params, 1).size() > 0:
				break
			left = o
		# 奥行き方向(通り抜け)に詰まりがないか
		var thru := 0
		for t in [-1.2, -0.8, -0.4, 0.0, 0.4, 0.8, 1.2]:
			params.transform = Transform3D(Basis(), c + along * t + Vector3(0, 0.92, 0))
			if space.intersect_shape(params, 1).size() > 0:
				thru += 1
		var clear := left + right + 0.64
		var ok: bool = thru == 0 and clear >= 0.75
		print("  [%s] %-20s 有効幅 %.2f m  通り抜け詰まり %d" % ["OK " if ok else "NG ", dw[0], clear, thru])

	# NPC のスポーンがナビメッシュから出られるか(director からの指摘で追加)
	print("--- NPC spawn reachability ---")
	for np in [["Spawn_Boss → Anchor_BossDesk", &"Spawn_Boss", &"Anchor_BossDesk"],
			["Spawn_Boss → Anchor_Altar", &"Spawn_Boss", &"Anchor_Altar"],
			["Spawn_Granddaughter → Anchor_Coffin", &"Spawn_Granddaughter", &"Anchor_Coffin"],
			["Spawn_Granddaughter → Spawn_Player", &"Spawn_Granddaughter", &"Spawn_Player"],
			["Spawn_Boss → Spawn_Player", &"Spawn_Boss", &"Spawn_Player"],
			["Spawn_Son → Spawn_Player", &"Spawn_Son", &"Spawn_Player"],
			["Spawn_Kasha → Anchor_Coffin", &"Spawn_Kasha", &"Anchor_Coffin"]]:
		var a: Node3D = b.get_anchor(np[1])
		var c: Node3D = b.get_anchor(np[2])
		if a == null or c == null:
			print("  [NG] %-36s アンカーが無い" % np[0])
			continue
		var pth := NavigationServer3D.map_get_path(map, a.global_position, c.global_position, true)
		var dd := 0.0
		for i in range(1, pth.size()):
			dd += pth[i].distance_to(pth[i - 1])
		# 経路の始点がスポーン位置から離れていたら、ナビメッシュの外に立っている
		var off := 99.0 if pth.size() == 0 else pth[0].distance_to(a.global_position)
		# 経路上を実際に体が通れるか。終点の 0.6m は「物の手前で止まる」ので除く。
		var hit := 0
		var travelled := 0.0
		for i in range(1, pth.size()):
			var seg := pth[i] - pth[i - 1]
			var steps := maxi(1, int(seg.length() / 0.25))
			for k in steps + 1:
				var at := travelled + seg.length() * (float(k) / steps)
				if dd - at < 0.6:
					continue
				navparams.transform = Transform3D(Basis(),
					pth[i - 1] + seg * (float(k) / steps) + Vector3(0, 0.78, 0))
				if space.intersect_shape(navparams, 1).size() > 0:
					hit += 1
			travelled += seg.length()
		var ok: bool = pth.size() >= 2 and off < 0.6 and hit == 0
		print("  [%s] %-36s %5.1f m  投影ずれ %.2f m  家具に当たる点 %d" % [
			"OK " if ok else "NG ", np[0], dd, off, hit])

	# 椅子のブロックの中に立たされても通路へ出られるか(autoplay で実際に起きた位置)
	print("--- 椅子の間から脱出 ---")
	for pair2 in [[Vector3(12.157, 0.0, 0.65), Vector3(-9.6, 0.0, 0.0)],
			[Vector3(11.15, 0.0, -1.65), Vector3(-9.6, 0.0, 0.0)],
			[Vector3(13.55, 0.0, 0.65), Vector3(-9.6, 0.0, 0.0)],
			[Vector3(3.946, 0.0, -0.553), Vector3(0.916, 0.0, -6.931)]]:
		var trapped: Vector3 = pair2[0]
		var pth2 := NavigationServer3D.map_get_path(map, trapped, pair2[1], true)
		var off2 := 99.0 if pth2.size() == 0 else pth2[0].distance_to(trapped)
		var d2 := 0.0
		for i in range(1, pth2.size()):
			d2 += pth2[i].distance_to(pth2[i - 1])
		# 経路が壁を突っ切っていないか、カプセルで舐めて確かめる
		var h2 := 0
		for i in range(1, pth2.size()):
			var sg := pth2[i] - pth2[i - 1]
			var st := maxi(1, int(sg.length() / 0.2))
			for k in st + 1:
				navparams.transform = Transform3D(Basis(),
					pth2[i - 1] + sg * (float(k) / st) + Vector3(0, 0.78, 0))
				if space.intersect_shape(navparams, 1).size() > 0:
					h2 += 1
		print("  [%s] %s → %s  %5.1f m  投影ずれ %.2f m  当たり %d  経由点 %d" % [
			"OK " if (pth2.size() >= 2 and off2 < 1.0 and h2 == 0) else "NG ",
			trapped, pair2[1], d2, off2, h2, pth2.size()])

	# 廊下北枝の直線掃引。NPC が詰まる区間に何があるか名前で出す。
	print("--- 廊下の掃引(北枝と本線) ---")
	var sweep := CapsuleShape3D.new()
	sweep.radius = 0.3
	sweep.height = 1.75
	var sp := PhysicsShapeQueryParameters3D.new()
	sp.shape = sweep
	sp.collision_mask = 1
	sp.collide_with_areas = false
	var seen_names := {}
	# 北枝: (6.4, 0) → (6.4, -6)
	for i in 61:
		var z := -0.1 * i
		for ox in [-0.5, -0.25, 0.0, 0.25, 0.5]:
			sp.transform = Transform3D(Basis(), Vector3(6.4 + ox, 0.9, z))
			for h in space.intersect_shape(sp, 8):
				var c = h.get("collider")
				if c == null:
					continue
				var nm2: String = String(c.get_parent().name) if c.get_parent() else String(c.name)
				var key := "北枝 %s @ x%+.2f" % [nm2, 6.4 + ox]
				if not seen_names.has(key):
					seen_names[key] = z
	# 本線: (-3.5, 0) → (7.2, 0)
	for i in 108:
		var x := -3.5 + 0.1 * i
		for oz in [-0.5, -0.25, 0.0, 0.25, 0.5]:
			sp.transform = Transform3D(Basis(), Vector3(x, 0.9, oz))
			for h in space.intersect_shape(sp, 8):
				var c = h.get("collider")
				if c == null:
					continue
				var nm2: String = String(c.get_parent().name) if c.get_parent() else String(c.name)
				var key := "本線 %s @ z%+.2f" % [nm2, oz]
				if not seen_names.has(key):
					seen_names[key] = x
	if seen_names.is_empty():
		print("  [OK ] 当たるものなし")
	else:
		for k in seen_names:
			print("  [NG ] %-34s z=%.1f" % [k, seen_names[k]])

	# アンカーの高さ。モデルの原点は底面中央なので、真下の面と一致しているか見る。
	# 壁付け(分電盤)と天井付け(CCTV)は床までの距離が出るので別扱い。
	print("--- anchor 接地面 ---")
	# 床や天板に載らないアンカー(壁付け・天井付け・他の物の内部)は接地判定の対象外。
	var wall_mounted := {&"Anchor_Breaker": "壁", &"Anchor_Cam_Shikijo": "天井",
		&"Anchor_Cam_Genkan": "天井", &"Anchor_Iei": "祭壇の枠の中",
		&"Anchor_IncenseBox": "焼香台の引き出しの中"}
	var rp := PhysicsRayQueryParameters3D.new()
	rp.collision_mask = 1
	for an in ["Anchor_Coffin", "Anchor_Altar", "Anchor_Iei", "Anchor_IncenseStand", "Anchor_IncenseBox",
			"Anchor_Candle", "Anchor_FlowerL", "Anchor_FlowerR", "Anchor_Sink", "Anchor_Phone",
			"Anchor_Monitor", "Anchor_Freezer", "Anchor_Breaker", "Anchor_Safe", "Anchor_Futon",
			"Anchor_TV", "Anchor_GuestBook", "Anchor_Matches", "Anchor_BossDesk"]:
		var nd: Node3D = b.get_anchor(StringName(an))
		if nd == null:
			continue
		var ap := nd.global_position
		rp.from = ap + Vector3(0, 0.03, 0)
		rp.to = ap - Vector3(0, 3.0, 0)
		var hit := space.intersect_ray(rp)
		if wall_mounted.has(StringName(an)):
			print("  [--] %-20s y=%.2f  (%s)" % [an, ap.y, wall_mounted[StringName(an)]])
		elif hit.is_empty():
			print("  [NG] %-20s y=%.2f  真下に面が無い" % [an, ap.y])
		else:
			var gap: float = ap.y - float(hit["position"].y)
			var ok: bool = absf(gap) < 0.12
			print("  [%s] %-20s y=%.2f  真下の面 y=%.2f  差 %+.2f m" % [
				"OK " if ok else "NG ", an, ap.y, hit["position"].y, gap])

	# 距離の実測(式場 <-> 事務所 / 式場 <-> バックヤード)
	print("--- distances ---")
	for pair in [["焼香台→事務所の電話", Vector3(14.3, 0, -0.5), Vector3(-9.4, 0, 6.6)],
			["焼香台→冷凍庫", Vector3(14.3, 0, -0.5), Vector3(3.6, 0, -5.3)],
			["焼香台→流し", Vector3(14.3, 0, -0.5), Vector3(-2.6, 0, -3.2)],
			["焼香台→分電盤", Vector3(14.3, 0, -0.5), Vector3(4.3, 0, -5.6)]]:
		var pth := NavigationServer3D.map_get_path(map, pair[1], pair[2], true)
		var dd := 0.0
		for i in range(1, pth.size()):
			dd += pth[i].distance_to(pth[i - 1])
		print("  %-22s %5.1f m  %4.1f s" % [pair[0], dd, dd / 2.5])
	get_tree().quit()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not free_look:
		return
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * 0.15
		pitch = clampf(pitch - event.relative.y * 0.15, -89, 89)
		cam.rotation_degrees = Vector3(pitch, yaw, 0)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_capture("out/level/free_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))


func _process(delta: float) -> void:
	if not free_look:
		return
	var d := Vector3.ZERO
	if Input.is_action_pressed(&"move_forward"): d -= cam.global_transform.basis.z
	if Input.is_action_pressed(&"move_back"): d += cam.global_transform.basis.z
	if Input.is_action_pressed(&"move_left"): d -= cam.global_transform.basis.x
	if Input.is_action_pressed(&"move_right"): d += cam.global_transform.basis.x
	cam.global_position += d.normalized() * delta * 4.0
