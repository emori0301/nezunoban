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

## ブラウン管の粗さに合わせて低解像度で描く(事務所の描画量を減らすため)。
@export var viewport_size: Vector2i = Vector2i(160, 120)
## 映像の更新頻度。毎フレーム世界を描き直す必要はないので 15fps 相当にする。
@export var feed_fps: float = 15.0
@export var camera_fov: float = 72.0
## 監視カメラの描画距離。館内しか映さないので短くてよい。
@export var cctv_far: float = 25.0
@export var screen_size: Vector2 = Vector2(0.29, 0.215)
## モデルは +Z が正面(models 担当のモデルはすべてこの向き)。
@export var screen_offset: Vector3 = Vector3(0, 0.205, 0.222)
@export var screen_rotation_degrees: Vector3 = Vector3(0, 0, 0)
@export var auto_switch: bool = true
@export var auto_switch_seconds: float = 9.0
@export var base_static: float = 0.10
## 監視カメラが見るレンダーレイヤー。既定は player_hidden(11)以外すべて。
@export_flags_3d_render var cctv_cull_mask: int = 1047551
## true にするとモニター本体をレンダーレイヤー 11 に移し、監視カメラから隠す。
## プレイヤーのカメラが 11 を含まないと本体ごと見えなくなるので既定は false。
@export var hide_from_cctv: bool = false
@export var look_prompt: String = "モニターを見る"
## 映像を描くのはプレイヤーがこの部屋にいるときだけ(毎フレーム式場と玄関を
## 描き直すと draw call がもったいない)。まだ一度も部屋イベントが来ていない間は
## 描き続けるので、部屋 Area3D の無いテストシーンでもそのまま映る。
@export var active_room: StringName = &"Room_Office"
@export var only_update_in_room: bool = true

var feed_index: int = 0

var _cams: Array[Camera3D] = []
var _vp: SubViewport
var _screen: MeshInstance3D
var _mat: ShaderMaterial
var _switch_t: float = 0.0
var _glitch: float = 0.0
var _static_amount: float = 0.10
var _force_update: bool = false
var _room_seen: bool = false
var _in_room: bool = false
var _feed_active: bool = true
var _feed_t: float = 0.0

func _ready() -> void:
	super._ready()
	prompt = look_prompt
	_static_amount = base_static
	_build()
	Events.on(&"player_entered_room", _on_player_entered_room)
	call_deferred(&"_resolve_cameras")
	set_process(true)

func _build() -> void:
	_vp = SubViewport.new()
	_vp.name = "Feed"
	_vp.size = viewport_size
	_vp.own_world_3d = false            # 本編の World3D をそのまま覗く
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	# 常時更新はしない。_apply_feed_update / _process が feed_fps の間隔で描かせる。
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.handle_input_locally = false
	add_child(_vp)

	for i in CAM_ANCHORS.size():
		var cam := Camera3D.new()
		cam.name = "Cam%d" % i
		cam.fov = camera_fov
		cam.near = 0.05
		cam.far = cctv_far
		# 11(player_hidden)以外は全部見る。「1 と 10 を含み 11 を含まない」という
		# 要件を満たしつつ、level が別のレンダーレイヤーを使っていても映像が
		# 真っ暗にならないようにする。
		cam.cull_mask = cctv_cull_mask | SystemUtil.LAYER_DEFAULT | SystemUtil.LAYER_CCTV_ONLY
		cam.cull_mask &= ~SystemUtil.LAYER_PLAYER_HIDDEN
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
	if hide_from_cctv:
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
		# 監視カメラ自身に映り込ませたくない場合だけレイヤー 11 に移す。
		# ただしプレイヤーのカメラが 11 を見ない設定だとモニターごと見えなくなるので、
		# 既定は false。式場/玄関のカメラは事務所を映さないので入れ子は起きない。
		if hide_from_cctv:
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

func _on_player_entered_room(data: Dictionary) -> void:
	_room_seen = true
	_in_room = StringName(String(data.get("room", ""))) == active_room
	_apply_feed_update()

func _apply_feed_update() -> void:
	if _vp == null:
		return
	_feed_active = _force_update or not only_update_in_room or not _room_seen or _in_room
	if _feed_active:
		# 1枚だけ描かせる。以降は _process が feed_fps の間隔で描き直す。
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_feed_t = 0.0
	else:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

## director の --cctv-shot など、プレイヤーが事務所に居なくても映像が要るとき。
func set_force_update(on: bool) -> void:
	_force_update = on
	_apply_feed_update()

func is_feed_updating() -> bool:
	return _vp != null and _feed_active

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
	# 映像は毎フレームではなく feed_fps の間隔で描き直す
	if _feed_active and _vp and feed_fps > 0.0:
		_feed_t += delta
		if _feed_t >= 1.0 / feed_fps:
			_feed_t = 0.0
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
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

## 映像の SubViewport。director の --cctv-shot がここからテクスチャを取る。
## 事務所に居ないと feed は止まっているので、取り出すときに 1 枚だけ描かせる
## (呼び出し側は await RenderingServer.frame_post_draw してから get_image する)。
func get_viewport_node() -> SubViewport:
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	return _vp

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func _interact(player: Node3D) -> void:
	SystemUtil.look_at_point(player, screen_point(), 0.6)
	switch_feed((feed_index + 1) % maxi(_cams.size(), 1))
