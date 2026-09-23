class_name Radio
extends Interactable
## 事務所の棚のトランジスタラジオ(E-6)。
## 01:30 に勝手につき、消しても 20 秒後にまたつく。2 回目は途中で濡れた声に変わる。
##
## director からの使い方:
##     var r := SystemsInstaller.find(&"radio") as Radio
##     r.turn_on()
##     r.play_voice(&"phone_voice_wet")   # 放送の途中で声が変わる
##     r.turn_off()
##     Events.on(&"radio_off", func(_d): ...)

signal turned_on
signal turned_off

@export var on_prompt: String = "ラジオを消す"
@export var off_prompt: String = "ラジオをつける"
@export var start_on: bool = false
@export var voice_name: StringName = &"radio_talk"
@export var volume_db: float = -12.0
@export var max_distance: float = 14.0

var is_on: bool = false

var _loop: AudioStreamPlayer3D
var _current_voice: StringName = &""

func _ready() -> void:
	super._ready()
	_loop = _make_loop_player()
	if start_on:
		turn_on()

func _make_loop_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "Loop"
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.position = Vector3(0, 0.08, 0)
	p.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	add_child(p)
	return p

## 指定の音をループで流す。無い音でも警告だけで落ちない。
func _set_stream(sound: StringName) -> void:
	if _loop == null:
		return
	_current_voice = sound
	var path := "res://assets/audio/%s.wav" % sound
	if not ResourceLoader.exists(path):
		path = "res://assets/audio/%s.ogg" % sound
	if not ResourceLoader.exists(path):
		push_warning("Radio: 音が無い %s(音なしで動く)" % sound)
		_loop.stream = null
		return
	var s: AudioStream = load(path)
	if s is AudioStreamWAV:
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = 0
		_loop.stream = w
	elif s is AudioStreamOggVorbis:
		var o := (s as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		o.loop = true
		_loop.stream = o
	else:
		_loop.stream = s

# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------

func turn_on() -> void:
	if is_on:
		return
	is_on = true
	Audio.play_at(&"radio_on", global_position)
	_set_stream(voice_name)
	if _loop and _loop.stream:
		_loop.play()
	Events.emit_event(&"radio_on")
	turned_on.emit()

func turn_off() -> void:
	if not is_on:
		return
	is_on = false
	Audio.play_at(&"radio_off", global_position)
	if _loop:
		_loop.stop()
	Events.emit_event(&"radio_off")
	turned_off.emit()

## 放送の中身を差し替える(ついたままなら即座に切り替わる)。
func play_voice(sound: StringName) -> void:
	voice_name = sound
	if not is_on:
		return
	_set_stream(sound)
	if _loop and _loop.stream:
		_loop.play()

func current_voice() -> StringName:
	return _current_voice

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
