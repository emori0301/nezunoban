extends Node
## Dread: 隠しパラメータ「異変度」。加算のみ。閾値で怪異の段階が変わる。

signal changed(value: int, reason: StringName)
signal level_changed(level: int)   # 0: 静か / 1: 不穏(3-5) / 2: 危険(6+)

var value: int = 0
var log: Array[Dictionary] = []

func add(amount: int, reason: StringName = &"") -> void:
	var before_level := level()
	value += amount
	log.append({"t": Clock.hhmm(), "amount": amount, "reason": reason})
	changed.emit(value, reason)
	if level() != before_level:
		level_changed.emit(level())

func reset() -> void:
	value = 0
	log.clear()

func level() -> int:
	if value >= 6:
		return 2
	if value >= 3:
		return 1
	return 0

func is_doomed() -> bool:
	return value >= 6
