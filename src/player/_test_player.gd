extends Node
## player 担当の単体確認シーン。main.tscn と同じ構成(SubViewport 640x360 → 2倍表示)で
## 床(lino/tatami/concrete)・壁・段差・Interactable 3種・暗い照明を作り、
## player.tscn / hud.tscn / vhs_layer.tscn を載せる。
##
##   godot --path . res://src/player/_test_player.tscn
##   godot --path . res://src/player/_test_player.tscn -- --shots=out/player

const PLAYER_PATH := "res://src/player/player.tscn"
const HUD_PATH := "res://src/ui/hud.tscn"
const VHS_PATH := "res://src/fx/vhs_layer.tscn"
const TITLE_PATH := "res://src/ui/title.tscn"
const ENDING_PATH := "res://src/ui/ending.tscn"
const INTER_SCRIPT := "res://src/player/_test_interactable.gd"

@onready var container: SubViewportContainer = $GameViewportContainer
@onready var viewport: SubViewport = $GameViewportContainer/GameViewport
@onready var world: Node3D = $GameViewportContainer/GameViewport/World

var player: Node3D = null
var hud: Node = null
var vhs: Node = null
var args: Dictionary = {}

func _ready() -> void:
	args = _parse_args()
	_build_world()
	_spawn()
	Clock.skip_to(Clock.minutes_from_hhmm("23:32"))
	Clock.start()
	Tasks.set_task(&"incense", "線香を立てる")
	if args.has("shots"):
		_run_shots(String(args["shots"]))
	elif args.has("titleshot"):
		_run_title_shot(String(args["titleshot"]))
	elif args.has("selftest"):
		_run_selftest()

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out

# ---------------------------------------------------------------- 世界

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.010, 0.013)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.40, 0.48)
	env.ambient_light_energy = 0.22
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.035, 0.045)
	env.fog_density = 0.020
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	_floor(Vector3(0, 0, 0), Vector2(10, 14), Color(0.34, 0.33, 0.30), &"lino", "")
	_floor(Vector3(9, 0, 0), Vector2(8, 14), Color(0.46, 0.41, 0.26), &"", "surface_tatami")
	_floor(Vector3(-9, 0, 0), Vector2(8, 14), Color(0.24, 0.24, 0.25), &"", "surface_concrete")

	# 壁
	_wall(Vector3(0, 1.6, -7.1), Vector3(26, 3.2, 0.3))
	_wall(Vector3(0, 1.6, 7.1), Vector3(26, 3.2, 0.3))
	_wall(Vector3(-13.2, 1.6, 0), Vector3(0.3, 3.2, 14))
	_wall(Vector3(13.2, 1.6, 0), Vector3(0.3, 3.2, 14))
	# 仕切り(廊下らしさ)
	_wall(Vector3(5.0, 1.6, -3.0), Vector3(0.25, 3.2, 8))

	# 段差 0.3(乗り越えられるか)
	_wall(Vector3(-2.5, 0.15, 2.5), Vector3(3, 0.3, 3))
	# 箱(Prop ではないただの StaticBody。近さで「物」と判定される側)
	_wall(Vector3(2.0, 0.6, 3.4), Vector3(0.7, 1.2, 0.7), Color(0.34, 0.30, 0.26))
	# Prop(level が置く物。距離に関係なく「物」と判定される側)
	var pr := Prop.new()
	pr.position = Vector3(-2.6, 0, -2.0)   # 段差(x -4..-1, z 1..4)と重ならない場所に置く
	pr.placeholder_size = Vector3(0.8, 1.6, 0.8)
	pr.placeholder_color = Color(0.30, 0.28, 0.32)
	world.add_child(pr)

	# 照明(暗め)
	_light(Vector3(0, 2.7, -4.5), Color(0.96, 0.90, 0.76), 3.2, 11.0)
	_light(Vector3(0, 2.7, 0.5), Color(0.88, 0.90, 0.96), 2.2, 10.0)
	_light(Vector3(0, 2.7, 5.0), Color(0.88, 0.90, 0.96), 2.2, 9.0)
	_light(Vector3(9, 2.7, 0.0), Color(0.96, 0.84, 0.62), 3.0, 9.0)
	_light(Vector3(-9, 2.7, 0.0), Color(0.72, 0.80, 0.92), 2.4, 9.0)

	# Interactable 3種
	_interactable(Vector3(0, 1.3, -5.4), "線香を立てる", 0.0, &"", "社長", "線香は絶やすなよ。一本が一時間ももたん。")
	_interactable(Vector3(-1.7, 1.3, -5.4), "棺の小窓を開ける", 1.5, &"", "", "……開けてはいけない。")
	_interactable(Vector3(1.7, 1.3, -5.4), "ドライアイスを入れる", 0.0, &"dry_ice", "", "ドライアイスを足した。")
	# 押しても反応しない対象(ユーザー指摘の金庫に相当)
	var safe := _interactable(Vector3(-3.8, 1.3, -2.0), "金庫を開ける", 0.0, &"", "", "")
	safe.force_blocked = true
	safe.blocked_text = "鍵がかかっている。"
	safe.color = Color(0.26, 0.26, 0.28)
	safe.say_text = ""

	var giver := _interactable(Vector3(3.8, 1.3, -2.0), "ドライアイスを持つ", 0.0, &"", "", "")
	giver.color = Color(0.58, 0.60, 0.62)
	giver.give_on_use = &"dry_ice"
	giver.give_carried = true
	giver.say_text = ""

func _floor(pos: Vector3, size: Vector2, color: Color, surface: StringName, group: String) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 0.4, size.y)
	cs.shape = shape
	cs.position.y = -0.2
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.4, size.y)
	mi.mesh = bm
	mi.position.y = -0.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = mat
	sb.add_child(mi)
	if surface != &"":
		sb.set_meta(&"surface", surface)
	if group != "":
		sb.add_to_group(StringName(group))
	world.add_child(sb)
	return sb

func _wall(pos: Vector3, size: Vector3, color: Color = Color(0.20, 0.20, 0.21)) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = mat
	sb.add_child(mi)
	world.add_child(sb)
	return sb

func _light(pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = true
	world.add_child(l)

func _interactable(pos: Vector3, prompt: String, hold: float, need: StringName, speaker: String, text: String) -> Node:
	var n := Area3D.new()
	n.set_script(load(INTER_SCRIPT))
	n.position = pos
	n.prompt = prompt
	n.hold_time = hold
	n.required_item = need
	n.say_speaker = speaker
	n.say_text = text
	n.interact_distance = 2.4
	world.add_child(n)
	return n

# ---------------------------------------------------------------- 組み立て

func _spawn() -> void:
	player = load(PLAYER_PATH).instantiate()
	world.add_child(player)
	player.teleport(Vector3(0, 0.05, -1.6), 0.0, 0.0)
	Game.register_player(player)

	hud = load(HUD_PATH).instantiate()
	viewport.add_child(hud)

	# --titleshot のときは VhsLayer を作らない(title.gd の自前 attach を確かめるため)
	if args.has("titleshot"):
		return
	vhs = load(VHS_PATH).instantiate()
	add_child(vhs)
	vhs.attach(container)

## main.gd はタイトル中に VhsLayer を付けないので、title.gd が自前で付けられるかを見る
func _run_title_shot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	hud.visible = false
	var title: Node = load(TITLE_PATH).instantiate()
	viewport.add_child(title)
	await get_tree().create_timer(4.2, false).timeout
	await _shot(dir, "21_title_novhs")
	print("vhs nodes: %d" % get_tree().get_nodes_in_group(&"vhs").size())
	print("container material: %s" % str(container.material))
	get_tree().quit()

# ---------------------------------------------------------------- 機能テスト

var _fails: int = 0

func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  OK   %s %s" % [label, detail])
	else:
		_fails += 1
		print("  FAIL %s %s" % [label, detail])

## show_code_input を待たずに走らせ、結果を辞書に書く
func _run_code_input(out: Dictionary, title: String, length: int) -> void:
	out["v"] = await hud.show_code_input(title, length)

func _run_dialogue_code(out: Dictionary, title: String, length: int) -> void:
	out["v"] = await Dialogue.code_input(title, length)

## アクションを1回だけ押して離す(メニューのエッジ検出に合わせる)
func _tap(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().create_timer(0.1, false).timeout
	Input.action_release(action)
	await get_tree().create_timer(0.15, false).timeout

## ゲームパッドの軸を倒す/戻す。Input.parse_input_event で実機の無い環境でも試せる。
func _pad_axis(axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)

func _pad_button(index: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = index
	ev.pressed = pressed
	Input.parse_input_event(ev)

## 倒していた軸をすべて中立に戻す
func _pad_center() -> void:
	for a in [0, 1, 2, 3]:
		_pad_axis(a, 0.0)

## E を1回押して離す(押しっぱなしのゲートに引っかからないように)
func _press_interact() -> void:
	Input.action_press(&"interact")
	await get_tree().create_timer(0.12, false).timeout
	Input.action_release(&"interact")
	await get_tree().create_timer(0.25, false).timeout

## 加速ぶんを除いた定常速度を測る(0.8秒で加速しきってから1.0秒ぶん)
func _measure_speed() -> float:
	# 壁(z=±7.1)にぶつからない向きと距離を取る: z=4.0 から -Z へ 1.8秒 = 約4.5m
	player.teleport(Vector3(0, 0.05, 4.0), 0.0, 0.0)
	await get_tree().create_timer(0.3, false).timeout
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.8, false).timeout
	var a: Vector3 = player.global_position
	await get_tree().create_timer(1.0, false).timeout
	var b: Vector3 = player.global_position
	Input.action_release(&"move_forward")
	return Vector2(b.x - a.x, b.z - a.z).length() / 1.0

func _run_selftest() -> void:
	await get_tree().create_timer(0.8, false).timeout
	print("== player selftest ==")
	var p0 := Vector3.ZERO

	# 1) 歩行速度(2.5 m/s)。加速が終わってから測る
	var v: float = await _measure_speed()
	_check(absf(v - 2.5) < 0.2, "歩行速度", "= %.2f m/s (期待 2.5)" % v)

	# 2) 運搬中は 2.0 m/s
	await get_tree().create_timer(0.4, false).timeout
	player.give_item(&"dry_ice", true)
	var v2: float = await _measure_speed()
	_check(absf(v2 - 2.0) < 0.2, "運搬中の速度", "= %.2f m/s (期待 2.0)" % v2)
	_check(player.has_item(&"dry_ice"), "has_item(carried)")
	player.take_item(&"dry_ice")
	_check(not player.has_item(&"dry_ice"), "take_item")
	player.give_item(&"key_yukan")
	_check(player.has_item(&"key_yukan") and player.carried_item == &"", "inventory の小物")

	# 3) 床ごとの surface 判定
	await get_tree().create_timer(0.3, false).timeout
	for spec in [[Vector3(0, 0.05, 0), &"lino"], [Vector3(9, 0.05, 0), &"tatami"], [Vector3(-9, 0.05, 0), &"concrete"]]:
		player.teleport(spec[0], 0.0, 0.0)
		await get_tree().create_timer(0.25, false).timeout
		var got: StringName = player.surface_under_foot()
		_check(got == spec[1], "surface", "%s -> %s" % [str(spec[0]), got])

	# 4) 足音が歩幅で鳴るか
	var steps: Array[StringName] = []
	var conn := func(s: StringName) -> void: steps.append(s)
	player.stepped.connect(conn)
	player.teleport(Vector3(0, 0.05, 2.0), 180.0, 0.0)
	await get_tree().create_timer(0.3, false).timeout
	Input.action_press(&"move_forward")
	await get_tree().create_timer(2.0, false).timeout
	Input.action_release(&"move_forward")
	player.stepped.disconnect(conn)
	_check(steps.size() >= 4 and steps.size() <= 9, "足音の回数", "= %d 回 / 2秒 (歩幅 0.8m)" % steps.size())

	# 5) 0.3m の段差を乗り越える
	await get_tree().create_timer(0.3, false).timeout
	player.teleport(Vector3(-2.5, 0.05, 0.6), 180.0, 0.0)
	await get_tree().create_timer(0.3, false).timeout
	var y0: float = player.global_position.y
	Input.action_press(&"move_forward")
	await get_tree().create_timer(1.6, false).timeout
	Input.action_release(&"move_forward")
	var y1: float = player.global_position.y
	_check(y1 - y0 > 0.2, "段差 0.3m を登る", "y %.2f -> %.2f" % [y0, y1])

	# 6) 視線インタラクト(単押し)
	await get_tree().create_timer(0.4, false).timeout
	player.teleport(Vector3(0, 0.05, -3.8), 0.0, -7.0)
	await get_tree().create_timer(0.4, false).timeout
	_check(player.focus != null, "フォーカス取得", str(player.focus))
	var fired := {"n": 0}
	if player.focus:
		player.focus.interacted.connect(func(_p: Node3D) -> void: fired["n"] += 1)
	Input.action_press(&"interact")
	await get_tree().create_timer(0.2, false).timeout
	Input.action_release(&"interact")
	await get_tree().create_timer(0.2, false).timeout
	_check(fired["n"] == 1, "interact 1回で1発火", "= %d" % fired["n"])
	hud._dlg_active = false
	await get_tree().create_timer(0.4, false).timeout

	# 7) 長押し(hold_time 1.5)
	player.teleport(Vector3(-1.7, 0.05, -3.8), 0.0, -7.0)
	await get_tree().create_timer(0.4, false).timeout
	var held := {"n": 0}
	var ring := {"max": 0.0}
	player.hold_progress_changed.connect(func(r: float) -> void: ring["max"] = maxf(ring["max"], r))
	if player.focus:
		_check(player.focus.hold_time > 0.0, "長押し対象", "hold_time=%.1f" % player.focus.hold_time)
		player.focus.interacted.connect(func(_p: Node3D) -> void: held["n"] += 1)
	Input.action_press(&"interact")
	await get_tree().create_timer(0.7, false).timeout
	_check(ring["max"] > 0.2 and held["n"] == 0, "途中で離す前: 進捗のみ", "進捗 %.2f" % ring["max"])
	Input.action_release(&"interact")
	await get_tree().create_timer(0.3, false).timeout
	_check(held["n"] == 0, "離すとキャンセル")
	Input.action_press(&"interact")
	await get_tree().create_timer(1.8, false).timeout
	Input.action_release(&"interact")
	await get_tree().create_timer(0.2, false).timeout
	_check(held["n"] == 1, "長押し完了で1発火", "= %d" % held["n"])
	hud._dlg_active = false
	await get_tree().create_timer(0.4, false).timeout

	# 8) required_item
	player.teleport(Vector3(1.7, 0.05, -3.8), 0.0, -7.0)
	await get_tree().create_timer(0.4, false).timeout
	var target = player.focus
	_check(target != null and not target.can_interact(player), "required_item なしでは不可")
	player.give_item(&"dry_ice", true)
	await get_tree().create_timer(0.2, false).timeout
	_check(target != null and target.can_interact(player), "持っていれば可")
	player.take_item(&"dry_ice")

	# 9) 会話中は動けない / 会話後に動ける
	await get_tree().create_timer(0.3, false).timeout
	player.teleport(Vector3(0, 0.05, 2.0), 180.0, 0.0)
	Dialogue.say("テスト", "うごけないはず")
	await get_tree().create_timer(0.4, false).timeout
	p0 = player.global_position
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.8, false).timeout
	Input.action_release(&"move_forward")
	var moved_while_busy: float = p0.distance_to(player.global_position)
	_check(moved_while_busy < 0.05, "会話中は移動しない", "= %.3f m" % moved_while_busy)
	hud._dlg_active = false
	await get_tree().create_timer(0.4, false).timeout
	p0 = player.global_position
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.8, false).timeout
	Input.action_release(&"move_forward")
	_check(p0.distance_to(player.global_position) > 0.6, "会話後は動ける")

	# 10) set_locked / look_at_point / teleport
	player.set_locked(true)
	p0 = player.global_position
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.6, false).timeout
	Input.action_release(&"move_forward")
	_check(p0.distance_to(player.global_position) < 0.05, "set_locked(true) で移動しない")
	player.set_locked(false)
	player.teleport(Vector3(0, 0.05, 0), 0.0, 0.0)
	await get_tree().create_timer(0.2, false).timeout
	player.look_at_point(Vector3(4, 1.6, 0), 0.4)
	await get_tree().create_timer(0.7, false).timeout
	var fwd: Vector3 = -player.get_camera().global_transform.basis.z
	_check(fwd.x > 0.9, "look_at_point で右(+X)を向く", "forward=%.2f,%.2f,%.2f" % [fwd.x, fwd.y, fwd.z])

	# 11) 字幕が出ている間は動けない(Dialogue.busy が false でも) ← review H4
	await get_tree().create_timer(0.4, false).timeout
	player.teleport(Vector3(0, 0.05, 2.0), 180.0, 0.0)
	await get_tree().create_timer(0.3, false).timeout
	hud.show_line("", "……字幕のあいだは動けないはず。")   # Dialogue を通さないので busy は false のまま
	await get_tree().create_timer(0.3, false).timeout
	_check(not Dialogue.busy, "字幕だけ出ている状態", "Dialogue.busy=%s" % str(Dialogue.busy))
	_check(hud.blocks_player(), "字幕中は blocks_player()=true")
	p0 = player.global_position
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.8, false).timeout
	Input.action_release(&"move_forward")
	var moved_sub: float = p0.distance_to(player.global_position)
	_check(moved_sub < 0.05, "字幕中は移動しない", "= %.3f m" % moved_sub)

	# 12) 字幕を送る E が、そのまま目の前の Interactable を押さない ← review H4
	player.teleport(Vector3(0, 0.05, -3.8), 0.0, -7.0)
	await get_tree().create_timer(0.4, false).timeout
	var near: Node = null
	for n in get_tree().get_nodes_in_group(&"interactable"):
		if n.global_position.distance_to(Vector3(0, 1.3, -5.4)) < 0.1:
			near = n
	var e_fired := {"n": 0}
	if near:
		near.interacted.connect(func(_p: Node3D) -> void: e_fired["n"] += 1)
	hud.show_line("社長", "送りキーで閉じるだけにしたい。")
	await get_tree().create_timer(0.9, false).timeout   # タイプライターが出きるまで待つ(1回目の送りは全表示に使われる)
	Input.action_press(&"advance")      # E は advance と interact の両方に割り当たっている
	Input.action_press(&"interact")
	await get_tree().create_timer(0.7, false).timeout
	Input.action_release(&"advance")
	Input.action_release(&"interact")
	await get_tree().create_timer(0.3, false).timeout
	_check(not hud.is_dialogue_open(), "E で字幕が閉じる")
	_check(e_fired["n"] == 0, "同じ E で Interactable は押されない", "= %d 回" % e_fired["n"])
	hud._dlg_active = false
	await get_tree().create_timer(0.4, false).timeout

	# 13) 両手が塞がっていたら運搬物を受け取らない ← review M2
	player.drop_carried()
	var g1: bool = player.give_item(&"dry_ice", true)
	var g2: bool = player.give_item(&"water", true)
	_check(g1 and not g2, "2つめの運搬物は拒否", "dry_ice=%s water=%s" % [str(g1), str(g2)])
	_check(player.carried_item == &"dry_ice", "運搬中の物が消えない", "= %s" % player.carried_item)
	_check(player.is_carrying(), "is_carrying()")
	_check(player.give_item(&"key_office"), "小物は運搬中でも受け取れる")
	_check(player.give_item(&"dry_ice", true), "同じ物なら true(冪等)")
	player.drop_carried()
	_check(player.give_item(&"water", true) and player.carried_item == &"water", "置いたあとは受け取れる")
	player.drop_carried()

	# 14) クリップボードと字幕は重ならない ← review L4
	hud.toggle_clipboard()
	await get_tree().create_timer(0.2, false).timeout
	_check(hud._clip_open, "クリップボードが開く")
	hud.show_line("", "独白が割り込む。")
	await get_tree().create_timer(0.3, false).timeout
	_check(not hud._clip_open, "字幕が出るとクリップボードは閉じる")
	hud._dlg_active = false
	await get_tree().create_timer(0.3, false).timeout

	# 15) 押しても反応しないときに文が出る ← ユーザー指摘
	await get_tree().create_timer(0.3, false).timeout

	# 15a) can_interact が false の Interactable(金庫)
	player.teleport(Vector3(-3.8, 0.05, -0.4), 0.0, -7.0)
	await get_tree().create_timer(0.4, false).timeout
	_check(player.focus != null, "blocked な対象にもフォーカスは付く", str(player.focus))
	_check(player.focus != null and not player.focus.can_interact(player), "can_interact=false")
	await _press_interact()
	_check(hud.is_toast_visible(), "押すと文が出る", "「%s」" % hud.get_toast_text())
	_check(hud.get_toast_text() == "鍵がかかっている。", "blocked_text が使われる", "= 「%s」" % hud.get_toast_text())

	# 15b) blocked_text が空なら共通文
	player.teleport(Vector3(1.7, 0.05, -3.8), 0.0, -7.0)   # required_item = dry_ice、持っていない
	await get_tree().create_timer(0.5, false).timeout
	await _press_interact()
	_check(hud.get_toast_text() == "何かが要る。", "required_item の既定文", "= 「%s」" % hud.get_toast_text())

	# 15c) 目の前の箱(Prop ではない)に E → 近さで「物」と判定される
	player.teleport(Vector3(2.0, 0.05, 2.3), 180.0, -32.0)
	await get_tree().create_timer(0.5, false).timeout
	_check(player.focus == null, "箱は Interactable ではない")
	await _press_interact()
	_check(hud.get_toast_text() == "特に何もない。", "近くの物を見て押すと文が出る", "= 「%s」" % hud.get_toast_text())

	# 15c-2) Prop は 1.5m より遠くても「物」と判定される
	hud._toast.text = "(なし)"
	player.teleport(Vector3(-2.6, 0.05, 0.2), 0.0, -5.0)   # Prop まで約 1.8m(近さの閾値 1.5m より遠い)
	await get_tree().create_timer(0.5, false).timeout
	await _press_interact()
	_check(hud.get_toast_text() == "特に何もない。", "Prop は遠くても物と判定", "= 「%s」" % hud.get_toast_text())

	# 15d) 遠い壁に E → 何も出さない
	hud.show_toast("")                                      # 直前の文を消す
	hud._toast.text = "(なし)"
	player.teleport(Vector3(0, 0.05, 0.0), 0.0, 0.0)        # 壁(z=-7.1)まで 7m
	await get_tree().create_timer(0.5, false).timeout
	_check(player.focus == null, "壁にはフォーカスが付かない")
	await _press_interact()
	_check(hud.get_toast_text() == "(なし)", "遠い壁では黙る", "= 「%s」" % hud.get_toast_text())

	# 15e) 連打しても重ならない(常に最新の1つ)
	player.teleport(Vector3(-3.8, 0.05, -0.4), 0.0, -7.0)
	await get_tree().create_timer(0.4, false).timeout
	for i in 3:
		await _press_interact()
	_check(hud.get_toast_text() == "鍵がかかっている。", "連打しても文は1つ")

	# 16) 設定の保存と復元
	await get_tree().create_timer(0.3, false).timeout
	# 元の設定を控えておき、最後に書き戻す
	var backup := {
		"sens": Settings.mouse_sensitivity, "pad": Settings.pad_sensitivity, "m": Settings.volume_master,
		"s": Settings.volume_sfx, "a": Settings.volume_ambient,
		"v": Settings.vhs_intensity, "shake": Settings.screen_shake,
		"hints": Settings.show_hints, "seen": Settings.seen_hint,
	}

	Settings.mouse_sensitivity = 1.7
	Settings.volume_master = 0.4
	Settings.volume_sfx = 0.2
	Settings.volume_ambient = 0.6
	Settings.vhs_intensity = 0.8
	Settings.screen_shake = false
	Settings.show_hints = false
	Settings.seen_hint = true
	Settings.save()

	# 別の値で汚してから読み直す
	Settings.mouse_sensitivity = 1.0
	Settings.volume_master = 1.0
	Settings.vhs_intensity = 0.1
	Settings.screen_shake = true
	Settings.show_hints = true
	Settings.load_all(true)
	_check(is_equal_approx(Settings.mouse_sensitivity, 1.7), "感度が復元される", "= %.2f" % Settings.mouse_sensitivity)
	_check(is_equal_approx(Settings.volume_master, 0.4) and is_equal_approx(Settings.volume_sfx, 0.2) and is_equal_approx(Settings.volume_ambient, 0.6), "音量3つが復元される")
	_check(is_equal_approx(Settings.vhs_intensity, 0.8), "VHS の強さが復元される", "= %.2f" % Settings.vhs_intensity)
	_check(Settings.screen_shake == false and Settings.show_hints == false, "トグル2つが復元される")

	# apply() が実際の音量 / 感度 / VHS に届く
	Settings.apply()
	var mi := AudioServer.get_bus_index("Master")
	var si := AudioServer.get_bus_index("SFX")
	_check(mi >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(mi), linear_to_db(0.4)), "Master バスの db が変わる", "= %.2f db" % AudioServer.get_bus_volume_db(mi))
	_check(si >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(si), linear_to_db(0.2)), "SFX バスの db が変わる")
	_check(is_equal_approx(player.get_sensitivity_scale(), 1.7), "player に感度が届く", "= %.2f" % player.get_sensitivity_scale())
	_check(is_equal_approx(vhs.get_intensity(), 0.8), "VhsLayer に強さが届く", "= %.2f" % vhs.get_intensity())

	# 画面揺れ切り: shake() が無視される
	player._shake_amount = 0.0
	player.shake(1.0, 0.5)
	_check(is_equal_approx(player._shake_amount, 0.0), "画面揺れ切で shake() が効かない")
	Settings.screen_shake = true
	player.shake(1.0, 0.5)
	_check(player._shake_amount > 0.5, "画面揺れ入なら効く")
	player._shake_amount = 0.0

	# 音量 0 はミュート
	Settings.volume_sfx = 0.0
	Settings.apply()
	_check(AudioServer.is_bus_mute(si), "音量 0 でミュートになる")

	# 設定画面の操作: 上下で移動、左右で値が動く
	hud._open_pause()
	hud._activate_pause(1)
	await get_tree().create_timer(0.3, true).timeout
	_check(hud._pause_page == 1, "設定ページが開く")
	hud._settings_index = 0
	var before_sens: float = Settings.mouse_sensitivity
	hud._nudge_setting(1)
	_check(Settings.mouse_sensitivity > before_sens, "右で感度が上がる", "%.1f -> %.1f" % [before_sens, Settings.mouse_sensitivity])
	# 2回目に開いても行が作り直されて値が出る(queue_free の取り残し回帰)
	hud._show_pause_page(0)
	hud._activate_pause(1)
	await get_tree().create_timer(0.2, true).timeout
	var row1 := hud._settings_rows.get_child(1) as HBoxContainer
	_check(hud._settings_rows.get_child_count() == hud.settings_items.size(), "2回目でも行数が増えない", "= %d" % hud._settings_rows.get_child_count())
	_check((row1.get_child(2) as Label).text != "", "2回目でも値が出る", "= 「%s」" % (row1.get_child(2) as Label).text)
	hud._settings_index = hud.SETTING_KEYS.find(&"shake")
	var before_shake: bool = Settings.screen_shake
	hud._activate_setting()
	_check(Settings.screen_shake != before_shake, "決定でトグルが反転する")
	hud._settings_index = hud.settings_items.size() - 1
	hud._activate_setting()
	_check(hud._pause_page == 0, "「戻る」でポーズ本体に戻る")
	hud._close_pause()
	await get_tree().create_timer(0.2, false).timeout

	# 後片付け: 元の設定に戻して保存
	Settings.mouse_sensitivity = backup["sens"]
	Settings.pad_sensitivity = backup["pad"]
	Settings.volume_master = backup["m"]
	Settings.volume_sfx = backup["s"]
	Settings.volume_ambient = backup["a"]
	Settings.vhs_intensity = backup["v"]
	Settings.screen_shake = backup["shake"]
	Settings.show_hints = backup["hints"]
	Settings.seen_hint = backup["seen"]
	Settings.apply()
	Settings.save()

	# 17) タイトルの到達エンディング表示
	var pcf := ConfigFile.new()
	pcf.set_value("endings", "morning", true)
	pcf.set_value("endings", "substitute", true)
	pcf.save(Settings.PROGRESS_PATH)
	var reached := Settings.reached_endings()
	_check(reached[0] and not reached[1] and reached[2] and not reached[3], "progress.cfg を読める")
	_check(Settings.reached_count() == 2, "到達数 = 2", "= %d" % Settings.reached_count())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PROGRESS_PATH))
	_check(Settings.reached_count() == 0, "progress.cfg が無ければ 0/4")

	# 18) ゲームパッド
	await get_tree().create_timer(0.3, false).timeout

	# 18a) 左スティックで歩く(軸 1 = 前後)
	player.teleport(Vector3(0, 0.05, 4.0), 0.0, 0.0)
	await get_tree().create_timer(0.3, false).timeout
	_pad_axis(1, -1.0)                                  # 上に倒す = 前進
	await get_tree().create_timer(0.8, false).timeout
	var pa: Vector3 = player.global_position
	await get_tree().create_timer(1.0, false).timeout
	var pb: Vector3 = player.global_position
	_pad_center()
	var pad_speed: float = Vector2(pb.x - pa.x, pb.z - pa.z).length()
	_check(absf(pad_speed - 2.5) < 0.2, "左スティックで歩く", "= %.2f m/s" % pad_speed)
	_check(pb.z < pa.z, "倒した向きに進む", "z %.2f -> %.2f" % [pa.z, pb.z])

	# 18b) 左スティックを戻すと止まる
	await get_tree().create_timer(0.6, false).timeout
	var ps: Vector3 = player.global_position
	await get_tree().create_timer(0.5, false).timeout
	_check(ps.distance_to(player.global_position) < 0.05, "中立に戻すと止まる")

	# 18c) 右スティックで視点が回る(軸 2 = 左右)
	player.teleport(Vector3(0, 0.05, 0.0), 0.0, 0.0)
	await get_tree().create_timer(0.3, false).timeout
	var yaw0: float = player.rotation.y
	_pad_axis(2, 1.0)                                   # 右に倒す
	await get_tree().create_timer(0.8, false).timeout
	_pad_center()
	await get_tree().create_timer(0.2, false).timeout
	var dyaw: float = angle_difference(yaw0, player.rotation.y)
	_check(dyaw < -0.3, "右スティックで右を向く", "Δyaw = %.2f rad" % dyaw)

	# 18d) デッドゾーン内は無視する
	player.teleport(Vector3(0, 0.05, 0.0), 0.0, 0.0)
	await get_tree().create_timer(0.3, false).timeout
	yaw0 = player.rotation.y
	_pad_axis(2, 0.15)                                  # pad_deadzone 0.2 より小さい
	await get_tree().create_timer(0.6, false).timeout
	_pad_center()
	_check(absf(angle_difference(yaw0, player.rotation.y)) < 0.02, "デッドゾーン内は動かない")

	# 18e) 上下の視点(軸 3)とピッチの上限
	yaw0 = player.rotation.y
	var pitch0: float = player.get_camera().global_rotation.x
	_pad_axis(3, -1.0)                                  # 上に倒す = 上を向く
	await get_tree().create_timer(0.6, false).timeout
	_pad_center()
	await get_tree().create_timer(0.2, false).timeout
	_check(player.get_camera().global_rotation.x > pitch0 + 0.2, "右スティックで上を向く")
	_pad_axis(3, -1.0)
	await get_tree().create_timer(2.5, false).timeout   # 上限まで倒し続ける
	_pad_center()
	_check(player.get_camera().global_rotation.x <= deg_to_rad(player.pitch_limit_deg) + 0.01, "ピッチが上限で止まる", "= %.1f 度" % rad_to_deg(player.get_camera().global_rotation.x))

	# 18f) パッド感度の倍率が効く
	player.teleport(Vector3(0, 0.05, 0.0), 0.0, 0.0)
	player.set_pad_sensitivity_scale(0.5)
	await get_tree().create_timer(0.3, false).timeout
	yaw0 = player.rotation.y
	_pad_axis(2, 1.0)
	await get_tree().create_timer(0.4, false).timeout   # 感度 2.0 でも PI を超えない長さ
	_pad_center()
	await get_tree().create_timer(0.2, false).timeout
	var slow: float = absf(angle_difference(yaw0, player.rotation.y))
	player.set_pad_sensitivity_scale(2.0)
	player.teleport(Vector3(0, 0.05, 0.0), 0.0, 0.0)
	await get_tree().create_timer(0.3, false).timeout
	yaw0 = player.rotation.y
	_pad_axis(2, 1.0)
	await get_tree().create_timer(0.4, false).timeout
	_pad_center()
	await get_tree().create_timer(0.2, false).timeout
	var fast: float = absf(angle_difference(yaw0, player.rotation.y))
	_check(fast > slow * 3.0, "感度 2.0 は 0.5 より大きく回る", "%.2f -> %.2f rad" % [slow, fast])
	player.set_pad_sensitivity_scale(1.0)

	# 18g) A ボタンで調べる
	player.teleport(Vector3(0, 0.05, -3.8), 0.0, -7.0)
	await get_tree().create_timer(0.5, false).timeout
	var pad_fired := {"n": 0}
	if player.focus:
		player.focus.interacted.connect(func(_p: Node3D) -> void: pad_fired["n"] += 1)
	_pad_button(JOY_BUTTON_A, true)
	await get_tree().create_timer(0.2, false).timeout
	_pad_button(JOY_BUTTON_A, false)
	await get_tree().create_timer(0.2, false).timeout
	_check(pad_fired["n"] == 1, "A ボタンで調べる", "= %d 回" % pad_fired["n"])
	hud._dlg_active = false
	await get_tree().create_timer(0.3, false).timeout

	# 18h) プロンプト表記が [E] ⇔ [A] で切り替わる
	_check(UiTheme.using_joypad, "直前の入力がパッドだと覚えている")
	_check(UiTheme.key_name(&"interact") == "A", "パッド中は A", "= %s" % UiTheme.key_name(&"interact"))
	await get_tree().create_timer(0.3, false).timeout
	_check(hud._interact_key == "A", "HUD のプロンプトも A", "= %s" % hud._interact_key)
	var kev := InputEventKey.new()
	kev.physical_keycode = KEY_W
	kev.pressed = true
	Input.parse_input_event(kev)
	await get_tree().create_timer(0.3, false).timeout
	kev.pressed = false
	Input.parse_input_event(kev)
	_check(not UiTheme.using_joypad, "キーを叩くとキーボードに戻る")
	_check(UiTheme.key_name(&"interact") == "E", "キーボード中は E", "= %s" % UiTheme.key_name(&"interact"))
	await get_tree().create_timer(0.3, false).timeout
	_check(hud._interact_key == "E", "HUD のプロンプトも E に戻る", "= %s" % hud._interact_key)
	_pad_center()

	# 18i) B はゲーム中に押してもポーズを開かない(開くのは Esc / Start だけ)
	await get_tree().create_timer(0.3, false).timeout
	_check(not hud.is_paused(), "前提: ポーズしていない")
	_pad_button(JOY_BUTTON_B, true)
	await get_tree().create_timer(0.3, false).timeout
	_pad_button(JOY_BUTTON_B, false)
	await get_tree().create_timer(0.2, false).timeout
	_check(not hud.is_paused(), "B ではポーズが開かない")
	_pad_button(JOY_BUTTON_START, true)
	await get_tree().create_timer(0.2, true).timeout
	_pad_button(JOY_BUTTON_START, false)
	await get_tree().create_timer(0.2, true).timeout
	_check(hud.is_paused(), "Start ならポーズが開く")

	# 18j) メニュー内では B が「戻る」
	hud._activate_pause(1)
	await get_tree().create_timer(0.2, true).timeout
	_check(hud._pause_page == 1, "前提: 設定ページ")
	_pad_button(JOY_BUTTON_B, true)
	await get_tree().create_timer(0.2, true).timeout
	_pad_button(JOY_BUTTON_B, false)
	await get_tree().create_timer(0.2, true).timeout
	_check(hud._pause_page == 0, "設定で B を押すとポーズ本体に戻る")
	_pad_button(JOY_BUTTON_B, true)
	await get_tree().create_timer(0.2, true).timeout
	_pad_button(JOY_BUTTON_B, false)
	await get_tree().create_timer(0.2, false).timeout
	_check(not hud.is_paused(), "ポーズ本体で B を押すと閉じる")
	_pad_center()

	# 19) 数字入力(金庫のダイヤル / 電話の番号)
	await get_tree().create_timer(0.3, false).timeout

	# 19a) 桁を回して確定する。1009 を入れる。
	var code_task := {"v": "pending"}
	_run_code_input(code_task, "金庫", 4)
	await get_tree().create_timer(0.4, false).timeout
	_check(hud.is_code_open(), "入力 UI が開く")
	_check(hud.blocks_player(), "入力中はプレイヤーが動けない")
	_check(hud._code_values.size() == 4, "桁数が 4", "= %d" % hud._code_values.size())
	_check(hud._code_digit == 0, "最初は 1 桁目")

	# 1 桁目 = 1(上に1回)
	await _tap(&"ui_up")
	_check(hud._code_values[0] == 1, "上で数字が増える", "= %d" % hud._code_values[0])
	# 2 桁目へ移って 0 のまま、3 桁目へ
	await _tap(&"ui_right")
	_check(hud._code_digit == 1, "右で次の桁へ", "= %d 桁目" % (hud._code_digit + 1))
	await _tap(&"ui_right")
	# 3 桁目 = 0、4 桁目 = 9(下に1回で 0 -> 9 に巻き戻る)
	await _tap(&"ui_right")
	_check(hud._code_digit == 3, "4 桁目まで移動")
	await _tap(&"ui_down")
	_check(hud._code_values[3] == 9, "下で 0 から 9 に巻き戻る", "= %d" % hud._code_values[3])
	await _tap(&"ui_right")
	_check(hud._code_digit == 0, "端で 1 桁目に戻る")
	await _tap(&"ui_left")
	_check(hud._code_digit == 3, "左でも巻き戻る")

	await _tap(&"advance")
	await get_tree().create_timer(0.3, false).timeout
	_check(not hud.is_code_open(), "決定で閉じる")
	_check(String(code_task["v"]) == "1009", "入れた数字が返る", "= 「%s」" % str(code_task["v"]))

	# 19b) キャンセルは空文字
	await get_tree().create_timer(0.3, false).timeout
	var code_task2 := {"v": "pending"}
	_run_code_input(code_task2, "番号", 4)
	await get_tree().create_timer(0.4, false).timeout
	await _tap(&"ui_up")
	await _tap(&"ui_cancel")
	await get_tree().create_timer(0.3, false).timeout
	_check(not hud.is_code_open(), "キャンセルで閉じる")
	_check(String(code_task2["v"]) == "", "キャンセルは空文字", "= 「%s」" % str(code_task2["v"]))

	# 19c) Dialogue 経由でも同じ
	await get_tree().create_timer(0.3, false).timeout
	var code_task3 := {"v": "pending"}
	_run_dialogue_code(code_task3, "金庫", 4)
	await get_tree().create_timer(0.4, false).timeout
	_check(hud.is_code_open(), "Dialogue.code_input が UI を出す")
	_check(Dialogue.busy, "入力中は Dialogue.busy")
	await _tap(&"ui_down")
	await _tap(&"advance")
	await get_tree().create_timer(0.3, false).timeout
	_check(String(code_task3["v"]) == "9000", "Dialogue 経由でも値が返る", "= 「%s」" % str(code_task3["v"]))
	_check(not Dialogue.busy, "終わると busy が下りる")

	print("== %s (fail %d) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)

# ---------------------------------------------------------------- スクリーンショット

func _run_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.2, false).timeout

	# 1) 素の HUD
	player.teleport(Vector3(0, 0.05, -0.6), 0.0, -3.0)
	await get_tree().create_timer(0.6, false).timeout
	await _shot(dir, "01_hud")

	# 2) フォーカス時のプロンプト
	player.teleport(Vector3(0, 0.05, -3.8), 0.0, -7.0)
	await get_tree().create_timer(0.5, false).timeout
	await _shot(dir, "02_prompt")

	# 3) 長押しリング
	hud.set_hold_progress(0.62)
	await get_tree().create_timer(0.2, false).timeout
	await _shot(dir, "03_hold")
	hud.set_hold_progress(0.0)

	# 4) 会話ボックス
	Dialogue.say("社長", "線香は絶やすなよ。一本が一時間ももたん。切らしたら取りに行け。")
	await get_tree().create_timer(1.1, false).timeout
	await _shot(dir, "04_dialogue")
	hud._dlg_active = false
	await get_tree().create_timer(0.3, false).timeout

	# 5) 独白(話者なし)
	Dialogue.monologue("……線香の匂いが、さっきより濃い。")
	await get_tree().create_timer(1.4, false).timeout
	await _shot(dir, "05_monologue")
	hud._dlg_active = false
	await get_tree().create_timer(0.3, false).timeout

	# 6) 選択肢
	Dialogue.choose("小窓を開けさせるか", ["断る", "開けさせる"])
	await get_tree().create_timer(0.5, false).timeout
	await _shot(dir, "06_choice")
	hud._choice_result = 0
	await get_tree().create_timer(0.4, false).timeout

	# 7) 手紙リーダ
	Dialogue.note("祖母の日記 一", "　十月三日。\n　三毛がまた戻ってきた。首輪がない。\n　誠は猫をきらう。あの子は昔からそうだ。\n　わたしが死んだら、この子たちはどうなるのだろう。\n\n　十月九日。\n　夜、廊下で足音がした。誠ではない。")
	await get_tree().create_timer(0.8, false).timeout
	await _shot(dir, "07_note")
	hud._note_open = false
	await get_tree().create_timer(0.4, false).timeout

	# 8) クリップボード
	Tasks.set_task(&"lock_back", "勝手口の鍵を閉める")
	Tasks.set_task(&"water", "供花の水を替える")
	hud.toggle_clipboard()
	await get_tree().create_timer(0.4, false).timeout
	await _shot(dir, "08_clipboard")
	hud.toggle_clipboard()
	await get_tree().create_timer(0.3, false).timeout

	# 9) 運搬中の見た目
	player.give_item(&"dry_ice", true)
	player.teleport(Vector3(0, 0.05, -2.2), 6.0, -9.0)
	await get_tree().create_timer(0.7, false).timeout
	await _shot(dir, "09_carry")

	# 9b) 両手が塞がっているときのトースト
	player.give_item(&"water", true)      # 拒否されて HUD に出るはず
	await get_tree().create_timer(0.35, false).timeout
	await _shot(dir, "09b_hands_full")
	player.take_item(&"dry_ice")

	# 10) VHS グリッチ
	vhs.glitch(0.9)
	await get_tree().create_timer(0.3, false).timeout
	await _shot(dir, "10_glitch")

	# 11) VHS 最大
	vhs.set_intensity(0.95)
	await get_tree().create_timer(1.1, false).timeout
	await _shot(dir, "11_vhs_high")
	vhs.set_intensity(0.32)
	await get_tree().create_timer(0.6, false).timeout

	# 12) ポーズ
	hud._open_pause()
	await get_tree().create_timer(0.4, true).timeout   # ポーズ中なので process_always
	await _shot(dir, "12_pause")
	hud._close_pause()
	await get_tree().create_timer(0.3, false).timeout

	# 13) タイトル(演出の途中と、メニューが出た後)
	var title: Node = load(TITLE_PATH).instantiate()
	viewport.add_child(title)
	await get_tree().create_timer(0.9, false).timeout
	await _shot(dir, "13_title_intro")
	await get_tree().create_timer(3.2, false).timeout
	await _shot(dir, "14_title")
	title.queue_free()
	await get_tree().create_timer(0.3, false).timeout

	# 15) エンディング
	var ending: Node = load(ENDING_PATH).instantiate()
	viewport.add_child(ending)
	ending.play(&"morning", "朝", ["空が白んだ。", "霊柩車の屋根に、猫が一匹座っている。"])
	await get_tree().create_timer(3.4, false).timeout
	await _shot(dir, "15_ending_lines")
	await get_tree().create_timer(6.0, false).timeout
	await _shot(dir, "16_ending_title")
	await get_tree().create_timer(3.0, false).timeout
	await _shot(dir, "17_ending_hint")

	ending.queue_free()
	await get_tree().create_timer(0.4, false).timeout

	# 18) 遺影エンド(show_portrait)
	var ending2: Node = load(ENDING_PATH).instantiate()
	viewport.add_child(ending2)
	var iei := "res://assets/textures/iei_photo_player.png"
	if ResourceLoader.exists(iei):
		ending2.show_portrait(load(iei))
	ending2.play(&"portrait", "遺影", ["目が覚めると、朝だった。", "祭壇の遺影が、自分の顔になっている。"])
	await get_tree().create_timer(3.6, false).timeout
	await _shot(dir, "18_ending_portrait")
	ending2.queue_free()
	await get_tree().create_timer(0.4, false).timeout

	# 19) 画面演出(darken / flash / fade)
	hud.darken(0.75, 0.3)
	ScreenFX.zoom_punch(0.9, 2.0)
	player.shake(0.6, 2.0)
	await get_tree().create_timer(0.6, false).timeout
	await _shot(dir, "19_darken_shake")
	hud.darken(0.0, 0.2)
	await hud.fade_out(0.4)
	await _shot(dir, "19b_fade_out")
	await hud.fade_in(0.4)

	await hud.fade_in(0.4)

	# 20) 押しても反応しない対象(金庫): 薄いプロンプト + 理由の文
	player.teleport(Vector3(-3.8, 0.05, -0.4), 0.0, -7.0)
	await get_tree().create_timer(0.6, false).timeout
	await _shot(dir, "22_blocked_prompt")
	Input.action_press(&"interact")
	await get_tree().create_timer(0.15, false).timeout
	Input.action_release(&"interact")
	await get_tree().create_timer(0.3, false).timeout
	await _shot(dir, "23_blocked_text")

	# 21) ただの物を見て押す
	player.teleport(Vector3(2.0, 0.05, 2.3), 180.0, -32.0)
	await get_tree().create_timer(0.6, false).timeout
	Input.action_press(&"interact")
	await get_tree().create_timer(0.15, false).timeout
	Input.action_release(&"interact")
	await get_tree().create_timer(0.3, false).timeout
	await _shot(dir, "24_nothing_here")

	# 22) 設定画面
	hud._open_pause()
	hud._activate_pause(1)
	await get_tree().create_timer(0.4, true).timeout   # ポーズ中なので process_always
	await _shot(dir, "25_settings")
	hud._settings_index = 4                            # VHS の強さを選んだ状態
	hud._update_settings_rows()
	await get_tree().create_timer(0.3, true).timeout
	await _shot(dir, "26_settings_vhs")
	hud._close_pause()
	await get_tree().create_timer(0.3, false).timeout

	# 23) 初回の操作ヒント
	player.teleport(Vector3(0, 0.05, -1.0), 0.0, -3.0)
	hud.show_controls_hint(6.0)
	await get_tree().create_timer(2.0, false).timeout
	await _shot(dir, "27_controls_hint")

	# 24) タイトルの到達エンディング(4つ中2つ到達した状態)
	var pcf := ConfigFile.new()
	pcf.set_value("endings", "morning", true)
	pcf.set_value("endings", "substitute", true)
	pcf.save(Settings.PROGRESS_PATH)
	var title2: Node = load(TITLE_PATH).instantiate()
	title2.skip_intro = true
	viewport.add_child(title2)
	await get_tree().create_timer(1.6, false).timeout
	await _shot(dir, "28_title_endings")
	title2.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PROGRESS_PATH))
	await get_tree().create_timer(0.3, false).timeout

	# 25) パッド: プロンプト表記が [A] になる
	_pad_button(JOY_BUTTON_A, true)
	await get_tree().create_timer(0.1, false).timeout
	_pad_button(JOY_BUTTON_A, false)
	player.teleport(Vector3(0, 0.05, -3.8), 0.0, -7.0)
	await get_tree().create_timer(0.7, false).timeout
	await _shot(dir, "29_prompt_pad")
	hud._dlg_active = false
	await get_tree().create_timer(0.3, false).timeout

	# 26) パッド視点の感度が並んだ設定画面
	hud._open_pause()
	hud._activate_pause(1)
	hud._settings_index = hud.SETTING_KEYS.find(&"pad")
	hud._update_settings_rows()
	await get_tree().create_timer(0.4, true).timeout   # ポーズ中なので process_always
	await _shot(dir, "30_settings_pad")
	hud._close_pause()
	await get_tree().create_timer(0.3, false).timeout

	# 27) 数字入力(金庫のダイヤル)
	var ct := {"v": "pending"}
	_run_code_input(ct, "金庫", 4)
	await get_tree().create_timer(0.5, false).timeout
	hud._code_values[0] = 1
	hud._code_values[1] = 0
	hud._code_values[2] = 0
	hud._code_digit = 2
	hud._update_code_digits()
	await get_tree().create_timer(0.3, false).timeout
	await _shot(dir, "31_code_input")
	hud._code_result = ""
	hud._code_done = true
	await get_tree().create_timer(0.4, false).timeout

	# 28) 真相の回想(画像あり / 画像なし)
	var rec: Node = load(ENDING_PATH).instantiate()
	viewport.add_child(rec)
	# recap_*.png はまだ models 待ちなので、有り物のテクスチャで代用して見え方を確かめる
	var stand_in: Array = []
	for t in ["res://assets/textures/guest_book.png", "res://assets/textures/iei_photo.png"]:
		stand_in.append(load(t) if ResourceLoader.exists(t) else null)
	stand_in.append(null)     # 3 枚目は画像なし(黒に文だけ)
	rec.show_recap(stand_in, [
		"十月九日。十九匹の猫が、軽トラで運ばれた。",
		"その週、キヨは首を絞められて死んだ。",
		"……",
	])
	await get_tree().create_timer(2.6, false).timeout
	await _shot(dir, "32_recap_image")
	await get_tree().create_timer(5.3, false).timeout
	await _shot(dir, "33_recap_second")
	await get_tree().create_timer(5.3, false).timeout
	await _shot(dir, "34_recap_no_image")
	rec.queue_free()
	await get_tree().create_timer(0.4, false).timeout

	print("shots done: %s" % dir)
	get_tree().quit()

func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [dir, name]
	img.save_png(path)
	print("shot: %s" % path)
