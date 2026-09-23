class_name Timeline
extends Node
## 一夜の時刻イベント。1 イベント = 1 関数。docs/design.md v0.2 の台本表が正。
##
##   register(from_minutes) … from_minutes 以降のイベントだけ Events.at に積む
##   apply_past(minutes)    … その時刻より前のイベントの「結果」だけを適用する(--time= 起動用)
##
## 21:00 の導入だけは Events ではなく Director.play_intro() が直接動かす。

var dir                                    ## Director(型は付けない)
var scares: Scares

## 台本表。[時刻, メソッド名, 覚え書き]
const SCHEDULE := [
	["21:40", "ev_flowers", "供花の水替え"],
	["22:00", "ev_window", "式場の窓が開く / 線香が早く減る"],
	["22:30", "ev_phone_silent", "電話(無言)"],
	["23:00", "ev_monitor_figure", "モニターに座る人影"],
	["23:20", "ev_cats_begin", "猫が来はじめる"],
	["23:40", "ev_tv", "控室の TV が勝手につく"],
	["00:00", "ev_blackout", "廊下の照明が落ちる / 分電盤"],
	["00:30", "ev_son", "息子が来館 / 選択"],
	["01:00", "ev_dry_ice", "ドライアイス交換 / 足音が2人分"],
	["01:30", "ev_office_note", "宿直日誌(収集②)/ 扉が閉まる"],
	["02:00", "ev_yukan", "湯灌室が開く(収集③)"],
	["02:30", "ev_phone_wet", "電話(濡れた声)"],
	["03:00", "ev_ushimitsu", "丑三つ時"],
	["03:20", "ev_safe", "金庫の台帳(収集④)/ 廊下の人影"],
	["03:40", "ev_freezer_empty", "冷凍庫が空 / 濡れた足跡"],
	["04:00", "ev_finale", "全消灯 / 火車 / 灯し直し x3"],
	["04:45", "ev_dawn_light", "夜明けの光 / 鴉"],
	["05:00", "ev_dawn", "朝 / エンディング"],
]

var _cat_visits_left: int = 0
var _finale_relights: int = 0
var _finale_running: bool = false
var _hikaeshitsu_spot: Scares.Spot = null


# ============================================================ 登録

func register(from_minutes: int) -> void:
	for row in SCHEDULE:
		var t := int(Clock.minutes_from_hhmm(String(row[0])))
		if t < from_minutes:
			continue
		Events.at(String(row[0]), Callable(self, String(row[1])), String(row[1]))


## m 以降でいちばん早い台本イベントの時刻(分)。無ければ 9999。
func next_event_minute(m: int) -> int:
	var best := 9999
	for row in SCHEDULE:
		var t := int(Clock.minutes_from_hhmm(String(row[0])))
		if t >= m and t < best:
			best = t
	return best


## --time= で途中から始めたとき、それより前のイベントの結果だけを反映する。
func apply_past(m: int) -> void:
	var b: Building = dir.building()
	if m > 40:
		# 供花は替え済み
		for f in SystemsInstaller.find_all(&"flower_stand"):
			f.call(&"set_wilted", false)
	if m > 60:
		# 窓は閉めたあと
		var w: WindowPane = b.get_window_pane(&"Window_Shikijo") if b else null
		if w and w.is_open:
			w.close()
	if m > 120:
		scares.chair_pulled_out()
		if Dread.value >= 3:
			scares.zabuton_before_coffin()
	if m > 140:
		dir.cats_enabled = true
		_cat_visits_left = 3
		_activate_cats()
	if m > 180:
		Game.set_flag(&"breaker_restored", true)
	if m > 210:
		# 息子は断られて控室で飲んでいる(真エンドの前提)
		Game.set_flag(&"son_refused", true)
		dir.spawn_son_asleep()
	if m > 240:
		var c: Node = dir.sys(&"coffin")
		if c:
			c.call(&"set_face_state", 1)
	if m > 270:
		dir.enable_office_note(true)
	if m > 300:
		var d: Door = b.get_door(&"Door_Yukan") if b else null
		if d:
			d.set_locked(false)
		dir.enable_yukan_note(true)
	if m > 380:
		var desk: Node = dir.sys(&"boss_desk")
		if desk:
			desk.call(&"enable_key", true)
		_prepare_safe()
	if m > 465:
		scares.dawn_now()
	if m > 420:
		# 終盤の途中から始めたときは、終盤そのものを動かす
		call_deferred(&"ev_finale")
	if m > 400:
		var fz: Node = dir.sys(&"freezer")
		if fz:
			fz.call(&"set_empty", true)
		var c2: Node = dir.sys(&"coffin")
		if c2:
			c2.call(&"set_face_state", 3)
		scares.paw_prints()


# ============================================================ 21:40 供花

func ev_flowers() -> void:
	dir.log_event("ev_flowers")
	Tasks.set_task(&"flowers", ScriptText.TASK_FLOWERS)
	for f in SystemsInstaller.find_all(&"flower_stand"):
		f.call(&"set_wilted", true)


# ============================================================ 22:00 窓

func ev_window() -> void:
	dir.log_event("ev_window")
	var b: Building = dir.building()
	var w: WindowPane = b.get_window_pane(&"Window_Shikijo") if b else null
	if w:
		w.open(true)
	var inc: Node = dir.sys(&"incense_stand")
	if inc:
		inc.set(&"burn_multiplier", 3.0)
		inc.call(&"set_wind", Vector3(-0.8, 0, -0.5))
	Dialogue.monologue(ScriptText.M_WINDOW)
	Tasks.set_task(&"window", ScriptText.TASK_WINDOW)


## Director が window_closed{Window_Shikijo} を受けて呼ぶ
func on_shikijo_window_closed() -> void:
	var inc: Node = dir.sys(&"incense_stand")
	if inc:
		inc.set(&"burn_multiplier", 1.0)
		inc.call(&"set_wind", Vector3.ZERO)
	Tasks.complete(&"window")
	# 閉めた瞬間、外の駐車場に猫が1匹座ってこちらを見ている
	await get_tree().create_timer(0.7).timeout
	var cat: Node = dir.npc(&"cat", 0)
	if cat and cat.has_method(&"sit_at"):
		cat.call(&"set_active", true)
		cat.call(&"sit_at", Vector3(13.0, 0.0, 5.6), Vector3(0, 0, -1))
	else:
		scares.spawn_figure("cat", Vector3(13.0, 0.0, 5.6), 180.0, false, &"sit")
	Audio.play_at(&"cat_meow_1", Vector3(13.0, 0.3, 5.6), 0.0, 1.0, 22.0)
	scares.glitch(0.2)


# ============================================================ 22:30 電話(無言)

func ev_phone_silent() -> void:
	dir.log_event("ev_phone_silent")
	var ph: Node = dir.sys(&"phone")
	if ph == null:
		return
	ph.call(&"ring", 30.0)
	dir.pending_call = &"silent"


func play_silent_call() -> void:
	var ph: Node = dir.sys(&"phone")
	await Dialogue.monologue(ScriptText.M_PHONE_HELLO)
	Audio.play(&"phone_breath", -2.0)
	await get_tree().create_timer(3.0).timeout
	if ph:
		ph.call(&"hang_up")
	await Dialogue.monologue(ScriptText.M_PHONE_CUT)
	# 受話器を置くと受付の芳名帳のページがめくれる
	await get_tree().create_timer(0.8).timeout
	var gb: Node = dir.sys(&"guest_book")
	if gb:
		gb.call(&"rustle")
	scares.glitch(0.25)


# ============================================================ 23:00 モニターの人影

var _monitor_ghost: Node3D = null

func ev_monitor_figure() -> void:
	dir.log_event("ev_monitor_figure")
	# 後列の椅子に座る人影。render layer 10 なので CCTV にだけ映る。
	_monitor_ghost = scares.spawn_figure("npc_son", Vector3(12.9, 0.0, 0.2), -90.0, true, &"sit")
	var mon: Node = dir.sys(&"monitor")
	if mon:
		mon.set(&"auto_switch", false)
		mon.call(&"switch_feed", 0)
		mon.call(&"set_static", 0.16)
		mon.call(&"glitch", 0.8)
	Audio.play(&"vhs_tracking", -8.0)
	dir.pending_shikijo_reveal = true


## Director が player_entered_room{Room_Shikijo} で呼ぶ
func on_shikijo_reveal() -> void:
	if _monitor_ghost and is_instance_valid(_monitor_ghost):
		_monitor_ghost.queue_free()
		_monitor_ghost = null
	var mon: Node = dir.sys(&"monitor")
	if mon:
		mon.set(&"auto_switch", true)
		mon.call(&"set_static", 0.1)
	scares.chair_pulled_out()
	await get_tree().create_timer(0.6).timeout
	await Dialogue.monologue(ScriptText.M_CHAIR)
	if Dread.value >= 3:
		await get_tree().create_timer(0.4).timeout
		scares.zabuton_before_coffin()


# ============================================================ 23:20 猫

func ev_cats_begin() -> void:
	dir.log_event("ev_cats_begin")
	dir.cats_enabled = true
	_cat_visits_left = scares.rng.randi_range(3, 5)
	_activate_cats()
	_schedule_next_cat(2.0)


func _activate_cats() -> void:
	var c: Node = dir.npc(&"cat", 0)
	if c == null:
		return
	if c.has_method(&"activate"):
		c.call(&"activate")
	if c.has_method(&"set_target_entry"):
		c.call(&"set_target_entry", &"Door_Backyard")


const CAT_ENTRIES := [&"Door_Backyard", &"Window_Toilet", &"Window_Shikijo"]

func _schedule_next_cat(minutes: float) -> void:
	if _cat_visits_left <= 0:
		return
	var secs := minutes * Clock.seconds_per_game_minute / maxf(Clock.speed, 0.01)
	await get_tree().create_timer(secs).timeout
	if not dir.cats_enabled or Game.state == Game.State.ENDING:
		return
	_cat_visits_left -= 1
	var entry: StringName = CAT_ENTRIES[scares.rng.randi_range(0, CAT_ENTRIES.size() - 1)]
	var cats: Array = dir.npc_all(&"cat")
	if not cats.is_empty():
		var c: Node = cats[scares.rng.randi_range(0, cats.size() - 1)]
		if c.has_method(&"activate"):
			c.call(&"activate")
		if c.has_method(&"set_target_entry"):
			c.call(&"set_target_entry", entry)
	else:
		# 猫が居なくても気配だけは出す
		Audio.play_at(StringName("cat_scratch_%d" % scares.rng.randi_range(1, 3)),
			_entry_pos(entry), -2.0, 1.0, 18.0)
	_schedule_next_cat(scares.rng.randf_range(20.0, 25.0))


func _entry_pos(entry: StringName) -> Vector3:
	match entry:
		&"Window_Toilet": return Vector3(0.7, 1.4, 4.2)
		&"Window_Shikijo": return Vector3(13.0, 1.4, 4.2)
		_: return Vector3(0.0, 0.8, -8.2)


# ============================================================ 23:40 TV

func ev_tv() -> void:
	dir.log_event("ev_tv")
	var tv: Node = dir.sys(&"tv")
	if tv == null:
		return
	tv.call(&"turn_on")
	tv.call(&"set_noise", 0.9)
	dir.pending_tv_scare = true


## 控室に入る / TV に近づいたとき
func on_tv_approach() -> void:
	var tv: Node = dir.sys(&"tv")
	if tv == null:
		return
	await get_tree().create_timer(0.5).timeout
	tv.call(&"flash_face", 0.4)
	scares.glitch(0.5)
	scares.stinger(-6.0)
	await get_tree().create_timer(0.9).timeout
	tv.call(&"turn_off")


# ============================================================ 00:00 停電

func ev_blackout() -> void:
	dir.log_event("ev_blackout")
	var b: Building = dir.building()
	var br: Node = dir.sys(&"breaker")
	if b:
		# 廊下の蛍光灯が1本ずつ落ちる
		b.flicker(&"Room_Hall", 1.6)
		await get_tree().create_timer(1.8).timeout
		b.set_room_lights(&"Room_Hall", false)
		await get_tree().create_timer(0.6).timeout
		b.set_room_lights(&"Room_Office", false)
	if br:
		br.call(&"trip")
	Tasks.set_task(&"breaker", ScriptText.TASK_BREAKER)
	scares.glitch(0.6)


## Director が breaker_on で呼ぶ
func on_breaker_restored() -> void:
	var b: Building = dir.building()
	if b:
		b.set_room_lights(&"Room_Hall", true)
		b.set_room_lights(&"Room_Office", true)
	Tasks.complete(&"breaker")
	Game.set_flag(&"breaker_restored", true)
	dir.pending_blackout_reveal = true


## 復旧して式場に戻ったとき
func on_blackout_reveal() -> void:
	var inc: Node = dir.sys(&"incense_stand")
	var cnd: Node = dir.sys(&"candle")
	var iei: Node = dir.sys(&"iei")
	if inc:
		dir.quench(&"incense_stand")
	if cnd:
		dir.quench(&"candle")
	if iei:
		iei.call(&"set_face_down", true)
	scares.glitch(0.5)
	await get_tree().create_timer(0.6).timeout
	await Dialogue.monologue(ScriptText.M_IEI)


# ============================================================ 00:30 息子

func ev_son() -> void:
	dir.log_event("ev_son")
	var b: Building = dir.building()
	for i in 3:
		Audio.play_at(StringName("door_knock_%d" % (i + 1)), Vector3(-11.4, 1.2, 0.0), 2.0, 1.0, 26.0)
		await get_tree().create_timer(0.55).timeout
	var son: Node = dir.npc(&"son")
	if son and son.has_method(&"enter_from_genkan"):
		son.call(&"set_active", true)
		await son.call(&"enter_from_genkan", Vector3(-9.2, 0.0, 0.0))
		await dir.face_off(son)       # カメラに密着させない
	else:
		var d: Door = b.get_door(&"Door_Genkan") if b else null
		if d:
			d.open(true)
			await get_tree().create_timer(1.2).timeout
			d.close()
	for l in ScriptText.SON_KNOCK:
		await Dialogue.say(ScriptText.SPEAKER_SON, l)
	for l in ScriptText.SON_ENTER:
		await Dialogue.say(ScriptText.SPEAKER_SON, l)
	dir.look_at_npc(son)
	var i: int = await Dialogue.choose(ScriptText.SON_CHOICE_PROMPT, ScriptText.SON_CHOICE_OPTIONS)
	if i == 1:
		await _son_allowed(son)
	else:
		await _son_refused(son)


func _son_refused(son) -> void:
	Game.set_flag(&"son_refused", true)
	for l in ScriptText.SON_REFUSED:
		await Dialogue.say(ScriptText.SPEAKER_SON, l)
	if son and son.has_method(&"go_to"):
		son.call(&"set_talkable", false)
		await son.call(&"go_to", Vector3(-1.35, 0.0, 3.8))
		if son.has_method(&"face"):
			son.call(&"face", Vector3(-1.35, 0.0, 2.0))
	else:
		dir.spawn_son_asleep(false)
	Events.at("01:30", Callable(self, "ev_son_sleeps"), "ev_son_sleeps")


func ev_son_sleeps() -> void:
	dir.log_event("ev_son_sleeps")
	if not Game.get_flag(&"son_refused", false):
		return
	var son: Node = dir.npc(&"son")
	if son and son.has_method(&"sleep"):
		son.call(&"sleep")
	Game.set_flag(&"son_asleep", true)
	Audio.play_at(&"tatami_creak", Vector3(-1.35, 0.2, 3.8), -8.0)


func _son_allowed(son) -> void:
	var coffin: Node = dir.sys(&"coffin")
	if coffin:
		coffin.set(&"allow_open_window", true)
		coffin.call(&"set_face_state", 2)
		await coffin.call(&"show_face", 3.2, "son")
		coffin.set(&"allow_open_window", false)
	Dread.add(2, &"coffin_window_opened")
	Game.set_flag(&"son_opened_window", true)
	for l in ScriptText.SON_ALLOWED:
		await Dialogue.say(ScriptText.SPEAKER_SON, l)
	if son and son.has_method(&"leave_via_genkan"):
		son.call(&"leave_via_genkan")


# ============================================================ 01:00 ドライアイス

func ev_dry_ice() -> void:
	dir.log_event("ev_dry_ice")
	Tasks.set_task(&"dry_ice", ScriptText.TASK_DRY_ICE)
	var fz: Node = dir.sys(&"freezer")
	if fz:
		fz.call(&"set_empty", false)


## Director が carried_item == dry_ice で呼ぶ
func on_dry_ice_carried() -> void:
	scares.set_second_footsteps(true)
	await get_tree().create_timer(3.0).timeout
	if Game.get_flag(&"heard_second_steps", false):
		return
	Game.set_flag(&"heard_second_steps", true)
	await Dialogue.monologue(ScriptText.M_FOOTSTEPS)
	await get_tree().create_timer(1.4).timeout
	scares.breath_behind()


func on_dry_ice_replaced() -> void:
	scares.set_second_footsteps(false)
	Tasks.complete(&"dry_ice")
	var coffin: Node = dir.sys(&"coffin")
	if coffin and int(coffin.get(&"face_state")) < 1:
		coffin.call(&"set_face_state", 1)
	await get_tree().create_timer(0.4).timeout
	var st := int(coffin.get(&"face_state")) if coffin else 1
	match st:
		3: Dialogue.monologue(ScriptText.M_FACE3)
		2: Dialogue.monologue(ScriptText.M_FACE2)
		_: Dialogue.monologue(ScriptText.M_FACE1)


# ============================================================ 01:30 宿直日誌

func ev_office_note() -> void:
	dir.log_event("ev_office_note")
	dir.enable_office_note(true)


## Director が page_read{n:2} で呼ぶ
func on_office_note_read() -> void:
	var b: Building = dir.building()
	var d: Door = b.get_door(&"Door_Office") if b else null
	await get_tree().create_timer(0.5).timeout
	if d:
		d.slam()
	scares.stinger(-4.0)
	scares.glitch(0.5)


# ============================================================ 02:00 湯灌室

func ev_yukan() -> void:
	dir.log_event("ev_yukan")
	var b: Building = dir.building()
	var pos := Vector3(6.4, 1.0, -7.5)
	Audio.play_at(&"door_locked", pos, 2.0, 1.0, 26.0)
	await get_tree().create_timer(1.1).timeout
	Audio.play_at(&"door_open", pos, 2.0, 1.0, 26.0)
	var d: Door = b.get_door(&"Door_Yukan") if b else null
	if d:
		d.set_locked(false)
	dir.enable_yukan_note(true)
	scares.glitch(0.3)


## Room_Yukan に入るたび
func on_yukan_entered() -> void:
	if int(Clock.game_minutes) >= 380 and not Game.get_flag(&"robe_dropped", false):
		Game.set_flag(&"robe_dropped", true)
		scares.robe_drop()
	else:
		scares.robe_sway()


# ============================================================ 02:30 電話(濡れた声)

func ev_phone_wet() -> void:
	dir.log_event("ev_phone_wet")
	var ph: Node = dir.sys(&"phone")
	if ph == null:
		return
	ph.call(&"ring", 30.0)
	dir.pending_call = &"wet"


func play_wet_call() -> void:
	var ph: Node = dir.sys(&"phone")
	await Dialogue.monologue(ScriptText.M_PHONE_HELLO)
	Audio.play(&"phone_voice_wet", 0.0)
	await Dialogue.say("", ScriptText.PHONE_WET_LINE)
	await get_tree().create_timer(1.0).timeout
	if ph:
		ph.call(&"hang_up")
	var inc: Node = dir.sys(&"incense_stand")
	if inc:
		dir.quench(&"incense_stand")
	scares.glitch(0.5)
	await Dialogue.monologue(ScriptText.M_PHONE_WET_AFTER)


# ============================================================ 03:00 丑三つ時

func ev_ushimitsu() -> void:
	dir.log_event("ev_ushimitsu")
	var b: Building = dir.building()
	Audio.ambient(&"amb_drone_high", -8.0, 0.6)
	var vhs := scares.vhs()
	if vhs and vhs.has_method(&"set_intensity"):
		vhs.set_intensity(0.62)
	# 猫3匹を同時に開口部へ
	var cats: Array = dir.npc_all(&"cat")
	for i in mini(cats.size(), 3):
		var c: Node = cats[i]
		if c.has_method(&"activate"):
			c.call(&"activate")
		if c.has_method(&"set_target_entry"):
			c.call(&"set_target_entry", CAT_ENTRIES[i % CAT_ENTRIES.size()])
	# 20 ゲーム分のあいだ、4 回 火を消す(実時間では速度で割る)
	var step := 5.0 * Clock.seconds_per_game_minute / maxf(Clock.speed, 0.01)
	var coffin: Node = dir.sys(&"coffin")
	for i in 4:
		await get_tree().create_timer(step).timeout
		if Game.state == Game.State.ENDING:
			return
		var inc: Node = dir.sys(&"incense_stand")
		if inc:
			dir.quench(&"incense_stand")
		if coffin:
			coffin.call(&"scratch")
		if b:
			b.flicker(&"Room_Shikijo", 1.4)
		Audio.play_at(&"coffin_scratch", coffin.global_position if coffin else Vector3.ZERO, 0.0)
		scares.glitch(0.5)
		if i == 3:
			var cnd: Node = dir.sys(&"candle")
			if cnd:
				dir.quench(&"candle")
			if coffin:
				coffin.call(&"creak")
	await get_tree().create_timer(step * 0.6).timeout
	Audio.stop_ambient(&"amb_drone_high", 2.0)
	if vhs and vhs.has_method(&"set_intensity"):
		vhs.set_intensity(0.32 + 0.15 * Dread.level())
	dir.refresh_dread_ambient()


# ============================================================ 03:20 金庫

func ev_safe() -> void:
	dir.log_event("ev_safe")
	var desk: Node = dir.sys(&"boss_desk")
	if desk:
		desk.call(&"enable_key", true)
	_prepare_safe()


func _prepare_safe() -> void:
	var sf: Node = dir.sys(&"safe")
	if sf:
		sf.call(&"set_note", ScriptText.PAGE4_TITLE, ScriptText.PAGE4_BODY, 4)


## Director が page_read{n:4} で呼ぶ
func on_ledger_read() -> void:
	await get_tree().create_timer(0.8).timeout
	scares.hall_figure("kasha", 1.2)


# ============================================================ 03:40 冷凍庫が空

func ev_freezer_empty() -> void:
	dir.log_event("ev_freezer_empty")
	var fz: Node = dir.sys(&"freezer")
	if fz:
		fz.call(&"set_empty", true)
	var coffin: Node = dir.sys(&"coffin")
	if coffin:
		coffin.call(&"set_face_state", 3)
	scares.paw_prints()
	Tasks.set_task(&"dry_ice", ScriptText.TASK_DRY_ICE)


# ============================================================ 04:00 終盤

func ev_finale() -> void:
	if _finale_running:
		return
	_finale_running = true
	dir.log_event("ev_finale")
	var b: Building = dir.building()
	var inc: Node = dir.sys(&"incense_stand")
	var cnd: Node = dir.sys(&"candle")
	var coffin: Node = dir.sys(&"coffin")
	if b:
		b.set_all_lights(false)           # 外(自販機・外灯)は残る
		if b.has_method(&"set_emergency_lights"):
			b.call(&"set_emergency_lights", true)   # 緑の非常灯は点けたままにする
	scares.set_moonlight(true)            # 窓からの月明かり(真っ暗だと歩けない)
	if inc:
		dir.quench(&"incense_stand")
	if cnd:
		dir.quench(&"candle")
	if coffin:
		coffin.call(&"set_lid_ajar", true)
	Audio.stop_ambient(&"amb_drone_low", 1.0)
	Audio.ambient(&"amb_drone_high", -6.0, 1.0)
	scares.glitch(0.9)
	# マッチが要る
	if cnd:
		cnd.set(&"require_matches", true)
	var m: Node = dir.matches_pickup()
	if m:
		m.set(&"enabled", true)
		m.set(&"visible", true)
	Tasks.set_task(&"relight", ScriptText.TASK_RELIGHT)
	# 控室の戸を「開けるか」に差し替える(息子が寝ているとき)
	_install_hikaeshitsu_choice()
	# 火車。独白は「送りっぱなし」にする。
	# (Dialogue.say はプレイヤーが送るまで返らないので、await すると火車が出てこない)
	var k: Node = dir.npc(&"kasha")
	if k and k.has_method(&"activate"):
		k.call(&"set_active", true)
		k.call(&"activate")       # Kasha 側が chase_started を出す
	else:
		dir.start_fallback_chase()
		Events.emit_event(&"chase_started")
	await Dialogue.monologue(ScriptText.M_LIGHTS_OUT)
	await Dialogue.monologue(ScriptText.M_MATCHES)


## relight_success を受ける
func on_relight(n: int) -> void:
	if not _finale_running:
		return
	_finale_relights = n
	Tasks.complete(&"relight")
	Dialogue.monologue(ScriptText.M_RELIGHT_OK)
	var k: Node = dir.npc(&"kasha")
	if n >= 3:
		_finish_finale()
		return
	if k and k.has_method(&"retreat"):
		k.call(&"retreat")
	else:
		dir.set_fallback_chase(false)
	await get_tree().create_timer(18.0 / maxf(Clock.speed, 0.01)).timeout
	if not _finale_running or Game.state == Game.State.ENDING:
		return
	var cnd: Node = dir.sys(&"candle")
	if cnd:
		# 3 回目は異変度が高ければ必ず失敗する
		if n == 2 and (Dread.is_doomed() or Game.get_flag(&"cat_crossed_coffin", false)):
			cnd.set(&"fail_next", true)
		dir.quench(&"candle")
	Audio.play(&"kasha_growl", -4.0)
	scares.glitch(0.6)
	Tasks.set_task(&"relight", ScriptText.TASK_RELIGHT)
	if k and k.has_method(&"resume"):
		k.call(&"resume")
	else:
		dir.set_fallback_chase(true)


## relight_failed を受ける
func on_relight_failed() -> void:
	if not _finale_running:
		return
	Dialogue.monologue(ScriptText.M_RELIGHT_FAIL)
	scares.glitch(1.0)
	Audio.play(&"kasha_screech", 0.0)
	await get_tree().create_timer(2.2 / maxf(Clock.speed, 0.01)).timeout
	dir.kasha_catches()


func _finish_finale() -> void:
	_finale_running = false
	var k: Node = dir.npc(&"kasha")
	if k and k.has_method(&"stop_chase"):
		k.call(&"stop_chase")
	dir.set_fallback_chase(false)
	if k == null or not k.has_method(&"stop_chase"):
		Events.emit_event(&"chase_ended")
	Audio.stop_ambient(&"amb_drone_high", 2.0)
	var b: Building = dir.building()
	if b:
		b.set_room_lights(&"Room_Hall", true)
		b.set_room_lights(&"Room_Genkan", true)
	scares.set_moonlight(false)
	Tasks.set_task(&"last_incense", ScriptText.TASK_LAST_INCENSE)
	if int(Clock.game_minutes) < 460:
		Clock.skip_to(460)


# ---------------------------------------------------------- 控室の戸

func _install_hikaeshitsu_choice() -> void:
	var b: Building = dir.building()
	if b == null:
		return
	var d: Door = b.get_door(&"Door_Hikaeshitsu")
	if d == null:
		return
	d.enabled = false
	_hikaeshitsu_spot = Scares.Spot.make(b, d.global_position + Vector3(0, 1.0, 0),
		"控室の戸を調べる", Vector3(1.2, 2.0, 0.9), Callable(self, "_ask_hikaeshitsu"))


func _ask_hikaeshitsu(_p: Node3D) -> void:
	if _hikaeshitsu_spot:
		_hikaeshitsu_spot.enabled = false
	var i: int = await Dialogue.choose(ScriptText.CHOICE_HIKAESHITSU, ScriptText.CHOICE_HIKAESHITSU_OPTIONS)
	if i != 1:
		if _hikaeshitsu_spot:
			_hikaeshitsu_spot.enabled = true
		return
	var b: Building = dir.building()
	var d: Door = b.get_door(&"Door_Hikaeshitsu") if b else null
	if d:
		d.open(true)
	if not Game.get_flag(&"son_asleep", false) and not Game.get_flag(&"son_refused", false):
		return
	dir.kasha_takes_son()


func finale_running() -> bool:
	return _finale_running


# ============================================================ 04:45 夜明けの光

func ev_dawn_light() -> void:
	dir.log_event("ev_dawn_light")
	# 15 ゲーム分かけて明るくする(実時間は速度で割る)
	var secs := 15.0 * Clock.seconds_per_game_minute / maxf(Clock.speed, 0.01)
	scares.start_dawn(secs)
	Audio.stop_ambient(&"amb_drone_low", 3.0)
	Audio.stop_ambient(&"amb_drone_high", 3.0)
	# 外で鴉が鳴きはじめる
	for i in 3:
		await get_tree().create_timer(secs * 0.28).timeout
		if Game.state == Game.State.ENDING:
			return
		Audio.play_at(&"crow_morning", Vector3(13.0, 3.0, 6.0), -10.0 + i * 3.0, 1.0, 40.0)


# ============================================================ 05:00 朝

func ev_dawn() -> void:
	dir.log_event("ev_dawn")
	if Game.state == Game.State.ENDING:
		return
	dir.finish(dir.endings.decide())
