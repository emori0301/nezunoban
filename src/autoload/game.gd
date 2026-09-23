extends Node
## Game: 全体の状態と物語フラグ。夜の開始/終了、エンディング遷移を担う。

signal flag_changed(key: StringName, value: Variant)
signal night_started
signal night_ended(ending: StringName)
signal player_registered(player: Node3D)

enum State { TITLE, PLAYING, ENDING }

var state: State = State.TITLE
var player: Node3D = null
var level: Node3D = null
var flags: Dictionary = {}
var ending_reached: StringName = &""
var debug: bool = false
var boot_count: int = 0   # start_night が呼ばれた回数(タイトルへ戻って再開すると増える)

## エンディング ID
const ENDING_MORNING := &"morning"   # 朝
const ENDING_KASHA := &"kasha"       # 火車
const ENDING_SUBSTITUTE := &"substitute" # 代わり(真)
const ENDING_PORTRAIT := &"portrait" # 遺影

func set_flag(key: StringName, value: Variant = true) -> void:
	flags[key] = value
	flag_changed.emit(key, value)

func get_flag(key: StringName, default: Variant = false) -> Variant:
	return flags.get(key, default)

func add_flag(key: StringName, amount: int = 1) -> int:
	var v: int = int(flags.get(key, 0)) + amount
	flags[key] = v
	flag_changed.emit(key, v)
	return v

func register_player(p: Node3D) -> void:
	player = p
	player_registered.emit(p)

func start_night() -> void:
	state = State.PLAYING
	ending_reached = &""
	boot_count += 1
	night_started.emit()

func end_night(ending: StringName) -> void:
	if state == State.ENDING:
		return
	state = State.ENDING
	ending_reached = ending
	get_tree().paused = false   # ポーズ中にエンディングへ入っても止まったままにしない
	night_ended.emit(ending)
	# 実際の画面遷移は director (src/director) が night_ended を受けて行う

func reset() -> void:
	get_tree().paused = false
	flags.clear()
	state = State.TITLE
	ending_reached = &""
	player = null
	level = null
	# 前の夜が autoload のシグナルに繋いだハンドラ(director/HUD/systems のラムダ)を全部外す。
	# 外さないと「タイトルへ」→再開で二重に発火し、解放済みノードを触ってエラーになる。
	for sig in [flag_changed, night_started, night_ended, player_registered]:
		_disconnect_all(sig)
	for sig in [Clock.minute_passed, Clock.hour_passed]:
		_disconnect_all(sig)
	_disconnect_all(Clock.reached, [Callable(Events, "_on_minute")])
	for sig in [Dread.changed, Dread.level_changed, Tasks.changed, Events.event, Dialogue.line_shown, Dialogue.finished]:
		_disconnect_all(sig)
	Clock.reset()
	Dread.reset()
	Tasks.clear()
	Events.clear()
	Dialogue.auto_advance = false
	Audio.stop_all_ambient(0.5)

func _disconnect_all(sig: Signal, keep: Array = []) -> void:
	for c in sig.get_connections():
		var cb: Callable = c["callable"]
		var keep_it := false
		for k in keep:
			if cb == k:
				keep_it = true
		if not keep_it:
			sig.disconnect(cb)
