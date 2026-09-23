class_name Phone
extends Interactable
## 事務所の黒電話。鳴っている間に取らないと異変度 +1。
##
## director からの使い方:
##     var ph := SystemsInstaller.find(&"phone") as Phone
##     ph.ring(30.0)
##     var ok: bool = await ph.call_ended        # true=出た / false=取り逃した
##     if ok:
##         await Dialogue.say("？？？", "……かえして……")
##         ph.hang_up()
## 「出たときだけ」進めたいなら await ph.answered でもよいが、取り逃すと永久に待つので
## call_ended を待つほうが安全。

signal answered
signal missed
signal call_ended(was_answered: bool)

@export var ring_interval: float = 2.6      # ベルの間隔(秒)
@export var dread_on_missed: int = 1
@export var ring_prompt: String = "電話に出る"
@export var idle_prompt: String = "受話器を取る"
@export var hangup_prompt: String = "受話器を置く"
@export var shake_while_ringing: bool = true
@export var dial_tone_text: String = "発信音だけだ。"

var is_ringing: bool = false
var off_hook: bool = false
var was_answered: bool = false

var _deadline: float = 0.0
var _next_ring: float = 0.0
var _t: float = 0.0
var _prop: Node3D
var _prop_rest: Vector3 = Vector3.ZERO
var _handset: Node3D
var _handset_rest: Transform3D

func _ready() -> void:
	super._ready()
	prompt = idle_prompt
	_prop = get_node_or_null(^"Prop")
	if _prop:
		_prop_rest = _prop.position
		if _prop is Prop:
			# phone.glb の "Handset" を持ち上げる
			var inst := (_prop as Prop).get_instance()
			if inst:
				_handset = inst.find_child("Handset", true, false) as Node3D
				if _handset:
					_handset_rest = _handset.transform
	set_process(true)

## 受話器の見た目を上げ下げする。
func _apply_handset() -> void:
	if _handset == null:
		return
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var t := _handset_rest
	if off_hook:
		t.origin += Vector3(0, 0.07, -0.02)
		t.basis = t.basis.rotated(Vector3.FORWARD, deg_to_rad(12.0))
	tw.tween_property(_handset, "transform", t, 0.25)

func _process(delta: float) -> void:
	_t += delta
	if not is_ringing:
		return
	_next_ring -= delta
	if _next_ring <= 0.0:
		_next_ring = ring_interval
		Audio.play_at(&"phone_ring", global_position, 0.0, 1.0, 30.0)
	if shake_while_ringing and _prop:
		# ベルの直後だけ小さく震える
		var since := ring_interval - _next_ring
		var amp: float = maxf(0.0, 1.0 - since / 0.9) * 0.004
		_prop.position = _prop_rest + Vector3(sin(_t * 90.0) * amp, 0.0, cos(_t * 77.0) * amp)
	_deadline -= delta
	if _deadline <= 0.0:
		_on_missed()

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

## 鳴らす。timeout 秒で取り逃し。
func ring(timeout: float = 30.0) -> void:
	if is_ringing:
		return
	if off_hook:
		# 受話器を上げっぱなしだと台本の電話が丸ごと飛ぶので、勝手に戻す。
		# hang_up() が phone_hangup を鳴らすので「受話器が戻る音」も出る。
		hang_up()
	is_ringing = true
	was_answered = false
	_deadline = timeout
	_next_ring = 0.0
	prompt = ring_prompt
	Events.emit_event(&"phone_ring")

## 鳴っているのを取り逃し扱いにせず止める(台本の都合で切りたいとき)。
func stop_ring() -> void:
	if not is_ringing:
		return
	is_ringing = false
	prompt = idle_prompt
	_reset_prop()

## 受話器を取る(鳴っているとき = 出る)。
func answer() -> void:
	if not is_ringing:
		return
	is_ringing = false
	off_hook = true
	was_answered = true
	prompt = hangup_prompt
	_reset_prop()
	_apply_handset()
	Audio.play_at(&"phone_pickup", global_position)
	Events.emit_event(&"phone_answered")
	answered.emit()
	call_ended.emit(true)

## 鳴っていないのに受話器を取る。無音。
func pick_up() -> void:
	if off_hook:
		return
	off_hook = true
	prompt = hangup_prompt
	_apply_handset()
	Audio.play_at(&"phone_pickup", global_position)

func hang_up() -> void:
	if not off_hook:
		return
	off_hook = false
	prompt = ring_prompt if is_ringing else idle_prompt
	_apply_handset()
	Audio.play_at(&"phone_hangup", global_position)

func _on_missed() -> void:
	is_ringing = false
	prompt = idle_prompt
	_reset_prop()
	Dread.add(dread_on_missed, &"phone_missed")
	Events.emit_event(&"phone_missed")
	missed.emit()
	call_ended.emit(false)

func _reset_prop() -> void:
	if _prop:
		_prop.position = _prop_rest

# --------------------------------------------------------------------------
# Interactable
# --------------------------------------------------------------------------

func get_prompt() -> String:
	if off_hook:
		return hangup_prompt
	if is_ringing:
		return ring_prompt
	return idle_prompt

func get_blocked_text() -> String:
	if not is_ringing:
		return dial_tone_text
	return super.get_blocked_text()

func _interact(_player: Node3D) -> void:
	if off_hook:
		hang_up()
	elif is_ringing:
		answer()
	else:
		pick_up()
