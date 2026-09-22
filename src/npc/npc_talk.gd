class_name NpcTalk
extends Interactable
## NPC に話しかける当たり判定。NpcBase が子として自動で作る。
## 会話の中身は director が持つので、ここはシグナルを投げるだけ。

signal talk_requested(player: Node3D)

@export var radius: float = 0.75
@export var height: float = 1.8


func _ready() -> void:
	super._ready()
	prompt = "話す"
	interact_distance = 2.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(height, radius * 2.0 + 0.01)
	cs.shape = cap
	cs.position = Vector3(0, height * 0.5, 0)
	add_child(cs)


func _interact(player: Node3D) -> void:
	talk_requested.emit(player)
