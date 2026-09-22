class_name NpcUtil
extends RefCounted
## NPC / 猫 / 火車 が共有する小道具。すべて static。
##
## ここに置いてあるのは「建物の開口部の表」と、マテリアル・ナビ・視線の小さなヘルパ。
## 座標は src/level/building.gd の壁の開口部から取った実測値。


## 外から中へ入れる開口部。猫はここからしか侵入しない。
##   outside / inside … 床(y=0)の代表点。ナビはこの点を目標にする。
##   sill / head      … 開口部の下端・上端(窓をまたぐ演出の高さ)。
##   node             … Building.get_door() / get_window_pane() で引く名前。
const OPENINGS := {
	&"Door_Genkan": {
		"kind": "door", "room": &"Room_Genkan",
		"outside": Vector3(-12.6, 0.0, 0.0), "inside": Vector3(-9.6, 0.0, 0.0),
		"sill": 0.0, "head": 2.25, "width": 1.85,
	},
	&"Door_Backyard": {
		"kind": "door", "room": &"Room_Backyard",
		"outside": Vector3(0.0, 0.0, -9.0), "inside": Vector3(0.0, 0.0, -6.2),
		"sill": 0.0, "head": 2.05, "width": 0.95,
	},
	&"Window_Shikijo": {
		"kind": "window", "room": &"Room_Shikijo",
		"outside": Vector3(13.0, 0.0, 4.9), "inside": Vector3(13.0, 0.0, 2.2),
		"sill": 1.00, "head": 2.35, "width": 1.80,
	},
	&"Window_Toilet": {
		"kind": "window", "room": &"Room_Toilet",
		"outside": Vector3(0.7, 0.0, 5.0), "inside": Vector3(0.7, 0.0, 2.3),
		"sill": 1.35, "head": 1.95, "width": 0.65,
	},
	&"Window_Office": {
		"kind": "window", "room": &"Room_Office",
		"outside": Vector3(-8.0, 0.0, 11.4), "inside": Vector3(-8.0, 0.0, 8.8),
		"sill": 0.95, "head": 2.10, "width": 1.70,
	},
}

## 火車が引きこもる暗がり(湯灌室・廊下の突き当たり)。
const DARK_SPOTS := [
	Vector3(7.3, 0.0, -9.8),    # 湯灌室の奥
	Vector3(6.4, 0.0, -6.9),    # 廊下の突き当たり(湯灌室の戸の前)
]

## 屋内をうろつくときの経由点(廊下 → 式場)。
const WANDER_POINTS := [
	Vector3(-2.0, 0.0, 0.0),
	Vector3(3.0, 0.0, 0.0),
	Vector3(6.4, 0.0, 0.0),
	Vector3(6.4, 0.0, -3.4),
	Vector3(6.4, 0.0, -6.4),
	Vector3(2.0, 0.0, -4.0),
	Vector3(9.5, 0.0, -0.5),
	Vector3(12.0, 0.0, 1.8),
]

## 式場の入口から棺の脇までの通り道。
## ナビメッシュは椅子・焼香台を見ていないので、空いている中央通路(z = -0.5)と
## 焼香台の南(z = -1.35)を通る経由点を自分で持つ。最後の点が飛び乗る前の足場。
const COFFIN_ROUTE := [
	Vector3(9.6, 0.0, -0.5),
	Vector3(14.35, 0.0, -0.5),
	Vector3(14.35, 0.0, -1.35),
	Vector3(16.9, 0.0, -1.35),
]

## 追い払われた猫が隠れる室内の隅。
const HIDE_SPOTS := [
	Vector3(18.6, 0.0, 2.9),    # 式場の north-east 隅
	Vector3(8.3, 0.0, -3.9),    # 式場の入口脇
	Vector3(-3.4, 0.0, -6.8),   # バックヤードの隅
]


# ---------------------------------------------------------------- 建物

static func building() -> Building:
	var b := Game.level as Building
	if b != null:
		return b
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var list := tree.get_nodes_in_group(&"building")
	return list[0] as Building if not list.is_empty() else null


## 開口部の Door / WindowPane を返す(無ければ null)。
static func opening_node(opening: StringName) -> Node:
	var b := building()
	if b == null or not OPENINGS.has(opening):
		return null
	if String(OPENINGS[opening]["kind"]) == "door":
		return b.get_door(opening)
	return b.get_window_pane(opening)


## 開いているか。扉も窓も is_open を持つ。
static func is_opening_open(opening: StringName) -> bool:
	var n := opening_node(opening)
	if n == null:
		return false
	return bool(n.get(&"is_open"))


## 開口部の穴の中心(高さ込み)。引っ掻き音・窓を叩く音の鳴る位置。
static func opening_center(opening: StringName) -> Vector3:
	if not OPENINGS.has(opening):
		return Vector3.ZERO
	var o: Dictionary = OPENINGS[opening]
	var a: Vector3 = o["outside"]
	var b: Vector3 = o["inside"]
	var mid := (a + b) * 0.5
	mid.y = (float(o["sill"]) + float(o["head"])) * 0.5
	return mid


## from に一番近い「開いている」開口部。無ければ &""。
static func nearest_open_opening(from: Vector3, only_open: bool = true) -> StringName:
	var best: StringName = &""
	var best_d := INF
	for k in OPENINGS:
		if only_open and not is_opening_open(k):
			continue
		var d: float = from.distance_to(OPENINGS[k]["inside"])
		if d < best_d:
			best_d = d
			best = k
	return best


# ---------------------------------------------------------------- ナビ

## ナビメッシュ上の一番近い点に寄せる。マップが未同期なら元の座標を返す。
static func snap(world: World3D, pos: Vector3) -> Vector3:
	if world == null:
		return pos
	var p := NavigationServer3D.map_get_closest_point(world.navigation_map, pos)
	if p.is_equal_approx(Vector3.ZERO) and pos.length() > 1.0:
		return pos
	return p


# ---------------------------------------------------------------- 視線

## a → b が layer 1(world)に遮られていないか。
static func clear_line(world: World3D, a: Vector3, b: Vector3, exclude: Array[RID] = []) -> bool:
	if world == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.collide_with_areas = false
	q.exclude = exclude
	return world.direct_space_state.intersect_ray(q).is_empty()


## 窓越しでも「見えている」とみなす判定。
## 閉じた窓のガラスは layer 1 の当たり判定を持つので、線分が窓の穴を通るなら見えている扱いにする。
static func visible_through_openings(world: World3D, a: Vector3, b: Vector3,
		exclude: Array[RID] = []) -> bool:
	if clear_line(world, a, b, exclude):
		return true
	for k in OPENINGS:
		if _segment_through_opening(k, a, b):
			return true
	return false


static func _segment_through_opening(opening: StringName, a: Vector3, b: Vector3) -> bool:
	var o: Dictionary = OPENINGS[opening]
	var inside: Vector3 = o["inside"]
	var outside: Vector3 = o["outside"]
	# 開口部は軸に平行な壁にしかないので、法線は X か Z のどちらか。
	var axis_x: bool = absf(inside.x - outside.x) > absf(inside.z - outside.z)
	var plane: float = (inside.x + outside.x) * 0.5 if axis_x else (inside.z + outside.z) * 0.5
	var a0: float = a.x if axis_x else a.z
	var b0: float = b.x if axis_x else b.z
	if is_equal_approx(a0, b0):
		return false
	var t := (plane - a0) / (b0 - a0)
	if t < 0.0 or t > 1.0:
		return false
	var hit := a.lerp(b, t)
	var across: float = hit.z if axis_x else hit.x
	var center: float = inside.z if axis_x else inside.x
	if absf(across - center) > float(o["width"]) * 0.5:
		return false
	return hit.y >= float(o["sill"]) and hit.y <= float(o["head"])


# ---------------------------------------------------------------- マテリアル

## マテリアル名でサーフェスを探し、複製してから emission を差し替える。
## models_notes.md の「`Eyes` は duplicate() してから触る」に従う。返り値は触った枚数。
static func set_emission(root: Node, material_name: String, energy: float,
		color: Color = Color(0, 0, 0, 0)) -> int:
	if root == null:
		return 0
	var n := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src == null or String(src.resource_name) != material_name:
				continue
			var mat := mi.get_surface_override_material(i) as BaseMaterial3D
			if mat == null or mat == src:
				mat = (src as BaseMaterial3D).duplicate()
				mi.set_surface_override_material(i, mat)
			mat.emission_enabled = energy > 0.0
			if color.a > 0.0:
				mat.emission = Color(color.r, color.g, color.b)
			mat.emission_energy_multiplier = energy
			n += 1
	return n


## glb のアニメは全部 LOOP_NONE で入っているので、ループさせたいものだけ直す。
static func force_loop(player: AnimationPlayer, names: Array) -> void:
	if player == null:
		return
	for n in names:
		var an := String(n)
		if not player.has_animation(an):
			continue
		var a := player.get_animation(an)
		if a and a.loop_mode == Animation.LOOP_NONE:
			a.loop_mode = Animation.LOOP_LINEAR


## モデルの全メッシュの透明度(0 = 不透明 / 1 = 透明)。despawn のフェードに使う。
static func set_transparency(root: Node, v: float) -> void:
	if root == null:
		return
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).transparency = clampf(v, 0.0, 1.0)
