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

## 走行中の定期スクリーンショット(--shots=<dir> --shot-interval=<sec>)。
## 夜全体を目視するための連番。--headless では撮れないので通常モードで走らせること。
var shots_dir: String = ""
var shot_interval: float = 20.0

var _shot_t: float = 0.0
var _shot_n: int = 0
var _shooting: bool = false
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
	# 線香・ロウソクの減りは systems 側が delta * Clock.speed で進めるので、
	# ここで burn_seconds を speed で割ると二重に効いて一瞬で尽きる。何もしない。
	var a: Dictionary = dir.args
	shots_dir = String(a.get("shots", ""))
	shot_interval = float(a.get("shot-interval", "20"))
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
		_shot_t = 2.0
		print("AUTOPLAY SHOTS dir=%s interval=%.1fs" % [shots_dir, shot_interval])
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
	if shots_dir != "":
		_shot_t -= delta
		if _shot_t <= 0.0 and not _shooting:
			_shot_t = shot_interval
			_take_shot()
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
	var ph: Node = dir.sys(&"phone")
	if ph and bool(ph.get(&"is_ringing")) and mode != &"kasha":
		if await _use(ph, 1.0):
			return
	# 4. 線香(kasha モードは導入の1本だけで、以降は放置する)
	if mode != &"kasha" or not Game.get_flag(&"intro_done", false):
		if await _keep_incense():
			return
	# 5. 猫(kasha モードは棺をまたがせたいので追い払わない)
	if mode != &"kasha" and await _shoo_cat():
		return
	# 6. いまのタスク(モードによっては線香を無視する)
	var id := _pick_task()
	if id != &"":
		if await _do_task(id):
			return
	# 7. ロウソク(終盤以外)
	if not dir.timeline.finale_running() and mode != &"kasha":
		var cnd: Node = dir.sys(&"candle")
		if cnd and not bool(cnd.get(&"is_lit")) and not bool(cnd.get(&"require_matches")):
			await _use(cnd, 1.0)


func _keep_incense() -> bool:
	var inc: Node = dir.sys(&"incense_stand")
	if inc == null:
		return false
	var burning := bool(inc.get(&"is_burning"))
	var ratio := float(inc.get(&"remaining_ratio"))
	if burning and ratio >= 0.35:
		return false
	if int(Game.get_flag(&"incense_sticks", 0)) <= 0:
		var box: Node = dir.stock_box()
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
		# すでに追い出し中の猫に flee() をかけ直すと退出がリセットされ続ける(review N5)
		if c.has_method(&"state_name") and String(c.call(&"state_name")) == "SHOOED":
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


## 優先順にタスクを選ぶ。Tasks.current() は先頭固定なので、
## kasha モードで線香を放置すると以後のタスクに進めなくなる。
const TASK_ORDER := [
	&"talk_boss", &"relight", &"cat", &"breaker", &"backdoor", &"window",
	&"dry_ice", &"flowers", &"candle", &"lid", &"incense_stock", &"incense", &"last_incense",
]
## kasha モード(導入後)が触らないタスク。
## 線香を放置して異変度を溜め、勝手口と式場の窓を開けたままにして猫を入れる
## (`cat_entered` → `cat_crossed_coffin` の経路を QA で通すため)。
const KASHA_IGNORE := [
	&"incense", &"incense_stock", &"last_incense",
	&"backdoor", &"window", &"cat",
]

## 代わりエンドの回では勝手口を開けたままにして、猫を入れてから追い払う。
## こうしないと cat_entered → cat_shooed の経路が QA で一度も通らない。
const SUBSTITUTE_IGNORE := [&"backdoor"]

func _pick_task() -> StringName:
	var after_intro: bool = bool(Game.get_flag(&"intro_done", false))
	for id in TASK_ORDER:
		if not Tasks.has(id):
			continue
		if after_intro and mode == &"kasha" and KASHA_IGNORE.has(id):
			continue
		if after_intro and mode == &"substitute" and SUBSTITUTE_IGNORE.has(id):
			continue
		return id
	return &""


func _do_task(id: StringName) -> bool:
	match id:
		&"incense", &"last_incense":
			return await _use(dir.sys(&"incense_stand"), 1.1)
		&"incense_stock":
			return await _use(dir.stock_box(), 1.0)
		&"backdoor":
			var d := _door(&"Door_Backyard")
			if d == null:
				return false
			if d.is_open:
				return await _use(d, 1.3)
			# level が「鍵をかける」(長押し)を別の Interactable で出す場合はそれを使う
			var lock := _lock_spot(d)
			if lock:
				return await _use(lock, 1.3)
			if not d.locked:
				d.set_locked(true)
				Tasks.complete(&"backdoor")
				return true
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
		&"lid":
			var sp := _find_spot_named(ScriptText.TASK_LID)
			if sp:
				return await _use(sp, 1.2)
			return false
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


## 勝手口まわりの「鍵をかける」用 Interactable を探す(level が足すまでは null)。
func _lock_spot(d: Node3D) -> Node:
	var b: Building = dir.building()
	if b == null:
		return null
	for n in b.find_children("*", "Interactable", true, false):
		var i := n as Interactable
		if i == null or not i.enabled or i == d:
			continue
		if i.global_position.distance_to(d.global_position) > 2.0:
			continue
		if String(i.get_prompt()).find("鍵") >= 0:
			return i
	return null


func _find_spot() -> Node:
	return _find_spot_named(ScriptText.CHOICE_HIKAESHITSU_SPOT)


func _find_spot_named(prompt: String) -> Node:
	var b: Building = dir.building()
	if b == null:
		return null
	for c in b.get_children():
		if c is Scares.Spot and (c as Interactable).enabled \
				and String((c as Interactable).prompt) == prompt:
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
	await Events.wait(0.35 / maxf(speed, 0.1))
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

## 直近に発火したイベントの見どころ。[目線の位置, yaw, pitch]
const EVENT_VIEWS := {
	"intro": [Vector3(-9.5, 1.6, 0.0), -90.0, 0.0],
	"intro_done": [Vector3(-8.6, 1.6, -1.2), 90.0, 0.0],
	"ev_flowers": [Vector3(17.6, 1.6, -2.4), -55.0, -10.0],
	"ev_window": [Vector3(13.0, 1.6, 1.2), 180.0, 0.0],
	"ev_phone_silent": [Vector3(-9.85, 1.45, 7.3), 0.0, -16.0],
	"ev_monitor_figure": [Vector3(-6.4, 1.3, 8.05), 0.0, -11.0],
	"ev_cats_begin": [Vector3(0.0, 1.6, -5.2), 0.0, -4.0],
	"ev_tv": [Vector3(-2.4, 1.6, 3.0), -49.0, -12.0],
	"ev_blackout": [Vector3(2.0, 1.6, 0.0), -90.0, 0.0],
	"ev_son": [Vector3(-8.8, 1.6, -0.4), 90.0, 0.0],
	"ev_dry_ice": [Vector3(3.6, 1.6, -4.9), 0.0, -16.0],
	"ev_office_note": [Vector3(-8.85, 1.5, 7.4), 0.0, -24.0],
	"ev_son_sleeps": [Vector3(-2.6, 1.6, 2.3), -20.0, -18.0],
	"ev_yukan": [Vector3(7.3, 1.6, -8.6), -35.0, -6.0],
	"ev_phone_wet": [Vector3(-9.85, 1.45, 7.3), 0.0, -16.0],
	"ev_ushimitsu": [Vector3(13.0, 1.6, -0.5), -90.0, -6.0],
	"ev_safe": [Vector3(-9.6, 1.5, 9.0), 117.0, -14.0],
	"ev_freezer_empty": [Vector3(4.0, 1.6, 0.4), -90.0, -32.0],
	"ev_finale": [Vector3(6.4, 1.6, -1.6), 0.0, -14.0],
	"kasha_takes_son": [Vector3(-2.6, 1.6, 2.3), -20.0, -18.0],
}
const EYE_HEIGHT := 1.6


## 画面をそのまま連番で保存する。ファイル名は HHMM_<n>.png。
## ボットは焼香台に立ちっぱなしになりがちなので、撮る瞬間だけ
## 「直近に発火したイベントの見どころ」へ飛び、撮ってから元の位置に戻す。
func _take_shot() -> void:
	_shooting = true
	_shot_n += 1
	var name := "%s_%02d.png" % [Clock.hhmm().replace(":", ""), _shot_n]
	var p := player()
	var saved := _save_pose(p)
	_goto_view(p)
	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(shots_dir.path_join(name))
		_log.append("%s shot %s" % [Clock.hhmm(), name])
	_restore_pose(p, saved)
	_shooting = false


func _save_pose(p: Node3D) -> Array:
	if p == null:
		return []
	var pitch := 0.0
	var head: Variant = p.get(&"head")
	if head is Node3D:
		pitch = rad_to_deg((head as Node3D).rotation.x)
	return [p.global_position, rad_to_deg(p.rotation.y), pitch]


func _restore_pose(p: Node3D, saved: Array) -> void:
	if p == null or saved.is_empty() or not p.has_method(&"teleport"):
		return
	p.call(&"teleport", saved[0], saved[1], saved[2])


func _goto_view(p: Node3D) -> void:
	if p == null or not p.has_method(&"teleport"):
		return
	var log_lines: Array = dir.event_log()
	if log_lines.is_empty():
		return
	# "HH:MM name" の name 部分
	var last := String(log_lines[-1]).split(" ", true, 1)
	if last.size() < 2:
		return
	var key := last[1]
	if not EVENT_VIEWS.has(key):
		return
	var v: Array = EVENT_VIEWS[key]
	var pos: Vector3 = v[0]
	p.call(&"teleport", pos - Vector3(0, EYE_HEIGHT, 0), float(v[1]), float(v[2]))


func _on_ended(id: StringName) -> void:
	if _done:
		return
	_done = true
	print("AUTOPLAY RESULT ending=%s dread=%d minutes=%d" % [id, Dread.value, int(Clock.game_minutes)])
	if shots_dir != "":
		await _take_shot()
	_write_log(id)
	var want: StringName = EXPECTED.get(mode, mode)
	await Events.wait(0.4)
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
