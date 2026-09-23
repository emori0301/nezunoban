extends SceneTree
## assets/models/*.glb を Godot 側から読んで、ノード構成・マテリアル名・
## AnimationPlayer のアニメ名・頂点数を出す確認用スクリプト。
##
##   godot --headless --path . --script res://tools/blender/check_in_godot.gd
##
## 何も ERROR が出ず、各キャラに期待したアニメ名が並べば OK。

const DIR := "res://assets/models"

var expect_anims := {
	"cat": ["idle", "walk", "sit"],
	"kasha": ["crawl", "idle"],
	"npc_boss": ["idle", "walk", "sit", "sit_floor", "sleep"],
	"npc_son": ["idle", "walk", "sit", "sit_floor", "sleep"],
	"npc_granddaughter": ["idle", "walk", "sit", "sit_floor", "sleep"],
	"body_risen": ["rise"],
	"hanging_robe": ["sway", "drop"],
	"lantern_rotating": ["spin"],
}

## 名前で拾う約束のノード(systems / level がこの名前を使う)
var expect_nodes := {
	"coffin": ["Lid", "Window"],
	"coffin_lid_open": ["Lid", "Window"],
	"freezer_chest": ["Lid"],
	"safe": ["Door"],
	"breaker_box": ["Lever"],
	"phone": ["Handset"],
	"lantern_rotating": ["Inner"],
	"radio": ["Dial"],
}

var fail := 0


func _init() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		printerr("cannot open ", DIR)
		quit(1)
		return
	var names: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".glb"):
			names.append(f.get_basename())
	names.sort()

	print("=== %d glb in %s ===" % [names.size(), DIR])
	for n in names:
		_check(n)

	print("\n=== expected child nodes (名前で拾う部品) ===")
	for n in expect_nodes.keys():
		_check_nodes(n, expect_nodes[n])

	print("\n=== expected animations ===")
	for n in expect_anims.keys():
		var got := _anims_of(n)
		var want: Array = expect_anims[n]
		var missing: Array = []
		for w in want:
			if not got.has(w):
				missing.append(w)
		if missing.is_empty():
			print("  OK   %-20s %s" % [n, str(got)])
		else:
			fail += 1
			printerr("  MISS %-20s got=%s missing=%s" % [n, str(got), str(missing)])

	print("\nfailures: %d" % fail)
	quit(1 if fail > 0 else 0)


func _check_nodes(name: String, want: Array) -> void:
	var ps := load("%s/%s.glb" % [DIR, name])
	if ps == null:
		fail += 1
		printerr("  LOAD FAILED ", name)
		return
	var root: Node = ps.instantiate()
	var missing: Array = []
	var found: Array = []
	for w in want:
		var n: Node = root.find_child(w, true, false)
		if n == null:
			missing.append(w)
		else:
			var pos: Vector3 = (n as Node3D).position if n is Node3D else Vector3.ZERO
			var par: String = str(n.get_parent().name) if n.get_parent() != null else "-"
			found.append("%s(origin=%.3f,%.3f,%.3f parent=%s)" % [w, pos.x, pos.y, pos.z, par])
	if missing.is_empty():
		print("  OK   %-18s %s" % [name, " ".join(PackedStringArray(found))])
	else:
		fail += 1
		printerr("  MISS %-18s missing=%s" % [name, str(missing)])
	root.free()


func _anims_of(name: String) -> Array:
	var ps := load("%s/%s.glb" % [DIR, name])
	if ps == null:
		return []
	var root: Node = ps.instantiate()
	var out: Array = []
	for ap in _find_all(root, "AnimationPlayer"):
		for a in (ap as AnimationPlayer).get_animation_list():
			out.append(a)
	root.free()
	return out


func _check(name: String) -> void:
	var path := "%s/%s.glb" % [DIR, name]
	var ps := load(path)
	if ps == null:
		fail += 1
		printerr("LOAD FAILED: ", path)
		return
	var root: Node = ps.instantiate()
	var verts := 0
	var surfs: Array = []
	var meshes: Array = []
	for mi in _find_all(root, "MeshInstance3D"):
		var m := (mi as MeshInstance3D).mesh
		meshes.append(mi.name)
		if m == null:
			continue
		for i in m.get_surface_count():
			var arr := m.surface_get_arrays(i)
			verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var mat := m.surface_get_material(i)
			surfs.append(mat.resource_name if mat != null and mat.resource_name != "" else "?")
	var aps := _find_all(root, "AnimationPlayer")
	var anims: Array = []
	for ap in aps:
		anims.append_array((ap as AnimationPlayer).get_animation_list())
	var skel := _find_all(root, "Skeleton3D")
	var bones := (skel[0] as Skeleton3D).get_bone_count() if skel.size() > 0 else 0

	# 親子付けされたノード(棺の Window など)があるので、変換を辿って測る。
	# ツリーに入れずに測るため global_transform は使わない。
	var box: Array = [AABB(), true]
	_collect_aabb(root, Transform3D.IDENTITY, box)
	var aabb: AABB = box[0]

	print("%-22s verts=%-5d meshes=%s mats=%s bones=%-3d anims=%s size=%.2fx%.2fx%.2f" % [
		name, verts, str(meshes), str(surfs), bones, str(anims),
		aabb.size.x, aabb.size.y, aabb.size.z])
	root.free()


func _collect_aabb(n: Node, xform: Transform3D, box: Array) -> void:
	var t := xform
	if n is Node3D:
		t = xform * (n as Node3D).transform
	if n is MeshInstance3D:
		var b: AABB = (n as MeshInstance3D).get_aabb()
		for i in 8:
			var c: Vector3 = t * (b.position + Vector3(
				b.size.x * float(i & 1),
				b.size.y * float((i >> 1) & 1),
				b.size.z * float((i >> 2) & 1)))
			if box[1]:
				box[0] = AABB(c, Vector3.ZERO)
				box[1] = false
			else:
				box[0] = (box[0] as AABB).expand(c)
	for k in n.get_children():
		_collect_aabb(k, t, box)


func _find_all(n: Node, cls: String) -> Array:
	var out: Array = []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_all(c, cls))
	return out
