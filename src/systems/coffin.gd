class_name Coffin
extends Interactable
## 棺。式場の中心。小窓・ドライアイス・猫のまたぎ判定・蓋のずれ・顔の状態を持つ。
##
## ■ 小窓について
## 掟4「棺の小窓を開けぬこと」があるので allow_open_window は既定で false。
## ドライアイス交換のときだけ、仕事として小窓越しに顔が見える(design.md「顔を見る唯一の機会」)。
## 00:30 に息子へ開けさせる選択をしたら director が allow_open_window = true にする。
##
## director からの使い方:
##     var cof := SystemsInstaller.find(&"coffin") as Coffin
##     cof.knock()                     # 中から一度「コン」
##     cof.scratch()                   # 内側から引っ掻く
##     cof.set_lid_ajar(true)          # 蓋が 10cm ずれる
##     cof.set_face_state(2)           # 目が開いている
##     cof.set_handprint(true)         # 小窓の内側に手形
##     cof.set_open(true)              # 04:00 以降、棺が開いている
##     await cof.show_face(3.0)        # 顔ビューを見せる(プレイヤーは固定される)
##     Events.on(&"cat_crossed_coffin", func(_d): ...)   # 猫がまたいだ = 異変度 +3

signal face_shown
signal face_hidden
signal cat_crossed

@export var allow_open_window: bool = false
@export var refuse_line: String = "……開けてはいけない。"
@export var peek_prompt: String = "小窓を覗く"
@export var dry_ice_prompt: String = "ドライアイスを交換する"
@export var dry_ice_hold_time: float = 2.0
@export var dry_ice_item: StringName = &"dry_ice"
@export var cat_dread: int = 3
@export var face_view_seconds: float = 3.0

## 蓋の上面の高さと小窓の位置。coffin.glb に "Window" メッシュがあれば
## 起動時にその実寸で上書きするので、通常はいじらなくてよい。
@export var lid_top_y: float = 0.444
@export var window_offset: Vector3 = Vector3(0.64, 0.0, 0.0)
@export var window_size: Vector2 = Vector2(0.26, 0.20)
@export var lid_slide: float = 0.10
@export var body_length: float = 1.98
## coffin.glb の小窓は「枠」だけで蓋に穴が開いていないため、顔は薄い板として
## 小窓のガラス面のすぐ上に重ねる。ここはその持ち上げ量(m)。
## ごく薄いので蓋から飛び出しては見えない。
@export var face_lift: float = 0.0012
## 蓋に小窓の穴が開いたら true にすると、body_face.glb を立体で中に置く。
## 現状の coffin.glb には穴が無いので既定は false。
@export var use_face_model: bool = false
## use_face_model のときの、小窓から顔までの深さ。
@export var face_model_depth: float = 0.11
## 顔のわずかな自発光。暗い式場でも小窓を覗けば顔が読めるようにするため。
@export var face_emission: float = 0.10
## 小窓の中のごく弱い光。
@export var window_light_energy: float = 0.10

## face_state 0..3 に対応するテクスチャ名(assets/textures/)
const FACE_TEXTURES := ["body_face_calm", "body_face_mouth", "body_face_eyes", "body_face_turned"]

var face_state: int = 0:
	set = set_face_state

var is_lid_ajar: bool = false
var is_open: bool = false
var has_handprint: bool = false
var cat_has_crossed: bool = false
var is_showing_face: bool = false

var _prop: Prop
var _lid_placeholder: MeshInstance3D
var _lid_node: Node3D
var _lid_rest: Vector3 = Vector3.ZERO
var _window_root: Node3D
var _glass: MeshInstance3D
var _face: MeshInstance3D
var _face_prop: Prop
var _handprint: MeshInstance3D
var _window_light: OmniLight3D
var _face_cam: Camera3D
var _cat_zone: Area3D
var _breath_timer: float = 0.0
var _prev_cam: Camera3D

func _ready() -> void:
	super._ready()
	prompt = peek_prompt
	_prop = get_node_or_null(^"Prop") as Prop
	_cat_zone = get_node_or_null(^"CatZone") as Area3D
	_build_lid()
	_build_window()
	_build_face_camera()
	_connect_cat_zone()
	set_face_state(face_state)
	set_process(true)

# --------------------------------------------------------------------------
# 組み立て
# --------------------------------------------------------------------------

func _build_lid() -> void:
	# glb があれば蓋のノードを探す。無ければ箱の蓋を自前で作る。
	_lid_node = _find_lid_in_model()
	if _lid_node == null:
		_lid_placeholder = MeshInstance3D.new()
		_lid_placeholder.name = "LidPlaceholder"
		var box := BoxMesh.new()
		box.size = Vector3(body_length + 0.05, 0.08, 0.66)
		_lid_placeholder.mesh = box
		_lid_placeholder.material_override = SystemUtil.flat_material(Color(0.30, 0.24, 0.20))
		_lid_placeholder.position = Vector3(0, lid_top_y - 0.04, 0)
		_lid_placeholder.visible = not SystemUtil.has_model("coffin")
		add_child(_lid_placeholder)
		_lid_node = _lid_placeholder
	_lid_rest = _lid_node.position

func _find_lid_in_model() -> Node3D:
	if _prop == null:
		return null
	var inst := _prop.get_instance()
	if inst == null:
		return null
	for n in inst.find_children("*", "Node3D", true, false):
		if String(n.name).to_lower().contains("lid"):
			return n as Node3D
	return null

func _build_window() -> void:
	# coffin.glb に "Window"(小窓の枠)があれば、その実寸に合わせる
	var model_window := false
	if _prop:
		var wb := SystemUtil.part_bounds(_prop.get_instance(), "Window", self)
		if wb.size.x > 0.01:
			var c := wb.get_center()
			window_offset = Vector3(c.x, 0.0, c.z)
			lid_top_y = wb.position.y + wb.size.y
			window_size = Vector2(wb.size.x * 0.74, wb.size.z * 0.74)
			model_window = true

	_window_root = Node3D.new()
	_window_root.name = "SmallWindow"
	_window_root.position = Vector3(window_offset.x, lid_top_y + 0.001, window_offset.z)
	add_child(_window_root)

	if not model_window:
		# モデルが無いときだけ、自前で窓枠を作る
		var frame_mat := SystemUtil.flat_material(Color(0.16, 0.13, 0.11))
		var t := 0.018
		var fw := window_size.x
		var fh := window_size.y
		for spec in [
			[Vector3(0, 0, -fh * 0.5 - t * 0.5), Vector3(fw + t * 2.0, 0.012, t)],
			[Vector3(0, 0, fh * 0.5 + t * 0.5), Vector3(fw + t * 2.0, 0.012, t)],
			[Vector3(-fw * 0.5 - t * 0.5, 0, 0), Vector3(t, 0.012, fh)],
			[Vector3(fw * 0.5 + t * 0.5, 0, 0), Vector3(t, 0.012, fh)],
		]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = spec[1]
			mi.mesh = bm
			mi.position = spec[0] + Vector3(0, 0.006, 0)
			mi.material_override = frame_mat
			_window_root.add_child(mi)

	# 小窓の奥(暗い内側)
	var inner := MeshInstance3D.new()
	inner.name = "Inner"
	var iq := QuadMesh.new()
	iq.size = window_size * 1.05
	inner.mesh = iq
	inner.rotation_degrees = Vector3(-90, 0, 0)     # 上(+Y)を向く
	inner.position = Vector3(0, face_lift - 0.0006, 0)
	inner.material_override = SystemUtil.flat_material(Color(0.015, 0.015, 0.02))
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_window_root.add_child(inner)

	# body_face.glb を立体で置けるのは、蓋に小窓の穴が開いてから。
	if use_face_model and SystemUtil.has_model("body_face"):
		_face_prop = Prop.new()
		_face_prop.name = "FaceModel"
		_face_prop.add_collision = false
		_face_prop.cast_shadow = false
		_face_prop.position = Vector3(0, -face_model_depth, 0)
		var fit: float = minf(window_size.x / 0.40, window_size.y / 0.30)
		_face_prop.scale = Vector3(fit, 1.0, fit)
		_face_prop.model_name = "body_face"
		_window_root.add_child(_face_prop)

	# 顔(薄い板。枠のくぼみに収まるので蓋から飛び出さない)
	_face = MeshInstance3D.new()
	_face.name = "Face"
	var fq := QuadMesh.new()
	# 面内で 90 度回すので、幅と奥行きを入れ替えて小窓にぴったり収める
	fq.size = Vector2(window_size.y * 0.99, window_size.x * 0.99)
	_face.mesh = fq
	# 上向きにして、さらに面内で 90 度回す。こうすると画像の上が棺の -X(頭側)を向き、
	# 顔ビュー(カメラの上 = -X)で顔が正しい向きに見える。
	_face.rotation_degrees = Vector3(-90, 0, 90)
	_face.position = Vector3(0, face_lift, 0)
	_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_face.visible = _face_prop == null
	_window_root.add_child(_face)

	# 内側からの手形
	_handprint = MeshInstance3D.new()
	_handprint.name = "Handprint"
	var hq := QuadMesh.new()
	hq.size = Vector2(window_size.x * 0.46, window_size.x * 0.46)
	_handprint.mesh = hq
	_handprint.rotation_degrees = Vector3(-90, 0, 90)
	_handprint.position = Vector3(window_size.x * 0.22, face_lift + 0.0008, -window_size.y * 0.18)
	var hm := SystemUtil.alpha_material(SystemUtil.handprint_texture(), Color(0.34, 0.40, 0.48, 1.0), false, true)
	hm.render_priority = 2   # 顔より後に描く
	_handprint.material_override = hm
	_handprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_handprint.visible = false
	_window_root.add_child(_handprint)

	# ガラス(うっすら反射)
	_glass = MeshInstance3D.new()
	_glass.name = "Glass"
	var gq := QuadMesh.new()
	gq.size = window_size
	_glass.mesh = gq
	_glass.rotation_degrees = Vector3(-90, 0, 0)
	_glass.position = Vector3(0, face_lift + 0.0016, 0)
	var gm := SystemUtil.alpha_material(null, Color(0.55, 0.60, 0.62, 0.16), false, false)
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	gm.render_priority = 3   # 一番手前
	_glass.material_override = gm
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_window_root.add_child(_glass)

	# 小窓の中は真っ暗なので、顔が見える程度のごく弱い光を入れる
	_window_light = OmniLight3D.new()
	_window_light.name = "WindowLight"
	_window_light.light_color = Color(0.80, 0.82, 0.88)
	_window_light.light_energy = window_light_energy
	_window_light.omni_range = 0.7
	_window_light.omni_attenuation = 1.2
	_window_light.shadow_enabled = false
	_window_light.position = Vector3(0, 0.30, 0)
	_window_root.add_child(_window_light)

func _build_face_camera() -> void:
	_face_cam = Camera3D.new()
	_face_cam.name = "FaceCam"
	_face_cam.fov = 48.0
	_face_cam.near = 0.02
	_face_cam.current = false
	add_child(_face_cam)

func _connect_cat_zone() -> void:
	if _cat_zone == null:
		return
	_cat_zone.monitoring = true
	_cat_zone.monitorable = false
	_cat_zone.body_entered.connect(_on_cat_zone_entered)
	_cat_zone.area_entered.connect(_on_cat_zone_entered)

func _on_cat_zone_entered(node: Node) -> void:
	if node == null:
		return
	var n: Node = node
	# 猫本体でなく子の Area/Body が入ってくることもあるので親もたどる
	for _i in 3:
		if n == null:
			break
		if n.is_in_group(&"cat"):
			_on_cat_crossed()
			return
		n = n.get_parent()

func _on_cat_crossed() -> void:
	if cat_has_crossed:
		return
	cat_has_crossed = true
	Game.set_flag(&"cat_crossed_coffin", true)
	Events.emit_event(&"cat_crossed_coffin")
	Dread.add(cat_dread, &"cat_crossed_coffin")
	creak()
	cat_crossed.emit()

# --------------------------------------------------------------------------
# 音と動き
# --------------------------------------------------------------------------

## 中から一度「コン」。線香が絶えた瞬間に鳴る。
func knock() -> void:
	Audio.play_at(&"coffin_knock", global_position, 0.0, 1.0, 25.0)
	_shake(0.006, 0.10)

func creak() -> void:
	Audio.play_at(&"coffin_creak", global_position, 0.0, 1.0, 25.0)
	_shake(0.010, 0.45)

func scratch() -> void:
	Audio.play_at(&"coffin_scratch", global_position, 0.0, 1.0, 25.0)
	_shake(0.003, 0.60)

func _shake(amount: float, duration: float) -> void:
	if _lid_node == null:
		return
	var tw := create_tween()
	tw.tween_property(_lid_node, "position", _lid_rest + _lid_offset() + Vector3(0, amount, 0), duration * 0.3)
	tw.tween_property(_lid_node, "position", _lid_rest + _lid_offset(), duration * 0.7)

func _lid_offset() -> Vector3:
	return Vector3(lid_slide, 0, 0) if is_lid_ajar else Vector3.ZERO

## 蓋を 10cm ずらす/戻す。
func set_lid_ajar(ajar: bool) -> void:
	if is_lid_ajar == ajar:
		return
	is_lid_ajar = ajar
	Audio.play_at(&"coffin_lid_slide", global_position)
	if _lid_node == null:
		push_warning("Coffin: 蓋のノードが無いので見た目は変わらない(glb の蓋は名前に Lid を含めてほしい)")
		return
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_lid_node, "position", _lid_rest + _lid_offset(), 1.4)

## 棺が開いている状態にする(終盤)。glb があれば coffin_lid_open に差し替える。
func set_open(open: bool) -> void:
	is_open = open
	if _prop:
		_prop.model_name = "coffin_lid_open" if open else "coffin"
	if _lid_placeholder:
		_lid_placeholder.visible = (not open) and (not SystemUtil.has_model("coffin"))
	if _window_root:
		_window_root.visible = not open
	if open:
		Audio.play_at(&"coffin_lid_slide", global_position)

## 小窓の内側についた手形。
func set_handprint(on: bool) -> void:
	has_handprint = on
	if _handprint:
		_handprint.visible = on

## 顔の状態 0 穏やか / 1 口が開く / 2 目が開いている / 3 こちらを向く
func set_face_state(state: int) -> void:
	face_state = clampi(state, 0, 3)
	var tex := _face_texture(face_state)
	if _face_prop:
		# body_face.glb の "Face" サーフェスを差し替える
		var inst := _face_prop.get_instance()
		var n := SystemUtil.set_surface_texture(inst, "Face", tex)
		if n == 0:
			push_warning("Coffin: body_face.glb に Face サーフェスが無い")
		for s2 in SystemUtil.find_surfaces(inst, "Face"):
			var m2 := SystemUtil.surface_material(s2["mi"], s2["index"])
			m2.emission_enabled = face_emission > 0.0
			m2.emission = Color(1, 1, 1)
			m2.emission_texture = tex
			m2.emission_energy_multiplier = face_emission
		# 「こちらを向く」は少し回転も足す
		_face_prop.rotation_degrees.y = 8.0 if face_state >= 3 else 0.0
	if _face:
		var mat := SystemUtil.alpha_material(tex, Color(1, 1, 1, 1), false, false)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mat.emission_enabled = face_emission > 0.0
		mat.emission = Color(1, 1, 1)
		mat.emission_texture = tex
		mat.emission_energy_multiplier = face_emission
		_face.material_override = mat

func _face_texture(state: int) -> Texture2D:
	var tex := SystemUtil.load_texture(FACE_TEXTURES[clampi(state, 0, 3)])
	if tex == null:
		tex = SystemUtil.load_texture("body_face_%d" % state)
	if tex == null:
		tex = SystemUtil.face_texture(state)
	return tex

# --------------------------------------------------------------------------
# 顔ビュー
# --------------------------------------------------------------------------

## 小窓の真上にカメラをゆっくり寄せて顔を見せる。見ている間は息の音がする。
func show_face(seconds: float = -1.0, reason: String = "peek") -> void:
	if is_showing_face:
		return
	if seconds <= 0.0:
		seconds = face_view_seconds
	is_showing_face = true
	var p := Game.player
	SystemUtil.set_locked(p, true)
	Events.emit_event(&"coffin_window_opened", {"reason": reason})
	face_shown.emit()

	var target := _window_root.global_position
	_prev_cam = get_viewport().get_camera_3d() if is_inside_tree() else null
	_face_cam.global_position = target + Vector3(0, 0.95, 0.02)
	# 故人は棺の長辺に沿って寝ているので、画面の上を棺の +X(頭側)に合わせる
	_face_cam.look_at(target, -global_transform.basis.x)
	_face_cam.current = true

	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_face_cam, "global_position", target + Vector3(0, 0.34, 0.01), minf(seconds * 0.6, 1.6))
	_breath_timer = 0.0
	await get_tree().create_timer(seconds).timeout

	_face_cam.current = false
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	SystemUtil.set_locked(p, false)
	is_showing_face = false
	face_hidden.emit()

func _process(delta: float) -> void:
	if not is_showing_face:
		return
	# 見せている間、微かに息の音
	_breath_timer -= delta
	if _breath_timer <= 0.0:
		_breath_timer = 1.5
		Audio.play_at(&"breath_close", global_position + Vector3(0, 0.3, 0), -14.0, 0.92, 6.0)

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func _has_dry_ice() -> bool:
	return SystemUtil.has_item(Game.player, dry_ice_item)

func get_prompt() -> String:
	if _has_dry_ice():
		return dry_ice_prompt
	return peek_prompt

func _can_interact(_player: Node3D) -> bool:
	return not is_showing_face and not is_open

func _interact(player: Node3D) -> void:
	if _has_dry_ice():
		_replace_dry_ice(player)
	elif allow_open_window:
		show_face(face_view_seconds, "peek")
	else:
		Dialogue.monologue(refuse_line)

func _replace_dry_ice(player: Node3D) -> void:
	Audio.play_at(&"dry_ice_sizzle", global_position)
	SystemUtil.take_item(player, dry_ice_item)
	Events.emit_event(&"dry_ice_replaced")
	show_face(face_view_seconds, "dry_ice")

## hold 時間はドライアイスを持っているかで変える。
func _process_prompt_hold() -> void:
	hold_time = dry_ice_hold_time if _has_dry_ice() else 0.0

func _physics_process(_delta: float) -> void:
	_process_prompt_hold()
