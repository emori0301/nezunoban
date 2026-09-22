extends SceneTree
## default_bus_layout.tres を作り直す。
##   godot --headless --path . --script res://tools/audio/make_bus_layout.gd
## バス名は src/autoload/audio.gd が参照している "SFX" / "Ambient" と揃えること。

func _initialize() -> void:
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	AudioServer.set_bus_name(0, "Master")
	AudioServer.set_bus_volume_db(0, 0.0)
	while AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.remove_bus_effect(0, 0)

	# Master: こもり演出用のローパス。既定は無効、Audio.set_muffled(true) で有効になる。
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 600.0
	lp.resonance = 0.35
	lp.db = AudioEffectFilter.FILTER_12DB
	AudioServer.add_bus_effect(0, lp)
	AudioServer.set_bus_effect_enabled(0, 0, false)

	_add_bus(1, "SFX", "Master", 0.0)
	_add_bus(2, "Ambient", "Master", -3.0)
	# Ambient だけ薄いリバーブ。環境音を部屋に馴染ませる。
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.55
	rv.damping = 0.55
	rv.wet = 0.12
	rv.dry = 1.0
	rv.spread = 0.6
	rv.predelay_msec = 20.0
	rv.predelay_feedback = 0.2
	rv.hipass = 0.05
	AudioServer.add_bus_effect(2, rv)
	_add_bus(3, "UI", "Master", 0.0)

	var layout := AudioServer.generate_bus_layout()
	var err := ResourceSaver.save(layout, "res://default_bus_layout.tres")
	if err != OK:
		push_error("保存に失敗: %d" % err)
	print("バス数=%d 保存=%d" % [AudioServer.bus_count, err])
	for i in AudioServer.bus_count:
		print("  %d %s -> %s fx=%d" % [i, AudioServer.get_bus_name(i), AudioServer.get_bus_send(i), AudioServer.get_bus_effect_count(i)])
	quit()

func _add_bus(idx: int, bus_name: String, send: String, volume_db: float) -> void:
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
	AudioServer.set_bus_volume_db(idx, volume_db)
