class_name Altar
extends Interactable
## 三段祭壇。ライターやマッチの置き場で、基本は装飾。
## 調べる対象にしたいときは director が enabled = true にする。

@export var look_prompt: String = "祭壇"
@export var look_line: String = "白い布。三段。花と、写真と、火。"

func _ready() -> void:
	super._ready()
	prompt = look_prompt
	enabled = false        # 既定では調べられない(装飾)

func _interact(_player: Node3D) -> void:
	if look_line != "":
		Dialogue.monologue(look_line)
