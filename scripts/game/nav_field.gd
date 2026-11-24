## Fast 2D navigation & obstacle field baked once per District for the Colony
## swarm engine. Allows thousands of rats to slide cleanly along walls and flow
## around house blocks in O(1) per rat with zero 3D physics raycasts or
## CharacterBody3D collisions.
class_name NavField
extends RefCounted

const WALL_CELL := 0.5      # obstacle SDF resolution (u)
const FLOW_CELL := 1.0      # BFS flow-field resolution (u)

var bounds := Rect2(-34.0, -34.0, 68.0, 68.0)
var w_cols := 0
var w_rows := 0
var f_cols := 0
var f_rows := 0

## Signed distance (approx) to nearest obstacle on the 0.5u grid (<= 0 = blocked).
var _solid := PackedByteArray()
var _push_x := PackedFloat32Array()
var _push_z := PackedFloat32Array()

## Flow-field BFS grid (1.0u): direction (fx, fz) toward the goal (Lead Rat / target).
var _f_solid := PackedByteArray()
var _flow_x := PackedFloat32Array()
var _flow_z := PackedFloat32Array()
var _dist := PackedInt32Array()
var _queue := PackedInt32Array()
var _last_goal_cell := Vector2i(-9999, -9999)


## Bakes the static obstacle grid from District bounds and blockers
## ([{"xf": Transform3D, "half": Vector2}, ...]).
func bake(rect: Rect2, blockers: Array[Dictionary], rat_margin := 0.28) -> void:
	bounds = rect
	w_cols = maxi(4, ceili(bounds.size.x / WALL_CELL))
	w_rows = maxi(4, ceili(bounds.size.y / WALL_CELL))
	var wn := w_cols * w_rows
	_solid.resize(wn)
	_solid.fill(0)
	_push_x.resize(wn)
	_push_z.resize(wn)
	_push_x.fill(0.0)
	_push_z.fill(0.0)

	# Rasterize every blocker into the 0.5u grid and precompute outward escape normals.
	for b in blockers:
		var xf: Transform3D = b["xf"]
		var inv := xf.affine_inverse()
		var half: Vector2 = b["half"]
		var hx := half.x + rat_margin
		var hz := half.y + rat_margin
		var rad := sqrt(hx * hx + hz * hz) + WALL_CELL
		var c0 := clampi(floori((xf.origin.x - rad - bounds.position.x) / WALL_CELL), 0, w_cols - 1)
		var c1 := clampi(ceili((xf.origin.x + rad - bounds.position.x) / WALL_CELL), 0, w_cols - 1)
		var r0 := clampi(floori((xf.origin.z - rad - bounds.position.y) / WALL_CELL), 0, w_rows - 1)
		var r1 := clampi(ceili((xf.origin.z + rad - bounds.position.y) / WALL_CELL), 0, w_rows - 1)
		for r in range(r0, r1 + 1):
			var wz := bounds.position.y + (float(r) + 0.5) * WALL_CELL
			for c in range(c0, c1 + 1):
				var wx := bounds.position.x + (float(c) + 0.5) * WALL_CELL
				var l := inv * Vector3(wx, 0.0, wz)
				if absf(l.x) <= hx and absf(l.z) <= hz:
					var idx := r * w_cols + c
					_solid[idx] = 1
					# Shortest push out of this box in local space, rotated back to world.
					var ox := hx - absf(l.x)
					var oz := hz - absf(l.z)
					var local_out := Vector3.ZERO
					if ox < oz:
						local_out.x = (1.0 if l.x >= 0.0 else -1.0) * (ox + WALL_CELL * 0.75)
					else:
						local_out.z = (1.0 if l.z >= 0.0 else -1.0) * (oz + WALL_CELL * 0.75)
					var world_out := xf.basis * local_out
					_push_x[idx] = world_out.x
					_push_z[idx] = world_out.z

	# Build coarser 1.0u flow grid from the obstacle grid.
	f_cols = maxi(4, ceili(bounds.size.x / FLOW_CELL))
	f_rows = maxi(4, ceili(bounds.size.y / FLOW_CELL))
	var fn := f_cols * f_rows
	_f_solid.resize(fn)
	_f_solid.fill(0)
	_flow_x.resize(fn)
	_flow_z.resize(fn)
	_flow_x.fill(0.0)
	_flow_z.fill(0.0)
	_dist.resize(fn)
	_queue.resize(fn)
	for r in f_rows:
		var wz := bounds.position.y + (float(r) + 0.5) * FLOW_CELL
		for c in f_cols:
			var wx := bounds.position.x + (float(c) + 0.5) * FLOW_CELL
			if is_blocked_xy(wx, wz):
				_f_solid[r * f_cols + c] = 1
	_last_goal_cell = Vector2i(-9999, -9999)


## True if world XZ lies inside an obstacle or outside District bounds.
func is_blocked_xy(wx: float, wz: float) -> bool:
	var c := floori((wx - bounds.position.x) / WALL_CELL)
	var r := floori((wz - bounds.position.y) / WALL_CELL)
	if c < 0 or c >= w_cols or r < 0 or r >= w_rows:
		return true
	return _solid[r * w_cols + c] != 0


## Resolves world (x, z) out of static walls/blockers & bounds in O(1).
func resolve_xy(p: Vector2) -> Vector2:
	var x := clampf(p.x, bounds.position.x + 0.35, bounds.end.x - 0.35)
	var z := clampf(p.y, bounds.position.y + 0.35, bounds.end.y - 0.35)
	if w_cols <= 0:
		return Vector2(x, z)
	for _iter in 2:
		var c := clampi(floori((x - bounds.position.x) / WALL_CELL), 0, w_cols - 1)
		var r := clampi(floori((z - bounds.position.y) / WALL_CELL), 0, w_rows - 1)
		var idx := r * w_cols + c
		if _solid[idx] == 0:
			break
		var px := _push_x[idx]
		var pz := _push_z[idx]
		if px * px + pz * pz > 0.0001:
			x += px
			z += pz
		else:
			break
	x = clampf(x, bounds.position.x + 0.35, bounds.end.x - 0.35)
	z = clampf(z, bounds.position.y + 0.35, bounds.end.y - 0.35)
	return Vector2(x, z)


## Recomputes the BFS flow field toward `goal` whenever the goal moves to a new cell.
func update_flow(goal: Vector2) -> void:
	if f_cols <= 0:
		return
	var gc := clampi(floori((goal.x - bounds.position.x) / FLOW_CELL), 0, f_cols - 1)
	var gr := clampi(floori((goal.y - bounds.position.y) / FLOW_CELL), 0, f_rows - 1)
	var gcell := Vector2i(gc, gr)
	if gcell == _last_goal_cell:
		return
	_last_goal_cell = gcell
	var fn := f_cols * f_rows
	_dist.fill(-1)
	var head := 0
	var tail := 0
	var start_idx := gr * f_cols + gc
	# If goal sits on a solid cell, seed from the nearest open neighbour.
	if _f_solid[start_idx] != 0:
		var found := false
		for rad in range(1, 4):
			for dr in range(-rad, rad + 1):
				for dc in range(-rad, rad + 1):
					var nr := gr + dr
					var nc := gc + dc
					if nr >= 0 and nr < f_rows and nc >= 0 and nc < f_cols:
						var ni := nr * f_cols + nc
						if _f_solid[ni] == 0:
							_dist[ni] = 0
							_queue[tail] = ni
							tail += 1
							found = true
			if found:
				break
	else:
		_dist[start_idx] = 0
		_queue[tail] = start_idx
		tail += 1

	while head < tail:
		var cur := _queue[head]
		head += 1
		var d := _dist[cur] + 1
		var cr := cur / f_cols
		var cc := cur - cr * f_cols
		if cc > 0:
			var ni := cur - 1
			if _dist[ni] < 0 and _f_solid[ni] == 0:
				_dist[ni] = d
				_queue[tail] = ni
				tail += 1
		if cc + 1 < f_cols:
			var ni := cur + 1
			if _dist[ni] < 0 and _f_solid[ni] == 0:
				_dist[ni] = d
				_queue[tail] = ni
				tail += 1
		if cr > 0:
			var ni := cur - f_cols
			if _dist[ni] < 0 and _f_solid[ni] == 0:
				_dist[ni] = d
				_queue[tail] = ni
				tail += 1
		if cr + 1 < f_rows:
			var ni := cur + f_cols
			if _dist[ni] < 0 and _f_solid[ni] == 0:
				_dist[ni] = d
				_queue[tail] = ni
				tail += 1

	# Compute smooth downhill flow vector per open cell (including diagonals).
	for r in f_rows:
		for c in f_cols:
			var idx := r * f_cols + c
			var best_d := _dist[idx]
			if best_d <= 0:
				_flow_x[idx] = 0.0
				_flow_z[idx] = 0.0
				continue
			var bx := 0.0
			var bz := 0.0
			for dr in range(-1, 2):
				var nr := r + dr
				if nr < 0 or nr >= f_rows:
					continue
				for dc in range(-1, 2):
					if dr == 0 and dc == 0:
						continue
					var nc := c + dc
					if nc < 0 or nc >= f_cols:
						continue
					# Don't cut diagonally across a wall corner.
					if dr != 0 and dc != 0 and (_f_solid[r * f_cols + nc] != 0 or _f_solid[nr * f_cols + c] != 0):
						continue
					var nd := _dist[nr * f_cols + nc]
					if nd >= 0 and nd < best_d:
						best_d = nd
						bx = float(dc)
						bz = float(dr)
			var l := sqrt(bx * bx + bz * bz)
			if l > 0.001:
				_flow_x[idx] = bx / l
				_flow_z[idx] = bz / l
			else:
				_flow_x[idx] = 0.0
				_flow_z[idx] = 0.0


## Unit flow direction from world XZ toward the current BFS goal (or ZERO).
func flow_at(p: Vector2) -> Vector2:
	if f_cols <= 0:
		return Vector2.ZERO
	var c := clampi(floori((p.x - bounds.position.x) / FLOW_CELL), 0, f_cols - 1)
	var r := clampi(floori((p.y - bounds.position.y) / FLOW_CELL), 0, f_rows - 1)
	var idx := r * f_cols + c
	return Vector2(_flow_x[idx], _flow_z[idx])


## Fast 2D grid line-of-sight check (DDA step along 0.5u obstacle grid, zero 3D raycasts).
func clear_line_xy(a: Vector2, b: Vector2) -> bool:
	if w_cols <= 0:
		return true
	var d := b - a
	var dist := d.length()
	if dist < 0.05:
		return true
	var steps := maxi(1, ceili(dist / (WALL_CELL * 0.9)))
	var step := d / float(steps)
	var p := a
	for i in range(1, steps):
		p += step
		if is_blocked_xy(p.x, p.y):
			return false
	return true
