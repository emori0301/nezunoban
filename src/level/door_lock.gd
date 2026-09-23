class_name DoorLock
extends Interactable
## 扉の脇の締り金具(サムターン)。`Door.lockable = true` のとき Door が自分で作る。
##
## 扉板そのものとは別のインタラクトにしてある。プレイヤーのインタラクトは
## 「タップ」と「長押し」を1つの対象で撃ち分けられない(hold_time > 0 なら常に長押し)ので、
## 扉板に載せると「開ける」が押せなくなるため。枠側に置いて狙い分ける。
##
## 施錠 = 長押し 1.0 秒 / 解錠 = 長押し 0.6 秒。開いている扉は施錠できない。

const LOCK_HOLD := 1.0
const UNLOCK_HOLD := 0.6

var door: Door = null


func _ready() -> void:
	super._ready()
	add_to_group(&"door_lock")
	hold_time = LOCK_HOLD
	set_process(true)


func _process(_delta: float) -> void:
	# プレイヤーは focus.hold_time を毎フレーム読むので、状態に合わせて入れ替える
	if door:
		hold_time = UNLOCK_HOLD if door.locked else LOCK_HOLD


func get_prompt() -> String:
	if door == null:
		return ""
	return "鍵を開ける" if door.locked else "鍵をかける"


func _can_interact(_player: Node3D) -> bool:
	return door != null and not door.is_open


func get_blocked_text() -> String:
	return "扉が開いている"


func _interact(_player: Node3D) -> void:
	if door == null or door.is_open:
		return
	if door.locked:
		door.unlock()
	else:
		door.lock()
