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
	await get_tree().create_timer(sec).timeout

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
	ok(not fz.can_interact(player), "持っている間は取れない")
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

func t_installer_find() -> void:
	print("\n-- 取り出し: SystemsInstaller.find")
	var cof := spawn("res://src/systems/coffin.tscn")
	cof.add_to_group(&"system_coffin")
	var found := SystemsInstaller.find(&"coffin")
	ok(found == cof, "group から取り出せる")
	ok(SystemsInstaller.find(&"nonexistent") == null, "無いものは null")
	eq(SystemsInstaller.find_all(&"coffin").size(), 1, "find_all")
	cof.queue_free()
