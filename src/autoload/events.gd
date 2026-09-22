extends Node
## Events: 時刻スケジューラ + 疎結合のイベントバス。
## 使い方:
##   Events.at("23:00", func(): ...)            # 時刻で発火(1回)
##   Events.after(90.0, func(): ...)           # 実秒後に発火
##   Events.emit_event(&"cat_entered", {...})  # バス
##   Events.on(&"cat_entered", func(data): ...)

signal event(name: StringName, data: Dictionary)

var _scheduled: Dictionary = {}   # total_minute(int) -> Array[Dictionary{id, callable}]
var _next_id: int = 1
var _cancelled: Dictionary = {}

func _ready() -> void:
	Clock.reached.connect(_on_minute)

func at(hhmm: String, callable: Callable, id: String = "") -> String:
	var total := Clock.minutes_from_hhmm(hhmm)
	return at_minute(total, callable, id)

func at_minute(total: int, callable: Callable, id: String = "") -> String:
	if id == "":
		id = "ev%d" % _next_id
		_next_id += 1
	if not _scheduled.has(total):
		_scheduled[total] = []
	_scheduled[total].append({"id": id, "callable": callable})
	if int(Clock.game_minutes) >= total:
		# もう過ぎているなら次フレームで即発火
		call_deferred("_fire", id, callable)
	return id

func after(seconds: float, callable: Callable) -> void:
	var t := get_tree().create_timer(seconds)
	t.timeout.connect(callable)

func cancel(id: String) -> void:
	_cancelled[id] = true

func _on_minute(total: int) -> void:
	if not _scheduled.has(total):
		return
	var list: Array = _scheduled[total]
	_scheduled.erase(total)
	for entry in list:
		_fire(entry["id"], entry["callable"])

func _fire(id: String, callable: Callable) -> void:
	if _cancelled.has(id):
		_cancelled.erase(id)
		return
	if callable.is_valid():
		callable.call()

func emit_event(name: StringName, data: Dictionary = {}) -> void:
	if Game.debug:
		print("[event] %s %s %s" % [Clock.hhmm(), name, data])
	event.emit(name, data)

func on(name: StringName, callable: Callable) -> void:
	event.connect(func(n: StringName, d: Dictionary) -> void:
		if n == name:
			callable.call(d))

func clear() -> void:
	_scheduled.clear()
	_cancelled.clear()
