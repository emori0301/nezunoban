class_name ScreenFX
extends RefCounted
## 画面演出のショートカット。autoload ではなく static 関数の集まり。
## 内部でグループ("hud" / "vhs" / "player")から対象を探すので、どこからでも呼べる。
##
##   ScreenFX.zoom_punch(0.6, 0.25)     # カメラ FOV を一瞬狭める
##   ScreenFX.darken(0.7, 1.5)          # 画面を暗くする(1.5秒かけて)
##   ScreenFX.glitch(0.4)               # VHS トラッキングノイズ
##   ScreenFX.shake(0.5, 0.4)           # カメラ揺れ
##   await ScreenFX.blackout(0.8)       # 一瞬の暗転

static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static func hud() -> Node:
	var t := tree()
	if t == null:
		return null
	var list := t.get_nodes_in_group(&"hud")
	return list[0] if list.size() > 0 else null

static func vhs() -> Node:
	var t := tree()
	if t == null:
		return null
	var list := t.get_nodes_in_group(&"vhs")
	return list[0] if list.size() > 0 else null

static func player() -> Node:
	if Game.player != null:
		return Game.player
	var t := tree()
	if t == null:
		return null
	var list := t.get_nodes_in_group(&"player")
	return list[0] if list.size() > 0 else null

static func camera() -> Camera3D:
	var p := player()
	if p and p.has_method("get_camera"):
		return p.get_camera()
	var t := tree()
	if t == null:
		return null
	return t.root.get_camera_3d()

## FOV を strength(0..1)だけ一瞬狭めて戻す。近づかれた/見つかった時に。
static func zoom_punch(strength: float = 0.5, dur: float = 0.3) -> void:
	var cam := camera()
	if cam == null:
		return
	var base: float = cam.fov
	var p := player()
	if p and "base_fov" in p:
		base = float(p.base_fov)
	var target: float = maxf(20.0, base - 22.0 * clampf(strength, 0.0, 1.5))
	var tw := cam.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(cam, "fov", target, dur * 0.28)
	tw.tween_property(cam, "fov", base, dur * 0.72)

## 画面を暗くする。amount 0..1(1 で真っ暗)。dur=0 で即時。
static func darken(amount: float, dur: float = 0.5) -> void:
	var h := hud()
	if h and h.has_method("darken"):
		h.darken(amount, dur)
		return
	var v := vhs()
	if v and v.has_method("set_darken"):
		v.set_darken(amount, dur)

static func glitch(duration: float = 0.35) -> void:
	var v := vhs()
	if v and v.has_method("glitch"):
		v.glitch(duration)

static func set_intensity(f: float) -> void:
	var v := vhs()
	if v and v.has_method("set_intensity"):
		v.set_intensity(f)

static func shake(intensity: float = 0.5, dur: float = 0.4) -> void:
	var p := player()
	if p and p.has_method("shake"):
		p.shake(intensity, dur)

static func flash(color: Color = Color.WHITE, dur: float = 0.1) -> void:
	var h := hud()
	if h and h.has_method("flash"):
		h.flash(color, dur)

static func blackout(dur: float = 0.6) -> void:
	var h := hud()
	if h and h.has_method("blackout"):
		await h.blackout(dur)
		return
	var t := tree()
	if t:
		await t.create_timer(dur).timeout

static func fade_out(dur: float = 1.0) -> void:
	var h := hud()
	if h and h.has_method("fade_out"):
		await h.fade_out(dur)
		return
	var t := tree()
	if t:
		await t.create_timer(dur).timeout

static func fade_in(dur: float = 1.0) -> void:
	var h := hud()
	if h and h.has_method("fade_in"):
		await h.fade_in(dur)
		return
	var t := tree()
	if t:
		await t.create_timer(dur).timeout
