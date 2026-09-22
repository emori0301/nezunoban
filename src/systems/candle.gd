class_name Candle
extends Interactable
## 燭台(灯明)。1本 = burn_seconds(既定 720 秒 = 4ゲーム時間)。
## 消えると式場が暗くなる。暗さは自前の OmniLight3D だけで表現し、Building の照明は触らない。
##
## director からの使い方:
##     var c := SystemsInstaller.find(&"candle") as Candle
##     c.force_out()                  # 丑三つ時に消す
##     c.require_matches = true       # 終盤: マッチが無いと点け直せない(1.2秒の長押し)
##     c.fail_next = true             # 次の1回だけ必ず失敗させる(火車エンドの詰み演出)
##     await Events.on(&"relight_success", ...)   # {"n": 何回目か}

signal lit
signal went_out
signal relight_failed

@export var burn_seconds: float = 720.0
@export var burn_multiplier: float = 1.0
@export var dread_on_out: int = 0        # ロウソクは既定では異変度を上げない(director が判断)
@export var candle_height: float = 0.16
@export var candle_radius: float = 0.016
@export var stand_top: float = 0.24      # 燭台の皿の高さ(m。モデルが無いとき用)
## candle_stand.glb にはロウソクと炎が含まれているので、モデルがあるときは
## 自前のロウソクは出さず、この高さに自前の炎だけを重ねる(モデルの炎は消す)。
@export var model_wick_y: float = 0.405
@export var light_energy: float = 1.7
@export var light_range: float = 7.0
@export var light_color: Color = Color(1.0, 0.72, 0.42)
@export var relight_hold_time: float = 1.2
@export var fail_line: String = "……つかない。"

## 終盤に director が true にすると、マッチが無いと点け直せなくなる。
@export var require_matches: bool = false:
	set(v):
		require_matches = v
		required_item = &"matches" if v else &""
		hold_time = relight_hold_time if v else 0.0
		if is_inside_tree():
			prompt = relight_prompt if v else light_prompt

@export var light_prompt: String = "ロウソクを灯す"
@export var relight_prompt: String = "マッチで灯し直す"

## 次の1回だけ必ず失敗する。
var fail_next: bool = false
var is_lit: bool = false
var relight_count: int = 0

var remaining_ratio: float:
	get:
		if burn_seconds <= 0.0:
			return 0.0
		return clampf(_remaining / burn_seconds, 0.0, 1.0)

var _remaining: float = 0.0
var _t: float = 0.0
var _wax: MeshInstance3D
var _wax_mesh: CylinderMesh
var _flame: MeshInstance3D
var _flame_light: OmniLight3D
var _smoke: GPUParticles3D
var _flame_base_size: Vector2
var _use_model: bool = false

func _ready() -> void:
	super._ready()
	prompt = relight_prompt if require_matches else light_prompt
	hold_time = relight_hold_time if require_matches else 0.0
	required_item = &"matches" if require_matches else &""
	var prop := get_node_or_null(^"Prop") as Prop
	_use_model = SystemUtil.has_model("candle_stand") and prop != null
	if _use_model:
		# モデルに焼き込まれた炎は消し、揺らぐ自前の炎に置き換える
		SystemUtil.hide_surfaces(prop.get_instance(), "Flame")
	_build_visuals()
	if _use_model and _wax:
		_wax.visible = false
	_apply_visual_state()
	set_process(true)

func _build_visuals() -> void:
	# ロウソク本体(燃えると短くなる)
	_wax = MeshInstance3D.new()
	_wax.name = "Wax"
	_wax_mesh = CylinderMesh.new()
	_wax_mesh.top_radius = candle_radius
	_wax_mesh.bottom_radius = candle_radius
	_wax_mesh.height = candle_height
	_wax_mesh.radial_segments = 8
	_wax_mesh.rings = 1
	_wax.mesh = _wax_mesh
	_wax.material_override = SystemUtil.flat_material(Color(0.93, 0.90, 0.82))
	add_child(_wax)

	# 炎(ビルボードの板ポリ)
	_flame = MeshInstance3D.new()
	_flame.name = "Flame"
	var q := QuadMesh.new()
	_flame_base_size = Vector2(0.032, 0.056)
	q.size = _flame_base_size
	q.center_offset = Vector3(0, _flame_base_size.y * 0.5, 0)   # 下端を芯に合わせる
	_flame.mesh = q
	_flame.material_override = SystemUtil.emissive_material(SystemUtil.flame_texture(), Color(1.0, 0.80, 0.45), 2.6, true)
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)

	_flame_light = OmniLight3D.new()
	_flame_light.name = "FlameLight"
	_flame_light.light_color = light_color
	_flame_light.light_energy = light_energy
	_flame_light.omni_range = light_range
	_flame_light.omni_attenuation = 1.6
	_flame_light.shadow_enabled = false
	add_child(_flame_light)

	_smoke = SystemUtil.make_smoke(14, 1.6, 0.30, 0.015, 0.16, Color(0.72, 0.72, 0.74, 0.35), 18.0)
	_smoke.name = "Smoke"
	_smoke.one_shot = true
	_smoke.explosiveness = 0.8
	_smoke.emitting = false
	add_child(_smoke)

func _process(delta: float) -> void:
	_t += delta
	if not is_lit:
		return
	_remaining -= delta * maxf(burn_multiplier, 0.0)
	if _remaining <= 0.0:
		_remaining = 0.0
		_extinguish(&"burn_out")
		return
	_apply_visual_state()
	_flicker()

func _flicker() -> void:
	# energy と位置を毎フレーム微揺らぎさせる
	var n := 0.80 + 0.14 * sin(_t * 11.0) + 0.08 * sin(_t * 27.3 + 2.1) + 0.06 * sin(_t * 4.1)
	_flame_light.light_energy = light_energy * n
	var sway := Vector3(sin(_t * 7.7) * 0.0022, 0.0, cos(_t * 6.1) * 0.0022)
	var tip := _wick_position()
	_flame.position = tip + sway
	_flame_light.position = tip + Vector3(0, 0.035, 0) + sway * 1.5
	_flame.scale = Vector3(0.92 + 0.10 * sin(_t * 13.7), 0.88 + 0.22 * n, 1.0)
	_flame.rotation.z = sin(_t * 5.3) * 0.06

func _wick_position() -> Vector3:
	if _use_model:
		return Vector3(0, model_wick_y, 0)
	return Vector3(0, stand_top + candle_height * remaining_ratio, 0)

func _apply_visual_state() -> void:
	var h: float = maxf(candle_height * remaining_ratio, 0.012)
	_wax_mesh.height = h
	_wax.position = Vector3(0, stand_top + h * 0.5, 0)
	var tip := _wick_position()
	_flame.position = tip
	_flame_light.position = tip + Vector3(0, 0.035, 0)
	_smoke.position = tip
	_flame.visible = is_lit
	_flame_light.visible = is_lit

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

## 灯す。すでに灯っていればタイマーだけリセットする。
func light(reset_wax: bool = true) -> bool:
	if reset_wax or _remaining <= 0.0:
		_remaining = burn_seconds
	is_lit = true
	_apply_visual_state()
	Audio.play_at(&"candle_light", global_position)
	Events.emit_event(&"candle_lit")
	lit.emit()
	return true

## 台本で消す(丑三つ時など)。
func force_out() -> void:
	_extinguish(&"forced")

## 吹き消される(息・風)。見た目は同じだが煙が強い。
func blow_out() -> void:
	_extinguish(&"blown", 1.8)

## マッチを擦って灯し直す(終盤)。成功したら relight_success を出す。
func relight_attempt() -> bool:
	Audio.play_at(&"match_strike", global_position)
	if fail_next:
		fail_next = false
		Audio.play_at(&"match_fail", global_position)
		if _smoke:
			_smoke.restart()
			_smoke.emitting = true
		Dialogue.monologue(fail_line)
		relight_failed.emit()
		return false
	light(true)
	relight_count += 1
	Events.emit_event(&"relight_success", {"n": relight_count})
	return true

func seconds_remaining() -> float:
	return _remaining

func _extinguish(_reason: StringName, smoke_scale: float = 1.0) -> void:
	if not is_lit:
		return
	is_lit = false
	_remaining = maxf(_remaining, 0.0)
	_apply_visual_state()
	Audio.play_at(&"candle_blow", global_position)
	if _smoke:
		_smoke.amount_ratio = clampf(smoke_scale, 0.1, 1.0)
		_smoke.restart()
		_smoke.emitting = true
	if dread_on_out > 0:
		Dread.add(dread_on_out, &"candle_out")
	Events.emit_event(&"candle_out")
	went_out.emit()

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func _can_interact(_player: Node3D) -> bool:
	return not is_lit or not require_matches

func _interact(_player: Node3D) -> void:
	if require_matches:
		relight_attempt()
	else:
		light()
