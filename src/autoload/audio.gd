extends Node
## Audio: SFX/環境音の再生。assets/audio/<name>.wav をファイル名で引く。
## 音名の一覧と意味は CLAUDE.md「音名一覧」を正とする。
## 実装は audio 担当エージェントが差し替える。ここは他エージェントが依存できる最小 API。

const DIR := "res://assets/audio/"
## 音ごとの推奨ゲイン(docs/previews/audio_report.md の最終列から生成)。play/play_at の volume_db に加算される。
const GAIN_DB := {
	&"breath_close": -12.0,
	&"cat_purr": -16.0,
	&"coffin_scratch": -6.0,
	&"footstep_ceiling_1": -8.0,
	&"footstep_ceiling_2": -8.0,
	&"footstep_ceiling_3": -8.0,
	&"heartbeat": -10.0,
	&"incense_hiss": -24.0,
	&"page_turn": -10.0,
	&"paper_rustle": -10.0,
	&"phone_breath": -8.0,
	&"step_concrete_1": -14.0,
	&"step_concrete_2": -14.0,
	&"step_concrete_3": -14.0,
	&"step_concrete_4": -14.0,
	&"step_lino_1": -14.0,
	&"step_lino_2": -14.0,
	&"step_lino_3": -14.0,
	&"step_lino_4": -14.0,
	&"step_tatami_1": -14.0,
	&"step_tatami_2": -14.0,
	&"step_tatami_3": -14.0,
	&"step_tatami_4": -14.0,
	&"tv_static": -14.0,
	&"ui_back": -18.0,
	&"ui_confirm": -16.0,
	&"ui_select": -18.0,
	&"whisper_1": -20.0,
	&"whisper_2": -20.0,
	&"whisper_3": -20.0,
}
var _cache: Dictionary = {}
var _ambient_players: Dictionary = {}   # name -> AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []

func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
		add_child(p)
		_pool.append(p)
	for i in 12:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
		add_child(p3)
		_pool3d.append(p3)

func _exit_tree() -> void:
	for p in _ambient_players.values():
		p.stop()
		p.stream = null
	_ambient_players.clear()
	for p in _pool:
		p.stop()
		p.stream = null
	for p in _pool3d:
		p.stop()
		p.stream = null
	_cache.clear()

func _load(name: StringName) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + String(name) + ".wav"
	if not ResourceLoader.exists(path):
		path = DIR + String(name) + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("Audio: missing %s" % name)
		_cache[name] = null
		return null
	var s: AudioStream = load(path)
	_cache[name] = s
	return s

## 2D(位置なし)で単発再生
func play(name: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var s := _load(name)
	if s == null:
		return null
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db + float(GAIN_DB.get(name, 0.0))
			p.pitch_scale = pitch
			p.play()
			return p
	return null

## 3D位置で単発再生
func play_at(name: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0, max_distance: float = 20.0) -> AudioStreamPlayer3D:
	var s := _load(name)
	if s == null:
		return null
	for p in _pool3d:
		if not p.playing:
			p.stream = s
			p.global_position = position
			p.volume_db = volume_db + float(GAIN_DB.get(name, 0.0))
			p.pitch_scale = pitch
			p.max_distance = max_distance
			p.play()
			return p
	return null

## ループ環境音。同名は1つだけ。fade 秒でフェードイン。
func ambient(name: StringName, volume_db: float = -6.0, fade: float = 1.0) -> void:
	if _ambient_players.has(name):
		return
	var s := _load(name)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = &"Ambient" if AudioServer.get_bus_index("Ambient") >= 0 else &"Master"
	p.stream = s
	p.volume_db = -60.0
	add_child(p)
	p.play()
	_ambient_players[name] = p
	var tw := create_tween()
	tw.tween_property(p, "volume_db", volume_db, fade)

func stop_ambient(name: StringName, fade: float = 1.0) -> void:
	if not _ambient_players.has(name):
		return
	var p: AudioStreamPlayer = _ambient_players[name]
	_ambient_players.erase(name)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, fade)
	tw.tween_callback(p.queue_free)

func stop_all_ambient(fade: float = 1.0) -> void:
	for n in _ambient_players.keys():
		stop_ambient(n, fade)

## 恐怖演出用: マスターにローパス(こもり)をかける/外す
func set_muffled(enabled: bool) -> void:
	var idx := AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectLowPassFilter:
			AudioServer.set_bus_effect_enabled(idx, i, enabled)
