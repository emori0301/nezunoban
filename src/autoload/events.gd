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

## 実秒後に発火。ポーズ中は進まない(process_always=false)。
func after(seconds: float, callable: Callable) -> void:
	var t := get_tree().create_timer(seconds, false)
	t.timeout.connect(callable)

## ポーズを尊重する SceneTreeTimer。`await Events.wait(2.0)` の形で使う。
func wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds, false).timeout

## 1回だけ受ける購読。発火したら自分で外す。
func once(name: StringName, callable: Callable) -> void:
	var holder: Array = [Callable()]
	holder[0] = func(n: StringName, d: Dictionary) -> void:
		if n == name:
			if event.is_connected(holder[0]):
				event.disconnect(holder[0])
			callable.call(d)
	event.connect(holder[0])

## name のイベントが来るまで待つ(timeout 秒で諦める)。接続は必ず外す。
func wait_event(name: StringName, timeout: float = 120.0) -> void:
	var done := [false]
	var cb := func(n: StringName, _d: Dictionary) -> void:
		if n == name:
			done[0] = true
	event.connect(cb)
	var elapsed := 0.0
	while not done[0] and elapsed < timeout:
		await get_tree().process_frame
		if not get_tree().paused:
			elapsed += get_process_delta_time()
	if event.is_connected(cb):
		event.disconnect(cb)

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
