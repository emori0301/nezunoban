class_name WindowPane
extends Interactable
## 引き違いの窓。開いていると猫の侵入口になり、式場では線香が早く減る。
##
## 置き方: ノードは開口部の中心(高さも含む)に置く。
##   ローカル +X = 開口の幅方向、ローカル Z = 厚み方向。
##
## Events: window_opened{window} / window_closed{window}

const TWEEN_TIME := 0.45

@export var pane_width: float = 1.6
@export var pane_height: float = 1.2
@export var frame_depth: float = 0.10
@export var start_open: bool = false
@export var locked: bool = false

@export var open_prompt: String = "窓を開ける"
@export var close_prompt: String = "窓を閉める"
@export var locked_prompt: String = "鍵がかかっている"

var is_open: bool = false

var _leaf: Node3D = null
var _shape: CollisionShape3D = null
var _tween: Tween = null


func _ready() -> void:
	super._ready()
	add_to_group(&"window")
	_build()
	if start_open:
		is_open = true
		_leaf.position.x = pane_width * 0.5
		_shape.disabled = true


func get_prompt() -> String:
	if locked and not is_open:
		return locked_prompt
	return close_prompt if is_open else open_prompt


func _can_interact(_player: Node3D) -> bool:
	return true


func _interact(_player: Node3D) -> void:
	toggle()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open(force: bool = false) -> void:
	if is_open:
		return
	if locked and not force:
		Audio.play(&"door_locked")
		return
	is_open = true
	_shape.disabled = true
	_slide(pane_width * 0.5)
	Audio.play(&"window_open")
	Events.emit_event(&"window_opened", {"window": name})


func close() -> void:
	if not is_open:
		return
	is_open = false
	_slide(0.0)
	Audio.play(&"window_close")
	Events.emit_event(&"window_closed", {"window": name})


func _slide(target: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_leaf, "position:x", target, TWEEN_TIME)
	if not is_open:
		_tween.tween_callback(func() -> void:
			if not is_open:
				_shape.disabled = false)


func _build() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(pane_width + 0.1, pane_height + 0.1, 0.45)
	cs.shape = bs
	add_child(cs)

	var fm := LevelMaterials.plain(Color(0.42, 0.42, 0.40))
	var half := pane_width * 0.5
	var hh := pane_height * 0.5
	# 窓枠(上下・左右)
	LevelBuild.box(self, Vector3(0, hh + 0.03, 0), Vector3(pane_width + 0.1, 0.07, frame_depth), fm, false, "", false)
	LevelBuild.box(self, Vector3(0, -hh - 0.03, 0), Vector3(pane_width + 0.1, 0.07, frame_depth), fm, false, "", false)
	LevelBuild.box(self, Vector3(-half - 0.03, 0, 0), Vector3(0.07, pane_height, frame_depth), fm, false, "", false)
	LevelBuild.box(self, Vector3(half + 0.03, 0, 0), Vector3(0.07, pane_height, frame_depth), fm, false, "", false)

	var glass := LevelMaterials.translucent(Color(0.45, 0.52, 0.56), 0.26)
	# 固定側(右)
	LevelBuild.box(self, Vector3(half * 0.5, 0, 0.022), Vector3(half, pane_height, 0.02), glass, false, "", false)
	LevelBuild.box(self, Vector3(half * 0.5, 0, 0.022), Vector3(half, 0.05, 0.03), fm, false, "", false)

	# 可動側(左)。開くと右へスライドする。
	_leaf = Node3D.new()
	_leaf.name = "Leaf"
	add_child(_leaf)
	LevelBuild.box(_leaf, Vector3(-half * 0.5, 0, -0.022), Vector3(half, pane_height, 0.02), glass, false, "", false)
	LevelBuild.box(_leaf, Vector3(-half * 0.5, 0, -0.022), Vector3(half, 0.05, 0.03), fm, false, "", false)
	LevelBuild.box(_leaf, Vector3(-0.06, -pane_height * 0.25, -0.05),
		Vector3(0.04, 0.12, 0.05), LevelMaterials.plain(Color(0.5, 0.48, 0.4)), false, "", false)

	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	_shape = CollisionShape3D.new()
	var b2 := BoxShape3D.new()
	b2.size = Vector3(pane_width, pane_height, 0.08)
	_shape.shape = b2
	sb.add_child(_shape)
	add_child(sb)
