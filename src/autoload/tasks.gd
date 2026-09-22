extends Node
## Tasks: HUD 左上の「いまやること」。同時に複数持てるが表示は先頭。

signal changed(current: Dictionary, all: Array)

var _tasks: Array[Dictionary] = []   # {id, text, done}

func set_task(id: StringName, text: String) -> void:
	for t in _tasks:
		if t["id"] == id:
			t["text"] = text
			t["done"] = false
			changed.emit(current(), _tasks)
			return
	_tasks.append({"id": id, "text": text, "done": false})
	changed.emit(current(), _tasks)

func complete(id: StringName) -> void:
	for t in _tasks:
		if t["id"] == id and not t["done"]:
			t["done"] = true
			Events.emit_event(&"task_completed", {"id": id})
	_tasks = _tasks.filter(func(t): return not t["done"])
	changed.emit(current(), _tasks)

func has(id: StringName) -> bool:
	for t in _tasks:
		if t["id"] == id:
			return true
	return false

func current() -> Dictionary:
	return _tasks[0] if _tasks.size() > 0 else {}

func clear() -> void:
	_tasks.clear()
	changed.emit({}, _tasks)
