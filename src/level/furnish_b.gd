class_name LevelFurnishB
extends RefCounted
## 式場・バックヤード・湯灌室・外周の作り込み。building.gd から呼ばれる。

const WOOD := Color(0.26, 0.19, 0.13)
const COOL := Color(0.84, 0.91, 1.0)
const CANDLE := Color(1.0, 0.62, 0.26)


static func build(b: Building) -> void:
	_shikijo(b)
	_backyard(b)
	_yukan(b)
	_outside(b)


## glb の中の特定マテリアルの発光量だけ後から変える(Prop が複製した override を書き換える)。
static func _tune_emission(p: Prop, mat_name: String, energy: float) -> void:
	var inst := p.get_instance()
	if inst == null:
		return
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i)
			if m is BaseMaterial3D and String(m.resource_name).findn(mat_name) >= 0:
				var bm := m as BaseMaterial3D
				bm.emission_enabled = true
				bm.emission_energy_multiplier = energy


## glb の中の特定マテリアル(複製された override)を集める。
static func _find_materials(p: Prop, mat_name: String) -> Array:
	var out: Array = []
	var inst := p.get_instance()
	if inst == null:
		return out
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i)
			if m is BaseMaterial3D and String(m.resource_name).findn(mat_name) >= 0:
				out.append(m)
	return out


## glb に入っているアニメをループ再生する(回転灯籠の spin など)。
static func _play_loop(p: Prop, anim: String) -> void:
	var inst := p.get_instance()
	if inst == null:
		return
	for n in inst.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		var name_found := ""
		if ap.has_animation(anim):
			name_found = anim
		else:
			for candidate in ap.get_animation_list():
				if String(candidate).ends_with(anim):
					name_found = String(candidate)
					break
		if name_found == "":
			continue
		var a := ap.get_animation(name_found)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
		ap.play(name_found)
		return


static func _aim(m: Node3D, target: Vector3) -> void:
	if m.is_inside_tree():
		m.look_at(target, Vector3.UP)


# ------------------------------------------------------------------------ 式場

static func _shikijo(b: Building) -> void:
	const R := &"Room_Shikijo"
	var node := b.room_of(R)
	# 織り目が細かいので 1 タイル 0.33m 相当まで詰める(大きな面で巨大な染みに見えるのを防ぐ)
	var cloth := LevelMaterials.get_mat("white_cloth", 3.0)
	var brocade := LevelMaterials.get_mat("brocade", 1.0)
	var wood := LevelMaterials.get_mat("wood_dark", 1.0)

	# 白い幕(壁に沿って高さ 1.2〜2.6m)
	LevelBuild.box(node, Vector3(13.5, 1.9, -4.39), Vector3(11.9, 1.4, 0.04), cloth, false, "", false)
	LevelBuild.box(node, Vector3(9.7, 1.9, 3.39), Vector3(4.3, 1.4, 0.04), cloth, false, "", false)
	LevelBuild.box(node, Vector3(16.9, 1.9, 3.39), Vector3(5.1, 1.4, 0.04), cloth, false, "", false)
	# 祭壇の背面(金襴)
	LevelBuild.box(node, Vector3(19.39, 1.7, -0.5), Vector3(0.04, 2.6, 4.6), brocade, false, "", false)

	# --- 祭壇まわり -----------------------------------------------------------
	# 祭壇と遺影の glb は飾り面がローカル +Z 側。アンカーの向き(-Z が正面 = 西)のまま置くと
	# 壁を向いてしまうので、Prop だけ yaw -90 にして西を向かせる。
	b.add_anchor_prop(R, "Anchor_Altar", "altar", Vector3(18.55, 0.0, -0.5), 90.0,
		Vector3(3.3, 1.5, 1.45), Color(0.80, 0.78, 0.72), true, -90.0)
	b.add_anchor_prop(R, "Anchor_Iei", "iei_frame", Vector3(18.72, 1.5, -0.5), 90.0,
		Vector3(0.52, 0.62, 0.07), Color(0.10, 0.09, 0.09), false, -90.0)

	# 棺と棺台
	LevelBuild.box(node, Vector3(16.9, 0.22, -0.5), Vector3(2.15, 0.44, 0.98), cloth)
	b.add_anchor_prop(R, "Anchor_Coffin", "coffin", Vector3(16.9, 0.44, -0.5), 90.0,
		Vector3(0.58, 0.52, 1.92), Color(0.76, 0.74, 0.70))

	# 焼香台(棺の手前)
	LevelBuild.box(node, Vector3(15.1, 0.37, -0.5), Vector3(0.95, 0.74, 0.58), wood)
	LevelBuild.box(node, Vector3(15.1, 0.755, -0.5), Vector3(1.05, 0.03, 0.66), cloth, false, "", false)
	b.add_anchor_prop(R, "Anchor_IncenseStand", "incense_stand", Vector3(15.1, 0.77, -0.5), 90.0,
		Vector3(0.28, 0.16, 0.26), Color(0.32, 0.28, 0.22), false)
	b.add_anchor_prop(R, "Anchor_IncenseBox", "incense_box", Vector3(14.78, 0.48, -0.5), 90.0,
		Vector3(0.12, 0.05, 0.22), Color(0.55, 0.42, 0.28), false)

	# 燭台(左右)。glb は高さ 0.46m で原点が床なので、アンカーも床(y=0)に置く。
	# 灯明の光だけは炎より上の 0.9m に保つ(消灯しても祭壇まわりが完全に沈まないため)。
	var candle := b.add_anchor_prop(R, "Anchor_Candle", "candle_stand",
		Vector3(18.1, 0.0, -1.95), 90.0, Vector3(0.22, 0.46, 0.22), Color(0.45, 0.38, 0.18), false)
	b.add_prop(R, "CandleStandR", "candle_stand", Vector3(18.1, 0.0, 0.95), 90.0,
		Vector3(0.22, 0.46, 0.22), Color(0.45, 0.38, 0.18), false)
	var cl := OmniLight3D.new()
	cl.name = "Light"        # systems がロウソクを消すときに使う
	cl.light_color = CANDLE
	cl.light_energy = 1.45
	cl.omni_range = 5.2
	cl.omni_attenuation = 1.8
	# 燭台は床置きで低いので、影を出すと棺と祭壇の影が天井一面に伸びる。
	cl.shadow_enabled = false
	cl.light_specular = 0.0
	cl.position = Vector3(0, 0.9, 0)
	candle.add_child(cl)
	# 右の燭台。yaw 90 なのでローカル -X が世界 +Z。
	var cl2: OmniLight3D = cl.duplicate()
	cl2.name = "Light2"
	cl2.light_energy = 1.2
	cl2.position = Vector3(-2.9, 0.9, 0)
	candle.add_child(cl2)

	# 供花スタンド(左右)
	b.add_anchor_prop(R, "Anchor_FlowerL", "flower_stand", Vector3(19.0, 0.0, -3.5), 90.0,
		Vector3(0.55, 1.75, 0.55), Color(0.55, 0.52, 0.45))
	b.add_anchor_prop(R, "Anchor_FlowerR", "flower_stand", Vector3(19.0, 0.0, 2.5), 90.0,
		Vector3(0.55, 1.75, 0.55), Color(0.55, 0.52, 0.45))

	# 折りたたみ椅子 5 列 x 4 行。中央(z = -0.5)は焼香の通路として空ける。
	# 中央(z = -0.5)は焼香の通路。行の間にも 1.0m の横通路を入れて 4 ブロックに割る。
	# 椅子はナビの障害物なので、通路が無いと人が椅子の間に閉じ込められる。
	const CHAIR_Z := [-3.0, -2.1, -1.2, 0.2, 1.1]
	const CHAIR_X := [10.7, 11.6, 13.1, 14.0]
	for row in CHAIR_X.size():
		for col in CHAIR_Z.size():
			b.add_prop(R, "Chair_%d_%d" % [row, col], "folding_chair",
				Vector3(CHAIR_X[row], 0.0, CHAIR_Z[col]), -90.0,
				Vector3(0.46, 0.86, 0.5), Color(0.20, 0.20, 0.22))

	# 窓
	b.add_window(R, "Window_Shikijo", Vector3(13.0, 1.67, 3.5), 0.0,
		{"pane_width": 1.8, "pane_height": 1.32})

	# CCTV(後方上隅から棺を見る)
	LevelBuild.box(node, Vector3(8.1, 2.95, -4.1), Vector3(0.24, 0.16, 0.3),
		LevelMaterials.plain(Color(0.18, 0.18, 0.19)), false, "", false)
	var cam := b.add_anchor(R, "Anchor_Cam_Shikijo", Vector3(8.1, 2.93, -4.05), 0.0)
	_aim(cam, Vector3(16.9, 0.7, -0.5))

	# 孫娘は後列に残っている
	b.add_anchor(R, "Spawn_Granddaughter", Vector3(9.8, 0.0, 1.3), -90.0)

	# 祭壇スポット(天井の埋め込みダウンライト2灯)。蛍光灯とは別系統で、
	# set_room_lights では消えず set_all_lights(false) でだけ落ちる。影は出さない。
	#   A: 遺影と三段祭壇の正面  /  B: 棺の手前を薄く起こすだけ
	for cfg in [
			{"name": "Light_AltarSpot", "pos": Vector3(17.2, 3.12, -0.5),
			 "aim": Vector3(18.62, 1.78, -0.5), "angle": 27.0, "energy": 1.9},
			{"name": "Light_CoffinSpot", "pos": Vector3(15.4, 3.12, -0.5),
			 "aim": Vector3(16.9, 0.8, -0.5), "angle": 25.0, "energy": 1.05},
		]:
		var spot := SpotLight3D.new()
		spot.name = String(cfg["name"])
		spot.position = cfg["pos"]
		spot.light_color = Color(1.0, 0.87, 0.68)
		spot.light_energy = float(cfg["energy"])
		spot.spot_range = 7.0
		spot.spot_angle = float(cfg["angle"])
		spot.spot_angle_attenuation = 0.9
		spot.spot_attenuation = 1.1
		spot.shadow_enabled = false
		spot.light_specular = 0.0
		node.add_child(spot)
		spot.look_at(cfg["aim"], Vector3.UP)
		b.add_aux_light(R, spot)

	# 回転灯籠。祭壇の左右、供花スタンドの手前。祭壇スポットと同じ aux 系統で、
	# set_room_lights では消えず set_all_lights(false) で落ちる。
	for lz in [-3.3, 2.3]:
		var lan := b.add_prop(R, "Lantern_%d" % int(lz * 10), "lantern_rotating",
			Vector3(18.3, 0.0, lz), 0.0, Vector3(0.36, 0.96, 0.36), Color(0.78, 0.62, 0.32), false)
		var ll := OmniLight3D.new()
		ll.name = "Light"
		ll.position = Vector3(0, 0.62, 0)
		ll.light_color = Color(1.0, 0.80, 0.50)
		ll.light_energy = 0.6
		ll.omni_range = 3.0
		ll.omni_attenuation = 1.4
		ll.shadow_enabled = false
		ll.light_specular = 0.0
		lan.add_child(ll)
		b.add_aux_light(R, ll)
		# 紙と火袋は glb 側が光っているので、こちらも aux 系統に載せて一緒に落とす
		for mn in ["Paper", "LanternInner"]:
			for m in _find_materials(lan, mn):
				b.add_aux_material(R, m)
		_play_loop(lan, "spin")

	# 焼香の作法の掲示(式場の入口脇、廊下側)
	var hallnode := b.room_of(&"Room_Hall")
	LevelBuild.box(hallnode, Vector3(6.55, 1.48, 1.01), Vector3(0.46, 0.62, 0.02),
		LevelMaterials.plain(Color(0.30, 0.28, 0.24)), false, "", false)
	LevelBuild.box(hallnode, Vector3(6.55, 1.48, 0.998), Vector3(0.40, 0.55, 0.006),
		LevelMaterials.plain(Color(0.84, 0.83, 0.78)), false, "", false)
	for ly in [1.66, 1.56, 1.46, 1.36]:
		LevelBuild.box(hallnode, Vector3(6.57, ly, 0.992), Vector3(0.30, 0.012, 0.004),
			LevelMaterials.plain(Color(0.22, 0.22, 0.24)), false, "", false)
	LevelBuild.sign_text(hallnode, "焼香の作法", Vector3(6.55, 1.72, 0.99), 180.0,
		0.055, Color(0.10, 0.10, 0.11), true, 256)

	# 非常口サイン(入口の引き分け戸の上、室内から見える向き)
	b.add_exit_sign(R, Vector3(7.72, 2.55, 0.0), 90.0)

	# 照明(蛍光灯 4 本。落とすと燭台の暖色と祭壇スポットだけが残る)
	for p in [[10.2, -2.6], [10.2, 1.6], [15.4, -2.6], [15.4, 1.6]]:
		b.add_fluorescent(R, Vector3(p[0], 3.08, p[1]), 1.35, COOL, 0.85, 6.4, true)


# -------------------------------------------------------------- バックヤード

static func _backyard(b: Building) -> void:
	const R := &"Room_Backyard"
	var node := b.room_of(R)
	var steel := LevelMaterials.get_mat("steel", 1.0)
	var conc := LevelMaterials.get_mat("concrete", 1.0)

	b.add_anchor_prop(R, "Anchor_Freezer", "freezer_chest", Vector3(3.6, 0.0, -6.3), 180.0,
		Vector3(1.4, 0.9, 0.72), Color(0.72, 0.73, 0.74), true, 0.0)
	b.add_anchor_prop(R, "Anchor_Sink", "sink", Vector3(-3.55, 0.0, -3.2), -90.0,
		Vector3(0.95, 0.85, 0.55), Color(0.55, 0.57, 0.6))
	b.add_anchor_prop(R, "Anchor_Breaker", "breaker_box", Vector3(5.14, 1.3, -6.3), 90.0,
		Vector3(0.44, 0.52, 0.13), Color(0.55, 0.55, 0.52), false, -90.0)

	# 在庫棚
	b.add_prop(R, "Shelf_Stock1", "shelf", Vector3(-3.0, 0.0, -7.05), 0.0,
		Vector3(1.7, 2.0, 0.45), WOOD)
	b.add_prop(R, "Shelf_Stock2", "shelf", Vector3(2.4, 0.0, -7.05), 0.0,
		Vector3(1.7, 2.0, 0.45), WOOD)
	b.add_prop(R, "Shelf_Stock3", "shelf", Vector3(4.85, 0.0, -2.6), -90.0,
		Vector3(1.7, 2.0, 0.45), WOOD)
	b.add_prop(R, "DryIceBox", "dry_ice_box", Vector3(1.9, 0.0, -6.3), 0.0,
		Vector3(0.58, 0.42, 0.42), Color(0.45, 0.46, 0.48))

	# 作業台・段ボール・台車
	LevelBuild.box(node, Vector3(0.4, 0.42, -2.3), Vector3(1.9, 0.84, 0.72), steel)
	for cb in [[-2.6, -1.9, 0.0], [-2.6, -1.9, 0.42], [-1.7, -2.4, 0.0]]:
		LevelBuild.box(node, Vector3(cb[0], cb[2] + 0.21, cb[1]), Vector3(0.6, 0.42, 0.5),
			LevelMaterials.plain(Color(0.42, 0.33, 0.22)))
	LevelBuild.box(node, Vector3(4.6, 0.12, -2.0), Vector3(0.7, 0.24, 1.1), steel)

	# 霊柩車の車庫へ続く扉(飾り)
	LevelBuild.box(node, Vector3(-3.88, 1.2, -6.0), Vector3(0.09, 2.4, 2.6), steel, false, "", false)

	# 勝手口(鉄扉)
	b.add_door(R, "Door_Backyard", Vector3(0.0, 0.0, -7.5), 0.0, {
		"kind": Door.Kind.SWING, "door_width": 0.95, "door_height": 2.0,
		"door_thickness": 0.07, "steel": true, "hinge_side": -1.0, "swing_degrees": -92.0,
	})

	LevelBuild.box(node, Vector3(0.0, 0.01, -7.1), Vector3(1.2, 0.03, 0.7), conc, false, "concrete", false)

	# 非常口サイン(勝手口の上、室内から見える向き)
	b.add_exit_sign(R, Vector3(0.0, 2.2, -7.33), 0.0)

	b.add_fluorescent(R, Vector3(-1.0, 2.46, -3.2), 1.25, COOL, 0.9, 5.8, true)
	b.add_fluorescent(R, Vector3(3.0, 2.46, -6.0), 1.25, COOL, 0.9, 5.8, true)


# ------------------------------------------------------------------- 湯灌室

static func _yukan(b: Building) -> void:
	const R := &"Room_Yukan"
	var node := b.room_of(R)
	var steel := LevelMaterials.get_mat("steel", 1.0)

	# ステンレスの台
	LevelBuild.box(node, Vector3(7.3, 0.4, -9.9), Vector3(2.0, 0.8, 0.85), steel)
	LevelBuild.box(node, Vector3(7.3, 0.83, -9.9), Vector3(2.1, 0.06, 0.95), steel, false, "", false)
	# 排水口
	LevelBuild.box(node, Vector3(7.3, 0.005, -8.6), Vector3(0.32, 0.03, 0.32),
		LevelMaterials.plain(Color(0.10, 0.10, 0.11)), false, "", false)
	# 棚・桶
	b.add_prop(R, "Shelf_Yukan", "shelf", Vector3(5.65, 0.0, -10.5), 90.0,
		Vector3(1.4, 1.5, 0.4), WOOD)
	LevelBuild.box(node, Vector3(5.8, 0.15, -8.4), Vector3(0.45, 0.3, 0.45),
		LevelMaterials.plain(Color(0.5, 0.45, 0.35)))

	# 白装束が吊られたハンガー。director が揺らせるよう Node3D をピボットにする。
	# ピボットはモデルのフック(原点から +Y 2.0m)と同じ高さに置いてあるので、
	# Yukan_Robe を X / Z 軸まわりに回すとフックを支点に振れる。
	var robe := Node3D.new()
	robe.name = "Yukan_Robe"
	robe.position = Vector3(8.65, 2.0, -10.5)
	node.add_child(robe)
	LevelBuild.prop(robe, "Robe", "hanging_robe", Vector3(0, -2.0, 0), 0.0,
		Vector3(0.56, 1.5, 0.1), Color(0.82, 0.81, 0.78), false)
	# 吊り下げレール
	LevelBuild.box(node, Vector3(8.65, 2.0, -10.0), Vector3(0.04, 0.04, 1.6),
		LevelMaterials.plain(Color(0.45, 0.46, 0.48)), false, "", false)

	b.add_anchor(R, "Spawn_Kasha", Vector3(7.3, 0.0, -11.0), 180.0)

	b.add_fluorescent(R, Vector3(7.3, 2.28, -9.6), 1.1, Color(0.88, 0.94, 1.0), 0.6, 4.0, true)

	b.add_door(R, "Door_Yukan", Vector3(6.4, 0.0, -7.5), 0.0, {
		"kind": Door.Kind.SWING, "door_width": 0.95, "door_height": 2.0,
		"hinge_side": 1.0, "swing_degrees": -92.0, "locked": true,
		"panel_color": Color(0.90, 0.94, 0.92), "panel_tex": "wall_plaster",
	})
	LevelBuild.name_plate(b.room_of(&"Room_Hall"), "湯灌室", Vector3(5.72, 1.62, -7.41), 0.0)


# -------------------------------------------------------------------- 外周

static func _outside(b: Building) -> void:
	const R := &"Room_Outside"
	var node := b.room_of(R)
	var asphalt := LevelMaterials.get_mat("asphalt", 0.4)
	var conc := LevelMaterials.get_mat("concrete", 0.5)
	var steel := LevelMaterials.get_mat("steel", 1.0)
	var paint := LevelMaterials.plain(Color(0.46, 0.45, 0.41))

	# 駐車場
	LevelBuild.box(node, Vector3(-20.0, -0.012, 0.0), Vector3(18.0, 0.02, 26.0), asphalt, false, "concrete", false)
	for i in 9:
		LevelBuild.box(node, Vector3(-22.5, 0.0, -10.0 + i * 2.5), Vector3(4.8, 0.012, 0.12),
			paint, false, "", false)
	# 区画の頭の白線と車止め
	LevelBuild.box(node, Vector3(-22.5, 0.0, 0.0), Vector3(0.12, 0.012, 20.2), paint, false, "", false)
	for j in 8:
		var bz: float = -8.75 + j * 2.5
		# 12cm の段差に当たり判定を付けると歩きが引っかかるので飾りのみ
		LevelBuild.box(node, Vector3(-20.7, 0.06, bz), Vector3(0.5, 0.12, 0.62),
			LevelMaterials.get_mat_tinted("concrete", 2.0, Color(0.34, 0.34, 0.33)), false, "", false)

	# 建物まわりの犬走り
	LevelBuild.box(node, Vector3(-12.6, -0.008, 0.0), Vector3(3.4, 0.02, 12.0), conc, false, "concrete", false)

	# 玄関の庇
	LevelBuild.box(node, Vector3(-12.6, 2.28, 0.0), Vector3(3.45, 0.16, 4.2), conc, false, "", true)
	for pz in [-1.85, 1.85]:
		LevelBuild.box(node, Vector3(-14.15, 1.1, pz), Vector3(0.18, 2.2, 0.18), conc)
	b.add_bulb(R, Vector3(-12.6, 2.14, 0.0), Color(1.0, 0.88, 0.68), 2.1, 9.5, true)
	# 玄関口の灯り。CCTV に外に立つ人影が映るよう、ポーチの床まで届かせる。
	b.add_bulb(R, Vector3(-11.7, 2.12, 0.0), Color(1.0, 0.86, 0.64), 1.2, 6.5, false)

	# 花輪。自動ドアの両脇に2基ずつ、建物の西面に沿って並べる。
	for wr in [[-1.55, "贈 春日家親戚一同"], [-2.95, "贈 やすらぎ会館"],
			[1.55, "贈 春日 誠"], [2.95, "贈 白川商事株式会社"]]:
		_wreath(node, Vector3(-11.75, 0.0, float(wr[0])), -90.0, String(wr[1]))

	# 看板「やすらぎ会館」。庇の上、白地に黒。下から弱く照らす。
	LevelBuild.box(node, Vector3(-11.10, 2.63, 0.0), Vector3(0.08, 0.5, 2.9),
		LevelMaterials.plain(Color(0.22, 0.22, 0.23)), false, "", false)
	LevelBuild.box(node, Vector3(-11.15, 2.63, 0.0), Vector3(0.02, 0.42, 2.76),
		LevelMaterials.plain(Color(0.88, 0.87, 0.83)), false, "", false)
	LevelBuild.sign_text(node, "やすらぎ会館", Vector3(-11.17, 2.63, 0.0), -90.0,
		0.32, Color(0.07, 0.07, 0.08), true, 384)
	for sz in [-0.95, 0.95]:
		LevelBuild.box(node, Vector3(-11.42, 2.44, sz), Vector3(0.22, 0.07, 0.1),
			LevelMaterials.plain(Color(0.25, 0.25, 0.26)), false, "", false)
	var sign_light := OmniLight3D.new()
	sign_light.name = "Light_Sign"
	sign_light.position = Vector3(-11.5, 2.5, 0.0)
	sign_light.light_color = Color(1.0, 0.93, 0.80)
	sign_light.light_energy = 0.9
	sign_light.omni_range = 3.4
	sign_light.omni_attenuation = 1.5
	sign_light.shadow_enabled = false
	sign_light.light_specular = 0.0
	node.add_child(sign_light)
	b.add_light(R, sign_light)

	# 自販機。前面は glb の Panel マテリアル(vending_panel テクスチャ)が光るので板を重ねない。
	# glb の前面(Panel)はローカル +Z 側なので、西を向かせるには yaw = -90。
	var vend := b.add_prop(R, "VendingMachine", "vending_machine", Vector3(-11.5, 0.0, 6.2), -90.0,
		Vector3(1.15, 1.9, 0.75), Color(0.30, 0.16, 0.16))
	_tune_emission(vend, "Panel", 1.3)
	# 商品見本を照らす弱い光。自販機の手前に置いて足元だけ照らす(影は切って壁に黒板が出ないように)
	var vl := OmniLight3D.new()
	vl.name = "VendingGlow"
	vl.position = Vector3(-12.7, 0.95, 6.2)
	vl.light_color = Color(0.86, 0.92, 1.0)
	vl.light_energy = 1.0
	vl.omni_range = 4.2
	vl.omni_attenuation = 1.7
	vl.shadow_enabled = false
	vl.light_specular = 0.0
	node.add_child(vl)
	b.add_light(R, vl)

	# 霊柩車
	# 停めてある車なのでヘッドライトは消す(glb は点灯状態で作られている)
	var hearse := b.add_prop(R, "Hearse", "hearse", Vector3(-17.8, 0.0, -3.2), 6.0,
		Vector3(2.0, 1.75, 5.2), Color(0.09, 0.09, 0.11))
	_tune_emission(hearse, "HeadLight", 0.0)
	_tune_emission(hearse, "TailLight", 0.0)

	# フェンス
	_fence(node, -30.0, -14.0, -30.0, 14.0, steel)
	_fence(node, -30.0, -14.0, -11.5, -14.0, steel)
	_fence(node, -30.0, 14.0, -11.5, 14.0, steel)
	_fence(node, 22.0, -16.0, 22.0, 14.0, steel)

	# 暗い木々
	for t in [[24.5, -8.0], [26.0, 4.5], [23.0, 11.0], [-24.0, -20.0], [11.0, -18.0],
			[-8.0, 17.0], [4.0, 15.0], [18.0, -15.0], [-26.0, 19.0], [14.0, 12.0]]:
		b.add_prop(R, "Tree_%d_%d" % [int(t[0]), int(t[1])], "tree",
			Vector3(t[0], 0.0, t[1]), randf_range(0, 360), Vector3(1.7, 5.2, 1.7),
			Color(0.05, 0.06, 0.05), true, false)

	# 勝手口の外灯と車庫まわりの灯り(裏手が真っ暗で方向が分からなくなるのを防ぐ)
	LevelBuild.box(node, Vector3(0.0, 2.32, -7.72), Vector3(0.3, 0.14, 0.24),
		LevelMaterials.plain(Color(0.25, 0.25, 0.24)), false, "", false)
	b.add_bulb(R, Vector3(0.0, 2.2, -7.85), Color(1.0, 0.86, 0.62), 1.0, 6.5, true)
	LevelBuild.box(node, Vector3(-4.25, 2.55, -6.0), Vector3(0.3, 0.14, 0.24),
		LevelMaterials.plain(Color(0.25, 0.25, 0.24)), false, "", false)
	b.add_bulb(R, Vector3(-4.35, 2.42, -6.0), Color(1.0, 0.86, 0.62), 0.9, 6.0, true)

	# 遠景の民家。空(地平線 0.04)より少しだけ明るくして、切妻のシルエットが読めるようにする。
	var night_wall := LevelMaterials.plain(Color(0.048, 0.050, 0.058))
	var night_roof := LevelMaterials.plain(Color(0.036, 0.038, 0.046))
	# [x, z, 高さ, 窓の幅, 窓の高さ, 窓の色, 発光量]
	for hs in [
			[-49.0, 27.0, 5.0, 1.15, 1.25, Color(1.0, 0.84, 0.54), 1.5],   # 近い: カーテン越しの暖色
			[-54.0, -24.0, 4.4, 0.85, 0.95, Color(1.0, 0.88, 0.62), 1.1],
			[-61.0, 7.0, 3.8, 0.7, 0.8, Color(0.64, 0.78, 1.0), 1.25],     # 青白い TV の光
			[-66.0, -9.0, 4.0, 0.55, 0.62, Color(1.0, 0.86, 0.60), 0.7],   # 遠い: 小さく暗く
		]:
		var hx: float = hs[0]
		var hz: float = hs[1]
		var hh: float = hs[2]
		LevelBuild.box(node, Vector3(hx, hh * 0.5, hz), Vector3(9.0, hh, 8.0), night_wall, false, "", false)
		_gable(node, Vector3(hx, hh, hz), 9.6, 8.6, 2.1, night_roof)
		var wmat := LevelMaterials.emissive(hs[5], float(hs[6]))
		for wz in [-1.9, 1.9]:
			LevelBuild.box(node, Vector3(hx + 4.55, hh * 0.55, hz + wz),
				Vector3(0.06, float(hs[4]), float(hs[3])), wmat, false, "", false)

	# 電柱と電線(国道側)。3 本にはナトリウム灯を付けて遠くのアスファルトを橙に照らす。
	var pole_mat := LevelMaterials.get_mat_tinted("concrete", 1.0, Color(0.42, 0.42, 0.42))
	var wire_mat := LevelMaterials.plain(Color(0.05, 0.05, 0.06))
	var sodium := LevelMaterials.emissive(Color(1.0, 0.63, 0.24), 2.0)
	const POLE_Z := [-20.0, -4.0, 12.0, 28.0]
	const LAMP_Z := [-20.0, -4.0, 12.0]
	for pz in POLE_Z:
		LevelBuild.box(node, Vector3(-31.6, 4.2, pz), Vector3(0.22, 8.4, 0.22), pole_mat, true, "", false)
		LevelBuild.box(node, Vector3(-31.6, 7.9, pz), Vector3(1.5, 0.09, 0.09), pole_mat, false, "", false)
		LevelBuild.box(node, Vector3(-31.6, 7.35, pz), Vector3(1.1, 0.08, 0.08), pole_mat, false, "", false)
		if LAMP_Z.has(pz):
			# 腕金を車道側(+X)へ伸ばし、先に橙の灯具
			LevelBuild.box(node, Vector3(-30.7, 6.9, pz), Vector3(1.9, 0.08, 0.08), pole_mat, false, "", false)
			LevelBuild.box(node, Vector3(-29.85, 6.78, pz), Vector3(0.62, 0.1, 0.3),
				LevelMaterials.plain(Color(0.30, 0.30, 0.31)), false, "", false)
			LevelBuild.box(node, Vector3(-29.85, 6.70, pz), Vector3(0.5, 0.05, 0.22), sodium, false, "", false)
			var sl := OmniLight3D.new()
			sl.name = "Light_Sodium"
			sl.position = Vector3(-29.85, 6.6, pz)
			sl.light_color = Color(1.0, 0.64, 0.28)
			sl.light_energy = 1.7
			sl.omni_range = 12.0
			sl.omni_attenuation = 1.5
			sl.shadow_enabled = false
			sl.light_specular = 0.0
			node.add_child(sl)
			b.add_light(R, sl)
	for wi in POLE_Z.size() - 1:
		var z0: float = POLE_Z[wi]
		var z1: float = POLE_Z[wi + 1]
		for wy in [7.86, 7.62, 7.32]:
			LevelBuild.box(node, Vector3(-31.6, wy, (z0 + z1) * 0.5),
				Vector3(0.035, 0.035, z1 - z0), wire_mat, false, "", false)

	# 霊柩車の周りの水たまり(反射はしない暗い板)
	var puddle := LevelMaterials.plain(Color(0.028, 0.030, 0.038), 0.15)
	for pd in [[-17.2, -0.4, 2.6, 1.7], [-19.4, -5.6, 1.9, 1.2], [-15.8, -6.4, 1.4, 2.1],
			[-21.2, -1.8, 1.2, 1.0]]:
		LevelBuild.box(node, Vector3(pd[0], 0.002, pd[1]), Vector3(pd[2], 0.008, pd[3]),
			puddle, false, "", false)

	# CCTV(玄関の外側)。庇(下端 y=2.20)より下に潜らせないと、画が庇で黒く潰れる。
	LevelBuild.box(node, Vector3(-11.18, 2.12, 1.72), Vector3(0.3, 0.16, 0.24),
		LevelMaterials.plain(Color(0.18, 0.18, 0.19)), false, "", false)
	var cam := b.add_anchor(R, "Anchor_Cam_Genkan", Vector3(-11.24, 2.08, 1.66), 0.0)
	_aim(cam, Vector3(-13.9, 0.75, -0.35))

	# スポーン(息子は玄関の外、猫は外周の各所)
	b.add_anchor(R, "Spawn_Son", Vector3(-13.2, 0.0, 0.0), -90.0)
	b.add_anchor(R, "Spawn_Cat1", Vector3(-13.4, 0.0, 7.4), -90.0)
	b.add_anchor(R, "Spawn_Cat2", Vector3(-19.5, 0.0, -4.5), -55.0)
	b.add_anchor(R, "Spawn_Cat3", Vector3(1.4, 0.0, -9.2), 180.0)
	b.add_anchor(R, "Spawn_Cat4", Vector3(11.2, 0.0, -10.4), 100.0)
	b.add_anchor(R, "Spawn_Cat5", Vector3(14.5, 0.0, 6.2), 15.0)


## 花輪(花環)。丸い輪に白菊と黄菊、下に贈り主の札。影は出さない。
static func _wreath(parent: Node3D, pos: Vector3, yaw: float, giver: String) -> void:
	var holder := Node3D.new()
	holder.name = "Wreath"
	holder.position = pos
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	var frame := LevelMaterials.get_mat_tinted("wall_wood", 3.0, Color(0.55, 0.44, 0.30))
	# 三脚
	LevelBuild.box(holder, Vector3(0, 0.62, 0), Vector3(0.07, 1.24, 0.07), frame, false, "", false)
	for fs in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0, 0.34, 0)
		leg.rotation.z = fs * 0.22
		holder.add_child(leg)
		LevelBuild.box(leg, Vector3.ZERO, Vector3(0.05, 0.72, 0.05), frame, false, "", false)
	# 輪(白菊と黄菊を交互に)
	var white := LevelMaterials.plain(Color(0.86, 0.85, 0.80))
	var yellow := LevelMaterials.plain(Color(0.80, 0.70, 0.26))
	var green := LevelMaterials.plain(Color(0.24, 0.30, 0.21))
	LevelBuild.box(holder, Vector3(0, 1.74, -0.02), Vector3(0.78, 0.78, 0.03), green, false, "", false)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var seg := Node3D.new()
		seg.position = Vector3(sin(a) * 0.4, 1.74 + cos(a) * 0.4, 0.01)
		seg.rotation.z = -a
		holder.add_child(seg)
		LevelBuild.box(seg, Vector3.ZERO, Vector3(0.22, 0.17, 0.06),
			white if i % 2 == 0 else yellow, false, "", false)
	# 贈り主の札
	LevelBuild.box(holder, Vector3(0, 0.92, 0.05), Vector3(0.30, 0.62, 0.02), frame, false, "", false)
	LevelBuild.box(holder, Vector3(0, 0.92, 0.062), Vector3(0.25, 0.56, 0.006),
		LevelMaterials.plain(Color(0.88, 0.87, 0.82)), false, "", false)
	var l := LevelBuild.sign_text(holder, giver, Vector3(0, 0.92, 0.072), 0.0,
		0.062, Color(0.08, 0.08, 0.09), true, 256)
	l.width = 0.23 / l.pixel_size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## 切妻(きりづま)屋根。2 枚の板を傾けて載せる。
static func _gable(parent: Node3D, base: Vector3, width: float, depth: float,
		rise: float, mat: Material) -> void:
	var slope := atan2(rise, width * 0.5)
	var slab := sqrt(rise * rise + (width * 0.5) * (width * 0.5))
	for side in [-1.0, 1.0]:
		var holder := Node3D.new()
		holder.position = base + Vector3(side * width * 0.25, rise * 0.5, 0)
		holder.rotation.z = -side * slope
		parent.add_child(holder)
		LevelBuild.box(holder, Vector3.ZERO, Vector3(slab, 0.14, depth), mat, false, "", false)


static func _fence(parent: Node3D, x1: float, z1: float, x2: float, z2: float, mat: Material) -> void:
	var dx := x2 - x1
	var dz := z2 - z1
	var length := sqrt(dx * dx + dz * dz)
	if length < 0.1:
		return
	var seg := Node3D.new()
	seg.name = "Fence"
	seg.position = Vector3(x1, 0.0, z1)
	seg.rotation.y = atan2(-dz, dx)
	parent.add_child(seg)
	var n := int(length / 2.5)
	for i in n + 1:
		LevelBuild.box(seg, Vector3(i * 2.5, 0.65, 0), Vector3(0.09, 1.3, 0.09), mat, false, "", false)
	for y in [0.45, 1.15]:
		LevelBuild.box(seg, Vector3(length * 0.5, y, 0), Vector3(length, 0.06, 0.05), mat, false, "", false)
