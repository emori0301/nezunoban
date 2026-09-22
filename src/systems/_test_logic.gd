extends SceneTree
## systems のロジックテスト(描画なし)の入口。
##   godot --headless --path . --script res://src/systems/_test_logic.gd
##
## 注意: --script で渡したスクリプトは autoload が登録される前にコンパイルされるので、
## この中では Game / Events などの識別子が使えない。実体は _test_logic_body.gd にあり、
## 起動後に load() するのでそちらでは普通に autoload を参照できる。

const BODY := "res://src/systems/_test_logic_body.gd"

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	await process_frame
	var script: GDScript = load(BODY)
	if script == null:
		push_error("_test_logic: %s を読めない" % BODY)
		quit(1)
		return
	var body: Node = script.new()
	body.name = "SystemsLogicTest"
	root.add_child(body)
	var code: int = await body.run()
	quit(code)
