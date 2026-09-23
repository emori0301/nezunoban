class_name Director
extends Node
## 夜の監督。main.gd が Main 直下に置く。
##
##   _ready  … 子(Scares / Timeline / Endings / Autoplay)を作り、引数を読む
##   _boot   … main の --time スキップが終わった次のフレームに走る本体
##             apply_state_for_time → timeline.register → イベント購読 → 導入 → Clock.start()
##
## 所有範囲は src/director/ だけ。他の担当のノードは公開 API 越しにしか触らない。
## NPC(src/npc)はまだ無いかもしれないので、すべて has_method で守ってある。

const NOTE_SCENE := "res://src/systems/note.tscn"
const INCENSE_BOX_SCENE := "res://src/systems/incense_box.tscn"

## 位置(src/level の --api 出力から取った実測値)
const POS_RECEPTION := Vector3(-8.0, 0.0, -3.7)
const POS_OFFICE_DESK := Vector3(-7.0, 0.0, 5.2)
const POS_SHIKIJO_COFFIN := Vector3(15.2, 0.0, -1.9)
const POS_SHIKIJO_BACK := Vector3(10.35, 0.0, 1.1)
const POS_GENKAN_INSIDE := Vector3(-9.6, 0.0, 0.0)
const POS_HALL_JUNCTION := Vector3(3.0, 0.0, 0.0)
const POS_HIKAESHITSU_ZABUTON := Vector3(-1.35, 0.0, 3.8)
const POS_OFFICE_NOTE := Vector3(-8.85, 0.76, 6.15)
const POS_YUKAN_NOTE := Vector3(7.3, 0.87, -9.55)
const POS_BACKYARD_BOX := Vector3(2.4, 0.95, -6.95)

## 会話するときに NPC が止まるプレイヤーからの距離(m)
const TALK_DISTANCE := 1.8

var scares: Scares
var timeline: Timeline
var endings: Endings
var autoplay: Node = null

var args: Dictionary = {}
var start_minutes: int = 0
var intro_running: bool = false
var cats_enabled: bool = false

## timeline から立てられる「次に式場/控室に入ったときにやること」
var pending_shikijo_reveal: bool = false
var pending_blackout_reveal: bool = false
var pending_tv_scare: bool = false
var pending_call: StringName = &""

var _npc_installer: Node = null
var _office_note: Note = null
var _yukan_note: Note = null
var _stock_box: Node = null
var _scare_timer: float = 0.0
var _fallback_chase: bool = false
var _fallback_t: float = 0.0
var _event_log: Array[String] = []
var _last_event_minute: int = -99
var _drone: StringName = &""
var _applying_past: bool = false


# ============================================================ 起動

func _ready() -> void:
	args = _parse_args()
	scares = Scares.new()
	scares.name = "Scares"
	scares.dir = self
	add_child(scares)
	timeline = Timeline.new()
	timeline.name = "Timeline"
	timeline.dir = self
	timeline.scares = scares
	add_child(timeline)
	endings = Endings.new()
	endings.name = "Endings"
	endings.dir = self
	add_child(endings)
	if args.has("autoplay"):
		var bot := Autoplay.new()
		bot.name = "Autoplay"
		bot.dir = self
		bot.mode = StringName(String(args["autoplay"]))
		bot.speed = float(args.get("speed", "6"))
		add_child(bot)
		autoplay = bot
	Game.night_ended.connect(_on_night_ended)
	call_deferred(&"_boot")


func _boot() -> void:
	start_minutes = int(Clock.game_minutes)
	_npc_installer = _find_npc_installer()
	_connect_events()
	# QA 用: --dread=4 で異変度を先に積む(座布団や遺影の追従を撮るため)
	if args.has("dread"):
		Dread.add(int(String(args["dread"])), &"debug")
	apply_state_for_time(start_minutes)
	# QA 用: --reload-test で数秒ごとにシーンを再読み込みし続ける。
	# Game.reset() のシグナル一括 disconnect と director の _exit_tree が
	# 二重に外しても落ちないことを確かめるため。
	if args.has("reload-test"):
		_reload_loop(float(args.get("reload-test", "5")))
	# QA 用: --credits でクレジットだけ流す
	if args.has("credits"):
		_show_credits_only()
		return
	# QA 用: --scare=<関数名> で脅かしを1つだけ発火させる(チェックリストの撮影用)
	if args.has("scare"):
		_fire_scare(String(args["scare"]))
	# QA 用: --cctv-shot=out/x.png で監視モニターの映像そのものを保存する
	# (モニターの画面は小さくて、ゲーム画面のスクショでは人影が判別できないため)
	if args.has("cctv-shot"):
		_grab_cctv(String(args["cctv-shot"]), float(args.get("wait", "5")))
	# QA 用: --ending=morning|kasha|substitute|portrait でエンディング画面だけ出す
	if args.has("ending"):
		var id := StringName(String(args["ending"]))
		Game.set_flag(&"skip_prologue", true)
		call_deferred(&"finish", id)
		return
	timeline.register(start_minutes)
	set_process(true)
	if autoplay and autoplay.has_method(&"begin"):
		autoplay.call(&"begin")
	# --screenshot / --tour / --time は撮影と QA のためのフックなので導入演出を飛ばす。
	# (導入はフェードインと会話で数分かかるので、撮ると真っ黒や会話中の画になる)
	# --intro を付けると撮影時でも導入を流す(QA 用)
	var skip_intro: bool = (args.has("screenshot") or args.has("tour") or args.has("time") \
		or start_minutes > 0) and not args.has("intro")
	if skip_intro:
		var h := hud()
		if h and h.has_method(&"set_fade"):
			h.set_fade(0.0)
		var p := Game.player
		if p and p.has_method(&"set_locked"):
			p.set_locked(false)
		scares.set_room_ambience(building().current_room if building() else &"Room_Genkan")
		_arm_incense_dread()
		Clock.start()
	else:
		await play_intro()
		Clock.start()


func _show_credits_only() -> void:
	var h := hud()
	if h and h.has_method(&"set_fade"):
		h.set_fade(0.0)
	var c := Credits.new()
	c.name = "Credits"
	ui_parent().add_child(c)
	await c.play()
	c.queue_free()


func _reload_loop(sec: float) -> void:
	await Events.wait(maxf(sec, 1.0))
	if is_inside_tree():
		print("[dir] reload-test: reload_current_scene")
		get_tree().reload_current_scene()


## 引数が要る脅かしの呼び出し方(QA 専用)
const SCARE_ARGS := {
	"hall_figure": ["kasha", 30.0],
	"set_second_footsteps": [true],
	"set_moonlight": [true],
	"spawn_figure_cctv": null,     # 下で特別扱い
}

## 脅かしを1つだけ撃つ。--screenshot / --cctv-shot と組み合わせて使う。
func _fire_scare(n: String) -> void:
	await Events.wait(0.7)
	match n:
		"body_rises":                 # QA: 火車エンド直前の起き上がり
			_body_rises()
			return
		"coffin_peek":                # QA: 小窓を覗いた画(手形と顔)
			var cp := sys(&"coffin")
			if cp:
				cp.call(&"set_handprint", true)
				cp.set(&"allow_open_window", true)
				cp.call(&"show_face", 30.0, "qa")
			return
		"genkan_figure_visible":      # QA: CCTV 限定を外して実体を確認する
			scares.spawn_figure("npc_son", Vector3(-12.3, 0.0, -0.2), 18.0, false, &"idle", 0.42)
			return
		"monitor_figure":
			timeline.ev_monitor_figure()
			return
		"tv_face":
			timeline.ev_tv()
			timeline.on_tv_approach()
			return
		"coffin_face3":
			var c := sys(&"coffin")
			if c:
				c.call(&"set_face_state", 3)
			return
		"lid_ajar":
			var c2 := sys(&"coffin")
			if c2:
				c2.call(&"set_lid_ajar", true)
			return
		"iei_face_down":
			var i := sys(&"iei")
			if i:
				i.call(&"set_face_down", true)
			return
	if not scares.has_method(n):
		printerr("scare が無い: %s" % n)
		return
	if SCARE_ARGS.has(n):
		scares.callv(n, SCARE_ARGS[n])
	else:
		scares.call(n)


## 監視モニターの SubViewport をそのまま PNG に落とす(QA 専用)
func _grab_cctv(path: String, wait: float) -> void:
	await Events.wait(maxf(wait, 0.5))
	var mon := sys(&"monitor")
	if mon == null or not mon.has_method(&"get_viewport_node"):
		printerr("CCTV: モニターが見つからない")
		get_tree().quit(1)
		return
	# --cctv-feed=0(式場) / 1(玄関) で撮る前にチャンネルを切り替える
	if args.has("cctv-feed"):
		mon.set(&"auto_switch", false)
		mon.call(&"switch_feed", int(String(args["cctv-feed"])))
		await Events.wait(0.6)
	var vp: SubViewport = mon.call(&"get_viewport_node")
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("CCTV saved: %s (feed=%d)" % [path, int(mon.get(&"feed_index"))])
	get_tree().quit()


## Game.reset() が autoload のシグナルをまとめて外すので普段は不要だが、
## 二重に外しても落ちないよう is_connected で守ってから外す。
func _exit_tree() -> void:
	for pair in [
			[Game.night_ended, Callable(self, "_on_night_ended")],
			[Game.flag_changed, Callable(self, "_on_flag_changed")],
			[Dread.level_changed, Callable(self, "_on_dread_level")],
			[Clock.hour_passed, Callable(self, "_on_hour")],
		]:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func log_event(name: String) -> void:
	_last_event_minute = int(Clock.game_minutes)
	var line := "%s %s" % [Clock.hhmm(), name]
	_event_log.append(line)
	if Game.debug or autoplay != null:
		print("[dir] %s" % line)


func event_log() -> Array[String]:
	return _event_log


# ============================================================ 取り出し

func sys(n: StringName) -> Node:
	return SystemsInstaller.find(n)


func building() -> Building:
	return Game.level as Building


func hud() -> Node:
	var list := get_tree().get_nodes_in_group(&"hud")
	return list[0] if not list.is_empty() else null


## エンディング画面を入れる先(HUD と同じ SubViewport = VHS の下)
func ui_parent() -> Node:
	var h := hud()
	if h:
		return h.get_viewport()
	return get_tree().root


func _find_npc_installer() -> Node:
	for n in ["NpcInstaller", "NpcsInstaller", "Installer"]:
		var f := get_tree().root.find_child(n, true, false)
		if f and f.has_method(&"find") and not (f is SystemsInstaller):
			return f
	return null


## NpcInstaller.find(&"boss") 相当。無ければ group "npc" を npc_id で引く。
func npc(id: StringName, index: int = 0) -> Node:
	if _npc_installer and _npc_installer.has_method(&"find"):
		var n: Variant = _npc_installer.call(&"find", id, index)
		if n != null and is_instance_valid(n):
			return n
	var list := npc_all(id)
	return list[index] if index >= 0 and index < list.size() else null


func npc_all(id: StringName) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(&"npc"):
		var v: Variant = n.get(&"npc_id")
		if typeof(v) == TYPE_STRING_NAME or typeof(v) == TYPE_STRING:
			if StringName(v) == id:
				out.append(n)
	return out


## 独白。--time= で過去のイベントの結果だけを適用しているあいだは出さない
## (04:58 に「灯りが全部落ちた。」が出る、のような取り残しを防ぐ)。
## 台本の結果だけを組み立てるあいだ、独白を黙らせる。
func set_quiet(on: bool) -> void:
	_applying_past = on


func monologue(text: String) -> void:
	if _applying_past or Game.state == Game.State.ENDING:
		return
	await Dialogue.monologue(text)


func matches_pickup() -> Node:
	return sys(&"matches")


## 台本で火を消す。プレイヤーの失敗ではないので異変度は上げない。
## (掟「線香を絶やさぬこと」を破った判定は _on_hour の放置チェックで行う)
func quench(name: StringName) -> void:
	var n := sys(name)
	if n == null:
		return
	var prev: int = int(n.get(&"dread_on_out"))
	n.set(&"dread_on_out", 0)
	n.call(&"force_out")
	n.set(&"dread_on_out", prev)


# ============================================================ 下ごしらえ

func _setup_static() -> void:
	var h := hud()
	if h and h.has_method(&"set_rules"):
		h.set_rules(ScriptText.rules())
	Game.set_flag(&"incense_sticks", 10)
	var inc := sys(&"incense_stand")
	if inc:
		inc.set(&"no_stock_line", ScriptText.M_INCENSE_NONE)
		# 導入(チュートリアル)のあいだは Clock が止まっているのに線香は実時間で燃える。
		# ここで消えたぶんを数えると、会話が長引くほど異変度が上がってしまう。
		inc.set(&"dread_on_out", 0)
	var gb := sys(&"guest_book")
	if gb:
		gb.call(&"set_lines", ScriptText.GUEST_BOOK)
	# 祭壇の線香箱は「今使っている箱」。在庫は裏の棚にある。
	var box := sys(&"incense_box")
	if box:
		box.set(&"enabled", false)
	var m := matches_pickup()
	if m:
		m.set(&"enabled", false)
		m.set(&"visible", false)
	var sf := sys(&"safe")
	if sf:
		sf.call(&"set_note", ScriptText.PAGE4_TITLE, ScriptText.PAGE4_BODY, 4)
	var desk := sys(&"boss_desk")
	if desk:
		desk.call(&"enable_key", false)
	_office_note = _make_note(POS_OFFICE_NOTE, ScriptText.PAGE2_TITLE, ScriptText.PAGE2_BODY, 2)
	_yukan_note = _make_note(POS_YUKAN_NOTE, ScriptText.PAGE3_TITLE, ScriptText.PAGE3_BODY, 3)
	enable_office_note(false)
	enable_yukan_note(false)
	# VHS の基準値
	var v := scares.vhs()
	if v and v.has_method(&"set_intensity"):
		v.set_intensity(0.32)


func _make_note(pos: Vector3, title: String, body: String, page: int) -> Note:
	if not ResourceLoader.exists(NOTE_SCENE):
		return null
	var n: Note = (load(NOTE_SCENE) as PackedScene).instantiate()
	n.set_text(title, body, page)
	var root := building()
	if root == null:
		return null
	root.add_child(n)
	n.global_position = pos
	return n


func enable_office_note(on: bool) -> void:
	if _office_note and is_instance_valid(_office_note):
		_office_note.enabled = on
		_office_note.visible = on


func enable_yukan_note(on: bool) -> void:
	if _yukan_note and is_instance_valid(_yukan_note):
		_yukan_note.enabled = on
		_yukan_note.visible = on


## 線香が切れたときに裏の在庫棚に出す箱
func enable_stock_box() -> void:
	if _stock_box and is_instance_valid(_stock_box):
		return
	if not ResourceLoader.exists(INCENSE_BOX_SCENE):
		return
	var root := building()
	if root == null:
		return
	_stock_box = (load(INCENSE_BOX_SCENE) as PackedScene).instantiate()
	root.add_child(_stock_box)
	(_stock_box as Node3D).global_position = POS_BACKYARD_BOX


func stock_box() -> Node:
	return _stock_box


func spawn_son_asleep(with_sound: bool = true) -> void:
	if Game.get_flag(&"son_asleep", false):
		return
	Game.set_flag(&"son_asleep", true)
	var son := npc(&"son")
	if son:
		if son.has_method(&"teleport_to"):
			son.call(&"set_active", true)
			son.call(&"teleport_to", POS_HIKAESHITSU_ZABUTON)
		if son.has_method(&"sleep"):
			son.call(&"sleep")
	else:
		scares.spawn_figure("npc_son", POS_HIKAESHITSU_ZABUTON, 180.0, false, &"idle")
	if with_sound:
		Audio.play_at(&"tatami_creak", POS_HIKAESHITSU_ZABUTON + Vector3(0, 0.2, 0), -10.0)


# ============================================================ 時刻スキップ対応

## その時刻より前のイベントの「結果」だけを適用する。--time= と QA に必須。
func apply_state_for_time(m: int) -> void:
	_applying_past = true
	_apply_state_body(m)
	_applying_past = false


func _apply_state_body(m: int) -> void:
	_setup_static()
	var b := building()
	var inc := sys(&"incense_stand")
	var cnd := sys(&"candle")
	var back: Door = b.get_door(&"Door_Backyard") if b else null
	if m <= 0:
		# 導入の前。勝手口は開いていて、式場の蛍光灯はまだ点いている。
		if back:
			back.set_locked(false)
			back.open(true)
		return
	# --- 導入の結果 ---
	Game.set_flag(&"has_clipboard", true)
	Game.set_flag(&"intro_done", true)
	if inc:
		inc.call(&"light")
	if cnd:
		cnd.call(&"light")
	if b:
		b.set_room_lights(&"Room_Shikijo", false)
	if back:
		back.close()
		back.set_locked(true)
	for id in [&"boss", &"granddaughter"]:
		var n := npc(id)
		if n and n.has_method(&"despawn"):
			n.call(&"despawn", false)
	Game.add_flag(&"pages")          # 収集① は導入で読む
	# --- 以降のイベントの結果 ---
	timeline.apply_past(m)
	if m >= 180:
		guest_book_after_midnight()
	refresh_dread_ambient()
	if m >= 420:
		# 終盤の直前から始めたときは、ev_finale が即時発火する(register が >= で積む)
		pass


func guest_book_after_midnight() -> void:
	scares.guest_book_self_name()


# ============================================================ イベント購読

func _connect_events() -> void:
	Events.on(&"incense_out", func(_d): _on_incense_out())
	Events.on(&"incense_lit", func(_d): _on_incense_lit())
	Events.on(&"candle_out", func(_d): _on_candle_out())
	Events.on(&"candle_lit", func(_d): Tasks.complete(&"candle"))
	Events.on(&"window_closed", func(d): _on_window_closed(d))
	Events.on(&"door_closed", func(d): _on_door_closed(d))
	Events.on(&"phone_answered", func(_d): _on_phone_answered())
	Events.on(&"phone_missed", func(_d): pending_call = &"")
	Events.on(&"player_entered_room", func(d): _on_room(StringName(d.get("room", ""))))
	Events.on(&"breaker_on", func(_d): timeline.on_breaker_restored())
	Events.on(&"flowers_watered", func(_d): Tasks.complete(&"flowers"))
	Events.on(&"dry_ice_replaced", func(_d): timeline.on_dry_ice_replaced())
	Events.on(&"page_read", func(d): _on_page_read(int(d.get("n", 0))))
	Events.on(&"cat_entered", func(_d): _on_cat_entered())
	Events.on(&"cat_shooed", func(_d): Tasks.complete(&"cat"))
	Events.on(&"cat_crossed_coffin", func(_d): _on_cat_crossed())
	Events.on(&"futon_rest", func(_d): finish(Game.ENDING_PORTRAIT))
	Events.on(&"relight_success", func(d): timeline.on_relight(int(d.get("n", 1))))
	Game.flag_changed.connect(_on_flag_changed)
	Dread.level_changed.connect(_on_dread_level)
	Clock.hour_passed.connect(_on_hour)
	var cnd := sys(&"candle")
	if cnd and cnd.has_signal(&"relight_failed"):
		cnd.connect(&"relight_failed", Callable(timeline, "on_relight_failed"))
	var fz := sys(&"freezer")
	if fz and fz.has_signal(&"found_empty"):
		fz.connect(&"found_empty", func():
			monologue(ScriptText.M_FREEZER_EMPTY)
			Tasks.complete(&"dry_ice"))
	var gb := sys(&"guest_book")
	if gb and gb.has_signal(&"viewed"):
		gb.connect(&"viewed", func(): _on_guest_book_viewed())
	var p := Game.player
	if p and p.has_signal(&"carried_changed"):
		p.connect(&"carried_changed", func(item: StringName): _on_carried(item))
	var k := npc(&"kasha")
	if k and k.has_signal(&"caught"):
		k.connect(&"caught", Callable(self, "kasha_catches"))


# ---------------------------------------------------------- 線香とロウソク

func _on_incense_out() -> void:
	if Game.state == Game.State.ENDING:
		return
	monologue(ScriptText.M_INCENSE_OUT)
	# 終盤は「マッチを取って灯明を灯す」が唯一の用事。線香のタスクを出すと
	# HUD の先頭がそれに取られて、やるべきことが分からなくなる(review N1)。
	if timeline.finale_running():
		return
	Tasks.set_task(&"incense", ScriptText.TASK_INCENSE)


func _on_incense_lit() -> void:
	Tasks.complete(&"incense")
	Tasks.complete(&"last_incense")


func _on_candle_out() -> void:
	if timeline.finale_running() or Game.state == Game.State.ENDING:
		return
	Tasks.set_task(&"candle", ScriptText.TASK_CANDLE)


func _on_flag_changed(key: StringName, value: Variant) -> void:
	if key != &"incense_sticks":
		return
	if int(value) <= 0 and not Game.get_flag(&"stock_box_out", false):
		Game.set_flag(&"stock_box_out", true)
		enable_stock_box()
		Tasks.set_task(&"incense_stock", ScriptText.TASK_INCENSE_STOCK)
		monologue(ScriptText.M_INCENSE_NONE)
	elif int(value) > 0 and Game.get_flag(&"stock_box_out", false):
		Game.set_flag(&"stock_box_out", false)
		Tasks.complete(&"incense_stock")


## 1 ゲーム時間ごとに、線香が絶えていれば異変度 +1(掟「線香を絶やさぬこと」)
func _on_hour(_hour: int) -> void:
	if Game.state == Game.State.ENDING or timeline.finale_running():
		return
	if int(Clock.game_minutes) < 60:
		return
	var inc := sys(&"incense_stand")
	if inc and not bool(inc.get(&"is_burning")):
		Dread.add(1, &"incense_neglect")


# ---------------------------------------------------------- 扉・窓・電話

func _on_window_closed(d: Dictionary) -> void:
	if StringName(d.get("window", "")) == &"Window_Shikijo":
		timeline.on_shikijo_window_closed()


func _on_door_closed(d: Dictionary) -> void:
	if StringName(d.get("door", "")) != &"Door_Backyard":
		return
	if not Tasks.has(&"backdoor"):
		return
	var b := building()
	var door: Door = b.get_door(&"Door_Backyard") if b else null
	if door:
		door.set_locked(true)
	Tasks.complete(&"backdoor")
	Audio.play_at(&"door_locked", door.global_position if door else Vector3.ZERO, -4.0)


func _on_phone_answered() -> void:
	var which := pending_call
	pending_call = &""
	match which:
		&"silent": timeline.play_silent_call()
		&"wet": timeline.play_wet_call()
		_:
			var ph := sys(&"phone")
			if ph:
				await Events.wait(2.0)
				ph.call(&"hang_up")


# ---------------------------------------------------------- 部屋

func _on_room(room: StringName) -> void:
	scares.set_room_ambience(room)
	match room:
		&"Room_Shikijo":
			if pending_shikijo_reveal:
				pending_shikijo_reveal = false
				timeline.on_shikijo_reveal()
			elif pending_blackout_reveal:
				pending_blackout_reveal = false
				timeline.on_blackout_reveal()
		&"Room_Hikaeshitsu":
			if pending_tv_scare:
				pending_tv_scare = false
				timeline.on_tv_approach()
		&"Room_Yukan":
			timeline.on_yukan_entered()


# ---------------------------------------------------------- 収集物・猫

func _on_page_read(n: int) -> void:
	match n:
		2: timeline.on_office_note_read()
		4: timeline.on_ledger_read()


func _on_guest_book_viewed() -> void:
	if int(Clock.game_minutes) >= 180:
		scares.guest_book_self_name()
		monologue(ScriptText.M_GUEST_BOOK)


func _on_cat_entered() -> void:
	monologue(ScriptText.M_CAT)
	Tasks.set_task(&"cat", ScriptText.TASK_CAT)


func _on_cat_crossed() -> void:
	var coffin := sys(&"coffin")
	if coffin:
		coffin.call(&"creak")
		coffin.call(&"set_face_state", 3)
	scares.glitch(1.0)
	scares.stinger(0.0)
	Audio.play(&"heartbeat", -6.0)


func _on_carried(item: StringName) -> void:
	if item == &"dry_ice":
		timeline.on_dry_ice_carried()
	elif item == &"":
		scares.set_second_footsteps(false)


# ---------------------------------------------------------- 異変度

func _on_dread_level(_level: int) -> void:
	refresh_dread_ambient()


func refresh_dread_ambient() -> void:
	var lvl := Dread.level()
	var want: StringName = &""
	if lvl == 1:
		want = &"amb_drone_low"
	elif lvl >= 2:
		want = &"amb_drone_high"
	if want != _drone:
		if _drone != &"":
			Audio.stop_ambient(_drone, 2.0)
		_drone = want
		if want != &"":
			Audio.ambient(want, -14.0, 3.0)
	var v := scares.vhs()
	if v and v.has_method(&"set_intensity"):
		v.set_intensity(0.32 + 0.15 * lvl)
	var iei := sys(&"iei")
	if iei:
		iei.call(&"set_follow_player", lvl >= 1)


# ============================================================ 毎フレーム

func _process(delta: float) -> void:
	if Game.state != Game.State.PLAYING or intro_running:
		return
	# 追加の脅かし。前半は静か、後半ほど密度が上がる(_scare_interval を見よ)
	_scare_timer -= delta * maxf(Clock.speed, 1.0)
	if _scare_timer <= 0.0:
		var iv := _scare_interval()
		if iv < 0.0:
			_scare_timer = 30.0        # まだ出さない時間帯。30 秒後にまた見る
		elif not _can_scare():
			_scare_timer = 20.0        # 台本イベントの近く。少し待ってから出す
		else:
			_scare_timer = iv
			scares.random_scare(int(Clock.game_minutes) < 180)
	# 火車が居ないときの追跡の代役(音と画面だけ)
	if _fallback_chase:
		_fallback_t -= delta
		if _fallback_t <= 0.0:
			_fallback_t = scares.rng.randf_range(2.2, 4.5)
			var p := scares.player_pos()
			var back := p - scares.forward() * scares.rng.randf_range(3.0, 7.0) + Vector3(0, 2.3, 0)
			Audio.play_at(StringName("kasha_crawl" if scares.rng.randf() < 0.6 else "kasha_growl"),
				back, -2.0, 1.0, 22.0)
			scares.glitch(0.35)
			Audio.play(&"heartbeat", -14.0)


## 台本イベントの前後これだけ(ゲーム内分)は脅かしを出さない。実時間で約 20 秒。
const SCARE_GAP_MINUTES := 7

## 次のランダム脅かしまでの秒数(速度 1 の実秒)。-1 なら「まだ出さない」。
##   〜22:30   出さない(前半は本当に静かにする)
##   〜00:00   4〜6 分に 1 回(音だけの系統が中心)
##   〜03:00   2〜4 分に 1 回
##   03:00〜   1〜2 分に 1 回
## 異変度が上がるほど間隔を詰める(level 1 で -20%、level 2 で -40%)。
func _scare_interval() -> float:
	var m := int(Clock.game_minutes)
	if m < 90:
		return -1.0
	var lo := 240.0
	var hi := 360.0
	if m >= 360:
		lo = 60.0
		hi = 120.0
	elif m >= 180:
		lo = 120.0
		hi = 240.0
	return scares.rng.randf_range(lo, hi) * (1.0 - 0.2 * float(Dread.level()))


func _can_scare() -> bool:
	if timeline.finale_running() or Game.state != Game.State.PLAYING:
		return false
	var m := int(Clock.game_minutes)
	if m - _last_event_minute < SCARE_GAP_MINUTES:
		return false
	if timeline.next_event_minute(m) - m < SCARE_GAP_MINUTES:
		return false
	return true


# ============================================================ 火車(NPC が無いときの代役)

func start_fallback_chase() -> void:
	_fallback_chase = true
	_fallback_t = 1.0
	Audio.play(&"kasha_screech", -2.0)


func set_fallback_chase(on: bool) -> void:
	if not _fallback_chase and on and npc(&"kasha") == null:
		_fallback_chase = true
	elif not on:
		_fallback_chase = false
	if on:
		_fallback_t = 1.0


const BODY_RISEN_SCENE := "res://src/npc/body_risen.tscn"

## 火車エンド直前のカット。棺の蓋が開き、故人が起き上がる(2 秒)。
## body_risen は棺と同じ yaw だと祭壇を向くので、部屋側(-90)に向ける。
func _body_rises() -> void:
	var coffin := sys(&"coffin")
	if coffin == null or not ResourceLoader.exists(BODY_RISEN_SCENE):
		return
	var c3 := coffin as Node3D
	coffin.call(&"set_open", true)
	var br: Node3D = (load(BODY_RISEN_SCENE) as PackedScene).instantiate()
	var root := building()
	if root == null:
		return
	root.add_child(br)
	br.global_position = c3.global_position
	br.rotation.y = deg_to_rad(90.0)
	scares.glitch(0.8)
	var p := Game.player
	if p and p.has_method(&"look_at_point"):
		p.look_at_point(c3.global_position + Vector3(0, 0.9, 0), 0.6)
	if br.has_method(&"rise"):
		br.call(&"rise")
	await Events.wait(2.0)


## 火車に追いつかれた
func kasha_catches() -> void:
	if Game.state == Game.State.ENDING:
		return
	Game.set_flag(&"caught_by_kasha", true)
	_fallback_chase = false
	var p := Game.player
	if p and p.has_method(&"set_locked"):
		p.set_locked(true)
	await _body_rises()
	Audio.play(&"kasha_screech", 2.0)
	Audio.set_muffled(true)
	scares.glitch(1.0)
	ScreenFX.shake(1.0, 1.2)
	var h := hud()
	if h and h.has_method(&"flash"):
		h.flash(Color(0.6, 0.0, 0.0), 0.5)
	await Events.wait(1.6)
	Audio.set_muffled(false)
	finish(Game.ENDING_KASHA)


## 控室の戸を開けた → 火車は息子を連れて行く
func kasha_takes_son() -> void:
	if Game.get_flag(&"kasha_took_son", false):
		return
	Game.set_flag(&"kasha_took_son", true)
	log_event("kasha_takes_son")
	var k := npc(&"kasha")
	var son := npc(&"son")
	if k and son and k.has_method(&"go_to_and_take"):
		k.call(&"go_to_and_take", son)
		if k.has_signal(&"took_target"):
			await _wait_signal_or_timeout(k, &"took_target", 12.0)
	else:
		await Events.wait(1.2)
	Audio.play(&"kasha_screech", 0.0)
	scares.glitch(1.0)
	Audio.play_at(&"tatami_creak", POS_HIKAESHITSU_ZABUTON, 4.0)
	await Events.wait(1.4)
	Audio.play(&"kasha_growl", -2.0)
	_fallback_chase = false
	timeline._finish_finale()
	await Events.wait(2.0)
	if int(Clock.game_minutes) < 475:
		Clock.skip_to(475)


func _wait_signal_or_timeout(obj: Object, sig: StringName, seconds: float) -> void:
	var done := [false]
	var cb := func(_a = null): done[0] = true
	obj.connect(sig, cb)
	var t := 0.0
	while not done[0] and t < seconds:
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()
	if obj.is_connected(sig, cb):
		obj.disconnect(sig, cb)


# ============================================================ 終わり

func finish(ending: StringName) -> void:
	if Game.state == Game.State.ENDING:
		return
	log_event("ending:" + String(ending))
	_fallback_chase = false
	Game.end_night(ending)


func _on_night_ended(id: StringName) -> void:
	endings.save_progress(id)
	endings.run(id)


# ============================================================ 21:00 導入

func play_intro() -> void:
	intro_running = true
	log_event("intro")
	var h := hud()
	var p := Game.player
	if h and h.has_method(&"set_fade"):
		h.set_fade(1.0)
	if p and p.has_method(&"set_locked"):
		p.set_locked(true)
	scares.set_room_ambience(&"Room_Genkan")
	await Events.wait(0.8)
	if h and h.has_method(&"fade_in"):
		await h.fade_in(2.6)
	if p and p.has_method(&"set_locked"):
		p.set_locked(false)

	var boss := npc(&"boss")
	var hikari := npc(&"granddaughter")

	# --- 受付 ---
	if boss:
		boss.call(&"set_active", true)
		if boss.has_method(&"set_talkable"):
			boss.call(&"set_talkable", true)
		if boss.has_method(&"face_player"):
			boss.call(&"face_player")
		Tasks.set_task(&"talk_boss", "社長に話しかける")
		await _wait_talk(boss)
		Tasks.complete(&"talk_boss")
		await face_off(boss)
	await _say_lines(ScriptText.SPEAKER_BOSS, ScriptText.BOSS_RECEPTION)

	# --- 事務所(クリップボード) ---
	await _walk(boss, POS_OFFICE_DESK)
	await face_off(boss)
	await _say_lines(ScriptText.SPEAKER_BOSS, ScriptText.BOSS_OFFICE)
	Game.set_flag(&"has_clipboard", true)
	Audio.play(&"paper_rustle", -4.0)
	if h and h.has_method(&"toggle_clipboard") and not Dialogue.auto_advance:
		h.toggle_clipboard()
		await Events.wait(3.4)
		if h.has_method(&"toggle_clipboard"):
			h.toggle_clipboard()

	# --- 式場(線香とロウソク) ---
	await _walk(boss, POS_SHIKIJO_COFFIN)
	await face_off(boss)
	await _say_lines(ScriptText.SPEAKER_BOSS, ScriptText.BOSS_INCENSE)
	Tasks.set_task(&"incense", ScriptText.TASK_INCENSE)
	await _wait_event(&"incense_lit", 600.0)
	Tasks.complete(&"incense")
	var cnd := sys(&"candle")
	if cnd:
		cnd.call(&"light")
	await _say_lines(ScriptText.SPEAKER_BOSS, ScriptText.BOSS_RULES)

	# --- 孫娘 ---
	if hikari:
		hikari.call(&"set_active", true)
		await face_off(hikari, false)
	await _say_lines(ScriptText.SPEAKER_HIKARI, ScriptText.HIKARI)
	var page1 := _make_note(Vector3(15.1, 0.9, 1.1), ScriptText.PAGE1_TITLE, ScriptText.PAGE1_BODY, 1)
	if page1:
		page1.enabled = false
		page1.visible = false
		await page1.read()
	await _say_lines(ScriptText.SPEAKER_HIKARI, ScriptText.HIKARI_AFTER)
	_send_home(hikari)

	# --- 社長が帰る ---
	await _walk(boss, POS_GENKAN_INSIDE)
	await face_off(boss)
	# 「勝手口の鍵」→「式場の蛍光灯」→「じゃあな」の順で言わせる
	await Dialogue.say(ScriptText.SPEAKER_BOSS, String(ScriptText.BOSS_LEAVE[0]))
	await _say_lines(ScriptText.SPEAKER_BOSS, ScriptText.ADDED_BOSS_LIGHTS)
	await Dialogue.say(ScriptText.SPEAKER_BOSS, String(ScriptText.BOSS_LEAVE[1]))
	var b := building()
	if b:
		b.set_room_lights(&"Room_Shikijo", false)
	if boss and boss.has_method(&"leave_via_genkan"):
		boss.call(&"leave_via_genkan")
	else:
		Events.emit_event(&"npc_left", {"name": &"boss"})
		var d: Door = b.get_door(&"Door_Genkan") if b else null
		if d:
			d.open(true)
			await Events.wait(1.4)
			d.close()

	# --- 勝手口 ---
	Tasks.set_task(&"backdoor", ScriptText.TASK_BACKDOOR)
	_arm_incense_dread()
	Game.set_flag(&"intro_done", true)
	intro_running = false
	log_event("intro_done")


func _say_lines(speaker: String, lines: Array) -> void:
	for l in lines:
		await Dialogue.say(speaker, String(l))


## 導入が終わったら、線香を絶やした罰を有効にする。
func _arm_incense_dread() -> void:
	var inc := sys(&"incense_stand")
	if inc:
		inc.set(&"dread_on_out", 1)


## 玄関まで歩かせてから帰す。式場から直接 leave_via_genkan すると
## 経路が作れずその場で消える(review M4)。
func _send_home(who) -> void:
	if who == null:
		return
	await walk_via_hall(who, POS_GENKAN_INSIDE)
	if who.has_method(&"leave_via_genkan"):
		who.call(&"leave_via_genkan")
	else:
		Events.emit_event(&"npc_left", {"name": who.get(&"npc_id")})


## 式場から館の西側へ一息に歩かせると、経路はあるのに途中で詰まる。
## 廊下の合流点を経由させると通る(review M4)。
func walk_via_hall(who, dest: Vector3) -> void:
	if who == null or not who.has_method(&"go_to"):
		return
	var n3 := who as Node3D
	if n3 and n3.global_position.x > 7.0 and dest.x < 7.0:
		await who.call(&"go_to", _snap_nav(POS_HALL_JUNCTION))
	await who.call(&"go_to", _snap_nav(dest))
	# 折りたたみ椅子の列で挟まって動けなくなることがある(npc/level 側の課題)。
	# 台本が止まらないよう、着けなかったときだけ位置を合わせる。
	if n3 and n3.global_position.distance_to(dest) > 2.5 and who.has_method(&"teleport_to"):
		who.call(&"teleport_to", _snap_nav(dest))


## 会話の前に、プレイヤーから TALK_DISTANCE だけ離れた位置で向き合わせる。
## NPC がカメラに密着すると顔が画面いっぱいになるので、台詞の前に必ず通す。
func face_off(who, allow_teleport: bool = true) -> void:
	if who == null:
		return
	var p := Game.player
	if p == null:
		return
	var npc3 := who as Node3D
	if npc3 == null:
		return
	var to := p.global_position
	var away := npc3.global_position - to
	away.y = 0.0
	if away.length() < 0.6:
		# 真上に乗っているときはプレイヤーの正面へ回り込ませる
		away = -p.global_transform.basis.z
		away.y = 0.0
	var target := _snap_nav(to + away.normalized() * TALK_DISTANCE)
	if who.has_method(&"go_to") and npc3.global_position.distance_to(target) > 0.5:
		await who.call(&"go_to", target)
	# 歩いているあいだにプレイヤーが動いていることがあるので、現在位置から測り直す。
	# このあと自力で歩いて帰る NPC(孫娘)は飛ばすと経路を作れなくなるので teleport しない。
	if allow_teleport and npc3.global_position.distance_to(p.global_position) > TALK_DISTANCE + 1.5 \
			and who.has_method(&"teleport_to"):
		var away2 := npc3.global_position - p.global_position
		away2.y = 0.0
		if away2.length() < 0.6:
			away2 = -p.global_transform.basis.z
			away2.y = 0.0
		who.call(&"teleport_to", _snap_nav(p.global_position + away2.normalized() * TALK_DISTANCE))
	if who.has_method(&"face_player"):
		who.call(&"face_player")
	look_at_npc(who)
	if Game.debug or autoplay != null:
		var d := npc3.global_position.distance_to(p.global_position)
		print("[dir] face_off %s dist=%.2fm" % [String(who.get(&"npc_id")), d])


## ナビメッシュ上のいちばん近い点に寄せる。
## ここを通さずに teleport_to すると、以後その NPC は経路を作れなくなる(review M4)。
func _snap_nav(pos: Vector3) -> Vector3:
	var out := pos
	out.y = 0.0
	var p := Game.player
	if p == null or not p.is_inside_tree():
		return out
	return NpcUtil.snap(p.get_world_3d(), out)


## プレイヤーの視線を NPC の顔(Head)へ向ける。
func look_at_npc(who) -> void:
	var p := Game.player
	if p == null or who == null or not p.has_method(&"look_at_point"):
		return
	var head: Vector3
	if who.has_method(&"head_position"):
		head = who.call(&"head_position")
	else:
		head = (who as Node3D).global_position + Vector3(0, 1.55, 0)
	p.look_at_point(head, 0.7)


func _walk(who, pos: Vector3) -> void:
	if who == null or not who.has_method(&"go_to"):
		await Events.wait(0.35 if Dialogue.auto_advance else 1.2)
		return
	await who.call(&"go_to", pos)
	# ナビが通らなかったときは位置だけ合わせる。
	# (Spawn_Boss が受付台の裏の 0.7m の隙間にあり、ナビメッシュが届かない。npc/level に依頼済み)
	var n3 := who as Node3D
	if n3 and n3.global_position.distance_to(pos) > 1.6 and who.has_method(&"teleport_to"):
		who.call(&"teleport_to", _snap_nav(pos))
	if who.has_method(&"face_player"):
		who.call(&"face_player")


func _wait_talk(who) -> void:
	if who == null or not who.has_signal(&"talked"):
		return
	if Dialogue.auto_advance:
		return
	await who.talked


func _wait_event(name: StringName, timeout: float = 120.0) -> void:
	await Events.wait_event(name, timeout)
