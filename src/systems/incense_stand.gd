class_name IncenseStand
extends Interactable
## 香炉。このゲームの主ループ。線香1本 = burn_seconds(既定 180 秒 = 1ゲーム時間)。
## 絶えた瞬間に異変度 +1、棺が一度鳴る。
##
## director からの使い方:
##     var inc := SystemsInstaller.find(&"incense_stand") as IncenseStand
##     inc.force_out()                 # 強制的に消す(丑三つ時など)
##     inc.burn_multiplier = 3.0       # 窓が開いている間は3倍で減る
##     inc.set_wind(Vector3(1, 0, 0))  # 煙が真横に流れる
##     print(inc.remaining_ratio)      # 0.0〜1.0

signal lit
signal went_out
signal burn_progress(ratio: float)

@export var burn_seconds: float = 180.0
## 窓が開いていると director が 3.0 にする。0 で止まる。
@export var burn_multiplier: float = 1.0
@export var dread_on_out: int = 1
@export var stick_height: float = 0.22        # 線香の長さ(m)
@export var stick_radius: float = 0.0035
@export var stand_top: float = 0.115          # 香炉の灰の高さ(m。incense_stand.glb に合わせてある)
## モデルに焼き込まれた古い線香と重ならないように少しずらす。
@export var stick_offset: Vector3 = Vector3(0.042, 0.0, 0.026)
@export var ember_light_energy: float = 0.035 # 火種はほとんど光らない
@export var smoke_amount: int = 46
## 在庫が無いときの独白。日本語の文面は director が差し替えられるように export にしてある。
@export var no_stock_line: String = "線香が無い。"
@export var no_stock_text: String = "線香が無い。裏の在庫棚か。"
## 煙がゆっくり横に流れる既定の風。director が set_wind() で上書きできる。
@export var smoke_drift: Vector3 = Vector3(0.035, 0.0, 0.02)

var is_burning: bool = false
var wind: Vector3 = Vector3.ZERO

var remaining_ratio: float:
	get:
		if burn_seconds <= 0.0:
			return 0.0
		return clampf(_remaining / burn_seconds, 0.0, 1.0)

var _remaining: float = 0.0
var _t: float = 0.0
var _stick: MeshInstance3D
var _stick_mesh: CylinderMesh
var _ember: MeshInstance3D
var _ember_light: OmniLight3D
var _smoke: GPUParticles3D
var _puff: GPUParticles3D
var _prop: Node3D

func _ready() -> void:
	super._ready()
	prompt = "線香を立てる"
	_prop = get_node_or_null(^"Prop")
	_build_visuals()
	_apply_visual_state()
	set_process(true)

func _build_visuals() -> void:
	# モデルに焼き込まれた火種は消す(燃えていないのに光ってしまうため)。
	# 立っている線香はそのまま残す(使い終わった線香として自然に見える)。
	if _prop and _prop is Prop:
		SystemUtil.hide_surfaces((_prop as Prop).get_instance(), "Ember")

	# 線香の棒(燃えるにつれ短くなる)
	_stick = MeshInstance3D.new()
	_stick.name = "Stick"
	_stick_mesh = CylinderMesh.new()
	_stick_mesh.top_radius = stick_radius
	_stick_mesh.bottom_radius = stick_radius
	_stick_mesh.height = stick_height
	_stick_mesh.radial_segments = 6
	_stick_mesh.rings = 1
	_stick.mesh = _stick_mesh
	_stick.material_override = SystemUtil.flat_material(Color(0.24, 0.19, 0.17))
	_stick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stick)

	# 先端の火種(小さな赤い点)
	_ember = MeshInstance3D.new()
	_ember.name = "Ember"
	var q := QuadMesh.new()
	q.size = Vector2(0.016, 0.016)
	_ember.mesh = q
	_ember.material_override = SystemUtil.emissive_material(SystemUtil.ember_texture(), Color(1.0, 0.30, 0.06), 1.1, true)
	_ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ember)

	_ember_light = OmniLight3D.new()
	_ember_light.name = "EmberLight"
	_ember_light.light_color = Color(1.0, 0.40, 0.12)
	_ember_light.light_energy = ember_light_energy
	_ember_light.omni_range = 0.30
	_ember_light.omni_attenuation = 1.4
	_ember_light.shadow_enabled = false
	add_child(_ember_light)

	# 細い灰色の煙(粒が離れて見えないよう、多め・大きめ・薄めにする)
	# 一筋の細い煙にする。粒を小さく薄くし、数を増やして途切れないようにする。
	# 上昇速度と寿命の組み合わせで 1.2m ほど昇って消える。
	_smoke = SystemUtil.make_smoke(smoke_amount, 3.2, 0.30, 0.008, 0.042, Color(0.58, 0.58, 0.61, 0.115), 2.2)
	_smoke.name = "Smoke"
	_smoke.emitting = false
	add_child(_smoke)

	# 消えた瞬間の一瞬強い煙
	_puff = SystemUtil.make_smoke(16, 1.6, 0.35, 0.02, 0.13, Color(0.72, 0.72, 0.75, 0.26), 26.0)
	_puff.name = "Puff"
	_puff.one_shot = true
	_puff.explosiveness = 0.85
	_puff.emitting = false
	add_child(_puff)

	set_wind(smoke_drift)

func _process(delta: float) -> void:
	_t += delta
	if not is_burning:
		return
	# --debug の F2/F3 で時計を倍速にしたときに線香だけ遅れないよう Clock.speed を掛ける
	_remaining -= delta * maxf(burn_multiplier, 0.0) * Clock.speed
	if _remaining <= 0.0:
		_remaining = 0.0
		_extinguish()
		return
	_apply_visual_state()
	_flicker()
	burn_progress.emit(remaining_ratio)

func _flicker() -> void:
	var n := 0.72 + 0.18 * sin(_t * 9.3) + 0.10 * sin(_t * 23.7 + 1.3)
	_ember_light.light_energy = ember_light_energy * n
	_ember.scale = Vector3.ONE * (0.85 + 0.25 * n)

## 線香の長さ・火種・煙の位置を残量に合わせる。
func _apply_visual_state() -> void:
	var r := remaining_ratio
	var h: float = maxf(stick_height * r, 0.001)
	_stick_mesh.height = h
	_stick.position = stick_offset + Vector3(0, stand_top + h * 0.5, 0)
	_stick.visible = is_burning or r > 0.0
	var tip := stick_offset + Vector3(0, stand_top + h, 0)
	_ember.position = tip
	_ember_light.position = tip + Vector3(0, 0.005, 0)
	_smoke.position = tip
	_puff.position = tip
	_ember.visible = is_burning
	_ember_light.visible = is_burning
	_smoke.emitting = is_burning

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

## 線香を立てる。在庫が無ければ false。燃えている最中でもタイマーをリセットできる。
func light() -> bool:
	if int(Game.get_flag(&"incense_sticks", 0)) <= 0:
		Dialogue.monologue(no_stock_line)
		return false
	Game.add_flag(&"incense_sticks", -1)
	_remaining = burn_seconds
	is_burning = true
	_apply_visual_state()
	Audio.play_at(&"incense_light", global_position)
	Events.emit_event(&"incense_lit")
	lit.emit()
	return true

## 強制的に消す(丑三つ時・電話のあとなど)。燃え尽きと同じ経路を通る。
func force_out() -> void:
	if not is_burning:
		return
	_remaining = 0.0
	_extinguish()

## 残り秒数(実時間)。
func seconds_remaining() -> float:
	return _remaining

## 煙を流す風。窓や空調の演出に使う。
func set_wind(v: Vector3) -> void:
	wind = v
	for p in [_smoke, _puff]:
		if p == null:
			continue
		var pm: ParticleProcessMaterial = p.process_material
		if pm:
			pm.gravity = Vector3(v.x, pm.gravity.y, v.z)

func _extinguish() -> void:
	is_burning = false
	_apply_visual_state()
	# 消えた瞬間、煙が一瞬強くなって止まる
	if _puff:
		_puff.restart()
		_puff.emitting = true
	Audio.play_at(&"incense_hiss", global_position, -4.0)
	Events.emit_event(&"incense_out")
	Dread.add(dread_on_out, &"incense_out")
	# 絶えた瞬間に棺が一度鳴る
	var coffin := SystemsInstaller.find(&"coffin")
	if coffin != null and coffin.has_method(&"knock"):
		coffin.call(&"knock")
	else:
		Audio.play_at(&"coffin_knock", global_position, -2.0)
	went_out.emit()

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func get_blocked_text() -> String:
	if int(Game.get_flag(&"incense_sticks", 0)) <= 0:
		return no_stock_text
	return super.get_blocked_text()

func _interact(_player: Node3D) -> void:
	light()
