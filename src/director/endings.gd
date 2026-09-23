class_name Endings
extends Node
## 4 つのエンディングの判定と演出。
##   判定: decide() … docs/design.md v0.2「エンディング条件(v0.2)」の表
##   演出: run(id) … src/ui/ending.tscn の play() を使い、終わったらタイトルへ戻す
##
## Game.end_night(id) → Game.night_ended → Director が run(id) を呼ぶ、という流れ。

const ENDING_SCENE := "res://src/ui/ending.tscn"
## 到達したエンディングの記録。タイトル画面が読む。
##   [endings]
##   morning=true
##   kasha=true
const PROGRESS_PATH := "user://progress.cfg"

signal ending_started(id: StringName)

var dir                                  ## Director(型は付けない)
var _running: bool = false


## いま夜が終わったとしたら、どのエンディングか。
func decide() -> StringName:
	if Game.get_flag(&"kasha_took_son", false):
		return Game.ENDING_SUBSTITUTE
	if Game.get_flag(&"caught_by_kasha", false):
		return Game.ENDING_KASHA
	if Dread.is_doomed() or Game.get_flag(&"cat_crossed_coffin", false):
		return Game.ENDING_KASHA
	# 終盤の灯し直し(3回)を終えていないなら、火を戻せなかった = 亡骸を奪われる。
	# docs/design.md v0.2「朝: 04:40 の灯し直しに成功。異変度 < 6」
	if not Game.get_flag(&"relight_done", false):
		return Game.ENDING_KASHA
	return Game.ENDING_MORNING


func text_for(id: StringName) -> Array:
	match id:
		Game.ENDING_KASHA:
			return [ScriptText.ENDING_KASHA_TITLE, ScriptText.ENDING_KASHA_LINES]
		Game.ENDING_SUBSTITUTE:
			return [ScriptText.ENDING_SUBSTITUTE_TITLE, ScriptText.ENDING_SUBSTITUTE_LINES]
		Game.ENDING_PORTRAIT:
			return [ScriptText.ENDING_PORTRAIT_TITLE, ScriptText.ENDING_PORTRAIT_LINES]
		_:
			return [ScriptText.ENDING_MORNING_TITLE, ScriptText.ENDING_MORNING_LINES]


# ============================================================ 演出

func run(id: StringName) -> void:
	if _running:
		return
	_running = true
	ending_started.emit(id)
	Clock.stop()
	Tasks.clear()
	dir.scares.set_second_footsteps(false)
	var p := Game.player
	if p and p.has_method(&"set_locked"):
		p.set_locked(true)
	if Game.get_flag(&"skip_prologue", false):
		pass                              # QA(--ending=)は画面だけ見たいので前口上を飛ばす
	elif id == Game.ENDING_PORTRAIT:
		await _portrait_prologue()
	else:
		await _morning_prologue(id)
	Audio.stop_all_ambient(1.4)
	var hud: Node = dir.hud()
	if hud and hud.has_method(&"fade_out"):
		await hud.fade_out(1.6)
	else:
		await Events.wait(1.6)
	_show_screen(id)


## 駐車場(玄関の外)。社長の車が入ってくる位置。
const CAR_POS := Vector3(-14.6, 0.6, 2.2)

## 05:00 の朝。鴉と鐘、そして車の音。
func _morning_prologue(id: StringName) -> void:
	Audio.play(&"crow_morning", -2.0)
	# 火車エンドは 04:20 前後で終わるので社長は来ない。
	if id != Game.ENDING_KASHA:
		Audio.play_at(&"car_arrive", CAR_POS, 0.0, 1.0, 45.0)
	await Events.wait(2.2)
	Audio.play(&"chime_dawn", -4.0)
	var b: Building = dir.building()
	if b:
		b.set_all_lights(true)
	if id == Game.ENDING_KASHA:
		var coffin: Node = dir.sys(&"coffin")
		if coffin:
			coffin.call(&"set_open", true)
	await Events.wait(2.6)


## 布団で休んだとき。目覚めたら 05:00、遺影が自分の顔になっている。
func _portrait_prologue() -> void:
	var hud: Node = dir.hud()
	if hud and hud.has_method(&"fade_out"):
		await hud.fade_out(1.4)
	await Events.wait(1.6)
	Clock.skip_to(480)
	# 目覚めた式場の状態を作る
	var inc: Node = dir.sys(&"incense_stand")
	if inc:
		dir.quench(&"incense_stand")
	var cnd: Node = dir.sys(&"candle")
	if cnd:
		dir.quench(&"candle")
	var coffin: Node = dir.sys(&"coffin")
	if coffin:
		coffin.call(&"set_open", true)
	var b: Building = dir.building()
	if b:
		b.set_all_lights(false)
		b.set_room_lights(&"Room_Shikijo", false)
	# 目が覚めたら五時。館内の灯りは消えているが、窓から朝の光は入っている。
	# (空の棺が見えないと「中は空だった」が成立しない)
	dir.scares.dawn_now()
	var iei: Node = dir.sys(&"iei")
	var tex: Texture2D = SystemUtil.load_texture("iei_photo_player")
	if iei:
		iei.call(&"set_face_down", false)
		iei.call(&"set_follow_player", false)
		if tex:
			iei.call(&"set_portrait", tex)
	# 祭壇の前で目が覚める
	var p := Game.player
	if p and p.has_method(&"teleport"):
		p.teleport(Vector3(16.6, 0.0, 1.35), -60.0, 0.0)
	if hud and hud.has_method(&"fade_in"):
		await hud.fade_in(2.2)
	Audio.play(&"crow_morning", -6.0)
	await Events.wait(1.2)
	if p and p.has_method(&"look_at_point") and iei:
		p.look_at_point((iei as Node3D).global_position + Vector3(0, 0.33, 0), 1.6)
	await Events.wait(3.4)


## 到達したエンディングを user://progress.cfg に書き足す。
## 既存の内容は読んでから上書きするので、周回しても消えない。
func save_progress(id: StringName) -> void:
	if id == &"":
		return
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)          # 無ければ空のまま
	cfg.set_value("endings", String(id), true)
	cfg.set_value("endings", "last", String(id))
	var err := cfg.save(PROGRESS_PATH)
	if err != OK:
		push_warning("Endings: progress.cfg を書けない (%d)" % err)


## エンディング文のあとにクレジットを流す。
func _roll_credits(vp: Node) -> void:
	if vp == null:
		return
	var c := Credits.new()
	c.name = "Credits"
	vp.add_child(c)
	await c.play()
	c.queue_free()


func _show_screen(id: StringName) -> void:
	var info := text_for(id)
	var vp: Node = dir.ui_parent()
	if not ResourceLoader.exists(ENDING_SCENE) or vp == null:
		print("ENDING %s" % id)
		await Events.wait(1.0)
		get_tree().reload_current_scene()
		return
	var e: Node = load(ENDING_SCENE).instantiate()
	vp.add_child(e)
	if id == Game.ENDING_PORTRAIT and e.has_method(&"show_portrait"):
		e.show_portrait(SystemUtil.load_texture("iei_photo_player"))
	var hud: Node = dir.hud()
	if hud and hud.has_method(&"set_fade"):
		hud.set_fade(0.0)
		hud.set_rec(false)
	await e.play(id, String(info[0]), info[1])
	await _roll_credits(vp)
	get_tree().reload_current_scene()
