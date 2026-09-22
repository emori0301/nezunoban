extends SceneTree
## 生成した wav が Godot 側で正しく読めるか確かめる。
##   godot --headless --path . --script res://tools/audio/verify_audio.gd

const DIR := "res://assets/audio/"

func _initialize() -> void:
	var expected := _expected_names()
	var files := PackedStringArray()
	var d := DirAccess.open(DIR)
	if d == null:
		push_error("assets/audio が開けない")
		quit(1)
		return
	for f in d.get_files():
		if f.ends_with(".wav"):
			files.append(f.get_basename())
	files.sort()

	var missing := PackedStringArray()
	for n in expected:
		if not files.has(n):
			missing.append(n)
	var orphan := PackedStringArray()
	for n in files:
		if not expected.has(n):
			orphan.append(n)

	var looped := 0
	var bad := PackedStringArray()
	for n in files:
		var path := DIR + n + ".wav"
		var s := ResourceLoader.load(path)
		if s == null or not (s is AudioStreamWAV):
			bad.append(n + " (load失敗)")
			continue
		var w: AudioStreamWAV = s
		if w.mix_rate != 44100:
			bad.append(n + " (mix_rate=%d)" % w.mix_rate)
		if w.stereo:
			bad.append(n + " (stereo)")
		if w.format != AudioStreamWAV.FORMAT_16_BITS:
			bad.append(n + " (format=%d)" % w.format)
		if w.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			looped += 1
			print("LOOP %-20s %6.2fs loop=%d..%d" % [n, w.get_length(), w.loop_begin, w.loop_end])

	print("---")
	print("wav %d / CLAUDE.md %d / 欠け %d / 余り %d / ループ検出 %d" % [files.size(), expected.size(), missing.size(), orphan.size(), looped])
	if missing.size() > 0:
		print("欠け: ", missing)
	if orphan.size() > 0:
		print("余り: ", orphan)
	if bad.size() > 0:
		print("不正: ", bad)
	for b in ["Master", "SFX", "Ambient", "UI"]:
		print("bus %-8s index=%d" % [b, AudioServer.get_bus_index(b)])
	quit(1 if (missing.size() + orphan.size() + bad.size()) > 0 else 0)

func _expected_names() -> PackedStringArray:
	var text := FileAccess.get_file_as_string("res://CLAUDE.md")
	var start := text.find("## 音名一覧")
	var end := text.find("## ", start + 8)
	var body := text.substr(start, end - start)
	var out := PackedStringArray()
	var re := RegEx.create_from_string("`([A-Za-z0-9_\\.]+)`")
	var rng := RegEx.create_from_string("^([A-Za-z0-9_]+?)_(\\d+)\\.\\.(\\d+)$")
	for m in re.search_all(body):
		var tok := m.get_string(1)
		var rm := rng.search(tok)
		if rm != null:
			for i in range(int(rm.get_string(2)), int(rm.get_string(3)) + 1):
				out.append("%s_%d" % [rm.get_string(1), i])
		elif not tok.contains("."):
			if not out.has(tok):
				out.append(tok)
	return out
