class_name LevelFurnishA
extends RefCounted
## 玄関・事務所・廊下・控室・トイレの作り込み。building.gd から呼ばれる。

const WOOD := Color(0.26, 0.19, 0.13)
const PALE := Color(0.72, 0.70, 0.65)
const DARKGREY := Color(0.24, 0.24, 0.25)
const COOL := Color(0.84, 0.91, 1.0)
const WARM := Color(1.0, 0.90, 0.76)


static func build(b: Building) -> void:
	_genkan(b)
	_office(b)
	_hall(b)
	_hikaeshitsu(b)
	_toilet(b)


# ------------------------------------------------------------------ 玄関・受付

static func _genkan(b: Building) -> void:
	const R := &"Room_Genkan"
	var node := b.room_of(R)
	var wood := LevelMaterials.get_mat("wood_dark", 1.0)
	var conc := LevelMaterials.get_mat("concrete", 1.0)

	# 三和土(たたき)。玄関を入ってすぐのコンクリート部分。
	LevelBuild.box(node, Vector3(-10.2, 0.0, 0.0), Vector3(1.55, 0.02, 3.8), conc, false, "concrete", false)

	# 受付台
	var counter := LevelMaterials.get_mat("wall_wood", 0.8)
	LevelBuild.box(node, Vector3(-8.0, 0.5, -2.95), Vector3(3.0, 1.0, 0.62), counter)
	LevelBuild.box(node, Vector3(-8.0, 1.02, -2.9), Vector3(3.2, 0.05, 0.78), counter)
	LevelBuild.box(node, Vector3(-8.0, 0.52, -2.63), Vector3(2.9, 0.9, 0.03),
		LevelMaterials.plain(Color(0.55, 0.51, 0.44)), false, "", false)
	# 記帳台(芳名帳)は受付の手前に床置き
	b.add_anchor_prop(R, "Anchor_GuestBook", "guest_book_stand",
		Vector3(-6.5, 0.0, -2.4), 150.0, Vector3(0.5, 1.0, 0.4), Color(0.4, 0.33, 0.24), false, -30.0)

	# 下駄箱・傘立て・スリッパ
	b.add_prop(R, "ShoeCabinet", "cabinet", Vector3(-10.6, 0.0, 3.0), 90.0,
		Vector3(1.6, 1.15, 0.42), WOOD)
	b.add_prop(R, "UmbrellaStand", "umbrella_stand", Vector3(-10.5, 0.0, 2.0), 0.0,
		Vector3(0.36, 0.62, 0.36), Color(0.3, 0.32, 0.33))
	b.add_prop(R, "Slippers1", "slippers", Vector3(-10.4, 0.0, -2.2), 0.0,
		Vector3(1.0, 0.06, 0.62), Color(0.16, 0.16, 0.18), false)
	b.add_prop(R, "Slippers2", "slippers", Vector3(-10.4, 0.0, -1.3), 0.0,
		Vector3(1.0, 0.06, 0.62), Color(0.16, 0.16, 0.18), false)

	# 掲示板(南の壁)
	b.add_prop(R, "NoticeBoard", "notice_board", Vector3(-5.9, 1.0, 3.84), 180.0,
		Vector3(1.3, 0.95, 0.07), Color(0.32, 0.3, 0.26), false)

	# 案内看板「故 春日 キヨ 儀 葬儀式場」。入ってすぐ正面に見える向き(西向き)。
	LevelBuild.box(node, Vector3(-8.5, 0.45, 1.4), Vector3(0.09, 0.9, 0.85), wood)
	LevelBuild.box(node, Vector3(-8.5, 1.52, 1.4), Vector3(0.09, 1.25, 1.62), wood)
	LevelBuild.box(node, Vector3(-8.56, 1.52, 1.4), Vector3(0.02, 1.08, 1.48),
		LevelMaterials.plain(Color(0.88, 0.86, 0.8)), false)
	LevelBuild.sign_text(node, "故 春日 キヨ 儀\n葬儀式場", Vector3(-8.58, 1.55, 1.4), -90.0,
		0.165, Color(0.03, 0.03, 0.04), true, 384)

	# 受付まわりの小物
	b.add_prop(R, "ReceptionFlower", "flower_stand", Vector3(-6.3, 0.0, -3.3), 180.0,
		Vector3(0.5, 1.1, 0.5), Color(0.5, 0.45, 0.4))
	LevelBuild.box(node, Vector3(-9.4, 1.07, -2.9), Vector3(0.22, 0.04, 0.3),
		LevelMaterials.plain(Color(0.8, 0.78, 0.72)), false)

	# 照明(電球色。切ると真っ暗)
	b.add_fluorescent(R, Vector3(-9.2, 2.6, -1.6), 1.2, WARM, 0.85, 6.2, true)
	b.add_fluorescent(R, Vector3(-6.2, 2.6, 1.8), 1.2, WARM, 0.85, 6.2, true)
	b.add_bulb(R, Vector3(-8.0, 2.55, -2.2), WARM, 0.75, 4.2, true)

	# 非常口サイン(玄関の自動ドアの上、室内から見える向き)
	b.add_exit_sign(R, Vector3(-10.88, 2.42, 0.0), 90.0)

	# スポーン
	b.add_anchor(R, "Spawn_Player", Vector3(-9.5, 0.0, 0.0), -90.0)
	b.add_anchor(R, "Spawn_Boss", Vector3(-8.0, 0.0, -2.2), 90.0)

	# 玄関の自動ドア風(引き分け戸・ガラス)。施錠可。
	b.add_door(R, "Door_Genkan", Vector3(-11.0, 0.0, 0.0), 90.0, {
		"kind": Door.Kind.SLIDE_DOUBLE, "door_width": 1.85, "door_height": 2.2,
		"door_thickness": 0.05, "glass": true, "build_frame": true,
	})

	# 玄関脇のガラス(はめ殺し)
	var glass := LevelMaterials.translucent(Color(0.4, 0.48, 0.52), 0.25)
	LevelBuild.box(node, Vector3(-10.93, 1.57, -2.0), Vector3(0.03, 1.3, 1.18), glass, false, "", false)
	LevelBuild.box(node, Vector3(-10.93, 1.57, 2.4), Vector3(0.03, 1.3, 1.18), glass, false, "", false)


# ---------------------------------------------------------------------- 事務所

static func _office(b: Building) -> void:
	const R := &"Room_Office"
	var node := b.room_of(R)
	var paper := LevelMaterials.plain(Color(0.85, 0.83, 0.77))

	b.add_prop(R, "Desk_Boss", "office_desk", Vector3(-9.3, 0.0, 6.3), 0.0,
		Vector3(1.45, 0.72, 0.72), WOOD)
	b.add_prop(R, "Desk_Sub", "office_desk", Vector3(-6.4, 0.0, 6.3), 0.0,
		Vector3(1.45, 0.72, 0.72), WOOD)
	b.add_prop(R, "Chair_Boss", "office_chair", Vector3(-9.3, 0.0, 7.25), 180.0,
		Vector3(0.5, 0.95, 0.52), DARKGREY)
	b.add_prop(R, "Chair_Sub", "office_chair", Vector3(-6.4, 0.0, 7.25), 180.0,
		Vector3(0.5, 0.95, 0.52), DARKGREY)

	b.add_anchor(R, "Anchor_BossDesk", Vector3(-9.3, 0.72, 6.3), 180.0)
	b.add_anchor_prop(R, "Anchor_Phone", "phone", Vector3(-9.85, 0.72, 6.1), 180.0,
		Vector3(0.26, 0.13, 0.22), Color(0.14, 0.14, 0.15), false, 0.0)
	b.add_anchor_prop(R, "Anchor_Monitor", "monitor_crt", Vector3(-6.4, 0.72, 6.1), 180.0,
		Vector3(0.44, 0.42, 0.42), Color(0.2, 0.2, 0.19), false, 0.0)
	b.add_anchor_prop(R, "Anchor_Matches", "matches", Vector3(-8.75, 0.72, 6.5), 180.0,
		Vector3(0.06, 0.02, 0.045), Color(0.7, 0.35, 0.2), false)
	# 扉は室内(北)向き。プレイヤーは北側に立つのでアンカーの向きは 0。
	b.add_anchor_prop(R, "Anchor_Safe", "safe", Vector3(-10.4, 0.0, 9.4), 0.0,
		Vector3(0.54, 0.64, 0.5), Color(0.26, 0.27, 0.28), true, 180.0)

	# 書類・日誌・ポット・棚
	LevelBuild.box(node, Vector3(-8.85, 0.76, 6.2), Vector3(0.3, 0.08, 0.22), paper, false, "", false)
	LevelBuild.box(node, Vector3(-6.95, 0.75, 6.5), Vector3(0.26, 0.06, 0.2), paper, false, "", false)
	b.add_prop(R, "Shelf_Office", "shelf", Vector3(-10.6, 0.0, 5.2), 90.0,
		Vector3(1.8, 1.85, 0.42), WOOD)
	b.add_prop(R, "Cabinet_Office", "cabinet", Vector3(-4.8, 0.0, 9.45), 180.0,
		Vector3(1.1, 0.85, 0.45), WOOD)
	b.add_prop(R, "Kettle", "kettle", Vector3(-4.8, 0.85, 9.45), 180.0,
		Vector3(0.22, 0.3, 0.22), Color(0.6, 0.6, 0.58), false)
	b.add_prop(R, "WallClock", "wall_clock", Vector3(-4.12, 1.95, 7.2), -90.0,
		Vector3(0.33, 0.33, 0.07), Color(0.75, 0.73, 0.68), false)

	# 社長の番号を貼った紙(電話の上の壁)
	LevelBuild.box(node, Vector3(-10.91, 1.5, 6.2), Vector3(0.02, 0.22, 0.16), paper, false, "", false)
	LevelBuild.sign_text(node, "090-2214-0077", Vector3(-10.895, 1.5, 6.2), 90.0,
		0.035, Color(0.1, 0.1, 0.12), false, 192)

	# ホワイトボード・カレンダー・書類棚
	LevelBuild.box(node, Vector3(-7.4, 1.55, 4.12), Vector3(1.6, 1.0, 0.05),
		LevelMaterials.plain(Color(0.80, 0.79, 0.74)), false, "", false)
	LevelBuild.box(node, Vector3(-5.4, 1.62, 4.12), Vector3(0.42, 0.56, 0.03), paper, false, "", false)
	b.add_prop(R, "Shelf_Office2", "shelf", Vector3(-7.6, 0.0, 9.5), 180.0,
		Vector3(1.6, 1.85, 0.42), WOOD)
	for bx in [[-8.2, 9.3, 0.0], [-8.2, 9.3, 0.36], [-6.9, 9.35, 0.0]]:
		LevelBuild.box(node, Vector3(bx[0], bx[2] + 0.18, bx[1]), Vector3(0.44, 0.36, 0.34),
			LevelMaterials.plain(Color(0.42, 0.33, 0.22)))

	b.add_window(R, "Window_Office", Vector3(-8.0, 1.53, 10.0), 0.0,
		{"pane_width": 1.7, "pane_height": 1.15})

	b.add_fluorescent(R, Vector3(-9.0, 2.44, 5.7), 1.25, COOL, 1.0, 6.0, true)
	b.add_fluorescent(R, Vector3(-8.2, 2.44, 8.7), 1.25, COOL, 1.15, 7.0, true)

	# 社長の机のデスクライト。金庫の隅(-10.4, 9.4)まで薄く届かせる。
	# 部屋の照明と同じ系統なので、分電盤を落とせば一緒に消える。
	LevelBuild.box(node, Vector3(-9.95, 0.88, 6.62), Vector3(0.05, 0.32, 0.05),
		LevelMaterials.plain(Color(0.25, 0.25, 0.26)), false, "", false)
	LevelBuild.box(node, Vector3(-9.95, 1.05, 6.62), Vector3(0.22, 0.09, 0.18),
		LevelMaterials.emissive(Color(1.0, 0.90, 0.72), 1.1), false, "", false)
	var desk_lamp := OmniLight3D.new()
	desk_lamp.name = "Light_DeskLamp"
	desk_lamp.position = Vector3(-9.95, 0.98, 6.62)
	desk_lamp.light_color = Color(1.0, 0.89, 0.70)
	desk_lamp.light_energy = 1.45
	desk_lamp.omni_range = 6.0
	desk_lamp.omni_attenuation = 1.1
	desk_lamp.shadow_enabled = false
	desk_lamp.light_specular = 0.0
	node.add_child(desk_lamp)
	b.add_light(R, desk_lamp)

	b.add_door(R, "Door_Office", Vector3(-8.0, 0.0, 4.0), 0.0, {
		"kind": Door.Kind.SWING, "door_width": 0.92, "door_height": 2.0,
		"hinge_side": 1.0, "swing_degrees": 92.0,
	})


# ------------------------------------------------------------------------ 廊下

static func _hall(b: Building) -> void:
	const R := &"Room_Hall"
	var node := b.room_of(R)
	var wood := LevelMaterials.get_mat("wall_wood", 1.0)

	# 腰板。廊下の生活感はこれで出る。
	for piece in [[-4.0, 5.3], [5.3, 7.5]]:
		var w: float = piece[1] - piece[0]
		LevelBuild.box(node, Vector3((piece[0] + piece[1]) * 0.5, 0.45, -1.02),
			Vector3(w, 0.9, 0.03), wood, false, "", false)
	for piece2 in [[-4.0, -2.68], [-1.72, 0.27], [1.13, 7.5]]:
		var w2: float = piece2[1] - piece2[0]
		LevelBuild.box(node, Vector3((piece2[0] + piece2[1]) * 0.5, 0.45, 1.02),
			Vector3(w2, 0.9, 0.03), wood, false, "", false)
	# L 字の北側(突き当たりまで)
	LevelBuild.box(node, Vector3(5.38, 0.45, -4.3), Vector3(0.03, 0.9, 6.4), wood, false, "", false)
	LevelBuild.box(node, Vector3(7.42, 0.45, -4.3), Vector3(0.03, 0.9, 6.4), wood, false, "", false)

	b.add_prop(R, "FireExtinguisher", "fire_extinguisher", Vector3(-3.6, 0.0, 0.88), 0.0,
		Vector3(0.2, 0.55, 0.2), Color(0.5, 0.1, 0.09))
	b.add_prop(R, "SlipperShelf", "shelf", Vector3(2.7, 0.0, 0.83), 180.0,
		Vector3(1.0, 0.78, 0.32), WOOD)
	b.add_prop(R, "HallShelf", "shelf", Vector3(5.55, 0.0, -2.2), 90.0,
		Vector3(0.95, 1.3, 0.34), WOOD)

	# 蛍光灯(等間隔)。突き当たり(z <= -6.5)には灯りを置かない → 暗い。
	for x in [-2.2, 0.8, 3.8, 6.4]:
		b.add_fluorescent(R, Vector3(x, 2.42, 0.0), 1.15, COOL, 0.8, 4.8, true)
	for z in [-3.0, -5.4]:
		b.add_fluorescent(R, Vector3(6.4, 2.42, z), 1.15, COOL, 0.62, 4.2, true)

	# 非常口サイン。廊下の両端と、L 字の突き当たり(湯灌室の扉の上)。
	# 全消灯でも消えないので、真っ暗な廊下でも進む向きが分かる。
	b.add_exit_sign(R, Vector3(-3.2, 2.28, 0.0), 90.0)
	b.add_exit_sign(R, Vector3(6.9, 2.28, 0.0), -90.0)
	b.add_exit_sign(R, Vector3(6.4, 2.2, -7.3), 0.0)

	# 式場の入口(引き分け戸)
	b.add_door(R, "Door_Shikijo", Vector3(7.5, 0.0, 0.0), 90.0, {
		"kind": Door.Kind.SLIDE_DOUBLE, "door_width": 1.68, "door_height": 2.3,
		"door_thickness": 0.05,
	})


# -------------------------------------------------------------------- 控室(和室)

static func _hikaeshitsu(b: Building) -> void:
	const R := &"Room_Hikaeshitsu"
	var node := b.room_of(R)
	var tatami := LevelMaterials.get_mat("tatami", 1.0)
	var heri := LevelMaterials.plain(Color(0.20, 0.17, 0.12))
	var wood := LevelMaterials.get_mat("wall_wood", 1.0)

	# 八畳。1.8 x 0.9 の畳を 2 列 x 4 枚。
	for col in 2:
		var cx: float = -3.1 + col * 1.8
		for row in 4:
			var cz: float = 1.55 + row * 0.9
			LevelBuild.box(node, Vector3(cx, 0.012, cz), Vector3(1.76, 0.05, 0.86), tatami, false, "tatami", false)
			LevelBuild.box(node, Vector3(cx, 0.014, cz - 0.43), Vector3(1.76, 0.048, 0.04), heri, false, "", false)
			LevelBuild.box(node, Vector3(cx, 0.014, cz + 0.43), Vector3(1.76, 0.048, 0.04), heri, false, "", false)

	b.add_prop(R, "LowTable", "low_table", Vector3(-1.35, 0.0, 3.0), 0.0,
		Vector3(1.15, 0.34, 0.72), Color(0.30, 0.20, 0.13))
	for zb in [[-1.35, 2.2], [-1.35, 3.8], [-2.2, 3.0], [-0.75, 3.0]]:
		b.add_prop(R, "Zabuton_%d_%d" % [int(zb[0] * 10), int(zb[1] * 10)], "zabuton",
			Vector3(zb[0], 0.03, zb[1]), 0.0, Vector3(0.55, 0.08, 0.55), Color(0.35, 0.16, 0.16), false)

	# 通夜ぶるまいの残り
	LevelBuild.box(node, Vector3(-1.35, 0.37, 3.0), Vector3(0.48, 0.07, 0.48),
		LevelMaterials.plain(Color(0.30, 0.23, 0.16)), false, "", false)
	b.add_prop(R, "BeerCan1", "beer_can", Vector3(-1.72, 0.34, 2.72), 0.0,
		Vector3(0.07, 0.13, 0.07), Color(0.62, 0.58, 0.2), false)
	b.add_prop(R, "BeerCan2", "beer_can", Vector3(-1.0, 0.34, 3.3), 22.0,
		Vector3(0.07, 0.13, 0.07), Color(0.62, 0.58, 0.2), false)
	b.add_prop(R, "BeerCan3", "beer_can", Vector3(-2.15, 0.0, 3.75), 70.0,
		Vector3(0.07, 0.13, 0.07), Color(0.62, 0.58, 0.2), false)
	b.add_prop(R, "SakeBottle", "sake_bottle", Vector3(-1.0, 0.34, 2.74), 0.0,
		Vector3(0.09, 0.3, 0.09), Color(0.16, 0.3, 0.18), false)

	# 布団・TV・押入れ
	b.add_anchor_prop(R, "Anchor_Futon", "futon", Vector3(-3.25, 0.0, 3.35), 0.0,
		Vector3(1.0, 0.18, 2.0), Color(0.72, 0.70, 0.66), false)
	LevelBuild.box(node, Vector3(-0.95, 0.21, 1.75), Vector3(0.78, 0.42, 0.48), wood)
	b.add_anchor_prop(R, "Anchor_TV", "tv_crt", Vector3(-0.95, 0.42, 1.75), 135.0,
		Vector3(0.54, 0.45, 0.47), Color(0.22, 0.21, 0.2), false, -45.0)
	# 押入れ(襖)
	LevelBuild.box(node, Vector3(-1.25, 1.0, 4.4), Vector3(1.52, 2.0, 0.48), wood)
	for fx in [-1.63, -0.87]:
		LevelBuild.box(node, Vector3(fx, 1.0, 4.14), Vector3(0.72, 1.92, 0.03),
			LevelMaterials.plain(Color(0.68, 0.64, 0.55)), false, "", false)

	# 障子窓(南の壁、開口 x = -3.0)
	LevelBuild.box(node, Vector3(-3.0, 1.25, 4.64), Vector3(1.38, 1.38, 0.03),
		LevelMaterials.translucent(Color(0.86, 0.84, 0.76), 0.75), false, "", false)
	for gx in [-3.46, -3.0, -2.54]:
		LevelBuild.box(node, Vector3(gx, 1.25, 4.62), Vector3(0.025, 1.38, 0.02), wood, false, "", false)
	for gy in [0.72, 1.25, 1.78]:
		LevelBuild.box(node, Vector3(-3.0, gy, 4.62), Vector3(1.38, 0.025, 0.02), wood, false, "", false)

	b.add_fluorescent(R, Vector3(-2.0, 2.3, 2.9), 0.9, Color(1.0, 0.93, 0.79), 0.8, 4.6, true)

	b.add_door(R, "Door_Hikaeshitsu", Vector3(-2.2, 0.0, 1.1), 0.0, {
		"kind": Door.Kind.SLIDE, "door_width": 0.92, "door_height": 2.0,
		"door_thickness": 0.04, "hinge_side": -1.0,
	})


# ------------------------------------------------------------------- トイレ

static func _toilet(b: Building) -> void:
	const R := &"Room_Toilet"
	var node := b.room_of(R)
	var white := LevelMaterials.plain(Color(0.78, 0.78, 0.75))
	var tile := LevelMaterials.get_mat("concrete", 2.0)

	b.add_prop(R, "Toilet", "toilet", Vector3(1.35, 0.0, 3.05), 180.0,
		Vector3(0.4, 0.78, 0.68), Color(0.78, 0.78, 0.75))
	LevelBuild.box(node, Vector3(1.5, 0.4, 1.65), Vector3(0.36, 0.8, 0.34), white)
	LevelBuild.box(node, Vector3(1.69, 1.35, 1.65), Vector3(0.03, 0.52, 0.44),
		LevelMaterials.plain(Color(0.42, 0.46, 0.48), 0.25), false, "", false)
	LevelBuild.box(node, Vector3(-0.31, 1.15, 2.35), Vector3(0.04, 2.3, 2.4), tile, false, "", false)

	b.add_window(R, "Window_Toilet", Vector3(0.7, 1.65, 3.6), 0.0,
		{"pane_width": 0.62, "pane_height": 0.58})

	b.add_fluorescent(R, Vector3(0.7, 2.2, 2.3), 0.6, Color(0.96, 0.96, 0.92), 0.45, 3.0, false)

	b.add_door(R, "Door_Toilet", Vector3(0.7, 0.0, 1.1), 0.0, {
		"kind": Door.Kind.SWING, "door_width": 0.82, "door_height": 2.0,
		"hinge_side": -1.0, "swing_degrees": -88.0,
	})
