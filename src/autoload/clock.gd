extends Node
## Clock: 夜の時刻。21:00 = 0分、05:00 = 480分。1ゲーム分 = seconds_per_game_minute 秒。

signal minute_passed(total_minutes: int)
signal hour_passed(hour: int)   # 22, 23, 0, 1, ...
signal reached(total_minutes: int)

const START_HOUR := 21
const END_MINUTES := 480          # 05:00
var seconds_per_game_minute: float = 3.0
var game_minutes: float = 0.0     # 21:00 からの経過(分)
var running: bool = false
var speed: float = 1.0            # デバッグ用倍率

var _last_whole: int = -1

func _process(delta: float) -> void:
	if not running:
		return
	var before := int(game_minutes)
	game_minutes = minf(game_minutes + delta * speed / seconds_per_game_minute, END_MINUTES)
	var after := int(game_minutes)
	if after != before:
		for m in range(before + 1, after + 1):
			minute_passed.emit(m)
			reached.emit(m)
			if m % 60 == 0:
				hour_passed.emit(hour_of(m))

func start() -> void:
	running = true

func stop() -> void:
	running = false

## 時刻を直接進める(スキップ演出や「休む」用)。途中の分イベントも発火する。
func skip_to(total_minutes: int) -> void:
	var before := int(game_minutes)
	game_minutes = clampf(total_minutes, 0, END_MINUTES)
	for m in range(before + 1, int(game_minutes) + 1):
		minute_passed.emit(m)
		reached.emit(m)
		if m % 60 == 0:
			hour_passed.emit(hour_of(m))

func hour_of(total: int) -> int:
	return (START_HOUR + int(total / 60.0)) % 24

func minute_of(total: int) -> int:
	return total % 60

## "PM 11:32" / "AM 2:05" 形式(VHS タイムスタンプ用)
func time_string() -> String:
	var t := int(game_minutes)
	var h := hour_of(t)
	var m := minute_of(t)
	var ampm := "PM" if h >= 12 else "AM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%s %d:%02d" % [ampm, h12, m]

## "23:05" 形式
func hhmm() -> String:
	var t := int(game_minutes)
	return "%02d:%02d" % [hour_of(t), minute_of(t)]

## "HH:MM" → 21:00 からの経過分。"01:30" → 270
static func minutes_from_hhmm(text: String) -> int:
	var parts := text.split(":")
	var h := int(parts[0])
	var m := int(parts[1]) if parts.size() > 1 else 0
	var rel := h - START_HOUR
	if rel < 0:
		rel += 24
	return rel * 60 + m
