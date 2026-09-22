class_name NpcInstaller
extends Node3D
## level が置いた Spawn_* を探し、同じ global_transform に NPC / 猫 / 火車を置く。
## main.gd が res://src/npc/installer.tscn を World に追加した時点で動く。
##
## 置いたノードは group "npc" と group "npc_<name>"(猫は "cat"、火車は "kasha" にも)に入る:
##     var boss := NpcInstaller.find(&"boss") as NpcBoss
##     var cat2 := NpcInstaller.find(&"cat", 2) as Cat      # Spawn_Cat3 の猫
##     for c in NpcInstaller.find_all(&"cat"): c.activate()
##
## 最初から居るのは社長と孫娘だけ。息子・猫・火車は非表示・無効で置いてあるので、
## director が activate() / set_active(true) で出す。
## Spawn_* が無ければ警告だけ出して何もしない(level と並列で作業できるように)。

const PREFAB_DIR := "res://src/npc/"

## Spawn 名 → プレハブ・グループのキー・最初から出ているか
const MAP := [
	{"spawn": "Spawn_Boss", "prefab": "boss", "key": &"boss", "active": true},
	{"spawn": "Spawn_Granddaughter", "prefab": "granddaughter", "key": &"granddaughter", "active": true},
	{"spawn": "Spawn_Son", "prefab": "son", "key": &"son", "active": false},
	{"spawn": "Spawn_Cat1", "prefab": "cat", "key": &"cat", "active": false},
	{"spawn": "Spawn_Cat2", "prefab": "cat", "key": &"cat", "active": false},
	{"spawn": "Spawn_Cat3", "prefab": "cat", "key": &"cat", "active": false},
	{"spawn": "Spawn_Cat4", "prefab": "cat", "key": &"cat", "active": false},
	{"spawn": "Spawn_Cat5", "prefab": "cat", "key": &"cat", "active": false},
	{"spawn": "Spawn_Kasha", "prefab": "kasha", "key": &"kasha", "active": false},
]

signal installed(count: int)

@export var verbose: bool = true

var placed: Dictionary = {}          # Spawn 名 -> Node
var missing: PackedStringArray = []


func _ready() -> void:
	_install()


func _install() -> void:
	var root: Node = Game.level
	if root == null:
		root = get_tree().current_scene
	if root == null:
		push_warning("NpcInstaller: レベルが見つからないので何も置かない")
		return
	var n := 0
	var index_by_key := {}
	for entry in MAP:
		var spawn_name := String(entry["spawn"])
		var spawn := root.find_child(spawn_name, true, false)
		if spawn == null:
			missing.append(spawn_name)
			continue
		var key: StringName = entry["key"]
		var idx: int = int(index_by_key.get(key, 0))
		index_by_key[key] = idx + 1
		var node := _place(spawn_name, String(entry["prefab"]), key, idx, spawn, bool(entry["active"]))
		if node != null:
			n += 1
	if verbose and missing.size() > 0:
		push_warning("NpcInstaller: Spawn が無い(level 未実装なら正常): %s" % ", ".join(missing))
	if verbose:
		print("[npc] %d 体を配置" % n)
	installed.emit(n)


func _place(spawn_name: String, prefab: String, key: StringName, index: int,
		spawn: Node, active: bool) -> Node:
	var path := PREFAB_DIR + prefab + ".tscn"
	if not ResourceLoader.exists(path):
		push_warning("NpcInstaller: プレハブが無い %s" % path)
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("NpcInstaller: プレハブを読めない %s" % path)
		return null
	var node: Node = packed.instantiate()
	node.name = spawn_name.replace("Spawn_", "")
	if node is NpcBase:
		(node as NpcBase).start_active = active
	node.add_to_group(StringName("npc_" + String(key)))
	node.set_meta(&"npc_index", index)
	node.set_meta(&"spawn", spawn_name)
	add_child(node)
	if node is Node3D and spawn is Node3D:
		var s := spawn as Node3D
		(node as Node3D).global_transform = Transform3D(s.global_basis.orthonormalized(), s.global_position)
	placed[spawn_name] = node
	return node


## Spawn 名で引く。例: get_placed("Spawn_Cat3")
func get_placed(spawn_name: String) -> Node:
	return placed.get(spawn_name, null)


# --------------------------------------------------------------------------
# どこからでも使える取り出し(director 用)
# --------------------------------------------------------------------------

## NpcInstaller.find(&"cat", 2) -> Spawn_Cat3 に置いた Cat
static func find(name: StringName, index: int = 0) -> Node:
	var list := find_all(name)
	if index < 0 or index >= list.size():
		return null
	return list[index]


## 同じ種類を Spawn の並び順で全部返す。
static func find_all(name: StringName) -> Array[Node]:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	var nodes := tree.get_nodes_in_group(StringName("npc_" + String(name)))
	nodes.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get_meta(&"npc_index", 0)) < int(b.get_meta(&"npc_index", 0)))
	return nodes


## 置かれている NPC を全部返す。
static func all() -> Array[Node]:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	return tree.get_nodes_in_group(&"npc")
