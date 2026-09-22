class_name SystemUtil
extends RefCounted
## systems 共通のヘルパ。
##  - プレイヤー API の安全な呼び出し(player 担当の実装が無い/引数が違っても落ちない)
##  - 手続き的なテクスチャ生成(炎・煙・顔・手形など。assets が無い間の見た目を自前で作る)
##  - パーティクル/マテリアルの生成
## 画像アセットが assets/textures に入ったら、各プレハブが自動でそちらを優先する。

## 3D レンダーレイヤー(project.godot の 3d_render/layer_* と対応)
const LAYER_DEFAULT := 1 << 0        # "default"      : 全部のカメラが見る
const LAYER_CCTV_ONLY := 1 << 9      # "cctv_only"    : 監視モニターにだけ映る
const LAYER_PLAYER_HIDDEN := 1 << 10 # "player_hidden": 監視モニターには映らない

const MODEL_DIR := "res://assets/models/"
const TEXTURE_DIR := "res://assets/textures/"

# --------------------------------------------------------------------------
# プレイヤー API(player 担当の実装が未完でも落ちないように全部 has_method 経由)
# --------------------------------------------------------------------------

static func player() -> Node:
	return Game.player

static func has_item(p: Node, item: StringName) -> bool:
	if p == null or not p.has_method(&"has_item"):
		return false
	return bool(p.call(&"has_item", item))

## give_item(name) / give_item(name, carried) のどちらの実装でも通るように呼び分ける。
static func give_item(p: Node, item: StringName, carried: bool = false) -> void:
	if p == null or item == &"" or not p.has_method(&"give_item"):
		push_warning("SystemUtil: give_item できない (player=%s item=%s)" % [p, item])
		return
	var c := Callable(p, &"give_item")
	if c.get_argument_count() >= 2:
		c.call(item, carried)
	else:
		c.call(item)

static func take_item(p: Node, item: StringName) -> void:
	if p == null or not p.has_method(&"take_item"):
		return
	p.call(&"take_item", item)

static func set_locked(p: Node, locked: bool) -> void:
	if p == null or not p.has_method(&"set_locked"):
		return
	p.call(&"set_locked", locked)

static func look_at_point(p: Node, point: Vector3, duration: float = 0.8) -> void:
	if p == null or not p.has_method(&"look_at_point"):
		return
	var c := Callable(p, &"look_at_point")
	if c.get_argument_count() >= 2:
		c.call(point, duration)
	else:
		c.call(point)

# --------------------------------------------------------------------------
# アセットの有無
# --------------------------------------------------------------------------

static func has_model(name: String) -> bool:
	return name != "" and ResourceLoader.exists(MODEL_DIR + name + ".glb")

static func texture_path(name: String) -> String:
	for ext: String in [".png", ".jpg", ".webp"]:
		var p: String = TEXTURE_DIR + name + ext
		if ResourceLoader.exists(p):
			return p
	return ""

static func load_texture(name: String) -> Texture2D:
	var p := texture_path(name)
	if p == "":
		return null
	return load(p) as Texture2D

# --------------------------------------------------------------------------
# glb のサーフェス操作
#   models 担当のモデルはマテリアル名が付いている(例: coffin の "CoffinWood"、
#   candle_stand の "Flame"、monitor_crt の "Screen"、iei_frame の "Photo")。
#   名前で探して、テクスチャを差し替える / 消す / 色を付ける。
# --------------------------------------------------------------------------

## マテリアル名でサーフェスを探す。戻り値は [{mi: MeshInstance3D, index: int}, ...]
static func find_surfaces(root: Node, material_name: String) -> Array:
	var out: Array = []
	if root == null:
		return out
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m != null and m.resource_name == material_name:
				out.append({"mi": mi, "index": i})
	return out

## そのサーフェス専用のマテリアル(無ければ複製して割り当てる)。
static func surface_material(mi: MeshInstance3D, index: int) -> BaseMaterial3D:
	var m := mi.get_surface_override_material(index)
	if m == null:
		var a := mi.get_active_material(index)
		m = (a as BaseMaterial3D).duplicate() if a is BaseMaterial3D else StandardMaterial3D.new()
		mi.set_surface_override_material(index, m)
	return m as BaseMaterial3D

## モデルの一部を見えなくする(炎や火種を自前のものに置き換えるとき)。
## 元のマテリアルを加工するのではなく、完全に空の透明マテリアルで上書きする
## (元が emission を持っていると albedo を透明にしても光って残るため)。
static func hide_surfaces(root: Node, material_name: String) -> int:
	var found := find_surfaces(root, material_name)
	for s in found:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0, 0, 0, 0)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = false
		m.disable_receive_shadows = true
		(s["mi"] as MeshInstance3D).set_surface_override_material(s["index"], m)
	return found.size()

## モデルの一部のテクスチャを差し替える(遺影・顔)。
static func set_surface_texture(root: Node, material_name: String, tex: Texture2D) -> int:
	var found := find_surfaces(root, material_name)
	for s in found:
		var m := surface_material(s["mi"], s["index"])
		m.albedo_texture = tex
		m.albedo_color = Color(1, 1, 1, 1)
	return found.size()

## モデルの一部に色を掛ける(しおれた花など)。
static func tint_surfaces(root: Node, material_name: String, color: Color) -> int:
	var found := find_surfaces(root, material_name)
	for s in found:
		var m := surface_material(s["mi"], s["index"])
		m.albedo_color = color
	return found.size()

## モデルの一部に自前のマテリアル(シェーダなど)を貼る(モニターの画面)。
static func override_surfaces(root: Node, material_name: String, mat: Material) -> int:
	var found := find_surfaces(root, material_name)
	for s in found:
		(s["mi"] as MeshInstance3D).set_surface_override_material(s["index"], mat)
	return found.size()

## 名前でメッシュを探し、その AABB を reference のローカル座標で返す。
## 見つからなければ size が 0。モデルの小窓や画面の実寸に合わせるために使う。
static func part_bounds(root: Node, node_name: String, reference: Node3D) -> AABB:
	if root == null or reference == null or not reference.is_inside_tree():
		return AABB()
	var n := root.find_child(node_name, true, false)
	if n == null or not (n is MeshInstance3D):
		return AABB()
	var mi := n as MeshInstance3D
	if not mi.is_inside_tree():
		return AABB()
	var t := reference.global_transform.affine_inverse() * mi.global_transform
	return t * mi.get_aabb()

# --------------------------------------------------------------------------
# マテリアル
# --------------------------------------------------------------------------

## 光って見える板(炎・画面・火種など)。unshaded + emission。
static func emissive_material(tex: Texture2D, color: Color, energy: float = 2.0, billboard: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.albedo_texture = tex
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.disable_receive_shadows = true
	m.no_depth_test = false
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	return m

## 半透明の板(煙・霧・手形など)。
static func alpha_material(tex: Texture2D, color: Color, billboard: bool = true, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	return m

## つや消しの単色(PSX 風)。
static func flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m

# --------------------------------------------------------------------------
# 手続き的テクスチャ(assets/textures が空でも「火が火に見える」ようにする)
# --------------------------------------------------------------------------

static func _make_texture(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)

## 中心が白く外が透明な丸。煙/霧/光のにじみに使う。
static func soft_circle(size: int = 64, softness: float = 1.0) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, softness * 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return _make_texture(img)

## ロウソク/線香の炎。下が青く、芯が白黄、外縁が橙のしずく形。
static func flame_texture(w: int = 48, h: int = 96) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var core := Color(1.0, 0.97, 0.80)
	var mid := Color(1.0, 0.66, 0.20)
	var edge := Color(0.95, 0.30, 0.04)
	var base := Color(0.35, 0.55, 1.0)
	for py in h:
		# y: 0 = 炎の下端, 1 = 先端
		var y := 1.0 - (float(py) + 0.5) / float(h)
		var hw := 0.0
		if y < 0.30:
			var k: float = (0.30 - y) / 0.30
			hw = 0.85 * sqrt(maxf(0.0, 1.0 - k * k))
		else:
			hw = 0.85 * pow(maxf(0.0, (1.0 - y) / 0.70), 0.75)
		for px in w:
			var x := ((float(px) + 0.5) / float(w) - 0.5) * 2.0
			if hw <= 0.001:
				img.set_pixel(px, py, Color(0, 0, 0, 0))
				continue
			var t: float = absf(x) / hw
			var a: float = clampf((1.0 - t) / 0.45, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			if a <= 0.0:
				img.set_pixel(px, py, Color(0, 0, 0, 0))
				continue
			var col := core.lerp(mid, clampf(t * 1.35, 0.0, 1.0))
			col = col.lerp(edge, clampf(y * 0.85 + t * 0.45 - 0.25, 0.0, 1.0))
			if y < 0.14:
				col = col.lerp(base, (0.14 - y) / 0.14 * 0.75)
			img.set_pixel(px, py, Color(col.r, col.g, col.b, a))
	return _make_texture(img)

## 線香の火種。小さな赤い点。
static func ember_texture(size: int = 24) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.8)
			var col := Color(1.0, 0.55, 0.14).lerp(Color(0.66, 0.06, 0.01), clampf(d * 1.5, 0.0, 1.0))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return _make_texture(img)

static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, col: Color, soft: float = 0.12) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var nx := (float(x) + 0.5) / float(w)
			var ny := (float(y) + 0.5) / float(h)
			var d := Vector2((nx - cx) / rx, (ny - cy) / ry).length()
			if d > 1.0 + soft:
				continue
			var a: float = clampf((1.0 + soft - d) / maxf(soft, 0.001), 0.0, 1.0) * col.a
			if a <= 0.0:
				continue
			var prev := img.get_pixel(x, y)
			var out := prev.lerp(Color(col.r, col.g, col.b, 1.0), a)
			out.a = maxf(prev.a, a)
			img.set_pixel(x, y, out)

## 棺の小窓越しの顔(assets/textures/body_face_<state>.png が無いとき用)。
## state 0: 穏やか / 1: 口が開く / 2: 目が開いている / 3: こちらを向く
static func face_texture(state: int, size: int = 96) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var skin := Color(0.80, 0.76, 0.70, 1.0)
	var shade := Color(0.55, 0.51, 0.47, 1.0)
	var dark := Color(0.06, 0.05, 0.05, 1.0)
	var off := 0.10 if state >= 3 else 0.0   # こちらを向く = 顔が横にずれる
	# 白布(顔の周り)
	_ellipse(img, 0.5, 0.52, 0.48, 0.50, Color(0.88, 0.87, 0.84, 1.0), 0.06)
	# 顔
	_ellipse(img, 0.5 + off, 0.52, 0.30, 0.38, skin, 0.08)
	_ellipse(img, 0.5 + off, 0.70, 0.22, 0.20, shade, 0.30)
	# 目
	if state >= 2:
		_ellipse(img, 0.40 + off, 0.45, 0.075, 0.055, Color(0.92, 0.90, 0.86, 1.0), 0.10)
		_ellipse(img, 0.60 + off, 0.45, 0.075, 0.055, Color(0.92, 0.90, 0.86, 1.0), 0.10)
		_ellipse(img, 0.40 + off * 1.6, 0.455, 0.032, 0.032, dark, 0.10)
		_ellipse(img, 0.60 + off * 1.6, 0.455, 0.032, 0.032, dark, 0.10)
	else:
		_ellipse(img, 0.40, 0.46, 0.070, 0.013, shade, 0.30)
		_ellipse(img, 0.60, 0.46, 0.070, 0.013, shade, 0.30)
	# 口
	var mouth_h := 0.012
	if state >= 1:
		mouth_h = 0.045
	if state >= 3:
		mouth_h = 0.060
	_ellipse(img, 0.5 + off, 0.665, 0.070, mouth_h, dark if state >= 1 else shade, 0.25)
	return _make_texture(img)

## 小窓の内側についた手の跡。
static func handprint_texture(size: int = 96) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.88, 0.90, 0.92, 0.60)
	_ellipse(img, 0.50, 0.68, 0.175, 0.150, c, 0.22)        # 手のひら
	_ellipse(img, 0.31, 0.45, 0.042, 0.115, c, 0.22)        # 指
	_ellipse(img, 0.44, 0.38, 0.042, 0.140, c, 0.22)
	_ellipse(img, 0.57, 0.39, 0.042, 0.135, c, 0.22)
	_ellipse(img, 0.68, 0.47, 0.038, 0.105, c, 0.22)
	_ellipse(img, 0.25, 0.74, 0.090, 0.042, c, 0.22)        # 親指
	return _make_texture(img)

## TV の砂嵐に浮かぶ顔(暗い)。
static func tv_face_texture(size: int = 96) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_ellipse(img, 0.5, 0.50, 0.30, 0.38, Color(0.02, 0.02, 0.03, 0.80), 0.35)
	_ellipse(img, 0.5, 0.86, 0.46, 0.20, Color(0.02, 0.02, 0.03, 0.60), 0.45)
	_ellipse(img, 0.40, 0.44, 0.070, 0.050, Color(0.0, 0.0, 0.0, 0.95), 0.20)
	_ellipse(img, 0.60, 0.44, 0.070, 0.050, Color(0.0, 0.0, 0.0, 0.95), 0.20)
	_ellipse(img, 0.50, 0.66, 0.055, 0.045, Color(0.0, 0.0, 0.0, 0.90), 0.25)
	return _make_texture(img)

## TV に映る「自分の後ろ姿」の暗いシルエット。
static func back_silhouette_texture(size: int = 96) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.015, 0.015, 0.02, 0.92)
	_ellipse(img, 0.5, 0.34, 0.16, 0.19, c, 0.10)   # 後頭部
	_ellipse(img, 0.5, 0.90, 0.40, 0.36, c, 0.10)   # 肩
	return _make_texture(img)

# --------------------------------------------------------------------------
# パーティクル
# --------------------------------------------------------------------------

## 上に細く立ちのぼる煙。rise が正で上昇、wind で横に流れる。
static func make_smoke(amount: int, lifetime: float, rise: float, scale_from: float, scale_to: float, color: Color, spread: float = 6.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.preprocess = 0.0
	p.explosiveness = 0.0
	p.randomness = 0.35
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-2, -1.5, -2), Vector3(4, 5, 4))

	var pm := ParticleProcessMaterial.new()
	pm.particle_flag_align_y = false
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.008
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = rise * 0.6
	pm.initial_velocity_max = rise * 1.2
	pm.gravity = Vector3(0, rise * 0.25, 0)
	pm.damping_min = 0.02
	pm.damping_max = 0.08
	# scale_curve は Curve の max_value(既定 1.0)で頭打ちになるので、
	# 「最終サイズ」を scale_min/max に入れ、カーブは 0..1 の倍率として使う。
	pm.scale_min = scale_to
	pm.scale_max = scale_to * 1.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.12
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.12

	var start_ratio: float = clampf(scale_from / maxf(scale_to, 0.0001), 0.02, 1.0)
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 1.0
	curve.add_point(Vector2(0.0, start_ratio))
	curve.add_point(Vector2(0.45, lerpf(start_ratio, 1.0, 0.7)))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct

	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.0))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	grad.add_point(0.12, Color(color.r, color.g, color.b, color.a))
	grad.add_point(0.55, Color(color.r, color.g, color.b, color.a * 0.55))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	p.draw_pass_1 = quad
	var mat := alpha_material(soft_circle(48, 1.2), Color(1, 1, 1, 1), true, true)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	quad.material = mat
	return p

## 下に落ちる白い霧(冷凍庫のドライアイス)。
static func make_fog(amount: int, lifetime: float, spread_radius: float) -> GPUParticles3D:
	# 薄い粒をたくさん重ねて「面」に見せる。1粒が目立つと霧ではなく玉に見える。
	var p := make_smoke(amount, lifetime, 0.05, 0.10, 0.34, Color(0.90, 0.93, 1.0, 0.055), 55.0)
	var pm: ParticleProcessMaterial = p.process_material
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(spread_radius, 0.02, spread_radius * 0.6)
	pm.direction = Vector3(0, -0.35, 0)
	pm.gravity = Vector3(0, -0.14, 0)
	pm.initial_velocity_min = 0.04
	pm.initial_velocity_max = 0.16
	pm.damping_min = 0.15
	pm.damping_max = 0.4
	return p
