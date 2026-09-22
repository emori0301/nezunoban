class_name SystemsInstaller
extends Node3D
## level が置いた Anchor_* を探し、対応する systems のプレハブを同じ global_transform に置く。
## main.gd が res://src/systems/installer.tscn を World に追加した時点で動く。
##
## 置いたノードは group "system_<name>" に入るので、どこからでも取り出せる:
##     var coffin := SystemsInstaller.find(&"coffin") as Coffin
##     coffin.knock()
##     for f in SystemsInstaller.find_all(&"flower_stand"):  # 供花は左右2つある
##         f.set_wilted(true)
##
## アンカーが無ければ警告だけ出して何もしない(level と並列で作業できるように)。

const PREFAB_DIR := "res://src/systems/"

## Anchor 名 → プレハブ名(= <name>.tscn / group "system_<name>")
const MAP := {
	"Anchor_Coffin": "coffin",
	"Anchor_Altar": "altar",
	"Anchor_Iei": "iei",
	"Anchor_IncenseStand": "incense_stand",
	"Anchor_Candle": "candle",
	"Anchor_Phone": "phone",
	"Anchor_Monitor": "monitor",
	"Anchor_Freezer": "freezer",
	"Anchor_Breaker": "breaker",
	"Anchor_Safe": "safe",
	"Anchor_Futon": "futon",
	"Anchor_TV": "tv",
	"Anchor_GuestBook": "guest_book",
	"Anchor_FlowerL": "flower_stand",
	"Anchor_FlowerR": "flower_stand",
	"Anchor_Sink": "sink",
	"Anchor_IncenseBox": "incense_box",
	"Anchor_Matches": "matches",
	"Anchor_BossDesk": "boss_desk",
}

signal installed(count: int)

@export var verbose: bool = true

var placed: Dictionary = {}      # anchor 名 -> Node
var missing: PackedStringArray = []

func _ready() -> void:
	_install()

func _install() -> void:
	var root: Node = Game.level
	if root == null:
		root = get_tree().current_scene
	if root == null:
		push_warning("SystemsInstaller: レベルが見つからないので何も置かない")
		return
	var n := 0
	for anchor_name in MAP.keys():
		var anchor := root.find_child(String(anchor_name), true, false)
		if anchor == null:
			missing.append(String(anchor_name))
			continue
		var node := _place(String(anchor_name), String(MAP[anchor_name]), anchor)
		if node != null:
			n += 1
	if verbose and missing.size() > 0:
		push_warning("SystemsInstaller: アンカーが無い(level 未実装なら正常): %s" % ", ".join(missing))
	if verbose:
		print("[systems] %d 個を配置" % n)
	installed.emit(n)
	if _has_cli_flag("systems-demo"):
		call_deferred(&"_demo_state")

## 確認用: godot --path . -- --skip-title --systems-demo
## director がまだ無い状態でも、火が点いた式場/ついた TV を見られるようにする。
func _demo_state() -> void:
	Game.set_flag(&"incense_sticks", 10)
	var inc := find(&"incense_stand")
	if inc:
		inc.call(&"light")
	var cnd := find(&"candle")
	if cnd:
		cnd.call(&"light")
	var tv := find(&"tv")
	if tv:
		tv.call(&"turn_on")
	# 確認用なので館内の照明も点ける(本番では director が制御する)
	var lvl: Node = Game.level
	if lvl and lvl.has_method(&"set_all_lights"):
		lvl.call(&"set_all_lights", true)
	print("[systems] demo: 線香とロウソクを点け、TV をつけ、照明を点けた")

static func _has_cli_flag(name: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--" + name or a.begins_with("--" + name + "="):
			return true
	return false

func _place(anchor_name: String, prefab: String, anchor: Node) -> Node:
	var path := PREFAB_DIR + prefab + ".tscn"
	if not ResourceLoader.exists(path):
		push_warning("SystemsInstaller: プレハブが無い %s" % path)
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("SystemsInstaller: プレハブを読めない %s" % path)
		return null
	var node: Node = packed.instantiate()
	node.name = anchor_name.replace("Anchor_", "")
	add_child(node)
	if node is Node3D and anchor is Node3D:
		var a := anchor as Node3D
		(node as Node3D).global_transform = Transform3D(a.global_basis.orthonormalized(), a.global_position)
	node.add_to_group(StringName("system_" + prefab))
	node.add_to_group(&"system")
	node.set_meta(&"anchor", anchor_name)
	placed[anchor_name] = node
	return node

## Anchor 名で引く。例: get_placed("Anchor_FlowerR")
func get_placed(anchor_name: String) -> Node:
	return placed.get(anchor_name, null)

# --------------------------------------------------------------------------
# どこからでも使える取り出し(director / npc 用)
# --------------------------------------------------------------------------

## SystemsInstaller.find(&"coffin") -> Coffin
static func find(name: StringName) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group(StringName("system_" + String(name)))
	return nodes[0] if not nodes.is_empty() else null

## 同じ種類が複数あるもの(供花など)を全部返す。
static func find_all(name: StringName) -> Array[Node]:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	return tree.get_nodes_in_group(StringName("system_" + String(name)))

## 置かれている systems を全部返す。
static func all() -> Array[Node]:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	return tree.get_nodes_in_group(&"system")
