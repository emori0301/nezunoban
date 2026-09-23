extends Node
## Dialogue: 会話・字幕・選択肢。UI は src/ui/hud.tscn 側が register_ui() で登録する。
## 使い方(await 必須):
##   await Dialogue.say("社長", "線香は絶やすなよ。")
##   var i: int = await Dialogue.choose("小窓を開けさせるか", ["断る", "開けさせる"])
##   await Dialogue.note("日記 1", "……")   # 収集物の全文表示

signal line_shown(speaker: String, text: String)
signal finished

var ui: Node = null
var busy: bool = false
## 自動プレイ(QA)用: true なら UI を待たず短時間で進める。choose は auto_chooser があればそれで決める。
var auto_advance: bool = false
var auto_line_seconds: float = 0.15
var auto_chooser: Callable = Callable()   # func(prompt: String, options: Array) -> int
var auto_code: String = ""                # 自動プレイ時に code_input が返す文字列(空なら "")

func register_ui(node: Node) -> void:
	ui = node

func is_ready() -> bool:
	return ui != null

## busy の間は順番待ち(独白が2つ同時に走っても片方が消えない)
func _acquire() -> void:
	while busy:
		await finished
	busy = true

func _release() -> void:
	busy = false
	finished.emit()

func say(speaker: String, text: String) -> void:
	await _acquire()
	line_shown.emit(speaker, text)
	if auto_advance:
		if Game.debug:
			print("[say] %s: %s" % [speaker, text])
		await get_tree().create_timer(auto_line_seconds).timeout
	elif ui and ui.has_method("show_line"):
		await ui.show_line(speaker, text)
	else:
		print("[say] %s: %s" % [speaker, text])
		await get_tree().create_timer(0.1).timeout
	_release()

## 連続で複数行。lines = [[speaker, text], ...]
func say_lines(lines: Array) -> void:
	for l in lines:
		await say(l[0], l[1])

func choose(prompt: String, options: Array) -> int:
	await _acquire()
	var result := 0
	if auto_advance:
		if auto_chooser.is_valid():
			result = int(auto_chooser.call(prompt, options))
		await get_tree().create_timer(auto_line_seconds).timeout
	elif ui and ui.has_method("show_choice"):
		result = await ui.show_choice(prompt, options)
	else:
		print("[choose] %s %s -> 0" % [prompt, options])
		await get_tree().create_timer(0.1).timeout
	_release()
	return result

## 手紙・日記などの全文表示。閉じるまで待つ。
func note(title: String, body: String) -> void:
	await _acquire()
	if auto_advance:
		await get_tree().create_timer(auto_line_seconds).timeout
	elif ui and ui.has_method("show_note"):
		await ui.show_note(title, body)
	else:
		print("[note] %s\n%s" % [title, body])
		await get_tree().create_timer(0.1).timeout
	_release()

## 数字入力(金庫のダイヤル、電話の番号)。キャンセルは "" を返す。UI は HUD の show_code_input(title, length) -> String。
func code_input(title: String, length: int = 4) -> String:
	await _acquire()
	var result := ""
	if auto_advance:
		result = auto_code
		await get_tree().create_timer(auto_line_seconds, false).timeout
	elif ui and ui.has_method("show_code_input"):
		result = await ui.show_code_input(title, length)
	else:
		print("[code_input] %s (%d) -> ''" % [title, length])
		await get_tree().create_timer(0.1, false).timeout
	_release()
	return result

## 画面中央に短く出る独白(モノローグ)。話者なし。
func monologue(text: String) -> void:
	await say("", text)
