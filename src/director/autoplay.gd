class_name Autoplay
extends Node
## QA 用の自動プレイ。プレイヤーを台本どおりに操作して一夜を最後まで走らせる。
##
##   godot --path . -- --skip-title --autoplay=morning|kasha|substitute|portrait [--speed=6]
##
## 終了時に
##   AUTOPLAY RESULT ending=<id> dread=<n> minutes=<n>
## を出し、期待エンディングと違えば exit code 1 で落ちる。
## イベントログは user://autoplay_<mode>.log にも書く。
##
## 歩かせるのではなく teleport + interact() で用事をこなす(経路探索に依存しないため)。

var dir                                  ## Director
var mode: StringName = &"morning"
var speed: float = 6.0

var interval: float = 3.0                ## 判断の間隔(実秒。speed で割る)
var watchdog: float = 900.0              ## これを超えたら失敗扱い

var _t: float = 0.0
var _elapsed: float = 0.0
var _busy: bool = false
var _started: bool = false
var _done: bool = false
var _log: Array[String] = []

const EXPECTED := {
	&"morning": &"morning",
	&"kasha": &"kasha",
	&"substitute": &"substitute",
	&"portrait": &"portrait",
}


func begin() -> void:
	if _started:
		return
	_started = true
	Game.debug = true
	Dialogue.auto_advance = true
	Dialogue.auto_line_seconds = 0.08
	Dialogue.auto_chooser = Callable(self, "choose")
	Clock.speed = maxf(speed, 0.1)
	# 線香・ロウソクは実秒タイマーなので、倍速ぶんだけ短くする(ゲーム内の長さを保つ)
	var inc := dir.sys(&"incense_stand")
	if inc:
		inc.set(&"burn_seconds", 180.0 / maxf(speed, 0.1))
	var cnd := dir.sys(&"candle")
	if cnd:
		cnd.set(&"burn_seconds", 720.0 / maxf(speed, 0.1))
	Game.night_ended.connect(_on_ended)
	Events.event.connect(func(n: StringName, d: Dictionary):
		_log.append("%s %s %s" % [Clock.hhmm(), n, d]))
	print("AUTOPLAY START mode=%s speed=%.1f" % [mode, speed])
	set_process(true)


func player() -> Node3D:
	return Game.player


# ============================================================ 選択肢

func choose(prompt: String, options: Array) -> int:
	var idx := 0
	if prompt == ScriptText.SON_CHOICE_PROMPT:
		idx = 0                                   # いつも断る(真エンドの前提)
	elif prompt == ScriptText.CHOICE_HIKAESHITSU:
		idx = 1 if mode == &"substitute" else 0
	elif prompt.begins_with("少し休む"):
		idx = 1 if mode == &"portrait" else 0
	_log.append("%s choose %s -> %d" % [Clock.hhmm(), prompt, idx])
	print("[auto] choose '%s' -> %s" % [prompt, String(options[idx]) if idx < options.size() else idx])
	return idx


# ============================================================ ループ

func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed > watchdog:
		_fail("watchdog: %.0f 秒たっても終わらない" % _elapsed)
		return
	_t -= delta
	if _t > 0.0 or _busy:
		return
	_t = interval / maxf(speed, 0.1)
	_decide()


func _decide() -> void:
	if _busy or _done:
		return
	if Dialogue.busy or Game.state == Game.State.ENDING:
		return
	var p := player()
	if p == null or bool(p.get(&"locked")):
		return
	_busy = true
	await _act()
	_busy = false


func _act() -> void:
	# 1. 布団(遺影エンド)
	if mode == &"portrait" and int(Clock.game_minutes) >= 90:
		if await _use(dir.sys(&"futon"), 1.0):
			return
	# 2. 終盤で控室の戸(代わりエンド)
	if mode == &"substitute" and dir.timeline.finale_running():
		var spot := _find_spot()
		if spot and await _use(spot, 1.2):
			return
	# 3. 電話
	var ph := dir.sys(&"phone")
	if ph and bool(ph.get(&"is_ringing")) and mode != &"kasha":
		if await _use(ph, 1.0):
			return
	# 4. 線香(kasha モードは導入の1本だけで、以降は放置する)
	if mode != &"kasha" or not Game.get_flag(&"intro_done", false):
		if await _keep_incense():
			return
	# 5. 猫
	if await _shoo_cat():
		return
	# 6. いまのタスク
	var t := Tasks.current()
	if not t.is_empty():
		if await _do_task(StringName(t.get("id", &""))):
			return
	# 7. ロウソク(終盤以外)
	if not dir.timeline.finale_running() and mode != &"kasha":
		var cnd := dir.sys(&"candle")
		if cnd and not bool(cnd.get(&"is_lit")) and not bool(cnd.get(&"require_matches")):
			await _use(cnd, 1.0)


func _keep_incense() -> bool:
	var inc := dir.sys(&"incense_stand")
	if inc == null:
		return false
	var burning := bool(inc.get(&"is_burning"))
	var ratio := float(inc.get(&"remaining_ratio"))
	if burning and ratio >= 0.35:
		return false
	if int(Game.get_flag(&"incense_sticks", 0)) <= 0:
		var box := dir.stock_box()
		if box == null:
			dir.enable_stock_box()
			box = dir.stock_box()
		if box and await _use(box, 1.0):
			return true
		return false
	return await _use(inc, 1.1)


func _shoo_cat() -> bool:
	for c in dir.npc_all(&"cat"):
		if not (c is Node3D):
			continue
		var inside: Variant = c.get(&"is_inside")
		if inside == null or not bool(inside):
			continue
		var target: Node = c
		for ch in c.find_children("*", "Interactable", true, false):
			target = ch
			break
		if await _use(target, 1.0):
			return true
		if c.has_method(&"flee"):
			c.call(&"flee")
			return true
	return false


func _do_task(id: StringName) -> bool:
	match id:
		&"incense", &"last_incense":
			return await _use(dir.sys(&"incense_stand"), 1.1)
		&"incense_stock":
			return await _use(dir.stock_box(), 1.0)
		&"backdoor":
			var d := _door(&"Door_Backyard")
			if d and d.is_open:
				return await _use(d, 1.3)
			return false
		&"window":
			var w := _window(&"Window_Shikijo")
			if w and w.is_open:
				return await _use(w, 1.3)
			return false
		&"flowers":
			if not _has_item(&"water"):
				return await _use(dir.sys(&"sink"), 1.0)
			return await _use(SystemsInstaller.find(&"flower_stand"), 1.2)
		&"candle":
			return await _use(dir.sys(&"candle"), 1.0)
		&"breaker":
			return await _use(dir.sys(&"breaker"), 1.0)
		&"dry_ice":
			if _has_item(&"dry_ice"):
				return await _use(dir.sys(&"coffin"), 1.3)
			return await _use(dir.sys(&"freezer"), 1.2)
		&"cat":
			return await _shoo_cat()
		&"relight":
			if not _has_item(&"matches"):
				return await _use(dir.matches_pickup(), 1.0)
			return await _use(dir.sys(&"candle"), 1.0)
		&"talk_boss":
			Tasks.complete(&"talk_boss")
			return true
	return false


# ============================================================ 操作

func _has_item(item: StringName) -> bool:
	var p := player()
	return p != null and p.has_method(&"has_item") and p.has_item(item)


func _door(n: StringName) -> Door:
	var b: Building = dir.building()
	return b.get_door(n) if b else null


func _window(n: StringName) -> WindowPane:
	var b: Building = dir.building()
	return b.get_window_pane(n) if b else null


func _find_spot() -> Node:
	var b: Building = dir.building()
	if b == null:
		return null
	for c in b.get_children():
		if c is Scares.Spot and (c as Interactable).enabled:
			return c
	return null


## 近くへ飛んでから interact する。
func _use(n: Node, dist: float = 1.1) -> bool:
	if n == null or not is_instance_valid(n) or not (n is Node3D):
		return false
	var target := n as Node3D
	var p := player()
	if p == null:
		return false
	_go(target, dist)
	await get_tree().physics_frame
	if n.has_method(&"can_interact") and not n.call(&"can_interact", p):
		return false
	if not n.has_method(&"interact"):
		return false
	_log.append("%s use %s" % [Clock.hhmm(), n.name])
	n.call(&"interact", p)
	await get_tree().create_timer(0.35 / maxf(speed, 0.1)).timeout
	return true


func _go(target: Node3D, dist: float) -> void:
	var p := player()
	if p == null or not p.has_method(&"teleport"):
		return
	var fwd := -target.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3(0, 0, 1)
	fwd = fwd.normalized()
	var pos := target.global_position + fwd * dist
	pos.y = 0.0
	var d := target.global_position - pos
	d.y = 0.0
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	p.call(&"teleport", pos, yaw, -8.0)


# ============================================================ 終わり

func _on_ended(id: StringName) -> void:
	if _done:
		return
	_done = true
	print("AUTOPLAY RESULT ending=%s dread=%d minutes=%d" % [id, Dread.value, int(Clock.game_minutes)])
	_write_log(id)
	var want: StringName = EXPECTED.get(mode, mode)
	await get_tree().create_timer(0.4).timeout
	if id != want:
		printerr("AUTOPLAY MISMATCH expected=%s got=%s" % [want, id])
		get_tree().quit(1)
	else:
		print("AUTOPLAY OK %s" % id)
		get_tree().quit(0)


func _fail(why: String) -> void:
	_done = true
	printerr("AUTOPLAY FAIL mode=%s: %s (dread=%d minutes=%d task=%s)"
		% [mode, why, Dread.value, int(Clock.game_minutes), Tasks.current()])
	_write_log(&"fail")
	get_tree().quit(1)


func _write_log(id: StringName) -> void:
	var path := "user://autoplay_%s.log" % mode
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("mode=%s expected=%s got=%s dread=%d minutes=%d elapsed=%.1fs"
		% [mode, EXPECTED.get(mode, mode), id, Dread.value, int(Clock.game_minutes), _elapsed])
	f.store_line("--- director ---")
	for l in dir.event_log():
		f.store_line(l)
	f.store_line("--- events ---")
	for l in _log:
		f.store_line(l)
	f.close()
	print("AUTOPLAY LOG %s" % ProjectSettings.globalize_path(path))
