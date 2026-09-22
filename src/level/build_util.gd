class_name LevelBuild
extends RefCounted
## 箱・壁・床・天井を組む静的ヘルパ。building.gd から呼ぶ。
## 壁は「線分 + 開口部リスト」で作る。開口部は扉/窓/出入口に使う。
##
## 座標系: X = 東、Z = 南、-Z = 北。床は y = 0。Marker3D の -Z が正面。

const WALL_T := 0.15     ## 壁の厚み
const FLOOR_T := 0.10    ## 床スラブの厚み

## 箱メッシュを1つ置く。center は箱の中心。
static func box(parent: Node, center: Vector3, size: Vector3, mat: Material,
		collide: bool = true, surface: String = "", shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if surface != "":
		mi.set_meta(&"surface", surface)
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		sb.add_child(cs)
		mi.add_child(sb)
		if surface != "":
			sb.set_meta(&"surface", surface)
	return mi

## 床。矩形 (x1,z1)-(x2,z2)、上面が y = top。足音用に surface メタを持たせる。
static func floor_slab(parent: Node, x1: float, z1: float, x2: float, z2: float,
		mat: Material, surface: String, top: float = 0.0) -> MeshInstance3D:
	var c := Vector3((x1 + x2) * 0.5, top - FLOOR_T * 0.5, (z1 + z2) * 0.5)
	var s := Vector3(absf(x2 - x1), FLOOR_T, absf(z2 - z1))
	var mi := box(parent, c, s, mat, true, surface, false)
	mi.name = "Floor"
	return mi

## 天井。下面が y = h。当たり判定は付けない(ナビのベイク対象から外すため)。
static func ceiling_slab(parent: Node, x1: float, z1: float, x2: float, z2: float,
		mat: Material, h: float) -> MeshInstance3D:
	var c := Vector3((x1 + x2) * 0.5, h + FLOOR_T * 0.5, (z1 + z2) * 0.5)
	var s := Vector3(absf(x2 - x1), FLOOR_T, absf(z2 - z1))
	var mi := box(parent, c, s, mat, false, "", false)
	mi.name = "Ceiling"
	return mi

## 壁。(x1,z1) から (x2,z2) へ、高さ h。
## openings = [{"t": 線分始点からの距離, "w": 幅, "sill": 下端, "head": 上端}, ...]
## sill > 0 なら腰壁が、head < h なら垂れ壁が残る(= 窓)。
static func wall(parent: Node, x1: float, z1: float, x2: float, z2: float, h: float,
		mat: Material, openings: Array = [], thickness: float = WALL_T) -> Node3D:
	var dx := x2 - x1
	var dz := z2 - z1
	var length := sqrt(dx * dx + dz * dz)
	if length < 0.001:
		return null
	var seg := Node3D.new()
	seg.name = "Wall"
	seg.position = Vector3(x1, 0.0, z1)
	seg.rotation.y = atan2(-dz, dx)
	parent.add_child(seg)

	var sorted := openings.duplicate()
	sorted.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var cursor := 0.0
	for o in sorted:
		var t := float(o["t"])
		var w := float(o["w"])
		var sill := float(o.get("sill", 0.0))
		var head := float(o.get("head", h))
		var a := clampf(t - w * 0.5, 0.0, length)
		var b := clampf(t + w * 0.5, 0.0, length)
		if a > cursor + 0.001:
			_piece(seg, cursor, a, 0.0, h, thickness, mat)
		if sill > 0.001:
			_piece(seg, a, b, 0.0, sill, thickness, mat)
		if head < h - 0.001:
			_piece(seg, a, b, head, h, thickness, mat)
		cursor = maxf(cursor, b)
	if cursor < length - 0.001:
		_piece(seg, cursor, length, 0.0, h, thickness, mat)
	return seg

static func _piece(seg: Node3D, t0: float, t1: float, y0: float, y1: float,
		thickness: float, mat: Material) -> void:
	var w := t1 - t0
	var hh := y1 - y0
	if w <= 0.001 or hh <= 0.001:
		return
	box(seg, Vector3((t0 + t1) * 0.5, (y0 + y1) * 0.5, 0.0), Vector3(w, hh, thickness), mat, true, "", true)

## 蛍光灯。灯体メッシュ(発光)と OmniLight3D を返す。
## 戻り値 [light, mesh, mat]
static func fluorescent(parent: Node, pos: Vector3, length: float, color: Color,
		energy: float, range_m: float, shadow: bool) -> Array:
	var holder := Node3D.new()
	holder.name = "Lamp"
	holder.position = pos
	parent.add_child(holder)
	# 器具の台座
	box(holder, Vector3(0, 0.06, 0), Vector3(length + 0.12, 0.08, 0.26),
		LevelMaterials.plain(Color(0.72, 0.71, 0.68)), false, "", false)
	var emat := LevelMaterials.emissive(color, 1.25)
	var mi := box(holder, Vector3(0, 0.0, 0), Vector3(length, 0.07, 0.11), emat, false, "", false)
	mi.name = "Tube"
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, -0.06, 0)
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.omni_attenuation = 1.4
	light.shadow_enabled = shadow
	light.light_specular = 0.0
	holder.add_child(light)
	return [light, mi, emat]

## 裸電球/ダウンライト風の点光源。戻り値 [light, mesh, mat]
static func bulb(parent: Node, pos: Vector3, color: Color, energy: float,
		range_m: float, shadow: bool) -> Array:
	var holder := Node3D.new()
	holder.name = "Lamp"
	holder.position = pos
	parent.add_child(holder)
	var emat := LevelMaterials.emissive(color, 1.15)
	var mi := box(holder, Vector3.ZERO, Vector3(0.22, 0.1, 0.22), emat, false, "", false)
	mi.name = "Bulb"
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, -0.08, 0)
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.omni_attenuation = 1.5
	light.shadow_enabled = shadow
	light.light_specular = 0.0
	holder.add_child(light)
	return [light, mi, emat]

## 非常口サイン。緑の発光板と弱い緑の光。ローカル +Z が表。戻り値 [light, mat]
static func exit_sign(parent: Node, pos: Vector3, yaw_deg: float,
		energy: float = 0.32, range_m: float = 5.0) -> Array:
	var holder := Node3D.new()
	holder.name = "ExitSign"
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	parent.add_child(holder)
	var emat := LevelMaterials.emissive(Color(0.13, 0.78, 0.30), 1.7)
	box(holder, Vector3.ZERO, Vector3(0.34, 0.15, 0.025), emat, false, "", false)
	# 非常口の白いピクトグラム代わり
	box(holder, Vector3(-0.04, 0.0, 0.016), Vector3(0.07, 0.10, 0.006),
		LevelMaterials.plain(Color(0.88, 0.95, 0.88)), false, "", false)
	box(holder, Vector3(0.08, 0.0, 0.016), Vector3(0.03, 0.10, 0.006),
		LevelMaterials.plain(Color(0.88, 0.95, 0.88)), false, "", false)
	# 天吊りの金具
	box(holder, Vector3(0, 0.11, 0), Vector3(0.36, 0.06, 0.07),
		LevelMaterials.plain(Color(0.20, 0.20, 0.21)), false, "", false)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, -0.2, 0.1)
	light.light_color = Color(0.40, 0.95, 0.55)
	light.light_energy = energy
	light.omni_range = range_m
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.light_specular = 0.0
	holder.add_child(light)
	return [light, emat]


## Marker3D のアンカー。yaw は度。-Z が正面。
static func marker(parent: Node, anchor_name: String, pos: Vector3, yaw_deg: float = 0.0) -> Marker3D:
	var m := Marker3D.new()
	m.name = anchor_name
	m.position = pos
	m.rotation_degrees.y = yaw_deg
	parent.add_child(m)
	return m

## Prop(models 担当の glb が無い間は箱)。pos は接地面の中心。
static func prop(parent: Node, node_name: String, model: String, pos: Vector3,
		yaw_deg: float, size: Vector3, color: Color, collide: bool = true) -> Prop:
	var p := Prop.new()
	p.name = node_name
	p.model_name = model
	p.placeholder_size = size
	p.placeholder_color = color
	p.add_collision = collide
	p.position = pos
	p.rotation_degrees.y = yaw_deg
	parent.add_child(p)
	return p

## 世界に置く文字(看板・貼り紙)。DotGothic16 ではなく明朝(看板向き)。
## font_px を大きくするほど文字のテクスチャが高解像度になる。
## 640x360 に縮小されるので、NEAREST だと画数の多い漢字が潰れる。ここだけ LINEAR + mipmap。
static func sign_text(parent: Node, text: String, pos: Vector3, yaw_deg: float,
		size_m: float, color: Color, mincho: bool = true, font_px: int = 256) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees.y = yaw_deg
	l.font_size = font_px
	l.pixel_size = size_m / float(font_px)
	l.modulate = color
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = false
	l.shaded = true
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var fpath := "res://assets/fonts/ShipporiMincho-Regular.ttf" if mincho else "res://assets/fonts/DotGothic16-Regular.ttf"
	if ResourceLoader.exists(fpath):
		l.font = load(fpath)
	parent.add_child(l)
	return l
