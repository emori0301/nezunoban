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

func register_ui(node: Node) -> void:
	ui = node

func is_ready() -> bool:
	return ui != null

func say(speaker: String, text: String) -> void:
	busy = true
	line_shown.emit(speaker, text)
	if ui and ui.has_method("show_line"):
		await ui.show_line(speaker, text)
	else:
		print("[say] %s: %s" % [speaker, text])
		await get_tree().create_timer(0.1).timeout
	busy = false
	finished.emit()

## 連続で複数行。lines = [[speaker, text], ...]
func say_lines(lines: Array) -> void:
	for l in lines:
		await say(l[0], l[1])

func choose(prompt: String, options: Array) -> int:
	busy = true
	var result := 0
	if ui and ui.has_method("show_choice"):
		result = await ui.show_choice(prompt, options)
	else:
		print("[choose] %s %s -> 0" % [prompt, options])
		await get_tree().create_timer(0.1).timeout
	busy = false
	return result

## 手紙・日記などの全文表示。閉じるまで待つ。
func note(title: String, body: String) -> void:
	busy = true
	if ui and ui.has_method("show_note"):
		await ui.show_note(title, body)
	else:
		print("[note] %s\n%s" % [title, body])
		await get_tree().create_timer(0.1).timeout
	busy = false

## 画面中央に短く出る独白(モノローグ)。話者なし。
func monologue(text: String) -> void:
	await say("", text)
