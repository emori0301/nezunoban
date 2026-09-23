class_name Breaker
extends Interactable
## バックヤードの分電盤。照明の実際の操作は director が Building に対して行う。
## ここは「落ちた/上げた」を音とイベントで伝えるだけ。
##
## director からの使い方:
##     var br := SystemsInstaller.find(&"breaker") as Breaker
##     br.trip()                                  # 00:00 廊下の照明が落ちる
##     Events.on(&"breaker_on", func(_d):
##         Building.set_all_lights(true))

signal tripped
signal restored
signal lever_raised(name: StringName, ok: bool)

@export var is_on: bool = true
@export var restore_prompt: String = "ブレーカーを上げる"
@export var idle_prompt: String = "分電盤"
@export var normal_text: String = "異常はない。"
@export var restore_hold_time: float = 1.0
@export var panel_size: Vector3 = Vector3(0.30, 0.40, 0.12)
## レバーの位置(breaker_box.glb の前面に合わせてある)
## モデルの主幹ブレーカーのレバーを倒す角度(X 回転)
@export var lever_down_degrees: float = 38.0
@export var lever_offset: Vector3 = Vector3(-0.263, 0.188, 0.045)
## 3本のレバー(E-2)。正しい順は 主幹 → 廊下 → 式場。director が差し替えてよい。
@export var required_order: Array[StringName] = [&"Lever_Main", &"Lever_Hall", &"Lever_Shikijo"]
## 各レバーの位置(breaker_box.glb の前面に合わせてある)と当たり判定の大きさ。
@export var lever_positions: Array[Vector3] = [
	Vector3(-0.140, 0.210, 0.02),
	Vector3(-0.020, 0.205, 0.02),
	Vector3(0.060, 0.205, 0.02),
]
@export var lever_touch_size: Vector3 = Vector3(0.07, 0.10, 0.08)
@export var lever_size: Vector3 = Vector3(0.030, 0.050, 0.022)

var _model_lever: Node3D
var _lever: MeshInstance3D
var _levers: Array[BreakerLever] = []

func _ready() -> void:
	super._ready()
	prompt = restore_prompt
	hold_time = restore_hold_time
	_build()
	_build_levers()
	_apply()

func _build() -> void:
	# breaker_box.glb の "Lever"(原点 (-0.140, 0.210, 0.006)、X 回転で上下に倒れる)
	var prop := get_node_or_null(^"Prop") as Prop
	if prop:
		var inst := prop.get_instance()
		if inst:
			_model_lever = inst.find_child("Lever", true, false) as Node3D
	if _model_lever:
		return
	_lever = MeshInstance3D.new()
	_lever.name = "Lever"
	var bm := BoxMesh.new()
	bm.size = lever_size if SystemUtil.has_model("breaker_box") else Vector3(0.05, 0.09, 0.035)
	_lever.mesh = bm
	_lever.position = lever_offset if SystemUtil.has_model("breaker_box") else Vector3(0, panel_size.y * 0.55, panel_size.z * 0.5 + 0.02)
	_lever.material_override = SystemUtil.flat_material(Color(0.85, 0.83, 0.78))
	# breaker_box.glb は主幹ブレーカーとスイッチ列を持っているので、自前のレバーは出さない
	# (models に "Lever" ノードを切ってもらえたら、そこを回して見た目でも上下を出せる)。
	_lever.visible = not SystemUtil.has_model("breaker_box")
	add_child(_lever)

## 子レバー3本を作る。主幹には glb の Lever を、残り2本は小さな箱を割り当てる。
func _build_levers() -> void:
	for i in required_order.size():
		var nm: StringName = required_order[i]
		var lv := BreakerLever.new()
		lv.name = String(nm)
		lv.lever_name = nm
		var pos: Vector3 = lever_positions[i] if i < lever_positions.size() else Vector3(0.0, 0.2, 0.02)
		lv.position = pos
		add_child(lv)

		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = lever_touch_size
		cs.shape = bs
		lv.add_child(cs)

		var visual: Node3D = null
		if i == 0 and _model_lever:
			# 主幹はモデルのレバーを動かす(位置はモデル側なので lv 自体は目印)
			visual = _model_lever
		else:
			var mi := MeshInstance3D.new()
			mi.name = "Stick"
			var bm := BoxMesh.new()
			bm.size = Vector3(0.022, 0.05, 0.02)
			mi.mesh = bm
			mi.material_override = SystemUtil.flat_material(Color(0.88, 0.86, 0.80))
			lv.add_child(mi)
			visual = mi
		lv.setup(visual)
		_levers.append(lv)
	# レバーがあるなら盤そのものは押せなくする(レバーを押してもらう)
	if not _levers.is_empty():
		enabled = false

func get_lever(name: StringName) -> BreakerLever:
	for lv in _levers:
		if lv.lever_name == name:
			return lv
	return null

func levers_up() -> int:
	var n := 0
	for lv in _levers:
		if lv.is_up:
			n += 1
	return n

## 次に上げるべきレバー。全部上がっていれば &""。
func next_expected() -> StringName:
	for nm in required_order:
		var lv := get_lever(nm)
		if lv and not lv.is_up:
			return nm
	return &""

## レバーを上げる。順が違えば火花が出て落ちる。
func raise_lever(name: StringName) -> bool:
	var lv := get_lever(name)
	if lv == null or lv.is_up:
		return false
	var expected := next_expected()
	if name != expected:
		Audio.play_at(&"spark", global_position)
		lv.set_up(false)
		Events.emit_event(&"breaker_lever", {"name": name, "ok": false})
		lever_raised.emit(name, false)
		return false
	Audio.play_at(&"breaker_click", global_position)
	lv.set_up(true)
	Events.emit_event(&"breaker_lever", {"name": name, "ok": true})
	lever_raised.emit(name, true)
	if next_expected() == &"":
		is_on = true
		_apply(true)
		Audio.play_at(&"lights_on", global_position, -4.0)
		Events.emit_event(&"breaker_on")
		restored.emit()
	return true

## 3本とも落とす(23:30 の停電)。
func trip_all() -> void:
	for lv in _levers:
		lv.set_up(false)
	is_on = false
	_apply(true)
	Audio.play_at(&"breaker_click", global_position)
	Audio.play_at(&"lights_off", global_position, -4.0)
	Events.emit_event(&"breaker_off")
	tripped.emit()

func _apply(animate: bool = false) -> void:
	if _model_lever:
		if animate:
			var tw := create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(_model_lever, "rotation_degrees:x", 0.0 if is_on else lever_down_degrees, 0.18)
		else:
			_model_lever.rotation_degrees.x = 0.0 if is_on else lever_down_degrees
		return
	if _lever:
		_lever.rotation_degrees.x = 0.0 if is_on else 34.0
		(_lever.material_override as StandardMaterial3D).albedo_color = (
			Color(0.85, 0.83, 0.78) if is_on else Color(0.55, 0.20, 0.16))

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

## ブレーカーを落とす(台本用)。レバーがあれば3本とも落とす。
func trip() -> void:
	if not is_on and levers_up() == 0:
		return
	trip_all()

## 正しい順で全部上げる(autoplay と台本の都合で一気に戻したいとき)。
func restore() -> void:
	for nm in required_order:
		var lv := get_lever(nm)
		if lv:
			lv.set_up(true)
	if is_on:
		return
	is_on = true
	_apply(true)
	Audio.play_at(&"breaker_click", global_position)
	Audio.play_at(&"lights_on", global_position, -4.0)
	Events.emit_event(&"breaker_on")
	restored.emit()

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func get_prompt() -> String:
	return restore_prompt if not is_on else idle_prompt

func get_blocked_text() -> String:
	if is_on:
		return normal_text
	return super.get_blocked_text()

func _can_interact(_player: Node3D) -> bool:
	return not is_on

func _interact(_player: Node3D) -> void:
	restore()
