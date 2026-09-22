class_name Monitor
extends Interactable
## 事務所の監視モニター(ブラウン管)。式場と玄関の2ch。走査線とノイズ混じり。
##
## ■ モニターにだけ映すやり方(脅かしの作り方) ─────────────────────────────
## 監視カメラの cull_mask は「1(default)+ 10(cctv_only)」、11(player_hidden)は入っていない。
## つまり VisualInstance3D の layers をこう設定すると:
##     node.layers = SystemUtil.LAYER_CCTV_ONLY      # 1 << 9
##       → モニターにだけ映る。式場へ走っても何もいない。
##     node.layers = SystemUtil.LAYER_PLAYER_HIDDEN  # 1 << 10
##       → プレイヤーの目には映るがモニターには映らない。
##     node.layers = SystemUtil.LAYER_DEFAULT        # 1 << 0(既定)
##       → 両方に映る。
## 例(23:00 の「後列の椅子に座る人影」):
##     var ghost := preload("res://src/npc/ghost_sitting.tscn").instantiate()
##     level.add_child(ghost)
##     for mi in ghost.find_children("*", "VisualInstance3D", true, false):
##         mi.layers = SystemUtil.LAYER_CCTV_ONLY
##     mon.switch_feed(Monitor.FEED_SHIKIJO)
##     mon.glitch()
## このモニター自身の画面は LAYER_PLAYER_HIDDEN なので、監視カメラに映り込んで
## 無限ループになることはない。
##
## director からの使い方:
##     mon.switch_feed(Monitor.FEED_GENKAN)
##     mon.set_static(0.6)     # ノイズを強める
##     mon.glitch()            # 一瞬だけ激しく乱れる
##     mon.auto_switch = false # 自動切替を止める

signal feed_switched(index: int)

enum { FEED_SHIKIJO = 0, FEED_GENKAN = 1 }

const CAM_ANCHORS := ["Anchor_Cam_Shikijo", "Anchor_Cam_Genkan"]
const SCREEN_SHADER := "res://src/systems/shaders/crt_screen.gdshader"

@export var viewport_size: Vector2i = Vector2i(256, 192)
@export var camera_fov: float = 72.0
@export var screen_size: Vector2 = Vector2(0.29, 0.215)
## モデルは +Z が正面(models 担当のモデルはすべてこの向き)。
@export var screen_offset: Vector3 = Vector3(0, 0.205, 0.222)
@export var screen_rotation_degrees: Vector3 = Vector3(0, 0, 0)
@export var auto_switch: bool = true
@export var auto_switch_seconds: float = 9.0
@export var base_static: float = 0.10
@export var look_prompt: String = "モニターを見る"

var feed_index: int = 0

var _cams: Array[Camera3D] = []
var _vp: SubViewport
var _screen: MeshInstance3D
var _mat: ShaderMaterial
var _switch_t: float = 0.0
var _glitch: float = 0.0
var _static_amount: float = 0.10

func _ready() -> void:
	super._ready()
	prompt = look_prompt
	_static_amount = base_static
	_build()
	call_deferred(&"_resolve_cameras")
	set_process(true)

func _build() -> void:
	_vp = SubViewport.new()
	_vp.name = "Feed"
	_vp.size = viewport_size
	_vp.own_world_3d = false            # 本編の World3D をそのまま覗く
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.handle_input_locally = false
	add_child(_vp)

	for i in CAM_ANCHORS.size():
		var cam := Camera3D.new()
		cam.name = "Cam%d" % i
		cam.fov = camera_fov
		cam.near = 0.05
		cam.far = 40.0
		# 1(default) + 10(cctv_only)。11(player_hidden)は含めない。
		cam.cull_mask = SystemUtil.LAYER_DEFAULT | SystemUtil.LAYER_CCTV_ONLY
		cam.current = (i == 0)
		_vp.add_child(cam)
		_cams.append(cam)

	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	var q := QuadMesh.new()
	q.size = screen_size
	_screen.mesh = q
	_screen.position = screen_offset
	_screen.rotation_degrees = screen_rotation_degrees
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 監視カメラ自身には映らないようにする(画面の無限ループ防止)
	_screen.layers = SystemUtil.LAYER_PLAYER_HIDDEN
	add_child(_screen)

	_mat = ShaderMaterial.new()
	if ResourceLoader.exists(SCREEN_SHADER):
		_mat.shader = load(SCREEN_SHADER)
	else:
		push_warning("Monitor: シェーダが無い %s" % SCREEN_SHADER)
	_mat.set_shader_parameter("screen_tex", _vp.get_texture())
	_mat.set_shader_parameter("static_amount", _static_amount)
	_mat.set_shader_parameter("glitch", 0.0)
	_mat.set_shader_parameter("rows", float(viewport_size.y) * 0.5)
	_mat.set_shader_parameter("scanline", 0.22)
	_screen.material_override = _mat

	# monitor_crt.glb に "Screen" サーフェスがあれば、そこへ直接シェーダを貼る
	# (板ポリを前に浮かせるより位置がぴったり合う)。
	var prop := get_node_or_null(^"Prop") as Prop
	if prop:
		var inst := prop.get_instance()
		var n_screen := SystemUtil.override_surfaces(inst, "Screen", _mat)
		if n_screen == 0:
			push_warning("Monitor: monitor_crt.glb に Screen サーフェスが無い。板ポリで代用する")
		if n_screen > 0:
			_screen.visible = false
		# モニター自身が監視カメラに映ると画面が入れ子になるので、本体ごと隠す
		for m in inst.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).layers = SystemUtil.LAYER_PLAYER_HIDDEN

	# 画面の光がわずかに部屋へ漏れる
	var glow := OmniLight3D.new()
	glow.name = "ScreenGlow"
	glow.light_color = Color(0.65, 0.85, 0.80)
	glow.light_energy = 0.14
	glow.omni_range = 3.0
	glow.shadow_enabled = false
	glow.position = screen_offset + Vector3(0, 0, 0.5)
	add_child(glow)

## Anchor_Cam_* にカメラを置く。無ければ警告して、モニターの前あたりを映す。
func _resolve_cameras() -> void:
	var root: Node = Game.level
	if root == null:
		root = get_tree().current_scene
	for i in _cams.size():
		var anchor: Node = null
		if root:
			anchor = root.find_child(CAM_ANCHORS[i], true, false)
		if anchor is Node3D:
			_cams[i].global_transform = (anchor as Node3D).global_transform.orthonormalized()
		else:
			push_warning("Monitor: %s が無い。仮の位置で映す" % CAM_ANCHORS[i])
			var t := global_transform
			_cams[i].global_transform = Transform3D(Basis(), t.origin + Vector3(0, 2.0, -3.0 - i * 2.0))
			_cams[i].look_at(t.origin + Vector3(0, 0.8, 0), Vector3.UP)

func _process(delta: float) -> void:
	if _glitch > 0.0:
		_glitch = maxf(0.0, _glitch - delta * 1.8)
		if _mat:
			_mat.set_shader_parameter("glitch", _glitch)
	if auto_switch:
		_switch_t += delta
		if _switch_t >= auto_switch_seconds:
			_switch_t = 0.0
			switch_feed((feed_index + 1) % _cams.size())

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

func switch_feed(i: int) -> void:
	if _cams.is_empty():
		return
	feed_index = posmod(i, _cams.size())
	for k in _cams.size():
		_cams[k].current = (k == feed_index)
	_switch_t = 0.0
	glitch(0.45)
	feed_switched.emit(feed_index)

## 砂嵐の量 0.0〜1.0。
func set_static(amount: float) -> void:
	_static_amount = clampf(amount, 0.0, 1.0)
	if _mat:
		_mat.set_shader_parameter("static_amount", _static_amount)

func get_static() -> float:
	return _static_amount

## 一瞬だけ画面が激しく乱れる。
func glitch(strength: float = 1.0) -> void:
	_glitch = maxf(_glitch, clampf(strength, 0.0, 1.0))
	if _mat:
		_mat.set_shader_parameter("glitch", _glitch)
	Audio.play_at(&"vhs_tracking", global_position, -6.0)

## 画面の中心のワールド座標(カメラを寄せる先)。
func screen_point() -> Vector3:
	return _screen.global_position if _screen else global_position

func get_camera(i: int) -> Camera3D:
	return _cams[i] if i >= 0 and i < _cams.size() else null

func get_viewport_node() -> SubViewport:
	return _vp

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func _interact(player: Node3D) -> void:
	SystemUtil.look_at_point(player, screen_point(), 0.6)
	switch_feed((feed_index + 1) % maxi(_cams.size(), 1))
