extends Interactable
## player 担当の動作確認用。Interactable の派生として最小の振る舞いを持つ。
## 箱の見た目と当たりを自前で作るので、レベルが無くても置くだけで試せる。

@export var box_size: Vector3 = Vector3(0.6, 0.6, 0.6)
@export var color: Color = Color(0.45, 0.30, 0.28)
@export var say_speaker: String = ""
@export var say_text: String = "調べた。"
@export var give_on_use: StringName = &""
@export var give_carried: bool = false

var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	cs.shape = shape
	add_child(cs)

	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mesh.material_override = mat
	add_child(_mesh)

	focused.connect(func() -> void:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.25)
	unfocused.connect(func() -> void:
		mat.emission_enabled = false)

func _interact(player: Node3D) -> void:
	if give_on_use != &"":
		player.give_item(give_on_use, give_carried)
	if say_text != "":
		Dialogue.say(say_speaker, say_text)
