class_name Settings
extends RefCounted
## user:// に置く設定と進捗の読み書き。autoload ではなく static の集まりで、HUD とタイトルから呼ぶ。
##
##   Settings.load_all()      # 起動時に1回(2回目以降は何もしない)
##   Settings.apply()         # 値を AudioServer / Player / VhsLayer へ反映
##   Settings.save()          # 変更したら呼ぶ
##
## 進捗(到達エンディング)は director が user://progress.cfg に書く。読むのはここ。

const PATH := "user://settings.cfg"
const PROGRESS_PATH := "user://progress.cfg"

## マウス感度は Player.mouse_sensitivity への倍率
const SENS_MIN := 0.5
const SENS_MAX := 2.0
const SENS_STEP := 0.1

const VOL_STEP := 0.1
const VHS_STEP := 0.05

## エンディング ID と表示順(タイトルの到達表示もこの順)
const ENDING_IDS: Array[StringName] = [&"morning", &"kasha", &"substitute", &"portrait"]

static var mouse_sensitivity: float = 1.0     ## 0.5〜2.0 の倍率
static var pad_sensitivity: float = 1.0       ## 右スティックの視点感度 0.5〜2.0
static var volume_master: float = 0.9         ## 0..1(linear)
static var volume_sfx: float = 1.0
static var volume_ambient: float = 0.9
static var vhs_intensity: float = 0.32        ## 0..1
static var screen_shake: bool = true
static var show_hints: bool = true            ## 操作ヒントを出すか
static var seen_hint: bool = false            ## 一度出したか(初回だけ出すため)

static var _loaded: bool = false

static func load_all(force: bool = false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	mouse_sensitivity = clampf(float(cf.get_value("input", "mouse_sensitivity", mouse_sensitivity)), SENS_MIN, SENS_MAX)
	pad_sensitivity = clampf(float(cf.get_value("input", "pad_sensitivity", pad_sensitivity)), SENS_MIN, SENS_MAX)
	volume_master = clampf(float(cf.get_value("audio", "master", volume_master)), 0.0, 1.0)
	volume_sfx = clampf(float(cf.get_value("audio", "sfx", volume_sfx)), 0.0, 1.0)
	volume_ambient = clampf(float(cf.get_value("audio", "ambient", volume_ambient)), 0.0, 1.0)
	vhs_intensity = clampf(float(cf.get_value("video", "vhs_intensity", vhs_intensity)), 0.0, 1.0)
	screen_shake = bool(cf.get_value("video", "screen_shake", screen_shake))
	show_hints = bool(cf.get_value("ui", "show_hints", show_hints))
	seen_hint = bool(cf.get_value("ui", "seen_hint", seen_hint))

static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("input", "pad_sensitivity", pad_sensitivity)
	cf.set_value("audio", "master", volume_master)
	cf.set_value("audio", "sfx", volume_sfx)
	cf.set_value("audio", "ambient", volume_ambient)
	cf.set_value("video", "vhs_intensity", vhs_intensity)
	cf.set_value("video", "screen_shake", screen_shake)
	cf.set_value("ui", "show_hints", show_hints)
	cf.set_value("ui", "seen_hint", seen_hint)
	cf.save(PATH)

## 既定値に戻す(保存はしない)
static func reset_to_defaults() -> void:
	mouse_sensitivity = 1.0
	pad_sensitivity = 1.0
	volume_master = 0.9
	volume_sfx = 1.0
	volume_ambient = 0.9
	vhs_intensity = 0.32
	screen_shake = true
	show_hints = true

## 値を実際の音量 / 感度 / VHS に反映する。対象が居なければその項目だけ飛ばす。
static func apply() -> void:
	_apply_bus("Master", volume_master)
	_apply_bus("SFX", volume_sfx)
	_apply_bus("Ambient", volume_ambient)

	var p := _player()
	if p and p.has_method("set_sensitivity_scale"):
		p.set_sensitivity_scale(mouse_sensitivity)
	if p and p.has_method("set_pad_sensitivity_scale"):
		p.set_pad_sensitivity_scale(pad_sensitivity)

	var v := _vhs()
	if v and v.has_method("set_intensity"):
		v.set_intensity(vhs_intensity)

static func _apply_bus(name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(name)
	if idx < 0:
		return
	if linear <= 0.005:
		AudioServer.set_bus_mute(idx, true)
		return
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static func _player() -> Node:
	if Game.player != null:
		return Game.player
	var t := _tree()
	if t == null:
		return null
	var list := t.get_nodes_in_group(&"player")
	return list[0] if list.size() > 0 else null

static func _vhs() -> Node:
	var t := _tree()
	if t == null:
		return null
	var list := t.get_nodes_in_group(&"vhs")
	return list[0] if list.size() > 0 else null

# ---------------------------------------------------------------- 進捗(読むだけ)

## 到達したエンディング。ENDING_IDS と同じ並びの bool 配列を返す。
## director が user://progress.cfg の [endings] に morning=true のように書く。
static func reached_endings() -> Array[bool]:
	var out: Array[bool] = [false, false, false, false]
	var cf := ConfigFile.new()
	if cf.load(PROGRESS_PATH) != OK:
		return out
	for i in ENDING_IDS.size():
		out[i] = bool(cf.get_value("endings", String(ENDING_IDS[i]), false))
	return out

static func reached_count() -> int:
	var n := 0
	for b in reached_endings():
		if b:
			n += 1
	return n
