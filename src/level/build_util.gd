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
	var emat := LevelMaterials.emissive(color, 0.85)
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
		energy: float = 0.26, range_m: float = 5.0) -> Array:
	var holder := Node3D.new()
	holder.name = "ExitSign"
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	parent.add_child(holder)
	var emat := LevelMaterials.emissive(Color(0.13, 0.78, 0.30), 1.7)
	var tex_path := "res://assets/textures/exit_sign.png"
	if ResourceLoader.exists(tex_path):
		# models の絵柄(緑地に走る人と矢印)。発光させて板そのものを光らせる。
		emat.albedo_texture = load(tex_path)
		emat.emission_texture = emat.albedo_texture
		emat.albedo_color = Color.WHITE
		emat.emission = Color.WHITE
		emat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		box(holder, Vector3.ZERO, Vector3(0.34, 0.15, 0.025), emat, false, "", false)
	else:
		box(holder, Vector3.ZERO, Vector3(0.34, 0.15, 0.025), emat, false, "", false)
		# 絵柄ができるまでの代用(白い板に見えないよう淡い緑)
		box(holder, Vector3(-0.035, 0.0, 0.016), Vector3(0.045, 0.075, 0.006),
			LevelMaterials.plain(Color(0.62, 0.86, 0.66)), false, "", false)
		box(holder, Vector3(0.06, 0.0, 0.016), Vector3(0.02, 0.075, 0.006),
			LevelMaterials.plain(Color(0.62, 0.86, 0.66)), false, "", false)
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


## 同じマテリアルの箱をまとめて 1 メッシュにする(描画回数を減らす)。
## boxes = [[中心 Vector3, 大きさ Vector3], ...]。当たり判定は付かないので飾り専用。
static func merge_boxes(parent: Node, boxes: Array, mat: Material,
		node_name: String = "Merged", shadow: bool = false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # 面ごとに平らな陰影(PSX 風の箱にする)
	for bx in boxes:
		add_box_surface(st, bx[0], bx[1])
	st.generate_normals()
	st.index()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	# 統合メッシュは巻き方向の取り違えで面が消えると気づきにくいので、両面描画にしておく。
	# 小物のクラッタ用途なので負荷は無視できる。
	var m2: Material = mat.duplicate()
	if m2 is BaseMaterial3D:
		(m2 as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## 箱 1 個ぶんの面を SurfaceTool に足す(反時計回り = 表)。
static func add_box_surface(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var v := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z),
		c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z),
		c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	var faces := [
		[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6],
		[0, 4, 7, 3], [3, 7, 6, 2], [0, 1, 5, 4],
	]
	for f in faces:
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[1]])
		st.add_vertex(v[f[2]])
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[2]])
		st.add_vertex(v[f[3]])


## 円盤(八角)を SurfaceTool に足す。花輪の花びらをまとめて 1 メッシュにするため。
static func add_disc(st: SurfaceTool, center: Vector3, radius: float, segments: int) -> void:
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(center)
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(center + Vector3(cos(a0) * radius, sin(a0) * radius, 0))
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(center + Vector3(cos(a1) * radius, sin(a1) * radius, 0))


## 縦書きの札。Label3D は縦組みができないので 1 文字ずつ改行して列にする。
static func vertical_text(parent: Node, text: String, pos: Vector3, yaw_deg: float,
		char_m: float, color: Color) -> Label3D:
	var lines := PackedStringArray()
	for i in text.length():
		lines.append(text.substr(i, 1))
	var l := sign_text(parent, "\n".join(lines), pos, yaw_deg, char_m, color, true, 384)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.line_spacing = -char_m * 0.18 / l.pixel_size
	return l


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
		yaw_deg: float, size: Vector3, color: Color, collide: bool = true,
		shadow: bool = true) -> Prop:
	var p := Prop.new()
	p.name = node_name
	p.cast_shadow = shadow
	p.model_name = model
	p.placeholder_size = size
	p.placeholder_color = color
	p.add_collision = collide
	p.position = pos
	p.rotation_degrees.y = yaw_deg
	parent.add_child(p)
	return p

## 扉の脇の室名札。壁付けの小さなサイン(0.12 x 0.30)。遠目に白い板に見えないよう明度は抑える。
static func name_plate(parent: Node, text: String, pos: Vector3, yaw_deg: float) -> void:
	var holder := Node3D.new()
	holder.name = "NamePlate"
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	parent.add_child(holder)
	box(holder, Vector3.ZERO, Vector3(0.12, 0.30, 0.018), get_plate_mat(), false, "", false)
	box(holder, Vector3(0, 0, 0.011), Vector3(0.095, 0.265, 0.004),
		LevelMaterials.plain(Color(0.60, 0.57, 0.50)), false, "", false)
	vertical_text(holder, text, Vector3(0, 0.005, 0.016), 0.0, 0.055, Color(0.09, 0.09, 0.10))


static func get_plate_mat() -> StandardMaterial3D:
	return LevelMaterials.get_mat_tinted("wall_wood", 3.0, Color(0.52, 0.40, 0.28))


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
