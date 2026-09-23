class_name Coffin
extends Interactable
## 棺。式場の中心。小窓・ドライアイス・猫のまたぎ判定・蓋のずれ・顔の状態を持つ。
##
## ■ coffin.glb の可動部(models 担当が用意した名前で拾う)
##   Lid    … 原点 (0, 0.340, 0.300)。足側の長辺が蝶番。X 回転 + で開く。
##            position.x を +0.10 すると「蓋がずれた」状態になる。
##   Window … Lid の子。visible = false で小窓が開き、中の body_face が見える。
## 小窓は本当に貫通しているので、body_face.glb を棺ローカル (0.64, 0.275, 0) に置く。
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
##     cof.set_open(true)              # 04:00 以降、棺の蓋が開いている
##     cof.set_window_open(true)       # 小窓だけ開ける
##     await cof.show_face(3.0)        # 小窓を開けて顔を見せる(プレイヤーは固定される)
##     Events.on(&"cat_crossed_coffin", func(_d): ...)   # 猫がまたいだ = 異変度 +3

signal lid_reset
signal face_shown
signal face_hidden
signal cat_crossed

@export var allow_open_window: bool = false
@export var refuse_line: String = "……開けてはいけない。"
@export var blocked_open_text: String = "開けてはいけない。"
@export var blocked_lid_open_text: String = "もう開いている。"
@export var blocked_viewing_text: String = "……見ている。"
@export var lid_reset_prompt: String = "蓋を戻す"
@export var lid_reset_hold_time: float = 1.0
## 03:40 以降、顔ビューの途中で隣にもう一つの顔が 0.5 秒だけ映る(E-11)。
@export var second_face_delay: float = 1.2
@export var second_face_seconds: float = 0.5
@export var second_face_texture: String = "body_face_second"
## もう一つの顔の位置(棺ローカル)。故人の顔の隣、小窓の端に来るようにする。
@export var second_face_offset: Vector3 = Vector3(0.628, 0.338, 0.084)
@export var second_face_size: Vector2 = Vector2(0.085, 0.108)
@export var peek_prompt: String = "小窓を覗く"
@export var dry_ice_prompt: String = "ドライアイスを交換する"
@export var dry_ice_hold_time: float = 2.0
@export var dry_ice_item: StringName = &"dry_ice"
@export var cat_dread: int = 3
@export var face_view_seconds: float = 3.0

## 故人の顔(body_face.glb)を置く位置。棺ローカル。小窓の真下。
@export var face_model_offset: Vector3 = Vector3(0.64, 0.275, 0.0)
## 顔のわずかな自発光。暗い式場でも小窓を覗けば顔が読めるようにするため。
@export var face_emission: float = 0.04
## 小窓の中のごく弱い光。
@export var window_light_energy: float = 0.14

## モデルが無いとき用のフォールバック寸法。glb があれば Window の実寸で上書きする。
@export var lid_top_y: float = 0.436
@export var window_offset: Vector3 = Vector3(0.64, 0.0, 0.0)
@export var window_size: Vector2 = Vector2(0.26, 0.20)
## 蓋をずらす距離(m)と、全開にするときの角度。
@export var lid_slide: float = 0.10
@export var lid_open_degrees: float = 62.0
@export var body_length: float = 1.98

## face_state 0..3 に対応するテクスチャ名(assets/textures/)
const FACE_TEXTURES := ["body_face_calm", "body_face_mouth", "body_face_eyes", "body_face_turned"]

var face_state: int = 0:
	set = set_face_state

var is_lid_ajar: bool = false
var is_open: bool = false
var is_window_open: bool = false
var has_handprint: bool = false
var has_second_face: bool = false
var cat_has_crossed: bool = false
var is_showing_face: bool = false

var _prop: Prop
var _lid_placeholder: MeshInstance3D
var _lid_node: Node3D
var _lid_rest: Vector3 = Vector3.ZERO
var _window_node: MeshInstance3D
var _face_prop: Prop
var _face_quad: MeshInstance3D          # glb が無いとき用
var _handprint: MeshInstance3D
var _second_face: MeshInstance3D
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
	_resolve_model_parts()
	_build_lid_fallback()
	_build_face()
	_build_handprint()
	_build_window_light()
	_build_face_camera()
	_connect_cat_zone()
	set_face_state(face_state)
	set_process(true)

# --------------------------------------------------------------------------
# 組み立て
# --------------------------------------------------------------------------

## coffin.glb の Lid / Window を名前で拾い、小窓の実寸を取り込む。
func _resolve_model_parts() -> void:
	if _prop == null:
		return
	var inst := _prop.get_instance()
	if inst == null:
		return
	for n in inst.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_lower()
		if nm == "lid" or (_lid_node == null and nm.contains("lid")):
			_lid_node = n as Node3D
		elif nm == "window":
			_window_node = n as MeshInstance3D
	if _window_node:
		var wb := SystemUtil.part_bounds(inst, "Window", self)
		if wb.size.x > 0.01:
			window_offset = Vector3(wb.get_center().x, 0.0, wb.get_center().z)
			lid_top_y = wb.position.y + wb.size.y
			window_size = Vector2(wb.size.x, wb.size.z)

## glb が無いときだけ、箱の蓋を自前で作る。
func _build_lid_fallback() -> void:
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

## 故人の顔。body_face.glb があれば小窓の真下に立体で置く。
func _build_face() -> void:
	if SystemUtil.has_model("body_face"):
		_face_prop = Prop.new()
		_face_prop.name = "FaceModel"
		_face_prop.add_collision = false
		_face_prop.cast_shadow = false
		_face_prop.position = face_model_offset
		_face_prop.model_name = "body_face"
		add_child(_face_prop)
		return
	# フォールバック: テクスチャを貼った薄い板
	_face_quad = MeshInstance3D.new()
	_face_quad.name = "FaceQuad"
	var fq := QuadMesh.new()
	fq.size = Vector2(window_size.y * 0.95, window_size.x * 0.95)
	_face_quad.mesh = fq
	_face_quad.rotation_degrees = Vector3(-90, 0, 90)
	_face_quad.position = Vector3(window_offset.x, lid_top_y - 0.16, window_offset.z)
	_face_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_face_quad)

## 小窓の内側についた手の跡。Window の子にして、小窓を開けたら一緒に消えるようにする。
func _build_handprint() -> void:
	_handprint = MeshInstance3D.new()
	_handprint.name = "Handprint"
	var hq := QuadMesh.new()
	hq.size = Vector2(window_size.x * 0.46, window_size.x * 0.46)
	_handprint.mesh = hq
	_handprint.rotation_degrees = Vector3(-90, 0, 90)
	var hm := SystemUtil.alpha_material(SystemUtil.handprint_texture(), Color(0.34, 0.40, 0.48, 1.0), false, true)
	hm.render_priority = 2
	_handprint.material_override = hm
	_handprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_handprint.visible = false
	if _window_node:
		# Window のメッシュ上面のすぐ上(Window ローカル)
		var top := _window_node.get_aabb().position.y + _window_node.get_aabb().size.y
		_handprint.position = Vector3(window_size.x * 0.20, top + 0.002, -window_size.y * 0.16)
		_window_node.add_child(_handprint)
	else:
		_handprint.position = Vector3(window_offset.x, lid_top_y + 0.003, window_offset.z)
		add_child(_handprint)

## 小窓の中は真っ暗なので、顔が読める程度のごく弱い光を入れる。
func _build_window_light() -> void:
	_window_light = OmniLight3D.new()
	_window_light.name = "WindowLight"
	_window_light.light_color = Color(0.80, 0.82, 0.88)
	_window_light.light_energy = window_light_energy
	_window_light.omni_range = 0.55
	_window_light.omni_attenuation = 1.3
	_window_light.shadow_enabled = false
	_window_light.position = Vector3(window_offset.x, lid_top_y - 0.05, window_offset.z)
	add_child(_window_light)

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
	var base := _lid_rest + _lid_offset()
	var tw := create_tween()
	tw.tween_property(_lid_node, "position", base + Vector3(0, amount, 0), duration * 0.3)
	tw.tween_property(_lid_node, "position", base, duration * 0.7)

func _lid_offset() -> Vector3:
	return Vector3(lid_slide, 0, 0) if is_lid_ajar else Vector3.ZERO

## 蓋を 10cm ずらす/戻す。
func set_lid_ajar(ajar: bool) -> void:
	if is_lid_ajar == ajar:
		return
	is_lid_ajar = ajar
	_update_hold_time()
	Audio.play_at(&"coffin_lid_slide", global_position)
	if _lid_node == null:
		return
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_lid_node, "position", _lid_rest + _lid_offset(), 1.4)

## ずれた蓋をプレイヤーが押し戻す。
func reset_lid() -> void:
	if not is_lid_ajar:
		return
	set_lid_ajar(false)
	Events.emit_event(&"lid_reset")
	lid_reset.emit()

## 棺の蓋を開ける/閉じる(終盤)。Lid を足側の蝶番で回す。
func set_open(open: bool) -> void:
	if is_open == open:
		return
	is_open = open
	Audio.play_at(&"coffin_lid_slide", global_position)
	if _lid_node:
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(_lid_node, "rotation_degrees:x", lid_open_degrees if open else 0.0, 1.8)
	elif _prop:
		_prop.model_name = "coffin_lid_open" if open else "coffin"
	if open:
		set_window_open(false)

## 小窓だけ開ける/閉じる。開くと中の顔が見える。
func set_window_open(open: bool) -> void:
	if is_window_open == open:
		return
	is_window_open = open
	if _window_node:
		_window_node.visible = not open
	Audio.play_at(&"coffin_lid_slide", global_position, -8.0, 1.35)

## 顔ビューの途中で、故人の顔の隣にもう一つの顔を出す(E-11)。
func set_second_face(on: bool) -> void:
	has_second_face = on
	if on and _second_face == null:
		_second_face = MeshInstance3D.new()
		_second_face.name = "SecondFace"
		var q := QuadMesh.new()
		q.size = second_face_size
		_second_face.mesh = q
		_second_face.rotation_degrees = Vector3(-90, 0, 90)
		_second_face.position = second_face_offset
		_second_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tex := SystemUtil.load_texture(second_face_texture)
		if tex == null:
			tex = SystemUtil.face_texture(2)
		var m := SystemUtil.alpha_material(tex, Color(1, 1, 1, 1), false, false)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		m.emission_enabled = true
		m.emission = Color(1, 1, 1)
		m.emission_texture = tex
		m.emission_energy_multiplier = 0.06
		m.render_priority = 1
		_second_face.material_override = m
		add_child(_second_face)
	if _second_face:
		_second_face.visible = false

## 顔ビューの最中に一瞬だけ見せる。
func _flash_second_face() -> void:
	if not has_second_face or _second_face == null:
		return
	await get_tree().create_timer(second_face_delay, false).timeout
	if not is_showing_face:
		return
	_second_face.visible = true
	Audio.play_at(&"breath_close", global_position + Vector3(0, 0.3, 0), -8.0, 0.88, 6.0)
	await get_tree().create_timer(second_face_seconds, false).timeout
	_second_face.visible = false

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
		var inst := _face_prop.get_instance()
		if SystemUtil.set_surface_texture(inst, "Face", tex) == 0:
			push_warning("Coffin: body_face.glb に Face サーフェスが無い")
		for s in SystemUtil.find_surfaces(inst, "Face"):
			var m := SystemUtil.surface_material(s["mi"], s["index"])
			m.emission_enabled = face_emission > 0.0
			m.emission = Color(1, 1, 1)
			m.emission_texture = tex
			m.emission_energy_multiplier = face_emission
		# 「こちらを向く」は少し回転も足す
		_face_prop.rotation_degrees.y = 8.0 if face_state >= 3 else 0.0
	if _face_quad:
		var mat := SystemUtil.alpha_material(tex, Color(1, 1, 1, 1), false, false)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mat.emission_enabled = face_emission > 0.0
		mat.emission = Color(1, 1, 1)
		mat.emission_texture = tex
		mat.emission_energy_multiplier = face_emission
		_face_quad.material_override = mat

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

## 小窓を開け、その真上にカメラをゆっくり寄せて顔を見せる。見ている間は息の音がする。
func show_face(seconds: float = -1.0, reason: String = "peek") -> void:
	if is_showing_face:
		return
	if seconds <= 0.0:
		seconds = face_view_seconds
	is_showing_face = true
	var p := Game.player
	SystemUtil.set_locked(p, true)
	set_window_open(true)
	Events.emit_event(&"coffin_window_opened", {"reason": reason})
	face_shown.emit()

	var target := _window_point()
	_prev_cam = get_viewport().get_camera_3d() if is_inside_tree() else null
	_face_cam.global_position = target + Vector3(0, 0.95, 0.02)
	# 故人は棺の長辺に沿って寝ているので、画面の上を棺の -X(頭側)に合わせる
	_face_cam.look_at(target, global_transform.basis.x)
	_face_cam.current = true

	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_face_cam, "global_position", target + Vector3(0, 0.30, 0.01), minf(seconds * 0.6, 1.6))
	_breath_timer = 0.0
	_flash_second_face()
	await get_tree().create_timer(seconds, false).timeout

	_face_cam.current = false
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	if _second_face:
		_second_face.visible = false
	set_window_open(false)
	SystemUtil.set_locked(p, false)
	is_showing_face = false
	face_hidden.emit()

## 小窓の中心のワールド座標。
func _window_point() -> Vector3:
	if _window_node and _window_node.is_inside_tree():
		var a := _window_node.get_aabb()
		return _window_node.global_transform * a.get_center()
	return global_transform * Vector3(window_offset.x, lid_top_y, window_offset.z)

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
	if is_lid_ajar:
		return lid_reset_prompt
	return peek_prompt

func get_blocked_text() -> String:
	if is_showing_face:
		return blocked_viewing_text
	if is_open:
		return blocked_lid_open_text
	if not allow_open_window and not _has_dry_ice():
		return blocked_open_text
	return super.get_blocked_text()

func _can_interact(_player: Node3D) -> bool:
	return not is_showing_face and not is_open

func _interact(player: Node3D) -> void:
	if _has_dry_ice():
		_replace_dry_ice(player)
	elif is_lid_ajar:
		reset_lid()
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
func _physics_process(_delta: float) -> void:
	_update_hold_time()

## 長押し時間は状況で変わる。持ち物は毎フレーム見るが、蓋の状態が変わった
## 瞬間にも呼んで 1 フレームの遅れを無くす。
func _update_hold_time() -> void:
	if _has_dry_ice():
		hold_time = dry_ice_hold_time
	elif is_lid_ajar:
		hold_time = lid_reset_hold_time
	else:
		hold_time = 0.0
