class_name Player
extends CharacterBody3D
## 一人称コントローラ。歩きのみ(走れない)。視線インタラクト、持ち物、足音、ヘッドボブ。
## 衝突: layer 3(player) / mask 1(world)。カプセル 半径0.3 / 高さ1.7。目線 1.6m。
##
## 主な API:
##   has_item(name) -> bool / give_item(name, carried := false) / take_item(name) / drop_carried()
##   teleport(pos, yaw_deg, pitch_deg) / set_locked(bool) / look_at_point(pos, duration)
##   shake(intensity, duration) / set_speed_multiplier(f) / get_camera() -> Camera3D

signal focus_changed(target: Node)
signal hold_progress_changed(ratio: float)
signal carried_changed(item: StringName)
signal inventory_changed(items: Array)
signal stepped(surface: StringName)
signal give_refused(wanted: StringName, holding: StringName)

const SURFACE_GROUPS := {
	&"surface_lino": &"lino",
	&"surface_tatami": &"tatami",
	&"surface_concrete": &"concrete",
}

@export_group("操作")
@export var mouse_sensitivity: float = 0.0026
@export var invert_y: bool = false
@export var pitch_limit_deg: float = 85.0
@export var capture_mouse: bool = true

@export_group("移動")
@export var walk_speed: float = 2.5          ## 歩き(走れない)
@export var carry_speed: float = 2.0         ## 両手が塞がっているとき
@export var acceleration: float = 7.0        ## 少し重め
@export var deceleration: float = 9.0
@export var step_height: float = 0.3         ## 乗り越えられる段差
@export var gravity: float = 9.8

@export_group("演出")
@export var base_fov: float = 72.0
@export var bob_amplitude: float = 0.020
@export var bob_sway: float = 0.014
@export var step_length: float = 0.80        ## 歩幅(足音の間隔)
@export var footstep_volume_db: float = -8.0

@export_group("インタラクト")
@export var max_interact_distance: float = 4.0
@export var default_surface: StringName = &"lino"
## 両手が塞がっていて運搬物を受け取れないときに HUD へ出す文(director が差し替えられる)
@export var hands_full_text: String = "両手が塞がっている"
## can_interact が false の対象を押したときの共通文(Interactable.get_blocked_text() が空のとき)
@export var blocked_default_text: String = "今は何もできない。"
## 調べる物ではない物を見て押したときの文
@export var nothing_here_text: String = "特に何もない。"
## 「特に何もない。」を出すために視線レイを飛ばす距離
@export var scenery_probe_distance: float = 2.2
## Prop 判定ができないときに「物」とみなす近さ(これより遠い壁や床では何も出さない)
@export var scenery_close_distance: float = 1.5

## 持ち物
var carried_item: StringName = &""            ## 両手で運ぶ物(1つだけ)
var inventory: Array[StringName] = []          ## 鍵などの小物(複数)

var locked: bool = false
var speed_multiplier: float = 1.0
var focus: Interactable = null

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var carry_pivot: Node3D = $Head/Camera3D/CarryPivot

var _yaw: float = 0.0
var _pitch: float = 0.0
var _walk_dist: float = 0.0
var _step_index: int = 0
var _bob_offset: Vector3 = Vector3.ZERO
var _shake_amount: float = 0.0
var _shake_decay: float = 1.0
var _shake_offset: Vector3 = Vector3.ZERO
var _look_tween: Tween = null
var _hold_t: float = 0.0
var _interact_down: bool = false
var _interact_gate: bool = false   ## 会話/手紙/ポーズが閉じた瞬間の押しっぱなしを無視する
var _carry_sway: Vector2 = Vector2.ZERO
var _carry_sway_vel: Vector2 = Vector2.ZERO
var _carry_mesh: Node3D = null
var _hud: Node = null
var _mouse_captured: bool = false
var _rng := RandomNumberGenerator.new()
var _head_base_y: float = 1.6
var _moving: bool = false
var _sens_scale: float = 1.0   ## 設定のマウス感度倍率(0.5〜2.0)

func _ready() -> void:
	add_to_group(&"player")
	collision_layer = 4     # layer 3 = player
	collision_mask = 1      # layer 1 = world
	_rng.randomize()
	_head_base_y = head.position.y
	camera.fov = base_fov
	_yaw = rotation.y
	_pitch = head.rotation.x
	if capture_mouse and not _is_capture_run():
		_set_mouse_captured(true)
	if Game.player == null:
		Game.register_player(self)
	_refresh_carry_mesh()

## --screenshot / --tour のような自動撮影中はマウスを奪わない
static func _is_capture_run() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot") or a.begins_with("--tour") or a.begins_with("--shots") or a == "--no-capture":
			return true
	return false

func get_camera() -> Camera3D:
	return camera

# ---------------------------------------------------------------- 入力

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured and not _blocked():
		var rel: Vector2 = event.relative
		if "screen_relative" in event:
			# SubViewportContainer の拡大で relative が割られるので、素の値を使う
			var sr: Vector2 = event.screen_relative
			if sr.length_squared() > 0.0:
				rel = sr
		_apply_look(rel)

func _apply_look(rel: Vector2) -> void:
	var sens := mouse_sensitivity * _sens_scale
	_yaw -= rel.x * sens
	var dy := rel.y * sens
	_pitch += dy if invert_y else -dy
	var lim := deg_to_rad(pitch_limit_deg)
	_pitch = clampf(_pitch, -lim, lim)
	# 運搬中の持ち物が視点移動に遅れて付いてくる
	_carry_sway_vel += Vector2(-rel.x, -rel.y) * 0.0016

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		# ポーズは HUD が受ける。HUD が無い時だけマウスを解放する。
		if _hud_node() == null:
			_set_mouse_captured(false)

func _blocked() -> bool:
	if locked or Dialogue.busy:
		return true
	var h := _hud_node()
	if h and h.has_method("blocks_player") and h.blocks_player():
		return true
	return false

func _hud_node() -> Node:
	if is_instance_valid(_hud):
		return _hud
	var list := get_tree().get_nodes_in_group(&"hud")
	_hud = list[0] if list.size() > 0 else null
	return _hud

func _set_mouse_captured(on: bool) -> void:
	_mouse_captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

# ---------------------------------------------------------------- 移動

func _physics_process(delta: float) -> void:
	var blocked := _blocked()
	rotation.y = _yaw

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	var wish := Vector3.ZERO
	if not blocked:
		var iv := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		wish = (transform.basis * Vector3(iv.x, 0.0, iv.y))
		wish.y = 0.0
		if wish.length_squared() > 1.0:
			wish = wish.normalized()

	var target_speed := current_speed()
	var target := wish * target_speed
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if wish.length_squared() > 0.001 else deceleration
	flat = flat.move_toward(target, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	var before := global_position
	move_and_slide()
	if is_on_wall() and flat.length() > 0.05:
		_try_step_up(flat * delta)

	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_advance_walk(moved)
	_moving = is_on_floor() and moved > 0.0005

	if not blocked:
		_update_focus()
		_update_interact(delta)
	else:
		_set_hold(0.0)
		_interact_down = Input.is_action_pressed(&"interact")
		# 字幕を送る E と「調べる」E が同じキーなので、塞がれている間に押された分は
		# 離すまで持ち越して無効にする(review H4)
		_interact_gate = true
		if focus != null:
			_set_focus(null)

	_sync_mouse_mode()

func current_speed() -> float:
	var s := carry_speed if carried_item != &"" else walk_speed
	return s * speed_multiplier

## 0.3m までの段差を乗り越える(CharacterBody3D には段差処理が無いので自前)
func _try_step_up(motion: Vector3) -> bool:
	if motion.length_squared() < 0.000001:
		return false
	var up := Vector3.UP * step_height
	var xf := global_transform
	if test_move(xf, up):
		return false
	var lifted := xf.translated(up)
	var fwd := motion.normalized() * maxf(motion.length(), 0.06)
	if test_move(lifted, fwd):
		return false
	var ahead := lifted.translated(fwd)
	if not test_move(ahead, Vector3.DOWN * (step_height + 0.02)):
		return false     # 着地面が無い = 段差ではなく穴
	global_transform = ahead
	move_and_collide(Vector3.DOWN * (step_height + 0.02))
	return true

# ---------------------------------------------------------------- ヘッドボブと足音

func _advance_walk(moved: float) -> void:
	if not is_on_floor() or moved <= 0.0005:
		return
	_walk_dist += moved
	var idx := int(_walk_dist / step_length)
	if idx != _step_index:
		_step_index = idx
		_play_footstep()

## 見た目(視点・ヘッドボブ・揺れ・運搬物)は描画フレームで更新する
func _process(delta: float) -> void:
	var phase := _walk_dist / step_length * PI
	var active: float = 1.0 if _moving else 0.0
	var want := Vector3.ZERO
	if active > 0.0:
		want = Vector3(sin(phase * 0.5) * bob_sway, -absf(sin(phase)) * bob_amplitude, 0.0)
	_bob_offset = _bob_offset.lerp(want, clampf(delta * 8.0, 0.0, 1.0))

	# カメラ揺れ
	if _shake_amount > 0.0:
		_shake_amount = maxf(0.0, _shake_amount - _shake_decay * delta)
		var a := _shake_amount
		_shake_offset = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0.0) * a * 0.05
		camera.rotation.z = _rng.randf_range(-1, 1) * a * 0.02
	else:
		_shake_offset = _shake_offset.lerp(Vector3.ZERO, clampf(delta * 10.0, 0.0, 1.0))
		camera.rotation.z = lerpf(camera.rotation.z, 0.0, clampf(delta * 8.0, 0.0, 1.0))

	head.position = Vector3(_bob_offset.x, _head_base_y + _bob_offset.y, 0.0) + _shake_offset
	rotation.y = _yaw
	head.rotation.x = _pitch
	_update_carry(delta, phase, active)

func _play_footstep() -> void:
	var surf := surface_under_foot()
	stepped.emit(surf)
	var n := _rng.randi_range(1, 4)
	Audio.play(StringName("step_%s_%d" % [surf, n]), footstep_volume_db, _rng.randf_range(0.94, 1.06))

## 足の下の床の surface を返す。metadata "surface" → グループ surface_* → 既定 lino。
func surface_under_foot() -> StringName:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.25
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.2, 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return default_surface
	var n := hit.get("collider") as Node
	while n != null:
		if n.has_meta(&"surface"):
			return StringName(str(n.get_meta(&"surface")))
		for g in SURFACE_GROUPS:
			if n.is_in_group(g):
				return SURFACE_GROUPS[g]
		n = n.get_parent()
	return default_surface

# ---------------------------------------------------------------- 視線インタラクト

func _update_focus() -> void:
	var target := _raycast_interactable()
	if target != focus:
		_set_focus(target)
	elif focus != null:
		_push_prompt(focus)

func _set_focus(target: Interactable) -> void:
	if focus != null and is_instance_valid(focus):
		focus.on_unfocus()
	focus = target
	_hold_t = 0.0
	_set_hold(0.0)
	if focus != null:
		focus.on_focus()
		_push_prompt(focus)
	else:
		var h := _hud_node()
		if h and h.has_method("hide_prompt"):
			h.hide_prompt()
	focus_changed.emit(focus)

func _push_prompt(target: Interactable) -> void:
	var h := _hud_node()
	if h == null or not h.has_method("show_prompt"):
		return
	h.show_prompt(target.get_prompt(), target.can_interact(self))

func _raycast_interactable() -> Interactable:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var to := from + dir * max_interact_distance

	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var node := hit.get("collider") as Node
	var target := node as Interactable
	if target == null:
		target = _find_interactable_ancestor(node)
	if target == null or not target.enabled:
		return null
	var dist: float = from.distance_to(hit.get("position"))
	if dist > target.interact_distance:
		return null

	# 壁越しに掴まないように、world(layer 1)で遮られていないか確かめる
	var wq := PhysicsRayQueryParameters3D.create(from, to, 1)
	wq.collide_with_areas = false
	wq.exclude = [get_rid()]
	var whit := space.intersect_ray(wq)
	if not whit.is_empty():
		var wd: float = from.distance_to(whit.get("position"))
		if wd + 0.12 < dist:
			return null
	return target

func _find_interactable_ancestor(node: Node) -> Interactable:
	var n := node
	while n != null:
		if n is Interactable:
			return n
		n = n.get_parent()
	return null

func _update_interact(delta: float) -> void:
	var pressed := Input.is_action_pressed(&"interact")
	if _interact_gate:
		# 会話・選択肢・手紙・クリップボード・ポーズが閉じた直後。
		# その押下は「閉じる」ために使われたものなので、一度離すまで調べるに使わない。
		if pressed:
			_interact_down = true
			_hold_t = 0.0
			_set_hold(0.0)
			return
		_interact_gate = false
	var just := pressed and not _interact_down
	_interact_down = pressed

	if focus == null or not is_instance_valid(focus) or not focus.can_interact(self):
		_hold_t = 0.0
		_set_hold(0.0)
		if just:
			_report_no_response()
		return

	if focus.hold_time > 0.0:
		if pressed:
			if just or _hold_t > 0.0:
				_hold_t += delta
				var r: float = clampf(_hold_t / focus.hold_time, 0.0, 1.0)
				_set_hold(r)
				if r >= 1.0:
					_hold_t = 0.0
					_set_hold(0.0)
					var t := focus
					_interact_down = true
					t.interact(self)
					_set_focus(null)
		else:
			if _hold_t > 0.0:
				_hold_t = 0.0
				_set_hold(0.0)
	else:
		_set_hold(0.0)
		if just:
			focus.interact(self)

## E を押したのに何も起きなかったとき、理由を一言出す。
## 1) フォーカス中だが can_interact が false → Interactable.get_blocked_text()(空なら共通文)
## 2) フォーカスは無いが、目の前に「物」がある → nothing_here_text
## 3) 壁・床・何も無い → 黙る(押すたびに文が出ると鬱陶しいため)
func _report_no_response() -> void:
	if focus != null and is_instance_valid(focus):
		var t: String = focus.get_blocked_text() if focus.has_method("get_blocked_text") else ""
		_say_feedback(t if t != "" else blocked_default_text)
		return
	if _looking_at_object():
		_say_feedback(nothing_here_text)

## 視線の先(layer 1)が壁や床ではなく「物」かどうか。
## Prop クラス / group "prop" を親に辿って探し、見つからなければ近さで代用する。
func _looking_at_object() -> bool:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * scenery_probe_distance, 1)
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var n := hit.get("collider") as Node
	while n != null:
		if n is Prop or n.is_in_group(&"prop"):
			return true
		n = n.get_parent()
	return from.distance_to(hit.get("position")) <= scenery_close_distance

## 画面下に一言出す(独白と同じ見た目)。連打しても重ならず上書きされる。
func _say_feedback(text: String) -> void:
	if text == "":
		return
	var h := _hud_node()
	if h and h.has_method("show_toast"):
		h.show_toast(text)
	Audio.play(&"ui_back", -10.0)

func _set_hold(r: float) -> void:
	hold_progress_changed.emit(r)
	var h := _hud_node()
	if h and h.has_method("set_hold_progress"):
		h.set_hold_progress(r)

# ---------------------------------------------------------------- 持ち物

func has_item(name: StringName) -> bool:
	return carried_item == name or inventory.has(name)

## carried = true なら両手で運ぶ物。既に別の物を運んでいたら受け取らず false を返す
## (design.md「運搬中は両手が塞がり他の操作不可」)。false なら鍵などの小物で、常に受け取る。
## 呼ぶ側は戻り値を見るか、事前に is_carrying() で弾くこと。
func give_item(name: StringName, carried: bool = false) -> bool:
	if name == &"":
		return false
	if carried:
		if carried_item == name:
			return true
		if carried_item != &"":
			give_refused.emit(name, carried_item)
			_show_hands_full()
			return false
		carried_item = name
		_refresh_carry_mesh()
		carried_changed.emit(carried_item)
		return true
	if not inventory.has(name):
		inventory.append(name)
		inventory_changed.emit(inventory)
	return true

## 両手が塞がっていて受け取れなかったことを短く知らせる
func _show_hands_full() -> void:
	_say_feedback(hands_full_text)

func take_item(name: StringName) -> bool:
	if carried_item == name:
		carried_item = &""
		_refresh_carry_mesh()
		carried_changed.emit(carried_item)
		return true
	var i := inventory.find(name)
	if i >= 0:
		inventory.remove_at(i)
		inventory_changed.emit(inventory)
		return true
	return false

func drop_carried() -> StringName:
	var was := carried_item
	if was != &"":
		carried_item = &""
		_refresh_carry_mesh()
		carried_changed.emit(carried_item)
	return was

func is_carrying() -> bool:
	return carried_item != &""

# ---------------------------------------------------------------- 運搬物の簡易メッシュ

const CARRY_SHAPES := {
	&"dry_ice": {"size": Vector3(0.28, 0.17, 0.21), "color": Color(0.40, 0.42, 0.44), "kind": "box"},
	&"water": {"size": Vector3(0.19, 0.22, 0.19), "color": Color(0.26, 0.30, 0.33), "kind": "cylinder"},
	&"incense_box": {"size": Vector3(0.20, 0.055, 0.12), "color": Color(0.30, 0.13, 0.12), "kind": "box"},
	&"matches": {"size": Vector3(0.085, 0.028, 0.055), "color": Color(0.40, 0.30, 0.17), "kind": "box"},
	&"flowers": {"size": Vector3(0.17, 0.28, 0.17), "color": Color(0.22, 0.27, 0.20), "kind": "cylinder"},
}

func _refresh_carry_mesh() -> void:
	if _carry_mesh and is_instance_valid(_carry_mesh):
		_carry_mesh.queue_free()
	_carry_mesh = null
	if carried_item == &"" or carry_pivot == null:
		return
	var d: Dictionary = CARRY_SHAPES.get(carried_item, {"size": Vector3(0.20, 0.15, 0.17), "color": Color(0.33, 0.30, 0.27), "kind": "box"})
	var mi := MeshInstance3D.new()
	var size: Vector3 = d["size"]
	if String(d["kind"]) == "cylinder":
		var cm := CylinderMesh.new()
		cm.top_radius = size.x * 0.5
		cm.bottom_radius = size.x * 0.42
		cm.height = size.y
		cm.radial_segments = 10
		mi.mesh = cm
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = d["color"]
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation_degrees = Vector3(-6, 12, 3)
	carry_pivot.add_child(mi)
	_carry_mesh = mi

func _update_carry(delta: float, phase: float, active: float) -> void:
	if carry_pivot == null:
		return
	carry_pivot.visible = carried_item != &""
	if not carry_pivot.visible:
		return
	# 視点移動の慣性(ばね)
	_carry_sway_vel *= 1.0 - clampf(delta * 7.0, 0.0, 1.0)
	_carry_sway += _carry_sway_vel
	_carry_sway = _carry_sway.lerp(Vector2.ZERO, clampf(delta * 5.0, 0.0, 1.0))
	_carry_sway.x = clampf(_carry_sway.x, -0.16, 0.16)
	_carry_sway.y = clampf(_carry_sway.y, -0.16, 0.16)
	var bob := -absf(sin(phase)) * 0.022 * active
	carry_pivot.position = Vector3(0.02 + _carry_sway.x * 0.35, -0.44 + _carry_sway.y * 0.35 + bob, -0.60)
	carry_pivot.rotation = Vector3(_carry_sway.y * 1.6, _carry_sway.x * 1.6, -_carry_sway.x * 0.8)

# ---------------------------------------------------------------- 外から呼ぶ操作

func teleport(pos: Vector3, yaw_deg: float = 0.0, pitch_deg: float = 0.0) -> void:
	global_position = pos
	_yaw = deg_to_rad(yaw_deg)
	var lim := deg_to_rad(pitch_limit_deg)
	_pitch = clampf(deg_to_rad(pitch_deg), -lim, lim)
	rotation.y = _yaw
	head.rotation.x = _pitch
	velocity = Vector3.ZERO
	_walk_dist = 0.0
	_step_index = 0
	_set_focus(null)

## 会話・カットシーン中の操作ロック
func set_locked(value: bool) -> void:
	locked = value
	if locked:
		velocity.x = 0.0
		velocity.z = 0.0
		_set_hold(0.0)
		if focus != null:
			_set_focus(null)

func is_locked() -> bool:
	return locked

## 視線を tween で向ける(会話や脅かしで「見せる」)
func look_at_point(pos: Vector3, duration: float = 0.8) -> void:
	if _look_tween and _look_tween.is_valid():
		_look_tween.kill()
	var to := pos - camera.global_position
	if to.length_squared() < 0.0001:
		return
	var horiz := Vector2(to.x, to.z).length()
	var target_yaw := atan2(-to.x, -to.z)
	var target_pitch := atan2(to.y, maxf(horiz, 0.0001))
	var lim := deg_to_rad(pitch_limit_deg)
	target_pitch = clampf(target_pitch, -lim, lim)
	var yaw_from := _yaw
	var yaw_to := yaw_from + angle_difference(yaw_from, target_yaw)
	var pitch_from := _pitch
	_look_tween = create_tween()
	_look_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_look_tween.tween_method(func(t: float) -> void:
		_yaw = lerpf(yaw_from, yaw_to, t)
		_pitch = lerpf(pitch_from, target_pitch, t), 0.0, 1.0, maxf(duration, 0.01))

## 設定で「画面揺れ」を切っていたら何もしない
func shake(intensity: float = 0.5, duration: float = 0.4) -> void:
	if not Settings.screen_shake:
		return
	_shake_amount = maxf(_shake_amount, clampf(intensity, 0.0, 2.0))
	_shake_decay = _shake_amount / maxf(duration, 0.05)

## 設定画面から渡されるマウス感度の倍率(0.5〜2.0)
func set_sensitivity_scale(f: float) -> void:
	_sens_scale = clampf(f, 0.1, 5.0)

func get_sensitivity_scale() -> float:
	return _sens_scale

func set_speed_multiplier(f: float) -> void:
	speed_multiplier = clampf(f, 0.0, 4.0)

func set_fov(v: float) -> void:
	camera.fov = v

## 会話中はマウスを掴んだまま。選択肢/手紙/クリップボード/ポーズのときだけ解放する。
func _sync_mouse_mode() -> void:
	if not capture_mouse or _is_capture_run():
		return
	var want := true
	var h := _hud_node()
	if h and h.has_method("wants_cursor") and h.wants_cursor():
		want = false
	if want != _mouse_captured:
		_set_mouse_captured(want)
