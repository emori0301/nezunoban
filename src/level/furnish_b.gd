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

	# 燭台(左右)。消灯してもここの暖色だけは残る。
	b.add_prop(R, "CandleStandL", "candle_stand", Vector3(18.1, 0.0, -1.95), 90.0,
		Vector3(0.22, 1.05, 0.22), Color(0.45, 0.38, 0.18))
	b.add_prop(R, "CandleStandR", "candle_stand", Vector3(18.1, 0.0, 0.95), 90.0,
		Vector3(0.22, 1.05, 0.22), Color(0.45, 0.38, 0.18))
	var candle := b.add_anchor(R, "Anchor_Candle", Vector3(18.1, 0.72, -1.95), 90.0)
	var cl := OmniLight3D.new()
	cl.name = "Light"        # systems がロウソクを消すときに使う
	cl.light_color = CANDLE
	cl.light_energy = 1.45
	cl.omni_range = 5.2
	cl.omni_attenuation = 1.8
	# 燭台は床から 0.9m と低いので、影を出すと棺と祭壇の影が天井一面に伸びる。
	# 灯明は「暖かい光が届く」ことが役目なので影は切る。
	cl.shadow_enabled = false
	cl.light_specular = 0.0
	cl.position = Vector3(0, 0.18, 0)
	candle.add_child(cl)
	LevelBuild.box(candle, Vector3(0, 0.06, 0), Vector3(0.035, 0.05, 0.035),
		LevelMaterials.emissive(Color(1.0, 0.82, 0.5), 2.2), false, "", false)
	# 右の燭台。Anchor_Candle の子なので systems は灯明をまとめて扱える。
	var cl2: OmniLight3D = cl.duplicate()
	cl2.name = "Light2"
	cl2.light_energy = 1.2
	cl2.position = Vector3(-2.9, 0.18, 0)
	candle.add_child(cl2)
	LevelBuild.box(candle, Vector3(-2.9, 0.06, 0), Vector3(0.035, 0.05, 0.035),
		LevelMaterials.emissive(Color(1.0, 0.82, 0.5), 2.2), false, "", false)

	# 供花スタンド(左右)
	b.add_anchor_prop(R, "Anchor_FlowerL", "flower_stand", Vector3(19.0, 0.0, -3.5), 90.0,
		Vector3(0.55, 1.75, 0.55), Color(0.55, 0.52, 0.45))
	b.add_anchor_prop(R, "Anchor_FlowerR", "flower_stand", Vector3(19.0, 0.0, 2.5), 90.0,
		Vector3(0.55, 1.75, 0.55), Color(0.55, 0.52, 0.45))

	# 折りたたみ椅子 5 列 x 4 行。中央(z = -0.5)は焼香の通路として空ける。
	const CHAIR_Z := [-3.0, -2.1, -1.2, 0.2, 1.1]
	for row in 4:
		for col in CHAIR_Z.size():
			b.add_prop(R, "Chair_%d_%d" % [row, col], "folding_chair",
				Vector3(10.9 + row * 1.0, 0.0, CHAIR_Z[col]), -90.0,
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
	b.add_anchor(R, "Spawn_Granddaughter", Vector3(10.35, 0.0, 1.1), -90.0)

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
	})


# -------------------------------------------------------------------- 外周

static func _outside(b: Building) -> void:
	const R := &"Room_Outside"
	var node := b.room_of(R)
	var asphalt := LevelMaterials.get_mat("asphalt", 0.4)
	var conc := LevelMaterials.get_mat("concrete", 0.5)
	var steel := LevelMaterials.get_mat("steel", 1.0)
	var paint := LevelMaterials.plain(Color(0.62, 0.61, 0.55))

	# 駐車場
	LevelBuild.box(node, Vector3(-20.0, -0.012, 0.0), Vector3(18.0, 0.02, 26.0), asphalt, false, "concrete", false)
	for i in 9:
		LevelBuild.box(node, Vector3(-22.5, 0.0, -10.0 + i * 2.5), Vector3(4.8, 0.012, 0.12),
			paint, false, "", false)
	# 建物まわりの犬走り
	LevelBuild.box(node, Vector3(-12.6, -0.008, 0.0), Vector3(3.4, 0.02, 12.0), conc, false, "concrete", false)

	# 玄関の庇
	LevelBuild.box(node, Vector3(-12.6, 2.28, 0.0), Vector3(3.45, 0.16, 4.2), conc, false, "", true)
	for pz in [-1.85, 1.85]:
		LevelBuild.box(node, Vector3(-14.15, 1.1, pz), Vector3(0.18, 2.2, 0.18), conc)
	b.add_bulb(R, Vector3(-12.6, 2.14, 0.0), Color(1.0, 0.88, 0.68), 1.5, 7.0, true)

	# 看板「やすらぎ会館」
	LevelBuild.box(node, Vector3(-11.1, 2.62, 0.0), Vector3(0.07, 0.52, 3.0),
		LevelMaterials.plain(Color(0.12, 0.12, 0.13)), false, "", false)
	LevelBuild.sign_text(node, "やすらぎ会館", Vector3(-11.15, 2.62, 0.0), -90.0,
		0.34, Color(0.86, 0.82, 0.70), true, 320)

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
	b.add_prop(R, "Hearse", "hearse", Vector3(-17.8, 0.0, -3.2), 6.0,
		Vector3(2.0, 1.75, 5.2), Color(0.09, 0.09, 0.11))

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
			Color(0.05, 0.06, 0.05))

	# 遠くの国道の街灯
	for lz in [-18.0, 0.0, 18.0]:
		LevelBuild.box(node, Vector3(-28.5, 3.5, lz), Vector3(0.16, 7.0, 0.16), steel)
		LevelBuild.box(node, Vector3(-28.0, 6.95, lz), Vector3(1.2, 0.12, 0.3), steel, false, "", false)
		b.add_bulb(R, Vector3(-27.5, 6.8, lz), Color(1.0, 0.80, 0.48), 1.5, 14.0, false)

	# 勝手口の外灯と車庫まわりの灯り(裏手が真っ暗で方向が分からなくなるのを防ぐ)
	LevelBuild.box(node, Vector3(0.0, 2.32, -7.72), Vector3(0.3, 0.14, 0.24),
		LevelMaterials.plain(Color(0.25, 0.25, 0.24)), false, "", false)
	b.add_bulb(R, Vector3(0.0, 2.2, -7.85), Color(1.0, 0.86, 0.62), 1.0, 6.5, true)
	LevelBuild.box(node, Vector3(-4.25, 2.55, -6.0), Vector3(0.3, 0.14, 0.24),
		LevelMaterials.plain(Color(0.25, 0.25, 0.24)), false, "", false)
	b.add_bulb(R, Vector3(-4.35, 2.42, -6.0), Color(1.0, 0.86, 0.62), 0.9, 6.0, true)

	# CCTV(玄関の外側上から)
	LevelBuild.box(node, Vector3(-11.3, 2.58, 2.45), Vector3(0.3, 0.16, 0.24),
		LevelMaterials.plain(Color(0.18, 0.18, 0.19)), false, "", false)
	var cam := b.add_anchor(R, "Anchor_Cam_Genkan", Vector3(-11.4, 2.56, 2.4), 0.0)
	_aim(cam, Vector3(-12.4, 0.9, -0.6))

	# スポーン(息子は玄関の外、猫は外周の各所)
	b.add_anchor(R, "Spawn_Son", Vector3(-13.2, 0.0, 0.0), -90.0)
	b.add_anchor(R, "Spawn_Cat1", Vector3(-13.4, 0.0, 7.4), -90.0)
	b.add_anchor(R, "Spawn_Cat2", Vector3(-19.5, 0.0, -4.5), -55.0)
	b.add_anchor(R, "Spawn_Cat3", Vector3(1.4, 0.0, -9.2), 180.0)
	b.add_anchor(R, "Spawn_Cat4", Vector3(11.2, 0.0, -10.4), 100.0)
	b.add_anchor(R, "Spawn_Cat5", Vector3(14.5, 0.0, 6.2), 15.0)


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
