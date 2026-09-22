class_name TV
extends Interactable
## 控室のブラウン管。映像入力は無いので砂嵐だけ。23:40 に勝手につく。
##
## director からの使い方:
##     var tv := SystemsInstaller.find(&"tv") as TV
##     tv.turn_on()
##     tv.flash_face(0.4)          # 砂嵐の中に一瞬だけ顔
##     tv.show_player_back(5.0)    # カメラの無い部屋なのに自分の後ろ姿が映る
##     tv.turn_off()

signal turned_on
signal turned_off

const STATIC_SHADER := "res://src/systems/shaders/tv_static.gdshader"

@export var screen_size: Vector2 = Vector2(0.42, 0.31)
## モデルは +Z が正面。
@export var screen_offset: Vector3 = Vector3(0, 0.235, 0.24)
@export var screen_rotation_degrees: Vector3 = Vector3(0, 0, 0)
@export var on_prompt: String = "消す"
@export var off_prompt: String = "つける"
@export var start_on: bool = false
@export var static_volume_db: float = -14.0

var is_on: bool = false

var _screen: MeshInstance3D
var _mat: ShaderMaterial
var _glow: OmniLight3D
var _loop: AudioStreamPlayer3D
var _face_tex: Texture2D
var _back_tex: Texture2D
var _overlay_tween: Tween

func _ready() -> void:
	super._ready()
	_build()
	_face_tex = SystemUtil.load_texture("tv_face")
	if _face_tex == null:
		_face_tex = SystemUtil.tv_face_texture()
	_back_tex = SystemUtil.back_silhouette_texture()
	_apply_power()
	if start_on:
		turn_on()

func _build() -> void:
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	var q := QuadMesh.new()
	q.size = screen_size
	_screen.mesh = q
	_screen.position = screen_offset
	_screen.rotation_degrees = screen_rotation_degrees
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_screen)

	_mat = ShaderMaterial.new()
	if ResourceLoader.exists(STATIC_SHADER):
		_mat.shader = load(STATIC_SHADER)
	else:
		push_warning("TV: シェーダが無い %s" % STATIC_SHADER)
	_mat.set_shader_parameter("power", 0.0)
	_mat.set_shader_parameter("overlay_amount", 0.0)
	_mat.set_shader_parameter("has_overlay", false)
	_screen.material_override = _mat

	# tv_crt.glb に "Screen" サーフェスがあればそこへ直接貼る
	var prop := get_node_or_null(^"Prop") as Prop
	if prop and SystemUtil.override_surfaces(prop.get_instance(), "Screen", _mat) > 0:
		_screen.visible = false

	_glow = OmniLight3D.new()
	_glow.name = "ScreenGlow"
	_glow.light_color = Color(0.72, 0.80, 0.92)
	_glow.light_energy = 0.0
	_glow.omni_range = 3.4
	_glow.shadow_enabled = false
	_glow.position = screen_offset + Vector3(0, 0, 0.55)
	add_child(_glow)

	_loop = _make_loop_player(&"tv_static", static_volume_db)

## ループ再生用の 3D プレイヤー(Audio autoload は単発と 2D ループしか持たないため)。
func _make_loop_player(sound: StringName, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "Loop_%s" % sound
	p.volume_db = db
	p.max_distance = 12.0
	p.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	add_child(p)
	var path := "res://assets/audio/%s.wav" % sound
	if not ResourceLoader.exists(path):
		path = "res://assets/audio/%s.ogg" % sound
	if not ResourceLoader.exists(path):
		push_warning("TV: 音が無い %s(音なしで動く)" % sound)
		return p
	var s: AudioStream = load(path)
	if s is AudioStreamWAV:
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = 0
		p.stream = w
	elif s is AudioStreamOggVorbis:
		var o := (s as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		o.loop = true
		p.stream = o
	else:
		p.stream = s
	return p

func _apply_power() -> void:
	if _mat:
		_mat.set_shader_parameter("power", 1.0 if is_on else 0.0)
	if _glow:
		_glow.light_energy = 0.22 if is_on else 0.0

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

func turn_on() -> void:
	if is_on:
		return
	is_on = true
	_apply_power()
	Audio.play_at(&"tv_on", global_position)
	if _loop and _loop.stream:
		_loop.play()
	turned_on.emit()

func turn_off() -> void:
	if not is_on:
		return
	is_on = false
	set_overlay(null, 0.0)
	_apply_power()
	Audio.play_at(&"tv_off", global_position)
	if _loop:
		_loop.stop()
	turned_off.emit()

## 砂嵐の中に一瞬だけ暗い顔が浮かぶ。
func flash_face(seconds: float = 0.35) -> void:
	if not is_on:
		return
	_flash(_face_tex, seconds, 1.0)

## 自分の後ろ姿(暗いシルエット)が映る。seconds <= 0 で消すまで出しっぱなし。
func show_player_back(seconds: float = 5.0) -> void:
	if not is_on:
		return
	if seconds <= 0.0:
		set_overlay(_back_tex, 0.85)
	else:
		_flash(_back_tex, seconds, 0.85)

func _flash(tex: Texture2D, seconds: float, peak: float) -> void:
	set_overlay(tex, 0.0)
	if _overlay_tween and _overlay_tween.is_valid():
		_overlay_tween.kill()
	_overlay_tween = create_tween()
	_overlay_tween.tween_method(_set_overlay_amount, 0.0, peak, minf(seconds * 0.25, 0.25))
	_overlay_tween.tween_interval(maxf(seconds * 0.5, 0.05))
	_overlay_tween.tween_method(_set_overlay_amount, peak, 0.0, minf(seconds * 0.25, 0.3))

func set_overlay(tex: Texture2D, amount: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("has_overlay", tex != null)
	if tex != null:
		_mat.set_shader_parameter("overlay_tex", tex)
	_set_overlay_amount(amount)

func _set_overlay_amount(a: float) -> void:
	if _mat:
		_mat.set_shader_parameter("overlay_amount", clampf(a, 0.0, 1.0))

## 砂嵐の強さ(0.0〜1.0)。
func set_noise(amount: float) -> void:
	if _mat:
		_mat.set_shader_parameter("noise_amount", clampf(amount, 0.0, 1.0))

func screen_point() -> Vector3:
	return _screen.global_position if _screen else global_position

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func get_prompt() -> String:
	return on_prompt if is_on else off_prompt

func _interact(_player: Node3D) -> void:
	if is_on:
		turn_off()
	else:
		turn_on()
