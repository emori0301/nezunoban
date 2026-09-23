class_name Scares
extends Node
## 脅かしの部品。1 関数 = 1 つの脅かし。director / timeline から呼ぶ。
## ここには「時刻」は書かない。いつ出すかは timeline.gd が決める。
##
## 追加の脅かし(docs/design.md v0.2「追加の脅かし」)はすべてここに実装してある。
## `random_scare()` が異変度と時刻と居場所を見て、条件に合うものを 1 つ選んで撃つ。

const MODEL_DIR := "res://assets/models/"

var dir                                   ## Director(循環参照を避けるため型を付けない)
var rng := RandomNumberGenerator.new()

var _spawned: Array[Node] = []            ## 後で片付ける演出ノード
var _ambient_room: StringName = &""
var _second_steps: bool = false
var _second_steps_t: float = 0.0
var _robe_visits: int = 0
var _chairs_turned: int = 0
var _recent: Array[StringName] = []       ## 直近に出した脅かし(連続で同じものを出さない)


func _ready() -> void:
	rng.randomize()
	set_process(true)


# ============================================================ 小道具

func sys(n: StringName) -> Node:
	return SystemsInstaller.find(n)


func building() -> Building:
	return Game.level as Building


func player() -> Node3D:
	return Game.player


func player_pos() -> Vector3:
	var p := player()
	return p.global_position if p else Vector3.ZERO


func head_pos() -> Vector3:
	return player_pos() + Vector3(0, 1.6, 0)


func forward() -> Vector3:
	var p := player()
	if p == null:
		return Vector3.FORWARD
	return -p.global_transform.basis.z


func current_room() -> StringName:
	var b := building()
	return b.current_room if b else &""


func level_root() -> Node:
	var b := building()
	return b if b else get_tree().current_scene


## 演出用のノードをワールドに足す(片付けられるように控えておく)
func attach(n: Node3D) -> Node3D:
	var root := level_root()
	if root == null:
		return n
	root.add_child(n)
	_spawned.append(n)
	return n


func clear_spawned() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()


func vhs() -> Node:
	var list := get_tree().get_nodes_in_group(&"vhs")
	return list[0] if not list.is_empty() else null


func glitch(strength: float = 0.4) -> void:
	var v := vhs()
	if v and v.has_method(&"glitch"):
		v.glitch(strength)


func stinger(db: float = -4.0) -> void:
	Audio.play(StringName("stinger_%d" % rng.randi_range(1, 3)), db)


func yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(atan2(-d.x, -d.z))


# ============================================================ 人影・置き物

## glb を真っ黒にした「人影」を置く。cctv_only なら監視モニターにだけ映る。
func spawn_figure(model: String, pos: Vector3, yaw_deg: float, cctv_only: bool = false,
		anim: StringName = &"idle", brightness: float = -1.0) -> Node3D:
	# CCTV にだけ映す人影は、式場が灯明だけで真っ暗なので完全な黒だと何も見えない。
	# わずかに明るく、ほんの少し自発光させて「暗いのに形が分かる」ところに合わせる。
	if brightness < 0.0:
		brightness = 0.16 if cctv_only else 0.015
	var root := Node3D.new()
	root.name = "Figure_" + model
	root.position = pos
	root.rotation_degrees = Vector3(0, yaw_deg, 0)
	var path := MODEL_DIR + model + ".glb"
	if ResourceLoader.exists(path):
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(inst)
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation(String(anim)):
			ap.play(String(anim))
		_blacken(inst, brightness)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 1.7, 0.3)
		mi.mesh = bm
		mi.position.y = 0.85
		mi.material_override = SystemUtil.flat_material(Color(brightness, brightness, brightness * 1.2))
		root.add_child(mi)
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		vi.layers = SystemUtil.LAYER_CCTV_ONLY if cctv_only else SystemUtil.LAYER_DEFAULT
		if vi is GeometryInstance3D:
			(vi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return attach(root) as Node3D


func _blacken(root: Node, brightness: float = 0.015) -> void:
	var col := Color(brightness, brightness, brightness * 1.15)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mat.roughness = 1.0
			mat.metallic = 0.0
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			# 真っ暗な部屋でも輪郭が出るように、ごくわずかに自発光させる
			if brightness > 0.05:
				mat.emission_enabled = true
				mat.emission = col
				mat.emission_energy_multiplier = 0.55
			mi.set_surface_override_material(i, mat)


## 座布団などの小物を足す。
func spawn_prop(model: String, pos: Vector3, yaw_deg: float = 0.0,
		size: Vector3 = Vector3(0.55, 0.08, 0.55), color: Color = Color(0.35, 0.16, 0.16)) -> Prop:
	var p := Prop.new()
	p.placeholder_size = size
	p.placeholder_color = color
	p.add_collision = false
	p.position = pos
	p.rotation_degrees = Vector3(0, yaw_deg, 0)
	p.model_name = model
	attach(p)
	return p


# ============================================================ 部屋の環境音

const ROOM_AMBIENT := {
	&"Room_Genkan": &"amb_room",
	&"Room_Office": &"amb_fluorescent",
	&"Room_Hall": &"amb_fluorescent",
	&"Room_Shikijo": &"amb_shikijo",
	&"Room_Hikaeshitsu": &"amb_tatami",
	&"Room_Toilet": &"amb_room",
	&"Room_Backyard": &"amb_freezer",
	&"Room_Yukan": &"amb_room",
	&"Room_Outside": &"amb_outside",
}


func set_room_ambience(room: StringName) -> void:
	var want: StringName = ROOM_AMBIENT.get(room, &"amb_room")
	if want == _ambient_room:
		return
	if _ambient_room != &"":
		Audio.stop_ambient(_ambient_room, 1.2)
	_ambient_room = want
	Audio.ambient(want, -12.0 if want == &"amb_fluorescent" else -9.0, 1.4)


## 04:00 の全消灯用。館内の照明を落としたあと、窓から入る月明かりだけを足す。
## 真っ暗だと廊下を歩けず「怖い」より「見えない」になるので、輪郭が分かる下限にしてある。
const MOONLIGHT := [
	[Vector3(-10.0, 2.2, 0.5), 7.0],      # 玄関(ガラス戸)
	[Vector3(-8.0, 2.1, 8.6), 6.5],       # 事務所(窓)
	[Vector3(0.6, 2.0, 2.4), 5.0],        # トイレ(窓)
	[Vector3(-1.5, 2.2, 0.2), 7.0],       # 廊下(西)
	[Vector3(6.4, 2.2, -3.2), 7.0],       # 廊下(北の枝)
	[Vector3(0.0, 2.2, -6.6), 7.0],       # バックヤード(勝手口)
	[Vector3(12.8, 2.1, 2.6), 8.0],       # 式場(南の窓)
]

var _moon: Array[Node3D] = []

func set_moonlight(on: bool) -> void:
	if on and _moon.is_empty():
		var root := level_root()
		if root == null:
			return
		for m in MOONLIGHT:
			var l := OmniLight3D.new()
			l.light_color = Color(0.52, 0.62, 0.86)
			l.light_energy = 0.38
			l.omni_range = float(m[1])
			l.omni_attenuation = 1.4
			l.shadow_enabled = false
			l.position = m[0]
			root.add_child(l)
			_moon.append(l)
			_spawned.append(l)
	elif not on:
		for l in _moon:
			if is_instance_valid(l):
				l.queue_free()
				_spawned.erase(l)
		_moon.clear()


## 04:45〜05:00 の夜明け。窓とガラス戸の外に青白い光を置いて 0 から上げる。
## 真っ暗のまま朝を迎えると落差が出ないので、エンディングのフェードは
## 「明るくなった式場」から始まるようにする。
const DAWN_LIGHTS := [
	[Vector3(13.0, 2.1, 4.8), 2.6, 15.0],    # 式場の南窓の外
	[Vector3(-12.3, 1.9, 0.0), 2.2, 13.0],   # 玄関のガラス戸の外
	[Vector3(-8.0, 1.9, 11.2), 1.4, 10.0],   # 事務所の窓の外
	[Vector3(0.7, 1.9, 4.9), 0.9, 7.0],      # トイレの窓の外
]
const DAWN_COLOR := Color(0.72, 0.82, 1.0)

var _dawn: Array[Node3D] = []

func start_dawn(duration: float) -> void:
	if not _dawn.is_empty():
		return
	var root := level_root()
	if root == null:
		return
	var dur := maxf(duration, 0.05)
	for d in DAWN_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = DAWN_COLOR
		l.light_energy = 0.0
		l.omni_range = float(d[2])
		l.omni_attenuation = 1.0
		l.shadow_enabled = false
		l.position = d[0]
		root.add_child(l)
		_dawn.append(l)
		_spawned.append(l)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		tw.tween_property(l, "light_energy", float(d[1]), dur)
	# 月明かりは引いていく
	for m in _moon:
		if is_instance_valid(m):
			create_tween().tween_property(m, "light_energy", 0.0, dur * 0.8)
	# VHS の色味を少し寒色へ
	var v := vhs()
	if v and v.has_method(&"set_tint"):
		v.set_tint(Color(0.88, 0.94, 1.08))


## --time= で 04:45 より後から始めたとき、いきなり明るい状態にする。
func dawn_now() -> void:
	start_dawn(0.05)


func stop_room_ambience() -> void:
	if _ambient_room != &"":
		Audio.stop_ambient(_ambient_room, 0.8)
		_ambient_room = &""


# ============================================================ 追加の脅かし

## 廊下を歩くと後ろで扉が閉まる
func door_behind() -> bool:
	var b := building()
	if b == null:
		return false
	var p := player_pos()
	var f := forward()
	var best: Door = null
	var best_d := 99.0
	for name in b.all_doors():
		var d: Door = b.get_door(name)
		if d == null:
			continue
		var to: Vector3 = d.global_position - p
		to.y = 0.0
		var dist := to.length()
		if dist < 2.5 or dist > 14.0:
			continue
		if to.normalized().dot(f) > -0.15:
			continue                      # 視界の中の扉は使わない
		if d.is_open and dist < best_d:
			best = d
			best_d = dist
	if best == null:
		return false
	best.slam()
	glitch(0.25)
	return true


## 控室の座布団が1枚、廊下に落ちている
func zabuton_in_hall() -> bool:
	if Game.get_flag(&"scare_zabuton_hall", false):
		return false
	Game.set_flag(&"scare_zabuton_hall", true)
	spawn_prop("zabuton", Vector3(1.6, 0.03, 0.15), rng.randf_range(-40.0, 40.0))
	Audio.play_at(&"tatami_creak", Vector3(1.6, 0.2, 0.15), -8.0)
	return true


## 座布団が棺の前に3枚並ぶ(異変度 >= 1)
func zabuton_before_coffin() -> bool:
	if Game.get_flag(&"scare_zabuton_coffin", false):
		return false
	Game.set_flag(&"scare_zabuton_coffin", true)
	for i in 3:
		spawn_prop("zabuton", Vector3(15.45, 0.03, -1.5 + i * 1.0), 90.0)
	Dialogue.monologue(ScriptText.M_ZABUTON)
	return true


## 式場の折りたたみ椅子が1脚ずつ棺の方を向く
func chairs_turn_to_coffin() -> bool:
	var root := level_root()
	if root == null:
		return false
	var coffin_pos := Vector3(16.9, 0.0, -0.5)
	var turned := 0
	for n in root.find_children("Chair_*", "Node3D", true, false):
		var p3 := n as Node3D
		if p3 == null or p3.get_meta(&"turned", false):
			continue
		p3.set_meta(&"turned", true)
		var y := yaw_to(p3.global_position, coffin_pos)
		var tw := create_tween()
		tw.tween_property(p3, "rotation_degrees:y", y, 0.01)
		turned += 1
		_chairs_turned += 1
		if turned >= 4:
			break
	if turned == 0:
		return false
	Audio.play_at(&"chair_drag", Vector3(12.0, 0.3, -0.5), -6.0)
	return true


## 23:00 のモニター: 椅子が1脚引き出されている
func chair_pulled_out() -> void:
	var root := level_root()
	if root == null:
		return
	var chair := root.find_child("Chair_2_3", true, false) as Node3D
	if chair == null:
		chair = root.find_child("Chair_1_2", true, false) as Node3D
	if chair == null:
		return
	chair.position.x -= 0.4
	chair.rotation_degrees.y += 22.0
	Audio.play_at(&"chair_drag", chair.global_position, -2.0)


## 囁き(すぐ後ろ)
func whisper() -> bool:
	var p := head_pos() - forward() * 0.9
	Audio.play_at(StringName("whisper_%d" % rng.randi_range(1, 3)), p, 0.0, rng.randf_range(0.92, 1.04), 8.0)
	return true


## 天井の足音
func ceiling_steps() -> bool:
	var base := player_pos() + Vector3(0, 2.6, 0)
	for i in 3:
		var pos := base + Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
		Audio.play_at(StringName("footstep_ceiling_%d" % (i + 1)), pos, 0.0, 1.0, 12.0)
		await get_tree().create_timer(rng.randf_range(0.28, 0.45)).timeout
	if rng.randf() < 0.5:
		Dialogue.monologue(ScriptText.M_CEILING)
	return true


## 屋根裏の猫の声
func attic_meow() -> bool:
	var pos := player_pos() + Vector3(rng.randf_range(-1.5, 1.5), 2.7, rng.randf_range(-1.5, 1.5))
	Audio.play_at(StringName("cat_meow_%d" % rng.randi_range(1, 3)), pos, -2.0, 0.88, 14.0)
	return true


## 線香の煙が真横に流れる(風がないのに)
func smoke_sideways() -> bool:
	var inc := sys(&"incense_stand")
	if inc == null or not bool(inc.get(&"is_burning")):
		return false
	inc.call(&"set_wind", Vector3(0.9, 0, -0.4))
	await get_tree().create_timer(9.0).timeout
	if is_instance_valid(inc):
		inc.call(&"set_wind", Vector3.ZERO)
	return true


## 棺の小窓の内側の手形
func handprint() -> bool:
	var c := sys(&"coffin")
	if c == null or bool(c.get(&"has_handprint")):
		return false
	c.call(&"set_handprint", true)
	Audio.play_at(&"coffin_creak", c.global_position, -6.0)
	return true


## 事務所の壁掛け時計が逆回転する
func clock_reverse() -> bool:
	var root := level_root()
	if root == null:
		return false
	var clock := root.find_child("WallClock", true, false) as Node3D
	if clock == null:
		return false
	var pivot := clock.get_node_or_null(^"ReverseHands") as Node3D
	if pivot == null:
		var aabb := _world_aabb(clock)
		pivot = Node3D.new()
		pivot.name = "ReverseHands"
		clock.add_child(pivot)
		pivot.global_position = aabb.get_center() + clock.global_transform.basis.z.normalized() * 0.035
		pivot.global_rotation = clock.global_rotation
		for h in [[0.075, 0.010, 1.0], [0.105, 0.007, 2.4]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(float(h[1]), float(h[0]), 0.004)
			mi.mesh = bm
			mi.position = Vector3(0, float(h[0]) * 0.5, 0)
			mi.material_override = SystemUtil.flat_material(Color(0.05, 0.05, 0.06))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var arm := Node3D.new()
			arm.set_meta(&"rate", float(h[2]))
			arm.add_child(mi)
			pivot.add_child(arm)
	pivot.visible = true
	var t := 0.0
	while t < 8.0 and is_instance_valid(pivot):
		var d := get_process_delta_time()
		t += d
		for arm in pivot.get_children():
			(arm as Node3D).rotation_degrees.z += d * 60.0 * float(arm.get_meta(&"rate", 1.0))
		await get_tree().process_frame
	if rng.randf() < 0.8:
		Dialogue.monologue(ScriptText.M_CLOCK)
	return true


func _world_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := mi.global_transform * mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	if first and root is Node3D:
		out = AABB((root as Node3D).global_position, Vector3.ZERO)
	return out


## 廊下の蛍光灯が明滅し、暗い瞬間だけ突き当たりに立つ影が見える
func hall_flicker_shadow() -> bool:
	var b := building()
	if b == null:
		return false
	var fig := spawn_figure("kasha", Vector3(6.4, 0.0, -7.0), 0.0, false, &"idle")
	fig.visible = false
	b.flicker(&"Room_Hall", 2.4)
	for i in 5:
		await get_tree().create_timer(0.24).timeout
		fig.visible = not fig.visible
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(fig):
		fig.queue_free()
		_spawned.erase(fig)
	return true


## 廊下の突き当たりに立つ人影(見た1秒後に消える)
func hall_figure(model: String = "kasha", seconds: float = 1.4) -> void:
	var fig := spawn_figure(model, Vector3(6.4, 0.0, -7.1), 0.0, false, &"idle")
	glitch(0.35)
	Audio.play_at(&"kasha_growl", fig.global_position, -8.0)
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(fig):
		fig.queue_free()
		_spawned.erase(fig)
	stinger(-8.0)


## 湯灌室の白装束。入るたびに揺れ方が変わり、最後は落ちる。
func robe_sway() -> void:
	var root := level_root()
	if root == null:
		return
	var robe := root.find_child("Yukan_Robe", true, false) as Node3D
	if robe == null:
		return
	_robe_visits += 1
	var ap := robe.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("sway"):
		ap.play("sway")
		ap.speed_scale = clampf(0.6 + _robe_visits * 0.45, 0.6, 2.6)
		ap.seek(rng.randf_range(0.0, 3.9), true)
	else:
		var tw := create_tween().set_loops(3)
		var amp := clampf(3.0 + _robe_visits * 3.0, 3.0, 16.0)
		tw.tween_property(robe, "rotation_degrees:z", amp, 1.1)
		tw.tween_property(robe, "rotation_degrees:z", -amp, 1.1)
	Dialogue.monologue(ScriptText.M_YUKAN)


func robe_drop() -> void:
	var root := level_root()
	if root == null:
		return
	var robe := root.find_child("Yukan_Robe", true, false) as Node3D
	if robe == null:
		return
	var ap := robe.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("drop"):
		ap.speed_scale = 1.0
		ap.play("drop")
	else:
		var tw := create_tween()
		tw.tween_property(robe, "position:y", robe.position.y - 1.6, 0.9)
		tw.parallel().tween_property(robe, "rotation_degrees:x", 82.0, 0.9)
	stinger(-6.0)
	glitch(0.5)


## 濡れた足跡(廊下 → 式場)。0.42m 間隔で左右に振りながら棺の前まで続く。
func paw_prints() -> void:
	if Game.get_flag(&"scare_paw_prints", false):
		return
	Game.set_flag(&"scare_paw_prints", true)
	var tex: Texture2D = SystemUtil.load_texture("paw_print")
	var path: Array[Vector3] = [
		Vector3(3.6, 0.0, 0.30), Vector3(7.4, 0.0, 0.05), Vector3(11.0, 0.0, -0.25),
		Vector3(14.6, 0.0, -0.45), Vector3(16.3, 0.0, -0.58),
	]
	var step := 0.42
	var left := true
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b2: Vector3 = path[i + 1]
		var seg := b2 - a
		var n := maxi(int(seg.length() / step), 1)
		var y := yaw_to(a, b2)
		var side := Vector3(cos(deg_to_rad(y)), 0.0, -sin(deg_to_rad(y)))
		for k in n:
			var pos: Vector3 = a + seg * (float(k) / float(n))
			var d := _paw_decal(tex)
			d.position = pos + side * (0.075 if left else -0.075) + Vector3(0, 0.02, 0)
			d.rotation_degrees = Vector3(0, y, 0)
			attach(d)
			left = not left
	Dialogue.monologue(ScriptText.M_PAW)


## 濡れた足跡。暗い廊下でも見えるように、わずかに濡れ光らせる。
func _paw_decal(tex: Texture2D) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.texture_emission = tex
	d.emission_energy = 1.1
	d.modulate = Color(0.78, 0.88, 1.0)
	d.size = Vector3(0.22, 0.6, 0.22)
	d.albedo_mix = 1.0
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	return d


## 玄関の外に濡れた足跡(モニターの人影のあと)
func paw_prints_outside() -> void:
	var tex: Texture2D = SystemUtil.load_texture("paw_print")
	for i in 5:
		var d := _paw_decal(tex)
		d.position = Vector3(-12.0 - i * 0.32, 0.02, (0.08 if i % 2 == 0 else -0.08))
		d.rotation_degrees = Vector3(0, 90.0, 0)
		attach(d)


## ドライアイスを運んでいる間、1.5m 後ろに足音がついてくる
func set_second_footsteps(on: bool) -> void:
	_second_steps = on
	_second_steps_t = 0.0


func breath_behind() -> void:
	Audio.play_at(&"breath_close", head_pos() - forward() * 0.7, -4.0, 0.95, 6.0)


## 控室の TV に自分の後ろ姿が映る
func tv_player_back() -> bool:
	var tv := sys(&"tv")
	if tv == null:
		return false
	if not bool(tv.get(&"is_on")):
		tv.call(&"turn_on")
		await get_tree().create_timer(0.6).timeout
	tv.call(&"show_player_back", 4.0)
	glitch(0.3)
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(tv) and bool(tv.get(&"is_on")):
		tv.call(&"turn_off")
	return true


## モニターの玄関に、こちらに背を向けて立つ人影
func monitor_ghost_genkan() -> bool:
	var mon := sys(&"monitor")
	if mon == null:
		return false
	var fig := spawn_figure("npc_son", Vector3(-12.3, 0.0, -0.2), 18.0, true, &"idle", 0.2)
	mon.set(&"auto_switch", false)
	mon.call(&"switch_feed", 1)
	mon.call(&"glitch", 0.7)
	await get_tree().create_timer(9.0).timeout
	if is_instance_valid(fig):
		fig.queue_free()
		_spawned.erase(fig)
	if is_instance_valid(mon):
		mon.set(&"auto_switch", true)
	paw_prints_outside()
	return true


## 自販機の前に猫が5匹並んで座っている
func vending_cats() -> bool:
	if Game.get_flag(&"scare_vending_cats", false):
		return false
	var cats: Array = dir.npc_all(&"cat")
	if cats.is_empty():
		return false
	Game.set_flag(&"scare_vending_cats", true)
	for i in mini(cats.size(), 5):
		var c: Node = cats[i]
		if c == null or not c.has_method(&"sit_at"):
			continue
		c.call(&"sit_at", Vector3(-10.3, 0.0, 5.0 + i * 0.6), Vector3(1, 0, 0))
	Audio.play_at(StringName("cat_meow_%d" % rng.randi_range(1, 3)), Vector3(-10.3, 0.3, 6.2), -4.0)
	return true


## 芳名帳の最後の行に自分の名前
func guest_book_self_name() -> void:
	var gb := sys(&"guest_book")
	if gb == null or Game.get_flag(&"guest_book_named", false):
		return
	Game.set_flag(&"guest_book_named", true)
	gb.call(&"add_line", "　　　　　(滲んだ字)")
	gb.call(&"rustle")


# ============================================================ 毎フレーム

func _process(delta: float) -> void:
	if not _second_steps:
		return
	var p := player()
	if p == null:
		return
	var vel: Vector3 = p.get(&"velocity") if p.get(&"velocity") != null else Vector3.ZERO
	if vel.length() < 0.4:
		_second_steps_t = 0.0
		return
	_second_steps_t -= delta
	if _second_steps_t <= 0.0:
		_second_steps_t = 0.72
		var pos := player_pos() - forward() * 1.5
		Audio.play_at(StringName("step_lino_%d" % rng.randi_range(1, 4)), pos, 2.0, 0.94, 10.0)


# ============================================================ ランダムな脅かし

## 音だけで済む系統。夜の前半(〜00:00)はここからしか撃たない。
const QUIET_SCARES := [&"whisper", &"ceiling", &"attic_meow", &"door_behind"]

## 異変度と時刻と居場所を見て、条件に合う脅かしを1つ撃つ。
## quiet = true なら音だけの系統に絞る(前半は物を動かさない)。
func random_scare(quiet: bool = false) -> void:
	var lvl := Dread.level()
	var minutes := int(Clock.game_minutes)
	var room := current_room()
	var pool: Array[StringName] = []
	var add := func(id: StringName, weight: int) -> void:
		if quiet and not QUIET_SCARES.has(id):
			return
		for i in weight:
			pool.append(id)

	# どこでも出るもの
	add.call(&"whisper", 1 + lvl)
	add.call(&"ceiling", 1 + lvl)
	add.call(&"attic_meow", 2 if minutes >= 140 else 0)
	add.call(&"door_behind", 2 if minutes >= 60 else 1)
	# 部屋ごと
	match room:
		&"Room_Shikijo":
			add.call(&"chairs", 2 + lvl)
			add.call(&"smoke", 2)
			add.call(&"handprint", lvl if minutes >= 180 else 0)
			add.call(&"zabuton_coffin", 3 if lvl >= 1 and minutes >= 120 else 0)
		&"Room_Hall":
			add.call(&"hall_flicker", 1 + lvl if minutes >= 120 else 0)
			add.call(&"zabuton_hall", 2 if minutes >= 90 else 0)
		&"Room_Office":
			add.call(&"clock", 2 if minutes >= 300 else 0)
			add.call(&"monitor_genkan", 2 if minutes >= 120 else 0)
		&"Room_Hikaeshitsu":
			add.call(&"tv_back", 2 if minutes >= 160 else 0)
		&"Room_Outside":
			add.call(&"vending_cats", 3 if minutes >= 360 else 0)
	if pool.is_empty():
		return
	var pick: StringName = pool[rng.randi_range(0, pool.size() - 1)]
	# 直前と同じものは避ける
	if _recent.has(pick) and pool.size() > 3:
		pick = pool[rng.randi_range(0, pool.size() - 1)]
	_recent.append(pick)
	if _recent.size() > 3:
		_recent.pop_front()
	if Game.debug:
		print("[scare] %s %s room=%s dread=%d" % [Clock.hhmm(), pick, room, Dread.value])
	match pick:
		&"whisper": whisper()
		&"ceiling": ceiling_steps()
		&"attic_meow": attic_meow()
		&"door_behind": door_behind()
		&"chairs": chairs_turn_to_coffin()
		&"smoke": smoke_sideways()
		&"handprint": handprint()
		&"zabuton_coffin": zabuton_before_coffin()
		&"hall_flicker": hall_flicker_shadow()
		&"zabuton_hall": zabuton_in_hall()
		&"clock": clock_reverse()
		&"monitor_genkan": monitor_ghost_genkan()
		&"tv_back": tv_player_back()
		&"vending_cats": vending_cats()


# ============================================================ インタラクト用の小さな足場

## 台本で一時的に出す「調べる」点。Door や Futon を横取りしたいときに使う。
class Spot extends Interactable:
	var on_use: Callable = Callable()

	static func make(parent: Node, pos: Vector3, text: String, size: Vector3, cb: Callable) -> Spot:
		var s := Spot.new()
		s.prompt = text
		s.on_use = cb
		s.collision_layer = 2
		s.collision_mask = 0
		s.monitorable = true
		s.monitoring = false
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		s.add_child(cs)
		parent.add_child(s)
		s.global_position = pos
		return s

	func _interact(p: Node3D) -> void:
		if on_use.is_valid():
			on_use.call(p)
