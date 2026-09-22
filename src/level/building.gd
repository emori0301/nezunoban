class_name Building
extends Node3D
## 家族葬ホール「やすらぎ会館」。平屋 L 字 + 外周。
## 形状・照明・小物はすべてコードで組む(models 担当の glb が入ったら Prop が自動で差し替わる)。
##
## 座標系: X = 東 / +Z = 南 / -Z = 北。床 y = 0。Marker3D の -Z が正面。
##   Anchor_* の -Z は「プレイヤーが立つ側(物の正面)」、Spawn_* の -Z は「その人/猫の向き」。
##
## 公開 API:
##   get_anchor(name) / get_door(name) / get_window_pane(name) / get_room_area(name) / current_room
##   set_room_lights(room, on) / set_all_lights(on) / flicker(room, duration) / get_light_state(room)
##   set_aux_lights(room, on) / get_aux_light_state(room)  … 祭壇スポットなど別系統
##   set_emergency_lights(on) / get_emergency_light_state()  … 非常口サイン(全消灯でも残る)
##   hide_anchor_prop(anchor)   … systems が実物を置くとき、level のプレースホルダを消す

const OUTSIDE := &"Room_Outside"

## 部屋 → 床の矩形 [x1, x2, z1, z2] の配列、天井高、床の材質。
const ROOMS := {
	&"Room_Genkan": {
		"rects": [[-11.0, -4.0, -4.0, 4.0]],
		"ceil": 2.7, "tex": "floor_lino", "surface": "lino",
	},
	&"Room_Office": {
		"rects": [[-11.0, -4.0, 4.0, 10.0]],
		"ceil": 2.6, "tex": "floor_lino", "surface": "lino",
	},
	&"Room_Hall": {
		"rects": [[-4.0, 7.5, -1.1, 1.1], [5.3, 7.5, -7.5, -1.1]],
		"ceil": 2.5, "tex": "floor_lino", "surface": "lino",
	},
	&"Room_Hikaeshitsu": {
		"rects": [[-4.0, -0.4, 1.1, 4.7]],
		"ceil": 2.4, "tex": "tatami", "surface": "tatami",
	},
	&"Room_Toilet": {
		"rects": [[-0.4, 1.8, 1.1, 3.6]],
		"ceil": 2.3, "tex": "floor_lino", "surface": "lino",
	},
	&"Room_Shikijo": {
		"rects": [[7.5, 19.5, -4.5, 3.5]],
		"ceil": 3.2, "tex": "floor_lino", "surface": "lino",
	},
	&"Room_Backyard": {
		"rects": [[-4.0, 5.3, -7.5, -1.1]],
		"ceil": 2.6, "tex": "concrete", "surface": "concrete",
	},
	&"Room_Yukan": {
		"rects": [[5.3, 9.3, -11.5, -7.5]],
		"ceil": 2.4, "tex": "concrete", "surface": "concrete",
	},
}

## 外周(プレイヤーが屋内のどの部屋にも居ないときの既定)
const OUTSIDE_RECT := [-32.0, 34.0, -30.0, 26.0]

var current_room: StringName = OUTSIDE

var _anchors: Dictionary = {}        # StringName -> Node3D
var _anchor_props: Dictionary = {}   # StringName -> Prop
var _doors: Dictionary = {}          # StringName -> Door
var _windows: Dictionary = {}        # StringName -> WindowPane
var _room_areas: Dictionary = {}     # StringName -> Area3D
var _room_nodes: Dictionary = {}     # StringName -> Node3D
var _lights: Dictionary = {}         # StringName -> Array[Light3D]
var _lamp_mats: Dictionary = {}      # StringName -> Array[StandardMaterial3D]
var _lamp_energy: Dictionary = {}    # StringName -> Array[float]
var _light_on: Dictionary = {}       # StringName -> bool
# 別系統の照明(祭壇スポットなど)。set_room_lights では消えず、set_all_lights でだけ消える。
var _aux_lights: Dictionary = {}     # StringName -> Array[Light3D]
var _aux_energy: Dictionary = {}     # StringName -> Array[float]
var _aux_on: Dictionary = {}         # StringName -> bool
# 非常灯(第3系統)。set_all_lights(false) でも消えず、set_emergency_lights() だけが切れる。
var _emg_lights: Array[Light3D] = []
var _emg_energy: Array[float] = []
var _emg_mats: Array[StandardMaterial3D] = []
var _emg_on: bool = true
var _inside_stack: Array[StringName] = []
var _flickering: Dictionary = {}

## 全照明の明るさ倍率。VHS フィルタを通すと画面が暗くなるので、
## director / fx 側から一括で調整できるようにしてある(既定 1.0 = level が合わせた値)。
var light_scale: float = 1.0

var nav: NavigationRegion3D = null
var shell: Node3D = null
var rooms_root: Node3D = null
var doors_root: Node3D = null


func _ready() -> void:
	add_to_group(&"building")
	_build_environment()
	nav = NavigationRegion3D.new()
	nav.name = "Nav"
	add_child(nav)
	shell = Node3D.new()
	shell.name = "Shell"
	nav.add_child(shell)
	rooms_root = Node3D.new()
	rooms_root.name = "Rooms"
	add_child(rooms_root)
	doors_root = Node3D.new()
	doors_root.name = "Doors"
	add_child(doors_root)

	for r in ROOMS:
		var node := Node3D.new()
		node.name = String(r)
		rooms_root.add_child(node)
		_room_nodes[r] = node
		_light_on[r] = true
		_lights[r] = []
		_lamp_mats[r] = []
		_lamp_energy[r] = []
		_aux_lights[r] = []
		_aux_energy[r] = []
		_aux_on[r] = true
	var out := Node3D.new()
	out.name = String(OUTSIDE)
	rooms_root.add_child(out)
	_room_nodes[OUTSIDE] = out
	_light_on[OUTSIDE] = true
	_lights[OUTSIDE] = []
	_lamp_mats[OUTSIDE] = []
	_lamp_energy[OUTSIDE] = []
	_aux_lights[OUTSIDE] = []
	_aux_energy[OUTSIDE] = []
	_aux_on[OUTSIDE] = true

	_build_floors_and_ceilings()
	_build_walls()
	LevelFurnishA.build(self)
	LevelFurnishB.build(self)
	_build_room_areas()
	_build_nav()


# ==================================================================== 公開 API

func get_anchor(anchor: StringName) -> Node3D:
	return _anchors.get(anchor, null)


func get_door(door: StringName) -> Door:
	return _doors.get(door, null)


## Node.get_window() と名前が衝突するため get_window_pane()。窓は Window_* の名前で引く。
func get_window_pane(w: StringName) -> WindowPane:
	return _windows.get(w, null)


## 窓の一覧(名前 -> WindowPane)
func all_windows() -> Dictionary:
	return _windows.duplicate()


## 扉の一覧(名前 -> Door)
func all_doors() -> Dictionary:
	return _doors.duplicate()


func get_room_area(room: StringName) -> Area3D:
	return _room_areas.get(room, null)


func get_room_node(room: StringName) -> Node3D:
	return _room_nodes.get(room, null)


func get_light_state(room: StringName) -> bool:
	return bool(_light_on.get(room, false))


## 非常灯の点灯状態。
func get_emergency_light_state() -> bool:
	return _emg_on


## 非常灯(非常口サイン)。全消灯でも消えないので、真っ暗でも輪郭が追える。
## 04:00 の演出でこれも落としたいときだけ director が false を呼ぶ。
func set_emergency_lights(on: bool) -> void:
	_emg_on = on
	_apply_emergency(on)


## 別系統(祭壇スポットなど)の点灯状態。
func get_aux_light_state(room: StringName) -> bool:
	return bool(_aux_on.get(room, false))


## 別系統だけを点けたり消したりする。
func set_aux_lights(room: StringName, on: bool) -> void:
	if not _aux_on.has(room):
		return
	_aux_on[room] = on
	_apply_aux(room, on)


## 部屋の照明を点ける/消す。光源だけでなく蛍光灯メッシュの emission も落とす。
func set_room_lights(room: StringName, on: bool) -> void:
	if not _light_on.has(room):
		return
	_light_on[room] = on
	_apply_lights(room, on)
	Audio.play(&"lights_on" if on else &"lights_off")


## 屋内の全照明。別系統(祭壇スポット)もここでは一緒に落とす(終盤の全消灯用)。include_outside = true なら外灯・自販機も落とす。
func set_all_lights(on: bool, include_outside: bool = false) -> void:
	for r in _light_on:
		if r == OUTSIDE and not include_outside:
			continue
		_light_on[r] = on
		_apply_lights(r, on)
		_aux_on[r] = on
		_apply_aux(r, on)
	Audio.play(&"lights_on" if on else &"lights_off")


## 屋内外すべての照明の明るさをまとめて倍率調整する。
func set_light_scale(f: float) -> void:
	light_scale = maxf(f, 0.0)
	for r in _light_on:
		_apply_lights(r, get_light_state(r))
		_apply_aux(r, get_aux_light_state(r))
	_apply_emergency(_emg_on)


## 蛍光灯の明滅。duration 秒だけちらついて、元の状態に戻る。
func flicker(room: StringName, duration: float = 2.0) -> void:
	if not _lights.has(room) or _flickering.get(room, false):
		return
	_flickering[room] = true
	Audio.play(&"fluorescent_flicker")
	var t := 0.0
	while t < duration:
		var step := randf_range(0.04, 0.16)
		await get_tree().create_timer(step).timeout
		if not is_inside_tree():
			return
		t += step
		_apply_lights(room, randf() < 0.42)
	_flickering[room] = false
	_apply_lights(room, get_light_state(room))


## systems が実物のインタラクト可能オブジェクトを置くとき、level のプレースホルダを消す。
func hide_anchor_prop(anchor: StringName) -> void:
	var p: Prop = _anchor_props.get(anchor, null)
	if p and is_instance_valid(p):
		p.queue_free()
		_anchor_props.erase(anchor)


# ============================================================ 組み立て用ヘルパ
# (furnish_a.gd / furnish_b.gd から呼ぶ)

func room_of(room: StringName) -> Node3D:
	return _room_nodes[room]


func add_anchor(room: StringName, anchor_name: String, pos: Vector3, yaw: float = 0.0) -> Marker3D:
	var m := LevelBuild.marker(_room_nodes[room], anchor_name, pos, yaw)
	_anchors[StringName(anchor_name)] = m
	return m


## アンカーとその場所のプレースホルダ Prop をまとめて置く。
## glb の前面がローカル +Z 側にあるモデル(祭壇・遺影など)は、アンカーの向き(-Z が正面)と
## 合わないので prop_yaw で Prop 側だけ別の角度にする。既定はアンカーと同じ。
func add_anchor_prop(room: StringName, anchor_name: String, model: String, pos: Vector3,
		yaw: float, size: Vector3, color: Color, collide: bool = true,
		prop_yaw: float = NAN) -> Marker3D:
	var m := add_anchor(room, anchor_name, pos, yaw)
	var py: float = yaw if is_nan(prop_yaw) else prop_yaw
	var p := LevelBuild.prop(_room_nodes[room], anchor_name + "_Prop", model, pos, py, size, color, collide)
	_anchor_props[StringName(anchor_name)] = p
	return m


func add_prop(room: StringName, node_name: String, model: String, pos: Vector3,
		yaw: float, size: Vector3, color: Color, collide: bool = true) -> Prop:
	return LevelBuild.prop(_room_nodes[room], node_name, model, pos, yaw, size, color, collide)


func add_box(room: StringName, center: Vector3, size: Vector3, mat: Material,
		collide: bool = true) -> MeshInstance3D:
	return LevelBuild.box(_room_nodes[room], center, size, mat, collide, "", true)


## 非常灯として登録する。set_all_lights でも消えない。
func add_emergency_light(light: Light3D, mat: StandardMaterial3D = null) -> void:
	_emg_lights.append(light)
	_emg_energy.append(light.light_energy)
	_emg_mats.append(mat)


## 非常口サインを1つ置く(緑の発光板 + 弱い緑の光)。
func add_exit_sign(room: StringName, pos: Vector3, yaw: float) -> void:
	var r := LevelBuild.exit_sign(_room_nodes[room], pos, yaw)
	add_emergency_light(r[0], r[1])


## 蛍光灯とは別系統で登録する。set_room_lights では消えない。
func add_aux_light(room: StringName, light: Light3D) -> void:
	_aux_lights[room].append(light)
	_aux_energy[room].append(light.light_energy)


func add_light(room: StringName, light: Light3D, mat: StandardMaterial3D = null) -> void:
	_lights[room].append(light)
	_lamp_energy[room].append(light.light_energy)
	_lamp_mats[room].append(mat)


func add_fluorescent(room: StringName, pos: Vector3, length: float, color: Color,
		energy: float, range_m: float = 7.0, shadow: bool = true) -> void:
	var r := LevelBuild.fluorescent(_room_nodes[room], pos, length, color, energy, range_m, shadow)
	add_light(room, r[0], r[2])


func add_bulb(room: StringName, pos: Vector3, color: Color, energy: float,
		range_m: float = 6.0, shadow: bool = true) -> void:
	var r := LevelBuild.bulb(_room_nodes[room], pos, color, energy, range_m, shadow)
	add_light(room, r[0], r[2])


## 扉を置く。pos は開口部の中心・床面。yaw は壁の向き(X 軸沿いの壁なら 0、Z 軸沿いなら 90)。
func add_door(_room: StringName, door_name: String, pos: Vector3, yaw: float, cfg: Dictionary) -> Door:
	var d := Door.new()
	d.name = door_name
	d.position = pos
	d.rotation_degrees.y = yaw
	for k in cfg:
		d.set(k, cfg[k])
	doors_root.add_child(d)
	_doors[StringName(door_name)] = d
	return d


func add_window(_room: StringName, win_name: String, pos: Vector3, yaw: float, cfg: Dictionary) -> WindowPane:
	var w := WindowPane.new()
	w.name = win_name
	w.position = pos
	w.rotation_degrees.y = yaw
	for k in cfg:
		w.set(k, cfg[k])
	doors_root.add_child(w)
	_windows[StringName(win_name)] = w
	return w


# ==================================================================== 内部実装

func _apply_lights(room: StringName, on: bool) -> void:
	var list: Array = _lights.get(room, [])
	var mats: Array = _lamp_mats.get(room, [])
	var energies: Array = _lamp_energy.get(room, [])
	for i in list.size():
		var l: Light3D = list[i]
		if not is_instance_valid(l):
			continue
		l.light_energy = float(energies[i]) * light_scale if on else 0.0
		l.visible = on
		var m: StandardMaterial3D = mats[i]
		if m:
			m.emission_energy_multiplier = 1.25 if on else 0.0
			m.albedo_color = Color(0.92, 0.94, 0.95) if on else Color(0.24, 0.25, 0.26)


func _apply_emergency(on: bool) -> void:
	for i in _emg_lights.size():
		var l: Light3D = _emg_lights[i]
		if not is_instance_valid(l):
			continue
		l.light_energy = float(_emg_energy[i]) * light_scale if on else 0.0
		l.visible = on
		var m: StandardMaterial3D = _emg_mats[i]
		if m:
			m.emission_energy_multiplier = 1.7 if on else 0.0
			m.albedo_color = Color(0.13, 0.78, 0.30) if on else Color(0.07, 0.16, 0.09)


func _apply_aux(room: StringName, on: bool) -> void:
	var list: Array = _aux_lights.get(room, [])
	var energies: Array = _aux_energy.get(room, [])
	for i in list.size():
		var l: Light3D = list[i]
		if not is_instance_valid(l):
			continue
		l.light_energy = float(energies[i]) * light_scale if on else 0.0
		l.visible = on


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "Env"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.014, 0.022)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.11, 0.13, 0.20)
	env.ambient_light_energy = 0.055
	env.fog_enabled = true
	env.fog_light_color = Color(0.055, 0.062, 0.085)
	env.fog_light_energy = 1.0
	env.fog_density = 0.021
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.80
	env.adjustment_brightness = 1.0
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-38, 128, 0)
	moon.light_color = Color(0.56, 0.64, 0.88)
	moon.light_energy = 0.10
	moon.light_specular = 0.0
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	add_child(moon)


func _build_floors_and_ceilings() -> void:
	var ceil_mat := LevelMaterials.get_mat("ceiling_tile", 0.55)
	for r in ROOMS:
		var info: Dictionary = ROOMS[r]
		var holder := Node3D.new()
		holder.name = "Shell_" + String(r)
		shell.add_child(holder)
		var fmat := LevelMaterials.get_mat(String(info["tex"]), 1.0)
		for rect in info["rects"]:
			LevelBuild.floor_slab(holder, rect[0], rect[2], rect[1], rect[3], fmat, String(info["surface"]))
			LevelBuild.ceiling_slab(holder, rect[0], rect[2], rect[1], rect[3], ceil_mat, float(info["ceil"]))

	# 外周の地面。屋内の床(y=0)より 2cm 下げて Z ファイトを避ける。
	var ground := Node3D.new()
	ground.name = "Shell_Outside"
	shell.add_child(ground)
	var asphalt := LevelMaterials.get_mat("asphalt", 0.35)
	LevelBuild.floor_slab(ground, OUTSIDE_RECT[0], OUTSIDE_RECT[2], OUTSIDE_RECT[1], OUTSIDE_RECT[3],
		asphalt, "concrete", -0.02)


## 開口部の敷居。壁の厚み分だけ床が空くので、そこを埋める。
func _threshold(x: float, z: float, along_x: bool, width: float) -> void:
	var sz := Vector3(width + 0.3, 0.12, 0.34) if along_x else Vector3(0.34, 0.12, width + 0.3)
	LevelBuild.box(shell, Vector3(x, -0.062, z), sz,
		LevelMaterials.get_mat("floor_lino", 1.0), true, "lino", false)


func _build_walls() -> void:
	var plaster := LevelMaterials.get_mat("wall_plaster", 0.6)
	var wood := LevelMaterials.get_mat("wall_wood", 0.6)
	var conc := LevelMaterials.get_mat("concrete", 0.5)
	var holder := Node3D.new()
	holder.name = "Walls"
	shell.add_child(holder)

	# --- X 一定(南北に走る壁) ------------------------------------------------
	# 玄関・事務所の西面(正面)。玄関の自動ドア。
	LevelBuild.wall(holder, -11.0, -4.0, -11.0, 10.0, 2.9, plaster,
		[{"t": 4.0, "w": 1.9, "sill": 0.0, "head": 2.25},
		 {"t": 2.0, "w": 1.2, "sill": 0.9, "head": 2.25},
		 {"t": 6.4, "w": 1.2, "sill": 0.9, "head": 2.25}])
	_threshold(-11.0, 0.0, false, 1.9)

	# 玄関/バックヤード・玄関/廊下(出入口)・玄関/控室・事務所/控室・事務所東面
	LevelBuild.wall(holder, -4.0, -7.5, -4.0, 10.0, 2.9, plaster,
		[{"t": 7.5, "w": 2.2, "sill": 0.0, "head": 2.3}])
	_threshold(-4.0, 0.0, false, 2.2)

	# 控室/トイレ
	LevelBuild.wall(holder, -0.4, 1.1, -0.4, 4.7, 2.5, wood)
	# トイレ東面
	LevelBuild.wall(holder, 1.8, 1.1, 1.8, 3.6, 2.5, plaster)
	# バックヤード/廊下(北側)
	LevelBuild.wall(holder, 5.3, -7.5, 5.3, -1.1, 2.7, conc,
		[{"t": 3.2, "w": 1.3, "sill": 0.0, "head": 2.2}])
	_threshold(5.3, -4.3, false, 1.3)
	# 廊下/式場の西面。式場の入口(引き分け戸)
	LevelBuild.wall(holder, 7.5, -7.5, 7.5, 3.5, 3.4, plaster,
		[{"t": 7.5, "w": 1.7, "sill": 0.0, "head": 2.35}])
	_threshold(7.5, 0.0, false, 1.7)
	# 式場の東面(祭壇の壁)
	LevelBuild.wall(holder, 19.5, -4.5, 19.5, 3.5, 3.4, plaster)
	# 湯灌室の西面・東面
	LevelBuild.wall(holder, 5.3, -11.5, 5.3, -7.5, 2.6, conc)
	LevelBuild.wall(holder, 9.3, -11.5, 9.3, -7.5, 2.6, conc)

	# --- Z 一定(東西に走る壁) ------------------------------------------------
	# 玄関の北面
	LevelBuild.wall(holder, -11.0, -4.0, -4.0, -4.0, 2.9, plaster)
	# 廊下の北面(バックヤードとの境 / 廊下 L 字の合流部は開口)
	LevelBuild.wall(holder, -4.0, -1.1, 7.5, -1.1, 2.9, plaster,
		[{"t": 10.4, "w": 2.2, "sill": 0.0, "head": 2.35}])
	_threshold(6.4, -1.1, true, 2.2)
	# 廊下の南面(控室の戸・トイレの戸・外壁)
	LevelBuild.wall(holder, -4.0, 1.1, 7.5, 1.1, 2.9, plaster,
		[{"t": 1.8, "w": 0.95, "sill": 0.0, "head": 2.05},
		 {"t": 4.7, "w": 0.85, "sill": 0.0, "head": 2.05}])
	_threshold(-2.2, 1.1, true, 0.95)
	_threshold(0.7, 1.1, true, 0.85)
	# 玄関/事務所
	LevelBuild.wall(holder, -11.0, 4.0, -4.0, 4.0, 2.9, plaster,
		[{"t": 3.0, "w": 0.95, "sill": 0.0, "head": 2.05}])
	_threshold(-8.0, 4.0, true, 0.95)
	# 控室の南面(障子窓)
	LevelBuild.wall(holder, -4.0, 4.7, -0.4, 4.7, 2.5, wood,
		[{"t": 1.0, "w": 1.4, "sill": 0.55, "head": 1.95}])
	# トイレの南面(窓)
	LevelBuild.wall(holder, -0.4, 3.6, 1.8, 3.6, 2.5, plaster,
		[{"t": 1.1, "w": 0.65, "sill": 1.35, "head": 1.95}])
	# 事務所の南面(窓)
	LevelBuild.wall(holder, -11.0, 10.0, -4.0, 10.0, 2.9, plaster,
		[{"t": 3.0, "w": 1.7, "sill": 0.95, "head": 2.1}])
	# バックヤードの北面(勝手口)
	LevelBuild.wall(holder, -4.0, -7.5, 5.3, -7.5, 2.8, conc,
		[{"t": 4.0, "w": 0.95, "sill": 0.0, "head": 2.05}])
	_threshold(0.0, -7.5, true, 0.95)
	# 廊下の突き当たり / 湯灌室の南面
	LevelBuild.wall(holder, 5.3, -7.5, 9.3, -7.5, 2.6, conc,
		[{"t": 1.1, "w": 0.95, "sill": 0.0, "head": 2.05}])
	_threshold(6.4, -7.5, true, 0.95)
	# 湯灌室の北面
	LevelBuild.wall(holder, 5.3, -11.5, 9.3, -11.5, 2.6, conc)
	# 式場の南面(窓)・北面
	LevelBuild.wall(holder, 7.5, 3.5, 19.5, 3.5, 3.4, plaster,
		[{"t": 5.5, "w": 1.8, "sill": 1.0, "head": 2.35}])
	LevelBuild.wall(holder, 7.5, -4.5, 19.5, -4.5, 3.4, plaster)

	# --- 屋根(外から見たときの見え方 + 上からの光漏れ防止) --------------------
	var roof := LevelMaterials.get_mat("concrete", 0.4)
	for r in ROOMS:
		var info: Dictionary = ROOMS[r]
		for rect in info["rects"]:
			LevelBuild.box(holder,
				Vector3((rect[0] + rect[1]) * 0.5, float(info["ceil"]) + 0.45, (rect[2] + rect[3]) * 0.5),
				Vector3(rect[1] - rect[0] + 0.3, 0.2, rect[3] - rect[2] + 0.3), roof, false, "", true)


func _build_room_areas() -> void:
	for r in ROOMS:
		var info: Dictionary = ROOMS[r]
		var area := Area3D.new()
		area.name = "Area"
		area.collision_layer = 0
		area.collision_mask = 4          # layer 3 = player
		area.monitoring = true
		area.monitorable = false
		for rect in info["rects"]:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			var h: float = float(info["ceil"])
			bs.size = Vector3(rect[1] - rect[0] - 0.1, h, rect[3] - rect[2] - 0.1)
			cs.shape = bs
			cs.position = Vector3((rect[0] + rect[1]) * 0.5, h * 0.5, (rect[2] + rect[3]) * 0.5)
			area.add_child(cs)
		_room_nodes[r].add_child(area)
		_room_areas[r] = area
		var rn: StringName = r
		area.body_entered.connect(func(_b: Node3D) -> void: _on_room_entered(rn))
		area.body_exited.connect(func(_b: Node3D) -> void: _on_room_exited(rn))

	# 外周。屋内のどこにも居ないときの既定。
	var out := Area3D.new()
	out.name = "Area"
	out.collision_layer = 0
	out.collision_mask = 4
	out.monitoring = true
	out.monitorable = false
	var cs2 := CollisionShape3D.new()
	var b2 := BoxShape3D.new()
	b2.size = Vector3(OUTSIDE_RECT[1] - OUTSIDE_RECT[0], 8.0, OUTSIDE_RECT[3] - OUTSIDE_RECT[2])
	cs2.shape = b2
	cs2.position = Vector3((OUTSIDE_RECT[0] + OUTSIDE_RECT[1]) * 0.5, 3.0,
		(OUTSIDE_RECT[2] + OUTSIDE_RECT[3]) * 0.5)
	out.add_child(cs2)
	_room_nodes[OUTSIDE].add_child(out)
	_room_areas[OUTSIDE] = out


func _on_room_entered(room: StringName) -> void:
	if not _inside_stack.has(room):
		_inside_stack.append(room)
	_update_current()


func _on_room_exited(room: StringName) -> void:
	_inside_stack.erase(room)
	_update_current()


func _update_current() -> void:
	var next: StringName = _inside_stack[-1] if _inside_stack.size() > 0 else OUTSIDE
	if next == current_room:
		return
	current_room = next
	Events.emit_event(&"player_entered_room", {"room": current_room})


func _build_nav() -> void:
	# 既定のナビマップは cell 0.25 で、0.9m の戸口が猫の半径で塞がってしまう。
	# マップ側を細かくしてから焼く(NPC/猫の NavigationAgent3D もこのマップを使う)。
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.1)
	NavigationServer3D.map_set_cell_height(map, 0.1)

	var nm := NavigationMesh.new()
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nm.agent_radius = 0.2
	nm.agent_height = 1.6
	nm.agent_max_climb = 0.2
	nm.agent_max_slope = 40.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	# 壁・床に加えて家具も障害物にする。扉だけは doors_root にあり、グループに入れていないので
	# 開閉に関係なく経路が通る(仕様どおり)。これを入れないと NPC が受付台や椅子を突き抜ける。
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"navsource"
	shell.add_to_group(&"navsource")
	rooms_root.add_to_group(&"navsource")
	# 壁の上面や屋根に歩ける島ができないよう、ベイクを腰から下の高さに絞る。
	nm.filter_baking_aabb = AABB(Vector3(-34.0, -1.0, -32.0), Vector3(70.0, 3.0, 60.0))
	nm.filter_low_hanging_obstacles = true
	nm.filter_ledge_spans = true
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)
