class_name NpcBoss
extends NpcBase
## 社長。21:00 に受付で待っていて、掟を教えて 21:20 に玄関から帰る。
##
## director からの使い方:
##     var boss := NpcInstaller.find(&"boss") as NpcBoss
##     boss.set_talkable(true)
##     boss.talked.connect(func(_p): director が会話を回す)
##     await boss.go_to(Vector3(9.0, 0.0, -0.5))   # 式場へ同行
##     await boss.leave_via_genkan()               # 玄関から出て npc_left{name:"boss"}

func _init() -> void:
	model_name = "npc_boss"
	npc_id = &"boss"
	move_speed = 1.2
	body_radius = 0.26
	body_height = 1.71
	head_height = 1.58
	agent_radius = 0.32
	talk_prompt = "話す"
	talkable = false
	start_active = true


func _ready() -> void:
	super._ready()
	add_to_group(&"npc_human")
