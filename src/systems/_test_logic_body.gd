extends Node
## systems のロジックテスト本体。_test_logic.gd から起動される。
## Clock / Dread / Events / Game フラグとの連携を assert する。

class StubPlayer extends Node3D:
	var items: Dictionary = {}
	var carried_item: StringName = &""
	var locked: bool = false
	func has_item(i: StringName) -> bool:
		return items.has(i)
	func give_item(i: StringName, carried: bool = false) -> void:
		items[i] = true
		if carried:
			carried_item = i
	func take_item(i: StringName) -> void:
		items.erase(i)
		if carried_item == i:
			carried_item = &""
	func is_carrying() -> bool:
		return carried_item != &""
	func set_locked(v: bool) -> void:
		locked = v
	func look_at_point(_p: Vector3, _d: float = 0.8) -> void:
		pass
	func teleport(p: Vector3, _yaw: float = 0.0, _pitch: float = 0.0) -> void:
		global_position = p

var failures: PackedStringArray = []
var checks: int = 0
var seen: Array = []          # [name, data]
var player: StubPlayer

func run() -> int:
	Events.event.connect(func(n: StringName, d: Dictionary) -> void: seen.append([n, d]))
	player = StubPlayer.new()
	get_tree().root.add_child(player)
	Game.register_player(player)

	await t_incense_burns_out()
	await t_incense_multiplier()
	await t_incense_no_stock()
	await t_incense_box_stock()
	await t_candle()
	await t_relight()
	await t_phone_missed()
	await t_phone_answered()
	await t_coffin_cat()
	await t_water_flow()
	await t_freezer()
	await t_note_pages()
	await t_clock_events()
	await t_installer_find()
	await t_moving_parts()
	await t_review_fixes()

	print("")
	if failures.is_empty():
		print("[systems test] OK  %d checks" % checks)
		return 0
	print("[systems test] FAILED %d / %d" % [failures.size(), checks])
	for f in failures:
		print("  - %s" % f)
	return 1

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

func ok(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures.append(label)
		print("  NG  %s" % label)
	else:
		print("  ok  %s" % label)

func eq(a: Variant, b: Variant, label: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [label, a, b])

func spawn(path: String) -> Node:
	var n: Node = load(path).instantiate()
	get_tree().root.add_child(n)
	return n

func clear_events() -> void:
	seen.clear()

func saw(name: StringName) -> bool:
	for e in seen:
		if e[0] == name:
			return true
	return false

func data_of(name: StringName) -> Dictionary:
	for e in seen:
		if e[0] == name:
			return e[1]
	return {}

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, false).timeout

# --------------------------------------------------------------------------
# tests
# --------------------------------------------------------------------------

func t_incense_burns_out() -> void:
	print("\n-- 線香: 燃え尽きると incense_out と Dread +1")
	var inc := spawn("res://src/systems/incense_stand.tscn") as IncenseStand
	inc.burn_seconds = 0.5
	Game.set_flag(&"incense_sticks", 3)
	clear_events()
	var dread_before := Dread.value
	var lit_ok := inc.light()
	ok(lit_ok, "在庫があれば点く")
	eq(int(Game.get_flag(&"incense_sticks", 0)), 2, "在庫が1本減る")
	ok(inc.is_burning, "is_burning が true")
	ok(saw(&"incense_lit"), "incense_lit が出る")
	ok(inc.remaining_ratio > 0.9, "残量比が最初は約1.0")
	await wait(0.8)
	ok(not inc.is_burning, "0.5秒で燃え尽きる")
	ok(saw(&"incense_out"), "incense_out が出る")
	eq(Dread.value - dread_before, 1, "Dread が +1")
	eq(inc.remaining_ratio, 0.0, "残量比が 0")
	inc.queue_free()

func t_incense_multiplier() -> void:
	print("\n-- 線香: burn_multiplier で減りが速くなる(窓が開いている)")
	var inc := spawn("res://src/systems/incense_stand.tscn") as IncenseStand
	inc.burn_seconds = 4.0
	inc.burn_multiplier = 8.0
	Game.set_flag(&"incense_sticks", 5)
	inc.light()
	await wait(0.75)
	ok(not inc.is_burning, "8倍なら 4秒ぶんが 0.5秒で尽きる")
	inc.queue_free()

func t_incense_no_stock() -> void:
	print("\n-- 線香: 在庫 0 なら点かない")
	var inc := spawn("res://src/systems/incense_stand.tscn") as IncenseStand
	Game.set_flag(&"incense_sticks", 0)
	clear_events()
	var r := inc.light()
	ok(not r, "light() が false")
	ok(not inc.is_burning, "燃えない")
	ok(not saw(&"incense_lit"), "incense_lit は出ない")
	inc.queue_free()

func t_incense_box_stock() -> void:
	print("\n-- 線香の箱: 拾うと在庫 +10")
	var box := spawn("res://src/systems/incense_box.tscn") as Pickup
	Game.set_flag(&"incense_sticks", 0)
	box.take(player)
	eq(int(Game.get_flag(&"incense_sticks", 0)), 10, "在庫が 10 になる")

func t_candle() -> void:
	print("\n-- ロウソク: candle_lit / candle_out")
	var c := spawn("res://src/systems/candle.tscn") as Candle
	c.burn_seconds = 0.4
	clear_events()
	c.light()
	ok(c.is_lit, "灯る")
	ok(saw(&"candle_lit"), "candle_lit が出る")
	await wait(0.7)
	ok(not c.is_lit, "燃え尽きる")
	ok(saw(&"candle_out"), "candle_out が出る")
	clear_events()
	c.light()
	c.force_out()
	ok(saw(&"candle_out"), "force_out でも candle_out")
	c.queue_free()

func t_relight() -> void:
	print("\n-- ロウソク: 終盤の灯し直し(fail_next で失敗)")
	var c := spawn("res://src/systems/candle.tscn") as Candle
	c.require_matches = true
	eq(c.required_item, &"matches", "require_matches で required_item がマッチになる")
	eq(c.hold_time, 1.2, "長押し 1.2 秒")
	clear_events()
	c.fail_next = true
	var r1 := c.relight_attempt()
	ok(not r1, "fail_next のとき失敗する")
	ok(not saw(&"relight_success"), "失敗時は relight_success が出ない")
	ok(not c.fail_next, "fail_next は1回だけ")
	var r2 := c.relight_attempt()
	ok(r2, "次は成功する")
	ok(saw(&"relight_success"), "relight_success が出る")
	eq(int(data_of(&"relight_success").get("n", -1)), 1, "n が 1")
	c.relight_attempt()
	eq(c.relight_count, 2, "2回成功している")
	c.queue_free()

func t_phone_missed() -> void:
	print("\n-- 電話: 取らないと phone_missed と Dread +1")
	var ph := spawn("res://src/systems/phone.tscn") as Phone
	clear_events()
	var before := Dread.value
	ph.ring(0.3)
	ok(ph.is_ringing, "鳴っている")
	ok(saw(&"phone_ring"), "phone_ring が出る")
	eq(ph.get_prompt(), "電話に出る", "鳴っている間のプロンプト")
	await wait(0.6)
	ok(not ph.is_ringing, "時間切れで止まる")
	ok(saw(&"phone_missed"), "phone_missed が出る")
	eq(Dread.value - before, 1, "Dread が +1")
	ph.queue_free()

func t_phone_answered() -> void:
	print("\n-- 電話: 出れば phone_answered、Dread は増えない")
	var ph := spawn("res://src/systems/phone.tscn") as Phone
	clear_events()
	var before := Dread.value
	ph.ring(5.0)
	ph.answer()
	ok(saw(&"phone_answered"), "phone_answered が出る")
	ok(ph.off_hook, "受話器が上がっている")
	eq(ph.get_prompt(), "受話器を置く", "受話器を置くプロンプトになる")
	eq(Dread.value - before, 0, "Dread は増えない")
	ph.hang_up()
	ok(not ph.off_hook, "置ける")
	await wait(0.4)
	ok(not saw(&"phone_missed"), "出たあとに取り逃しにならない")
	ph.queue_free()

func t_coffin_cat() -> void:
	print("\n-- 棺: 猫がまたぐと cat_crossed_coffin と Dread +3")
	var cof := spawn("res://src/systems/coffin.tscn") as Coffin
	cof.global_position = Vector3(50, 0, 50)
	await get_tree().physics_frame
	clear_events()
	var before := Dread.value
	var cat := Area3D.new()
	cat.collision_layer = 8          # npc レイヤー
	cat.collision_mask = 0
	cat.monitorable = true
	cat.monitoring = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.15
	cs.shape = sp
	cat.add_child(cs)
	cat.add_to_group(&"cat")
	get_tree().root.add_child(cat)
	cat.global_position = Vector3(50, 0.85, 50)
	for _i in 8:
		await get_tree().physics_frame
	ok(saw(&"cat_crossed_coffin"), "cat_crossed_coffin が出る(Area3D の当たり判定)")
	eq(Dread.value - before, 3, "Dread が +3")
	ok(bool(Game.get_flag(&"cat_crossed_coffin", false)), "フラグが立つ")
	var before2 := Dread.value
	cof._on_cat_zone_entered(cat)
	eq(Dread.value - before2, 0, "2回目は加算しない")
	eq(cof.get_prompt(), "小窓を覗く", "ドライアイス未所持なら「小窓を覗く」")
	ok(not cof.allow_open_window, "allow_open_window は既定で false(掟4)")
	cat.queue_free()
	cof.queue_free()

func t_water_flow() -> void:
	print("\n-- 供花: 流し → 水 → 水を替える")
	var sk := spawn("res://src/systems/sink.tscn") as Sink
	var fl := spawn("res://src/systems/flower_stand.tscn") as FlowerStand
	clear_events()
	eq(fl.get_prompt(), "供花", "水を持っていないと替えられない表示")
	sk.fill(player)
	ok(player.has_item(&"water"), "水を持つ")
	eq(player.carried_item, &"water", "両手が塞がる")
	eq(fl.get_prompt(), "水を替える", "水を持つとプロンプトが変わる")
	ok(fl.is_wilted, "最初はしおれている")
	fl.change_water(player)
	ok(not player.has_item(&"water"), "水を使う")
	ok(not fl.is_wilted, "元気になる")
	ok(saw(&"flowers_watered"), "flowers_watered が出る")
	sk.queue_free()
	fl.queue_free()

func t_freezer() -> void:
	print("\n-- 冷凍庫: ドライアイス / 空")
	var fz := spawn("res://src/systems/freezer.tscn") as Freezer
	fz.open_seconds = 0.05
	fz.take(player)
	await wait(0.9)
	ok(player.has_item(&"dry_ice"), "ドライアイスを持つ")
	eq(player.carried_item, &"dry_ice", "運搬中は両手が塞がる")
	ok(fz.can_interact(player), "同じ物を持っているときは調べられる(独白のため)")
	fz.take(player)
	await wait(0.3)
	eq(player.carried_item, &"dry_ice", "もう一度取ろうとしても二重にならない")
	player.take_item(&"dry_ice")
	fz.set_empty(true)
	fz.take(player)
	await wait(0.9)
	ok(not player.has_item(&"dry_ice"), "空のときは何も取れない")
	fz.queue_free()

func t_note_pages() -> void:
	print("\n-- 手紙: 収集物は初回だけ pages が増える")
	var n := spawn("res://src/systems/note.tscn") as Note
	n.set_text("日記 1", "……", 1)
	Game.set_flag(&"pages", 0)
	clear_events()
	await n.read()
	eq(int(Game.get_flag(&"pages", 0)), 1, "pages が 1")
	ok(saw(&"page_read"), "page_read が出る")
	eq(int(data_of(&"page_read").get("n", -1)), 1, "n が 1")
	clear_events()
	await n.read()
	eq(int(Game.get_flag(&"pages", 0)), 1, "2回目は増えない")
	ok(not saw(&"page_read"), "2回目は page_read が出ない")
	n.queue_free()

func t_clock_events() -> void:
	print("\n-- Clock: 時刻イベントが発火する")
	var fired := [false]
	Events.at("23:00", func() -> void: fired[0] = true)
	eq(Clock.minutes_from_hhmm("23:00"), 120, "23:00 は 120 分")
	Clock.skip_to(121)
	await get_tree().process_frame
	ok(fired[0], "Clock.skip_to で 23:00 のイベントが出る")
	eq(Clock.hhmm(), "23:01", "時刻表示")
	Clock.game_minutes = 0.0

## review_1.md の指摘(M1 受話器置き忘れ / M2 運搬物の上書き / M3 モニター描画 / L2 Clock.speed)
func t_review_fixes() -> void:
	print("\n-- review_1 の修正")

	# M1: 受話器を上げっぱなしでも台本の電話が鳴る
	var ph := spawn("res://src/systems/phone.tscn") as Phone
	ph.pick_up()
	ok(ph.off_hook, "受話器を上げた状態")
	clear_events()
	ph.ring(5.0)
	ok(ph.is_ringing, "置き忘れていても鳴る")
	ok(not ph.off_hook, "受話器が勝手に戻る")
	ok(saw(&"phone_ring"), "phone_ring が出る")
	ph.stop_ring()
	ph.queue_free()

	# M2: 運搬中は水もドライアイスも取れない
	var sk := spawn("res://src/systems/sink.tscn") as Sink
	var fz := spawn("res://src/systems/freezer.tscn") as Freezer
	player.items.clear()
	player.carried_item = &""
	ok(sk.can_interact(player), "手が空いていれば水を汲める")
	player.give_item(&"dry_ice", true)
	ok(not sk.can_interact(player), "ドライアイスを持っていると水を汲めない")
	eq(sk.get_prompt(), "両手が塞がっている", "流しのプロンプト")
	player.take_item(&"dry_ice")
	player.give_item(&"water", true)
	ok(not fz.can_interact(player), "水を持っていると冷凍庫を開けられない")
	eq(fz.get_prompt(), "両手が塞がっている", "冷凍庫のプロンプト")
	# N9: 同じ物を持っているときはガードせず独白を出す
	ok(sk.can_interact(player), "水を持っていても流しは調べられる(「もう汲んである」用)")
	eq(sk.get_prompt(), "水を汲む", "同じ物のときは通常のプロンプト")
	sk.fill(player)
	eq(player.carried_item, &"water", "もう一度汲んでも二重にならない")
	player.take_item(&"water")
	ok(sk.can_interact(player), "手を空ければまた汲める")
	sk.queue_free()
	fz.queue_free()

	# M3: モニターは事務所にいるときだけ描く
	var mon := spawn("res://src/systems/monitor.tscn") as Monitor
	ok(mon.is_feed_updating(), "部屋イベントが来るまでは描く(テストシーン向け)")
	Events.emit_event(&"player_entered_room", {"room": "Room_Hall"})
	await get_tree().process_frame
	ok(not mon.is_feed_updating(), "他の部屋にいるあいだは描かない")
	Events.emit_event(&"player_entered_room", {"room": "Room_Office"})
	await get_tree().process_frame
	ok(mon.is_feed_updating(), "事務所に入ると描く")
	Events.emit_event(&"player_entered_room", {"room": "Room_Shikijo"})
	await get_tree().process_frame
	mon.set_force_update(true)
	ok(mon.is_feed_updating(), "--cctv-shot 用に強制更新できる")
	mon.set_force_update(false)
	ok(not mon.is_feed_updating(), "強制更新を外すと戻る")
	mon.queue_free()

	# L2: Clock.speed を見る
	var inc := spawn("res://src/systems/incense_stand.tscn") as IncenseStand
	inc.burn_seconds = 4.0
	Game.set_flag(&"incense_sticks", 5)
	Clock.speed = 8.0
	inc.light()
	await wait(0.75)
	ok(not inc.is_burning, "Clock.speed=8 なら 4秒ぶんが 0.5秒で尽きる")
	Clock.speed = 1.0
	inc.queue_free()

## models が入れた Lid / Window / Door / Lever が実際に動くか。
func t_moving_parts() -> void:
	print("\n-- 可動部: Lid / Window / Door / Lever")

	var cof := spawn("res://src/systems/coffin.tscn") as Coffin
	ok(cof._lid_node != null, "coffin.glb の Lid を拾えている")
	ok(cof._window_node != null, "coffin.glb の Window を拾えている")
	ok(cof._face_prop != null, "body_face.glb を小窓の下に置けている")
	if cof._face_prop:
		eq(cof._face_prop.position, cof.face_model_offset, "顔の位置は棺ローカル (0.64, 0.275, 0)")
	if cof._window_node:
		ok(cof._window_node.visible, "最初は小窓が閉じている")
		cof.set_window_open(true)
		ok(not cof._window_node.visible, "set_window_open(true) で小窓が開く")
		cof.set_window_open(false)
		ok(cof._window_node.visible, "閉じられる")
	if cof._lid_node:
		var rest: Vector3 = cof._lid_node.position
		cof.set_lid_ajar(true)
		await wait(1.6)
		ok(cof._lid_node.position.x > rest.x + 0.08, "set_lid_ajar で Lid が 10cm ずれる")
		cof.set_open(true)
		await wait(2.0)
		ok(cof._lid_node.rotation_degrees.x > 50.0, "set_open で Lid が起き上がる")
	cof.queue_free()

	var fz := spawn("res://src/systems/freezer.tscn") as Freezer
	ok(fz._lid_node != null, "freezer_chest.glb の Lid を拾えている")
	ok(fz._ice != null, "庫内にドライアイスの箱がある")
	fz.set_lid_open(true)
	await wait(0.7)
	if fz._lid_pivot:
		ok(fz._lid_pivot.rotation_degrees.x < -60.0, "蓋が開く")
	fz.set_empty(true)
	if fz._ice:
		ok(not fz._ice.visible, "空にするとドライアイスが消える")
	fz.queue_free()

	var sf := spawn("res://src/systems/safe.tscn") as Safe
	ok(sf._door_node != null, "safe.glb の Door を拾えている")
	ok(sf.get_note() != null, "台帳が庫内にある")
	ok(not sf.get_note().enabled, "開ける前は台帳を読めない")
	sf.open()
	await wait(2.2)
	ok(sf.is_open, "金庫が開く")
	if sf._door_node:
		ok(absf(sf._door_node.rotation_degrees.y) > 90.0, "扉が回る")
	ok(sf.get_note().enabled, "開けたら台帳を読める")
	sf.queue_free()

	var br := spawn("res://src/systems/breaker.tscn") as Breaker
	ok(br._model_lever != null, "breaker_box.glb の Lever を拾えている")
	br.trip()
	await wait(0.4)
	if br._model_lever:
		ok(br._model_lever.rotation_degrees.x > 20.0, "落とすとレバーが倒れる")
	br.restore()
	await wait(0.4)
	if br._model_lever:
		ok(absf(br._model_lever.rotation_degrees.x) < 1.0, "上げると戻る")
	br.queue_free()

func t_installer_find() -> void:
	print("\n-- 取り出し: SystemsInstaller.find")
	var cof := spawn("res://src/systems/coffin.tscn")
	cof.add_to_group(&"system_coffin")
	var found := SystemsInstaller.find(&"coffin")
	ok(found == cof, "group から取り出せる")
	ok(SystemsInstaller.find(&"nonexistent") == null, "無いものは null")
	eq(SystemsInstaller.find_all(&"coffin").size(), 1, "find_all")
	cof.queue_free()
