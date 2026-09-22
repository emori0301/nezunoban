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
	"npc_boss": ["idle", "walk"],
	"npc_son": ["idle", "walk"],
	"npc_granddaughter": ["idle", "walk"],
	"body_risen": ["rise"],
	"hanging_robe": ["sway", "drop"],
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

	var aabb := AABB()
	var first := true
	for mi in _find_all(root, "MeshInstance3D"):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		b.position += (mi as Node3D).position
		if first:
			aabb = b
			first = false
		else:
			aabb = aabb.merge(b)

	print("%-22s verts=%-5d meshes=%s mats=%s bones=%-3d anims=%s size=%.2fx%.2fx%.2f" % [
		name, verts, str(meshes), str(surfs), bones, str(anims),
		aabb.size.x, aabb.size.y, aabb.size.z])
	root.free()


func _find_all(n: Node, cls: String) -> Array:
	var out: Array = []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_all(c, cls))
	return out
