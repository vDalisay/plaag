## Cuts draw calls (M5 performance): merges the many small MeshInstance3D
## parts the prop kit builds into one mesh per material (and shadow setting,
## and optionally per ground cell so culling still works), baked into the
## frame of a root node. The merged parts are freed; empty Node3D pivots stay.
## Only plain parts are merged: visible, triangle meshes, no script, no
## children. Keeps vertex positions and normals (the kit's materials are flat
## colours, so UVs are not needed).
class_name MeshBatcher
extends RefCounted


## Merges the parts under `root`, skipping the subtrees in `skip`. With
## `cell` > 0 parts are also grouped by an XZ grid of that size (root frame).
## Returns the number of parts merged.
static func merge(root: Node3D, skip: Array[Node] = [], cell := 0.0) -> int:
	var parts: Array[MeshInstance3D] = []
	_collect(root, skip, parts)
	# key -> {"mat", "shadow", "items": [[surface arrays, Transform3D], ...]}
	var groups := {}
	var merged: Array[MeshInstance3D] = []
	for mi in parts:
		if _add(mi, _relative(mi, root), cell, groups):
			merged.append(mi)
	if merged.is_empty():
		return 0
	for key: String in groups:
		var g: Dictionary = groups[key]
		var out := MeshInstance3D.new()
		out.name = "Batch"
		out.mesh = _build(g["items"])
		out.material_override = g["mat"]
		out.cast_shadow = g["shadow"]
		root.add_child(out)
	for mi in merged:
		mi.get_parent().remove_child(mi)
		mi.free()
	return merged.size()


static func _collect(n: Node, skip: Array[Node], out: Array[MeshInstance3D]) -> void:
	for c: Node in n.get_children():
		if skip.has(c):
			continue
		var mi := c as MeshInstance3D
		if mi and mi.mesh and mi.visible and mi.get_script() == null and mi.get_child_count() == 0:
			out.append(mi)
		elif c is Node3D and not (c is MultiMeshInstance3D) and (c as Node3D).visible:
			_collect(c, skip, out)


## `mi`'s transform in `root`'s frame, from the local transforms in between.
static func _relative(mi: Node3D, root: Node3D) -> Transform3D:
	var xf := mi.transform
	var p := mi.get_parent() as Node3D
	while p and p != root:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return xf


## Files every surface of `mi` under its group; false (nothing filed) if any
## surface can't be merged.
static func _add(mi: MeshInstance3D, xf: Transform3D, cell: float, groups: Dictionary) -> bool:
	var mesh := mi.mesh
	var mats: Array[Material] = []
	for s in mesh.get_surface_count():
		var arr_mesh := mesh as ArrayMesh
		if arr_mesh and arr_mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var mat: Material = mi.material_override
		if mat == null:
			mat = mi.get_surface_override_material(s)
		if mat == null:
			mat = mesh.surface_get_material(s)
		if mat == null:
			return false
		mats.append(mat)
	if mats.is_empty():
		return false
	var cell_key := ""
	if cell > 0.0:
		cell_key = "|%d,%d" % [floori(xf.origin.x / cell), floori(xf.origin.z / cell)]
	for s in mats.size():
		var key := "%d|%d%s" % [mats[s].get_instance_id(), mi.cast_shadow, cell_key]
		if not groups.has(key):
			groups[key] = {"mat": mats[s], "shadow": mi.cast_shadow, "items": []}
		(groups[key]["items"] as Array).append([mesh.surface_get_arrays(s), xf])
	return true


## One triangle surface from [surface arrays, transform] items.
static func _build(items: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var ii := PackedInt32Array()
	for item: Array in items:
		var arrays: Array = item[0]
		var xf: Transform3D = item[1]
		var nb := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals := PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL] != null:
			normals = arrays[Mesh.ARRAY_NORMAL]
		var idx := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			idx = arrays[Mesh.ARRAY_INDEX]
		var base := v.size()
		for k in verts.size():
			v.append(xf * verts[k])
			n.append((nb * normals[k]).normalized() if k < normals.size() else Vector3.UP)
		if idx.is_empty():
			idx.resize(verts.size())
			for k in verts.size():
				idx[k] = k
		for t in range(0, idx.size() - 2, 3):
			ii.append(base + idx[t])
			ii.append(base + idx[t + (2 if flip else 1)])
			ii.append(base + idx[t + (1 if flip else 2)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_INDEX] = ii
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
