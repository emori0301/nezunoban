class_name VhsLayer
extends Node
## VHS ポストエフェクト。main.gd が生成して attach(%GameViewportContainer) を呼ぶ。
## SubViewportContainer の material に ShaderMaterial を差し、毎フレーム揺らぎを更新する。
##
## API:
##   attach(container: SubViewportContainer)
##   set_intensity(f: float)            # 0..1 恐怖演出で上げる
##   glitch(duration: float)            # 短時間だけ強いトラッキングノイズ
##   set_tint(color: Color)
##   set_darken(amount: float, dur: float)
##   pulse(strength: float, dur: float) # 一瞬だけ intensity を上げて戻す

const SHADER_PATH := "res://src/fx/vhs.gdshader"

@export_range(0.0, 1.0) var intensity: float = 0.32
@export var band_interval: Vector2 = Vector2(7.0, 19.0)   # トラッキング帯が出る間隔(秒)
@export var enabled: bool = true

var material: ShaderMaterial = null
var container: SubViewportContainer = null

var _base_intensity: float = 0.32
var _band_timer: float = 4.0
var _band_life: float = 0.0
var _band_life_max: float = 1.0
var _band_pos: float = 1.2
var _band_speed: float = 0.5
var _band_amp: float = 0.4
var _glitch_t: float = 0.0
var _glitch_max: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group(&"vhs")
	_rng.randomize()
	_base_intensity = intensity
	_band_timer = _rng.randf_range(band_interval.x * 0.3, band_interval.y * 0.5)
	if material == null:
		_make_material()

func _make_material() -> void:
	if not ResourceLoader.exists(SHADER_PATH):
		push_error("VhsLayer: shader missing %s" % SHADER_PATH)
		return
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	material.set_shader_parameter("intensity", intensity)

## SubViewportContainer に取り付ける。container のサイズから src_size を決める。
func attach(target: SubViewportContainer) -> void:
	if material == null:
		_make_material()
	if material == null:
		return
	container = target
	if container == null:
		return
	container.material = material
	var sv := _find_subviewport(container)
	if sv:
		material.set_shader_parameter("src_size", Vector2(sv.size))

func _find_subviewport(node: Node) -> SubViewport:
	for c in node.get_children():
		if c is SubViewport:
			return c
	return null

func detach() -> void:
	if container and is_instance_valid(container) and container.material == material:
		container.material = null
	container = null

## 解放されるときは自分が付けたマテリアルを外す(SubViewportContainer に
## 宙ぶらりんの ShaderMaterial を残さないため)。既に別の VhsLayer が付け替えていたら触らない。
## main.gd はタイトルを queue_free した直後に自前の VhsLayer を attach するので、
## ここで無条件に container.material = null にすると付けたばかりの物を消してしまう。
func _exit_tree() -> void:
	detach()

func _process(delta: float) -> void:
	if material == null or not enabled:
		return

	# 時々のトラッキングノイズ帯
	if _band_life > 0.0:
		_band_life -= delta
		_band_pos -= delta * _band_speed
		if _band_pos < -0.2:
			_band_pos = 1.2
	else:
		_band_timer -= delta
		if _band_timer <= 0.0:
			_start_band(_rng.randf_range(0.35, 1.15), _rng.randf_range(0.30, 0.65))
			_band_timer = _rng.randf_range(band_interval.x, band_interval.y)

	if _glitch_t > 0.0:
		_glitch_t -= delta

	var band_strength := 0.0
	if _band_life > 0.0:
		var f: float = clampf(_band_life / maxf(_band_life_max, 0.001), 0.0, 1.0)
		band_strength = sin(f * PI) * _band_amp
	if _glitch_t > 0.0:
		var g: float = clampf(_glitch_t / maxf(_glitch_max, 0.001), 0.0, 1.0)
		band_strength = maxf(band_strength, 0.55 + 0.45 * g)

	var eff_intensity := intensity
	if _glitch_t > 0.0:
		eff_intensity = minf(1.0, intensity + 0.55)

	material.set_shader_parameter("intensity", eff_intensity)
	material.set_shader_parameter("tracking_amount", band_strength)
	material.set_shader_parameter("tracking_pos", _band_pos)

func _start_band(life: float, amp: float) -> void:
	_band_life = life
	_band_life_max = life
	_band_amp = amp
	_band_pos = _rng.randf_range(0.75, 1.15)
	_band_speed = _rng.randf_range(0.35, 1.1)

## 0..1。恐怖演出で上げる。
func set_intensity(f: float) -> void:
	intensity = clampf(f, 0.0, 1.0)
	if material:
		material.set_shader_parameter("intensity", intensity)

func get_intensity() -> float:
	return intensity

## 一瞬だけ強いノイズ(脅かし用)。
func glitch(duration: float = 0.35) -> void:
	_glitch_t = maxf(duration, 0.05)
	_glitch_max = _glitch_t
	_band_pos = _rng.randf_range(0.2, 0.9)
	Audio.play(&"vhs_tracking", -6.0)

## intensity を一時的に上げて戻す。
func pulse(strength: float = 0.5, dur: float = 1.2) -> void:
	var from := intensity
	var tw := create_tween()
	tw.tween_method(set_intensity, from, clampf(from + strength, 0.0, 1.0), dur * 0.25)
	tw.tween_method(set_intensity, clampf(from + strength, 0.0, 1.0), from, dur * 0.75)

func set_tint(color: Color) -> void:
	if material:
		material.set_shader_parameter("tint", color)

func set_darken(amount: float, dur: float = 0.0) -> void:
	if material == null:
		return
	if dur <= 0.0:
		material.set_shader_parameter("darken", clampf(amount, 0.0, 1.0))
		return
	var cur: float = float(material.get_shader_parameter("darken"))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		material.set_shader_parameter("darken", v), cur, clampf(amount, 0.0, 1.0), dur)

func set_param(name: StringName, value: Variant) -> void:
	if material:
		material.set_shader_parameter(name, value)
