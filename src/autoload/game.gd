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
	night_started.emit()

func end_night(ending: StringName) -> void:
	if state == State.ENDING:
		return
	state = State.ENDING
	ending_reached = ending
	night_ended.emit(ending)
	# 実際の画面遷移は director (src/director) が night_ended を受けて行う

func reset() -> void:
	flags.clear()
	state = State.TITLE
	ending_reached = &""
	player = null
	level = null
	Clock.reset()
	Dread.reset()
	Tasks.clear()
	Events.clear()
	Audio.stop_all_ambient(0.5)
