class_name NpcGranddaughter
extends NpcBase
## 孫娘(春日ひかり)。21:10 に式場の後列に残っていて、日記 1 ページを渡して帰る。
##
## director からの使い方:
##     var gd := NpcInstaller.find(&"granddaughter") as NpcGranddaughter
##     gd.set_talkable(true)
##     gd.talked.connect(func(_p): await Dialogue.say("孫娘", "…"); gd.leave_via_genkan())

func _init() -> void:
	model_name = "npc_granddaughter"
	npc_id = &"granddaughter"
	move_speed = 1.2
	body_radius = 0.26
	body_height = 1.62
	head_height = 1.49
	agent_radius = 0.30
	talk_prompt = "話す"
	talkable = false
	start_active = true


func _ready() -> void:
	super._ready()
	add_to_group(&"npc_human")
