## High-performance data-oriented (Struct-of-Arrays) rat swarm simulation &
## MultiMesh renderer. Simulates 2,000-3,500+ follower rats (Adults + Pups) at
## 60 FPS using:
##   * Flat Packed*Array storage + O(1) swap-remove on death (zero per-rat Nodes)
##   * 2 MultiMeshInstance3D draw calls total (1 Adults, 1 Pups)
##   * O(N) density-gradient separation + flat linked-list spatial hash (zero GC)
##   * O(1) NavField obstacle repulsion & BFS flow-field pathing around houses
##   * Staggered 15 Hz AI/Bite/Danger slices with per-frame VFX budgets
class_name SwarmSim
extends RefCounted

const Props := preload("res://scripts/town_props.gd")
const Vfx := preload("res://scripts/vfx/vfx.gd")

const MAX_RATS := 3500
const INITIAL_CAP := 256
const ADULT_SCALE := 0.92
const PUP_SCALE := 0.54
const HASH_CELL := 0.85
const SLICE_COUNT := 4
const FUNNEL_TIME := 0.28
const KNOCK_TIME := 0.25
const LUNGE_TIME := 0.20
const RAID_GIVE_UP := 6.0
const RAID_MIN_INSIDE := 0.5
const BITE_VFX_CAP := 14
const DEATH_VFX_CAP := 12

enum State { FOLLOW = 0, FEED = 1, RAID_GO = 2, FUNNEL_IN = 3, INSIDE = 4, POUR_OUT = 5 }

var count := 0
var cap := 0
var adult_count := 0
var pup_count := 0
var raiders_inside := 0

# SoA rat fields (indices 0..count-1 are live)
var pos_x := PackedFloat32Array()
var pos_z := PackedFloat32Array()
var vel_x := PackedFloat32Array()
var vel_z := PackedFloat32Array()
var yaw := PackedFloat32Array()
var slot_x := PackedFloat32Array()
var slot_z := PackedFloat32Array()
var slot_back := PackedFloat32Array()
var swarm_x := PackedFloat32Array()      # INF = not swarming
var swarm_z := PackedFloat32Array()
var goal_x := PackedFloat32Array()
var goal_z := PackedFloat32Array()
var bite_cd := PackedFloat32Array()
var maturity := PackedFloat32Array()
var breed_cd := PackedFloat32Array()
var feed_left := PackedFloat32Array()
var state_t := PackedFloat32Array()      # funnel/pour/inside/raid timer
var knock_t := PackedFloat32Array()
var knock_vx := PackedFloat32Array()
var knock_vz := PackedFloat32Array()
var lunge_t := PackedFloat32Array()
var phase := PackedFloat32Array()
var is_pup := PackedByteArray()          # 0 = Adult, 1 = Pup
var state := PackedByteArray()           # State enum
var raiding := PackedByteArray()         # 0 / 1
var escaping := PackedByteArray()        # 0 = none, 1 = escape, 2 = hold
var house_idx := PackedInt32Array()      # index into tracked houses, -1 = none
var corpse_ref: Array[Node3D] = []       # corpse being fed on (null when none)

# Spatial hash (flat linked list, zero allocations per frame)
var _grid_bounds := Rect2(-34.0, -34.0, 68.0, 68.0)
var _g_cols := 80
var _g_rows := 80
var _cell_head := PackedInt32Array()
var _cell_count := PackedInt32Array()
var _next_rat := PackedInt32Array()

# Rendering: 2 MultiMeshes total + preallocated flat 12-float transform buffers
var _adult_mm: MultiMesh
var _pup_mm: MultiMesh
var _adult_mmi: MultiMeshInstance3D
var _pup_mmi: MultiMeshInstance3D
var _adult_buf := PackedFloat32Array()
var _pup_buf := PackedFloat32Array()
var _sim_parity := 0

# References & cached per-frame target lists
var _colony: Colony
var _nav: NavField
var _houses: Array[House] = []
var _t_nodes: Array[Node3D] = []
var _t_infs: Array[InfectionComponent] = []
var _t_x := PackedFloat32Array()
var _t_z := PackedFloat32Array()
var _slice := 0
var _time := 0.0
var _bite_vfx_used := 0
var _death_vfx_used := 0
var _dirty_counts := false
var _dirty_layout := false
var _flow_left := 0.0
var _rng := RandomNumberGenerator.new()


func _init(colony: Colony, nav: NavField) -> void:
	_colony = colony
	_nav = nav
	_rng.seed = 97
	_grow(INITIAL_CAP)
	_build_grid_storage(nav.bounds if nav else Rect2(-34, -34, 68, 68))
	_build_multimeshes()


func set_bounds(rect: Rect2) -> void:
	_build_grid_storage(rect)


func _build_grid_storage(rect: Rect2) -> void:
	_grid_bounds = rect
	_g_cols = maxi(8, ceili(rect.size.x / HASH_CELL))
	_g_rows = maxi(8, ceili(rect.size.y / HASH_CELL))
	var n := _g_cols * _g_rows
	_cell_head.resize(n)
	_cell_count.resize(n)
	_cell_head.fill(-1)
	_cell_count.fill(0)


func _grow(new_cap: int) -> void:
	new_cap = mini(maxi(new_cap, cap * 2), MAX_RATS)
	if new_cap <= cap:
		return
	cap = new_cap
	pos_x.resize(cap)
	pos_z.resize(cap)
	vel_x.resize(cap)
	vel_z.resize(cap)
	yaw.resize(cap)
	slot_x.resize(cap)
	slot_z.resize(cap)
	slot_back.resize(cap)
	swarm_x.resize(cap)
	swarm_z.resize(cap)
	goal_x.resize(cap)
	goal_z.resize(cap)
	bite_cd.resize(cap)
	maturity.resize(cap)
	breed_cd.resize(cap)
	feed_left.resize(cap)
	state_t.resize(cap)
	knock_t.resize(cap)
	knock_vx.resize(cap)
	knock_vz.resize(cap)
	lunge_t.resize(cap)
	phase.resize(cap)
	is_pup.resize(cap)
	state.resize(cap)
	raiding.resize(cap)
	escaping.resize(cap)
	house_idx.resize(cap)
	_next_rat.resize(cap)
	corpse_ref.resize(cap)
	_adult_buf.resize(cap * 12)
	_pup_buf.resize(cap * 12)
	if _adult_mm != null:
		_adult_mm.instance_count = cap
		_pup_mm.instance_count = cap


func _build_multimeshes() -> void:
	var mesh := _build_rat_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Props.INK
	mat.roughness = 0.95

	_adult_mm = MultiMesh.new()
	_adult_mm.transform_format = MultiMesh.TRANSFORM_3D
	_adult_mm.mesh = mesh
	_adult_mm.instance_count = cap
	_adult_mm.visible_instance_count = 0
	_adult_mmi = MultiMeshInstance3D.new()
	_adult_mmi.name = "SwarmAdults"
	_adult_mmi.multimesh = _adult_mm
	_adult_mmi.material_override = mat
	_adult_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_adult_mmi.custom_aabb = AABB(Vector3(-120, -4, -120), Vector3(240, 12, 240))
	_colony.add_child(_adult_mmi)

	var pup_mat := StandardMaterial3D.new()
	pup_mat.albedo_color = Color(0.11, 0.09, 0.08)
	pup_mat.roughness = 1.0
	_pup_mm = MultiMesh.new()
	_pup_mm.transform_format = MultiMesh.TRANSFORM_3D
	_pup_mm.mesh = mesh
	_pup_mm.instance_count = cap
	_pup_mm.visible_instance_count = 0
	_pup_mmi = MultiMeshInstance3D.new()
	_pup_mmi.name = "SwarmPups"
	_pup_mmi.multimesh = _pup_mm
	_pup_mmi.material_override = pup_mat
	_pup_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pup_mmi.custom_aabb = AABB(Vector3(-120, -4, -120), Vector3(240, 12, 240))
	_colony.add_child(_pup_mmi)


## Builds one compact merged rat ArrayMesh matching Props.rat() silhouette.
func _build_rat_mesh() -> ArrayMesh:
	var tmp := Node3D.new()
	var kit := Props.new(41)
	kit.rat(tmp, Vector3.ZERO, 0.0, 1.0)
	var items: Array = []
	for n: Node in tmp.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := MeshBatcher._relative(mi, tmp)
		for s in mi.mesh.get_surface_count():
			var pa := MeshBatcher.part_arrays(mi.mesh, s)
			items.append([pa[0], xf * (pa[1] as Transform3D)])
	var merged := MeshBatcher._build(items)
	tmp.free()
	return merged


# ---------------------------------------------------------------------- spawning / removal
func add_rat(pup: bool, pos: Vector3) -> int:
	if count >= MAX_RATS:
		return -1
	if count >= cap:
		_grow(cap * 2)
	var i := count
	count += 1
	var p := _nav.resolve_xy(Vector2(pos.x, pos.z)) if _nav else Vector2(pos.x, pos.z)
	pos_x[i] = p.x
	pos_z[i] = p.y
	vel_x[i] = 0.0
	vel_z[i] = 0.0
	yaw[i] = _rng.randf() * TAU
	slot_x[i] = 0.0
	slot_z[i] = 0.0
	slot_back[i] = 1.5
	swarm_x[i] = INF
	swarm_z[i] = INF
	goal_x[i] = p.x
	goal_z[i] = p.y
	bite_cd[i] = _rng.randf() * _colony.bite_cooldown
	maturity[i] = _colony.pup_maturity if pup else 0.0
	breed_cd[i] = 0.0
	feed_left[i] = 0.0
	state_t[i] = 0.0
	knock_t[i] = 0.0
	knock_vx[i] = 0.0
	knock_vz[i] = 0.0
	lunge_t[i] = INF
	phase[i] = _rng.randf() * TAU
	is_pup[i] = 1 if pup else 0
	state[i] = State.FOLLOW
	raiding[i] = 0
	escaping[i] = 0
	house_idx[i] = -1
	corpse_ref[i] = null
	if pup:
		pup_count += 1
	else:
		adult_count += 1
	_dirty_layout = true
	return i


## O(1) swap-remove rat at `i`.
func kill_at(i: int, play_vfx := true) -> void:
	if i < 0 or i >= count:
		return
	var was_pup := is_pup[i] != 0
	var wx := pos_x[i]
	var wz := pos_z[i]
	if was_pup:
		pup_count = maxi(0, pup_count - 1)
	else:
		adult_count = maxi(0, adult_count - 1)
	_colony.deaths += 1
	if play_vfx and _death_vfx_used < DEATH_VFX_CAP:
		_death_vfx_used += 1
		Vfx.play(_colony.get_tree(), &"rat_splat", Vector3(wx, 0.0, wz), Vector3.ZERO, 0.65 if was_pup else 0.95)
	count -= 1
	if i < count:
		_copy(count, i)
	corpse_ref[count] = null
	_dirty_counts = true
	_dirty_layout = true


func _copy(from: int, to: int) -> void:
	pos_x[to] = pos_x[from]
	pos_z[to] = pos_z[from]
	vel_x[to] = vel_x[from]
	vel_z[to] = vel_z[from]
	yaw[to] = yaw[from]
	slot_x[to] = slot_x[from]
	slot_z[to] = slot_z[from]
	slot_back[to] = slot_back[from]
	swarm_x[to] = swarm_x[from]
	swarm_z[to] = swarm_z[from]
	goal_x[to] = goal_x[from]
	goal_z[to] = goal_z[from]
	bite_cd[to] = bite_cd[from]
	maturity[to] = maturity[from]
	breed_cd[to] = breed_cd[from]
	feed_left[to] = feed_left[from]
	state_t[to] = state_t[from]
	knock_t[to] = knock_t[from]
	knock_vx[to] = knock_vx[from]
	knock_vz[to] = knock_vz[from]
	lunge_t[to] = lunge_t[from]
	phase[to] = phase[from]
	is_pup[to] = is_pup[from]
	state[to] = state[from]
	raiding[to] = raiding[from]
	escaping[to] = escaping[from]
	house_idx[to] = house_idx[from]
	corpse_ref[to] = corpse_ref[from]


# ---------------------------------------------------------------------- layout & swarm slots
func relayout() -> void:
	_dirty_layout = false
	var a_n := 0
	var p_n := 0
	for i in count:
		if raiding[i] != 0:
			continue
		if is_pup[i] != 0:
			p_n += 1
		else:
			a_n += 1
	var ra := 0.45 * sqrt(float(maxi(1, a_n)))
	var rp := 0.35 * sqrt(float(maxi(1, p_n)))
	var a_back := 1.0 + minf(ra * 0.95, 6.0)
	var p_back := a_back + minf(ra * 0.9, 5.0) + 0.5 + minf(rp * 0.9, 4.0)
	var ai := 0
	var pi := 0
	for i in count:
		if raiding[i] != 0:
			continue
		if is_pup[i] != 0:
			var r := rp * sqrt((float(pi) + 0.5) / float(maxi(1, p_n)))
			var a := float(pi) * 2.39996
			slot_x[i] = r * cos(a)
			slot_z[i] = r * sin(a) * 1.18
			slot_back[i] = p_back
			pi += 1
		else:
			var r := ra * sqrt((float(ai) + 0.5) / float(maxi(1, a_n)))
			var a := float(ai) * 2.39996
			slot_x[i] = r * cos(a)
			slot_z[i] = r * sin(a) * 1.18
			slot_back[i] = a_back
			ai += 1


func assign_swarm(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		for i in count:
			swarm_x[i] = INF
			swarm_z[i] = INF
		return
	var ring := 0
	var in_ring := 0
	var ring_cap := 8
	var rad := Colony.SWARM_RING0
	for i in count:
		if is_pup[i] != 0 or raiding[i] != 0 or state[i] >= State.FUNNEL_IN:
			swarm_x[i] = INF
			swarm_z[i] = INF
			continue
		var a := TAU * (float(in_ring) + 0.5 * float(ring % 2)) / float(ring_cap)
		swarm_x[i] = sin(a) * rad
		swarm_z[i] = cos(a) * rad
		in_ring += 1
		if in_ring >= ring_cap:
			ring += 1
			in_ring = 0
			rad = Colony.SWARM_RING0 + Colony.SWARM_RING_GAP * float(ring)
			ring_cap = maxi(6, floori(TAU * rad / Colony.SWARM_SPACING))


func clear_swarm() -> void:
	for i in count:
		swarm_x[i] = INF
		swarm_z[i] = INF


# ---------------------------------------------------------------------- houses (Hide & Raid)
func _house_id(h: House) -> int:
	var idx := _houses.find(h)
	if idx < 0:
		idx = _houses.size()
		_houses.append(h)
	return idx


func hide_all_in(h: House) -> void:
	var hid := _house_id(h)
	var inside := h.door_position - h.door_normal * 0.45
	for i in count:
		if raiding[i] != 0 or state[i] == State.INSIDE or state[i] == State.FUNNEL_IN:
			continue
		state[i] = State.FUNNEL_IN
		house_idx[i] = hid
		goal_x[i] = inside.x
		goal_z[i] = inside.z
		state_t[i] = FUNNEL_TIME
		corpse_ref[i] = null


func pour_all_out(h: House) -> void:
	var hid := _houses.find(h)
	if hid < 0:
		return
	var out := h.door_position + h.door_normal * 0.9
	var side := h.door_normal.cross(Vector3.UP)
	for i in count:
		if raiding[i] != 0 or house_idx[i] != hid:
			continue
		if state[i] != State.INSIDE and state[i] != State.FUNNEL_IN:
			continue
		var spot := out + h.door_normal * _rng.randf_range(0.2, 2.2) + side * _rng.randf_range(-1.6, 1.6)
		var rp := _nav.resolve_xy(Vector2(spot.x, spot.z)) if _nav else Vector2(spot.x, spot.z)
		pos_x[i] = h.door_position.x - h.door_normal.x * 0.35
		pos_z[i] = h.door_position.z - h.door_normal.z * 0.35
		goal_x[i] = rp.x
		goal_z[i] = rp.y
		state[i] = State.POUR_OUT
		state_t[i] = FUNNEL_TIME
		house_idx[i] = -1


func raid_available_count() -> int:
	var n := 0
	for i in count:
		if is_pup[i] == 0 and raiding[i] == 0 and state[i] < State.FUNNEL_IN:
			n += 1
	return n


func start_raid(h: House, max_n: int, duration: float) -> int:
	var hid := _house_id(h)
	var door := h.door_position
	var picks: Array = []
	for i in count:
		if is_pup[i] == 0 and raiding[i] == 0 and state[i] < State.FUNNEL_IN:
			var dx := pos_x[i] - door.x
			var dz := pos_z[i] - door.z
			picks.append([dx * dx + dz * dz, i])
	if picks.is_empty():
		return 0
	picks.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var sent := mini(max_n, picks.size())
	for k in sent:
		var i := int(picks[k][1])
		raiding[i] = 1
		state[i] = State.RAID_GO
		house_idx[i] = hid
		goal_x[i] = door.x
		goal_z[i] = door.z
		state_t[i] = RAID_GIVE_UP
		feed_left[i] = duration
		corpse_ref[i] = null
	_dirty_layout = true
	return sent


func active_raid_houses() -> Dictionary:
	var out := {}
	var inside := 0
	for i in count:
		if raiding[i] != 0 and house_idx[i] >= 0 and house_idx[i] < _houses.size():
			var h := _houses[house_idx[i]]
			if is_instance_valid(h):
				out[h] = true
				if state[i] == State.INSIDE:
					inside += 1
	raiders_inside = inside
	return out


# ---------------------------------------------------------------------- per-frame tick
func step(delta: float) -> void:
	_time += delta
	_bite_vfx_used = 0
	_death_vfx_used = 0
	_dirty_counts = false
	if _dirty_layout:
		relayout()
	if count == 0:
		_adult_mm.visible_instance_count = 0
		_pup_mm.visible_instance_count = 0
		return

	var lead_p := _colony.lead_position()
	var lpx := lead_p.x
	var lpz := lead_p.z
	var heading := _colony.heading
	var head_ang := atan2(heading.x, heading.z)
	var cos_h := cos(head_ang)
	var sin_h := sin(head_ang)
	var gather := _colony.gather
	var gather_x := 1.0 + 0.2 * gather
	var gather_b := 1.0 - 0.5 * gather
	var lead_speed: float = float(_colony.lead.get("max_speed")) if _colony.lead else 6.0
	var top_speed := lead_speed * _colony.speed_factor
	var has_zones := _colony.has_zones()
	var swarm_t: Node3D = _colony.swarm_target
	var swarm_ok := swarm_t != null and is_instance_valid(swarm_t)
	var sw_cx := swarm_t.global_position.x if swarm_ok else 0.0
	var sw_cz := swarm_t.global_position.z if swarm_ok else 0.0

	# Refresh flow field at ~10 Hz toward Lead Rat (or swarm target).
	_flow_left -= delta
	if _nav != null and _flow_left <= 0.0:
		_flow_left = 0.1
		_nav.update_flow(Vector2(sw_cx, sw_cz) if swarm_ok else Vector2(lpx, lpz))

	# Cache living outdoor townsfolk & rebuild O(N) spatial hash + density grid.
	_cache_townsfolk()
	_rebuild_spatial_hash()

	var bite_r2 := _colony.bite_range * _colony.bite_range
	var bite_cd_base := _colony.bite_cooldown
	var bite_chunk := _colony.bite_chunk
	var bite_rate := _colony.bite_rate_bonus
	var tree := _colony.get_tree()
	var slice := _slice
	_slice = (_slice + 1) % SLICE_COUNT
	var new_pups: Array[Vector3] = []

	# Interleave heavy swarms (> 400 rats) across 2 alternating halves at 2x dt
	# so 2,500-3,500 rats stay comfortably under 8 ms/frame while moving smoothly!
	var interleave := count > 400
	var parity := _sim_parity
	_sim_parity = 1 - _sim_parity
	var step_dt := delta * 2.0 if interleave else delta
	var accel := minf(1.0, 9.5 * step_dt)
	var turn_k := minf(1.0, step_dt * 12.0)

	# Local cached references for fast tight-loop indexing (zero method calls in hot path!)
	var has_nav := _nav != null and _nav.w_cols > 0
	var nav_bx := _nav.bounds.position.x if has_nav else -34.0
	var nav_bz := _nav.bounds.position.y if has_nav else -34.0
	var nav_ex := _nav.bounds.end.x - 0.35 if has_nav else 33.65
	var nav_ez := _nav.bounds.end.y - 0.35 if has_nav else 33.65
	var nav_minx := nav_bx + 0.35
	var nav_minz := nav_bz + 0.35
	var nav_wc := _nav.w_cols if has_nav else 0
	var nav_wr := _nav.w_rows if has_nav else 0
	var nav_solid := _nav._solid if has_nav else PackedByteArray()
	var nav_px := _nav._push_x if has_nav else PackedFloat32Array()
	var nav_pz := _nav._push_z if has_nav else PackedFloat32Array()
	var nav_fc := _nav.f_cols if has_nav else 0
	var nav_fr := _nav.f_rows if has_nav else 0
	var nav_fx := _nav._flow_x if has_nav else PackedFloat32Array()
	var nav_fz := _nav._flow_z if has_nav else PackedFloat32Array()
	var inv_wcell := 1.0 / NavField.WALL_CELL
	var inv_hcell := 1.0 / HASH_CELL
	var g_bx := _grid_bounds.position.x
	var g_bz := _grid_bounds.position.y
	var g_cols := _g_cols
	var g_rows := _g_rows
	var g_cols_m1 := g_cols - 1
	var g_rows_m1 := g_rows - 1
	var has_t := not _t_nodes.is_empty()
	var feed_lead_r2 := _colony.feed_lead_radius * _colony.feed_lead_radius
	var t_now := _time

	var a_vis := 0
	var p_vis := 0
	var i := 0
	while i < count:
		var st := state[i]
		# Fast path for interleaved non-active half: advance smoothly by velocity & pack buffer!
		if interleave and (i & 1) != parity and st == State.FOLLOW and knock_t[i] <= 0.0:
			var fpx := pos_x[i] + vel_x[i] * delta
			var fpz := pos_z[i] + vel_z[i] * delta
			if has_nav:
				fpx = clampf(fpx, nav_minx, nav_ex)
				fpz = clampf(fpz, nav_minz, nav_ez)
				var wc := clampi(int((fpx - nav_bx) * inv_wcell), 0, nav_wc - 1)
				var wr := clampi(int((fpz - nav_bz) * inv_wcell), 0, nav_wr - 1)
				var widx := wr * nav_wc + wc
				if nav_solid[widx] != 0:
					fpx = clampf(fpx + nav_px[widx], nav_minx, nav_ex)
					fpz = clampf(fpz + nav_pz[widx], nav_minz, nav_ez)
			pos_x[i] = fpx
			pos_z[i] = fpz
			var a0 := yaw[i]
			var ca0 := cos(a0)
			var sa0 := sin(a0)
			var scl0 := PUP_SCALE if is_pup[i] != 0 else ADULT_SCALE
			var off0 := (p_vis if is_pup[i] != 0 else a_vis) * 12
			var buf0 := _pup_buf if is_pup[i] != 0 else _adult_buf
			buf0[off0] = ca0 * scl0
			buf0[off0 + 1] = 0.0
			buf0[off0 + 2] = sa0 * scl0
			buf0[off0 + 3] = fpx
			buf0[off0 + 4] = 0.0
			buf0[off0 + 5] = scl0
			buf0[off0 + 6] = 0.0
			buf0[off0 + 7] = 0.02
			buf0[off0 + 8] = -sa0 * scl0
			buf0[off0 + 9] = 0.0
			buf0[off0 + 10] = ca0 * scl0
			buf0[off0 + 11] = fpz
			if is_pup[i] != 0:
				p_vis += 1
			else:
				a_vis += 1
			i += 1
			continue

		var is_slice := (i % SLICE_COUNT) == slice
		if breed_cd[i] > 0.0:
			breed_cd[i] = maxf(0.0, breed_cd[i] - step_dt)
		if bite_cd[i] > 0.0:
			bite_cd[i] = maxf(0.0, bite_cd[i] - step_dt)
		if lunge_t[i] != INF:
			lunge_t[i] += step_dt
			if lunge_t[i] >= LUNGE_TIME:
				lunge_t[i] = INF
		if is_pup[i] != 0:
			maturity[i] -= step_dt
			if maturity[i] <= 0.0:
				is_pup[i] = 0
				pup_count = maxi(0, pup_count - 1)
				adult_count += 1
				_colony.maturings += 1
				_dirty_counts = true
				_dirty_layout = true

		# ---- Indoor / Funnel / Pour states
		if st == State.INSIDE:
			if is_pup[i] == 0 and bite_cd[i] <= 0.0 and is_slice:
				_bite_inside(i, bite_cd_base, bite_chunk, bite_rate)
			if raiding[i] != 0:
				state_t[i] += step_dt
				feed_left[i] -= step_dt
				var h := _houses[house_idx[i]] if house_idx[i] >= 0 and house_idx[i] < _houses.size() else null
				var done := h == null or not is_instance_valid(h) or feed_left[i] <= 0.0 \
					or (state_t[i] > RAID_MIN_INSIDE and h.living_occupants().is_empty())
				if done:
					if h != null and is_instance_valid(h):
						var side := h.door_normal.cross(Vector3.UP)
						var to := h.door_position + h.door_normal * _rng.randf_range(0.5, 1.3) + side * _rng.randf_range(-0.7, 0.7)
						pos_x[i] = h.door_position.x - h.door_normal.x * 0.3
						pos_z[i] = h.door_position.z - h.door_normal.z * 0.3
						goal_x[i] = to.x
						goal_z[i] = to.z
						state[i] = State.POUR_OUT
						state_t[i] = FUNNEL_TIME
					else:
						state[i] = State.FOLLOW
						raiding[i] = 0
						house_idx[i] = -1
			i += 1
			continue
		if st == State.FUNNEL_IN:
			state_t[i] -= step_dt
			var f := clampf(step_dt / maxf(state_t[i] + step_dt, 0.02), 0.0, 1.0)
			pos_x[i] = lerpf(pos_x[i], goal_x[i], f)
			pos_z[i] = lerpf(pos_z[i], goal_z[i], f)
			if state_t[i] <= 0.0:
				state[i] = State.INSIDE
				state_t[i] = 0.0
			else:
				var sc := lerpf(0.2, 1.0, clampf(state_t[i] / FUNNEL_TIME, 0.0, 1.0))
				if is_pup[i] != 0:
					_pack_buf(_pup_buf, p_vis, i, PUP_SCALE * sc)
					p_vis += 1
				else:
					_pack_buf(_adult_buf, a_vis, i, ADULT_SCALE * sc)
					a_vis += 1
			i += 1
			continue
		if st == State.POUR_OUT:
			state_t[i] -= step_dt
			var f := clampf(step_dt / maxf(state_t[i] + step_dt, 0.02), 0.0, 1.0)
			pos_x[i] = lerpf(pos_x[i], goal_x[i], f)
			pos_z[i] = lerpf(pos_z[i], goal_z[i], f)
			if state_t[i] <= 0.0:
				state[i] = State.FOLLOW
				raiding[i] = 0
				house_idx[i] = -1
				_dirty_layout = true
			var sc := lerpf(1.0, 0.2, clampf(state_t[i] / FUNNEL_TIME, 0.0, 1.0))
			if is_pup[i] != 0:
				_pack_buf(_pup_buf, p_vis, i, PUP_SCALE * sc)
				p_vis += 1
			else:
				_pack_buf(_adult_buf, a_vis, i, ADULT_SCALE * sc)
				a_vis += 1
			i += 1
			continue

		# ---- Outdoor rat
		var px := pos_x[i]
		var pz := pos_z[i]

		if knock_t[i] > 0.0:
			knock_t[i] = maxf(0.0, knock_t[i] - step_dt)
			var k := knock_t[i] / KNOCK_TIME
			var knx := clampf(px + knock_vx[i] * k * step_dt, nav_minx, nav_ex)
			var knz := clampf(pz + knock_vz[i] * k * step_dt, nav_minz, nav_ez)
			if has_nav:
				var wc := clampi(int((knx - nav_bx) * inv_wcell), 0, nav_wc - 1)
				var wr := clampi(int((knz - nav_bz) * inv_wcell), 0, nav_wr - 1)
				var widx := wr * nav_wc + wc
				if nav_solid[widx] != 0:
					knx = clampf(knx + nav_px[widx], nav_minx, nav_ex)
					knz = clampf(knz + nav_pz[widx], nav_minz, nav_ez)
			pos_x[i] = knx
			pos_z[i] = knz
			if is_pup[i] != 0:
				_pack_buf(_pup_buf, p_vis, i, PUP_SCALE)
				p_vis += 1
			else:
				_pack_buf(_adult_buf, a_vis, i, ADULT_SCALE)
				a_vis += 1
			i += 1
			continue

		var gx := px
		var gz := pz
		var eating := false
		if st == State.RAID_GO:
			state_t[i] -= step_dt
			var h := _houses[house_idx[i]] if house_idx[i] >= 0 and house_idx[i] < _houses.size() else null
			if h == null or not is_instance_valid(h) or state_t[i] <= 0.0:
				raiding[i] = 0
				house_idx[i] = -1
				state[i] = State.FOLLOW
				_dirty_layout = true
			else:
				gx = h.door_position.x
				gz = h.door_position.z
				if (gx - px) * (gx - px) + (gz - pz) * (gz - pz) < 1.1:
					state[i] = State.FUNNEL_IN
					var ins := h.door_position - h.door_normal * 0.45
					goal_x[i] = ins.x
					goal_z[i] = ins.z
					state_t[i] = FUNNEL_TIME
					i += 1
					continue
		else:
			var use_swarm := swarm_ok and is_pup[i] == 0 and swarm_x[i] != INF
			if use_swarm and st == State.FEED:
				state[i] = State.FOLLOW
				st = State.FOLLOW
				corpse_ref[i] = null
			if st == State.FEED:
				var c := corpse_ref[i]
				if c == null or not is_instance_valid(c) or not c.is_in_group("corpses") or Colony.meals_left(c) <= 0:
					state[i] = State.FOLLOW
					st = State.FOLLOW
					corpse_ref[i] = null
				else:
					var d_lead := (px - lpx) * (px - lpx) + (pz - lpz) * (pz - lpz)
					if d_lead > feed_lead_r2 + 20.0:
						state[i] = State.FOLLOW
						st = State.FOLLOW
						corpse_ref[i] = null
					else:
						gx = goal_x[i]
						gz = goal_z[i]
						if (gx - px) * (gx - px) + (gz - pz) * (gz - pz) < 0.25:
							eating = true
							feed_left[i] -= step_dt
							if feed_left[i] <= 0.0:
								state[i] = State.FOLLOW
								if Colony.take_meal(c):
									if is_pup[i] != 0:
										maturity[i] -= _colony.pup_feed_bonus
									else:
										breed_cd[i] = _colony.breed_cooldown
										var litter := 1 + _colony.extra_pups_per_feed
										for _k in litter:
											new_pups.append(Vector3(px, 0.0, pz))
								corpse_ref[i] = null
			if st == State.FOLLOW:
				if use_swarm:
					gx = sw_cx + swarm_x[i]
					gz = sw_cz + swarm_z[i]
				else:
					if is_slice and (is_pup[i] != 0 or breed_cd[i] <= 0.0):
						var dl2 := (px - lpx) * (px - lpx) + (pz - lpz) * (pz - lpz)
						if dl2 < feed_lead_r2:
							var c := _colony.find_corpse(Vector3(px, 0.0, pz), _colony.feed_seek_radius)
							if c != null:
								corpse_ref[i] = c
								var ang := phase[i] + t_now
								goal_x[i] = c.global_position.x + sin(ang) * 0.35
								goal_z[i] = c.global_position.z + cos(ang) * 0.35
								feed_left[i] = _colony.feed_time
								state[i] = State.FEED
					var lx := slot_x[i] * gather_x
					var lz := slot_z[i] - slot_back[i] * gather_b
					var wob_t := t_now * 1.6 + phase[i]
					gx = lpx + (lx * cos_h + lz * sin_h) + sin(wob_t) * 0.28
					gz = lpz + (-lx * sin_h + lz * cos_h) + cos(wob_t * 1.17) * 0.28

		if has_zones:
			if is_slice:
				var zi := _colony.zone_at(Vector3(px, 0.0, pz))
				if zi >= 0:
					var zc := _colony.zone_center(zi)
					var ox := px - zc.x
					var oz := pz - zc.z
					var ol := sqrt(ox * ox + oz * oz)
					if ol < 0.01:
						ox = sin(phase[i])
						oz = cos(phase[i])
						ol = 1.0
					goal_x[i] = px + (ox / ol) * 2.2
					goal_z[i] = pz + (oz / ol) * 2.2
					escaping[i] = 1
				else:
					escaping[i] = 0
		elif escaping[i] != 0:
			escaping[i] = 0

		var want_x := 0.0
		var want_z := 0.0
		if escaping[i] == 1:
			eating = false
			var dx := goal_x[i] - px
			var dz := goal_z[i] - pz
			var dl := sqrt(dx * dx + dz * dz)
			if dl > 0.05:
				var esp := top_speed * (0.75 if is_pup[i] != 0 else 1.15)
				want_x = dx / dl * esp
				want_z = dz / dl * esp
		elif not eating:
			var dx := gx - px
			var dz := gz - pz
			var d2 := dx * dx + dz * dz
			if d2 > 0.0025:
				var d := sqrt(d2)
				var dir_x := dx / d
				var dir_z := dz / d
				# Far rats use the O(1) BFS flow grid to stream effortlessly around houses!
				if has_nav and d > 5.0 and st != State.RAID_GO:
					var fc := clampi(int(px - nav_bx), 0, nav_fc - 1)
					var fr := clampi(int(pz - nav_bz), 0, nav_fr - 1)
					var fidx := fr * nav_fc + fc
					var fx := nav_fx[fidx]
					var fz := nav_fz[fidx]
					if fx != 0.0 or fz != 0.0:
						dir_x = fx
						dir_z = fz
				var sp := minf(d * 3.4, top_speed * (1.15 if d > 4.5 else 1.0))
				want_x = dir_x * sp
				want_z = dir_z * sp

		# Inlined O(1) density-gradient separation (zero helper calls / allocations)
		var gc := clampi(int((px - g_bx) * inv_hcell), 0, g_cols_m1)
		var gr := clampi(int((pz - g_bz) * inv_hcell), 0, g_rows_m1)
		var row_g := gr * g_cols
		var here_c := _cell_count[row_g + gc]
		var sep_x := float(_cell_count[row_g + maxi(0, gc - 1)] - _cell_count[row_g + mini(g_cols_m1, gc + 1)]) * 0.9
		var sep_z := float(_cell_count[maxi(0, gr - 1) * g_cols + gc] - _cell_count[mini(g_rows_m1, gr + 1) * g_cols + gc]) * 0.9
		if here_c > 1:
			var ang := phase[i] + float(i & 7) * 0.85
			var spread := minf(float(here_c - 1) * 0.52, 3.6)
			sep_x += sin(ang) * spread
			sep_z += cos(ang) * spread
		var sep_w := 0.35 if escaping[i] == 1 else 1.0
		want_x += clampf(sep_x, -5.0, 5.0) * sep_w
		want_z += clampf(sep_z, -5.0, 5.0) * sep_w

		var ldx := px - lpx
		var ldz := pz - lpz
		var ld2 := ldx * ldx + ldz * ldz
		if ld2 < 0.65 and ld2 > 0.0001:
			var ldl := sqrt(ld2)
			var push := (1.0 - ldl / 0.806) * 5.5
			want_x += ldx / ldl * push
			want_z += ldz / ldl * push

		var vx := lerpf(vel_x[i], want_x, accel)
		var vz := lerpf(vel_z[i], want_z, accel)
		var nx := clampf(px + vx * step_dt, nav_minx, nav_ex)
		var nz := clampf(pz + vz * step_dt, nav_minz, nav_ez)
		if has_nav:
			var wc := clampi(int((nx - nav_bx) * inv_wcell), 0, nav_wc - 1)
			var wr := clampi(int((nz - nav_bz) * inv_wcell), 0, nav_wr - 1)
			var widx := wr * nav_wc + wc
			if nav_solid[widx] != 0:
				nx = clampf(nx + nav_px[widx], nav_minx, nav_ex)
				nz = clampf(nz + nav_pz[widx], nav_minz, nav_ez)
		pos_x[i] = nx
		pos_z[i] = nz
		vel_x[i] = vx
		vel_z[i] = vz
		if vx * vx + vz * vz > 0.16:
			yaw[i] = lerp_angle(yaw[i], atan2(vx, vz), turn_k)

		if is_pup[i] == 0 and bite_cd[i] <= 0.0 and is_slice and has_t:
			_try_bite_street(i, nx, nz, bite_r2, bite_cd_base, bite_chunk, bite_rate, tree)

		# Pack directly into flat 12-float MultiMesh buffer (zero Transform3D/Basis objects!)
		var a := yaw[i]
		var ca := cos(a)
		var sa := sin(a)
		var scl := PUP_SCALE if is_pup[i] != 0 else ADULT_SCALE
		var bob := absf(sin(t_now * 18.0 + phase[i])) * 0.05 * minf((vx * vx + vz * vz) * 0.08, 1.0)
		var lz_off := 0.0
		var stretch := 1.0
		var lt := lunge_t[i]
		if lt != INF:
			var k := (lt / 0.06) if lt < 0.06 else (1.0 - (lt - 0.06) / (LUNGE_TIME - 0.06))
			lz_off = 0.38 * k
			stretch = 1.0 + 0.26 * k
		var sx := scl / sqrt(stretch)
		var sz := scl * stretch
		var ox := nx + sa * lz_off
		var oz := nz + ca * lz_off
		var off := (p_vis if is_pup[i] != 0 else a_vis) * 12
		var buf := _pup_buf if is_pup[i] != 0 else _adult_buf
		buf[off] = ca * sx
		buf[off + 1] = 0.0
		buf[off + 2] = sa * sz
		buf[off + 3] = ox
		buf[off + 4] = 0.0
		buf[off + 5] = scl
		buf[off + 6] = 0.0
		buf[off + 7] = bob
		buf[off + 8] = -sa * sx
		buf[off + 9] = 0.0
		buf[off + 10] = ca * sz
		buf[off + 11] = oz
		if is_pup[i] != 0:
			p_vis += 1
		else:
			a_vis += 1
		i += 1

	# Bulk upload both MultiMesh buffers in TWO single C++ calls!
	_adult_mm.visible_instance_count = a_vis
	if a_vis > 0:
		_adult_mm.buffer = _adult_buf
	_pup_mm.visible_instance_count = p_vis
	if p_vis > 0:
		_pup_mm.buffer = _pup_buf

	for bp in new_pups:
		_colony.spawn_pup(bp)
	if _dirty_counts:
		_colony._emit_counts_changed()


func _pack_buf(buf: PackedFloat32Array, slot: int, i: int, scl: float) -> void:
	var a := yaw[i]
	var ca := cos(a)
	var sa := sin(a)
	var off := slot * 12
	buf[off] = ca * scl
	buf[off + 1] = 0.0
	buf[off + 2] = sa * scl
	buf[off + 3] = pos_x[i]
	buf[off + 4] = 0.0
	buf[off + 5] = scl
	buf[off + 6] = 0.0
	buf[off + 7] = 0.02
	buf[off + 8] = -sa * scl
	buf[off + 9] = 0.0
	buf[off + 10] = ca * scl
	buf[off + 11] = pos_z[i]


# ---------------------------------------------------------------------- spatial hash & separation
func _rebuild_spatial_hash() -> void:
	_cell_head.fill(-1)
	_cell_count.fill(0)
	var bx := _grid_bounds.position.x
	var bz := _grid_bounds.position.y
	var cols := _g_cols
	var rows := _g_rows
	for i in count:
		if state[i] >= State.FUNNEL_IN:
			_next_rat[i] = -1
			continue
		var c := clampi(floori((pos_x[i] - bx) / HASH_CELL), 0, cols - 1)
		var r := clampi(floori((pos_z[i] - bz) / HASH_CELL), 0, rows - 1)
		var cell := r * cols + c
		_next_rat[i] = _cell_head[cell]
		_cell_head[cell] = i
		_cell_count[cell] += 1


func _density_separation(px: float, pz: float, i: int) -> Vector2:
	var c := clampi(floori((px - _grid_bounds.position.x) / HASH_CELL), 0, _g_cols - 1)
	var r := clampi(floori((pz - _grid_bounds.position.y) / HASH_CELL), 0, _g_rows - 1)
	var here := _cell_count[r * _g_cols + c]
	var left := _cell_count[r * _g_cols + maxi(0, c - 1)]
	var right := _cell_count[r * _g_cols + mini(_g_cols - 1, c + 1)]
	var up := _cell_count[maxi(0, r - 1) * _g_cols + c]
	var down := _cell_count[mini(_g_rows - 1, r + 1) * _g_cols + c]
	var gx := float(left - right) * 0.9
	var gz := float(up - down) * 0.9
	if here > 1:
		var ang := phase[i] + float(i % 7) * 0.9
		var spread := minf(float(here - 1) * 0.55, 3.8)
		gx += sin(ang) * spread
		gz += cos(ang) * spread
	return Vector2(clampf(gx, -5.0, 5.0), clampf(gz, -5.0, 5.0))


# ---------------------------------------------------------------------- Bite helpers
func _cache_townsfolk() -> void:
	_t_nodes.clear()
	_t_infs.clear()
	_t_x.clear()
	_t_z.clear()
	for n: Node in _colony.get_tree().get_nodes_in_group("townsfolk"):
		var t := n as Node3D
		if t == null:
			continue
		var inf := t.get_node_or_null("Infection") as InfectionComponent
		if inf == null or inf.is_dead():
			continue
		_t_nodes.append(t)
		_t_infs.append(inf)
		_t_x.append(t.global_position.x)
		_t_z.append(t.global_position.z)


func _try_bite_street(i: int, px: float, pz: float, r2: float, cd_base: float, chunk: float, rate: float, tree: SceneTree) -> void:
	var best := -1
	var best_d2 := r2
	var tn := _t_nodes.size()
	for k in tn:
		if _t_infs[k].is_dead():
			continue
		var dx := _t_x[k] - px
		var dz := _t_z[k] - pz
		var d2 := dx * dx + dz * dz
		if d2 <= best_d2:
			best_d2 = d2
			best = k
	if best < 0:
		return
	_t_infs[best].bite(chunk, rate)
	bite_cd[i] = cd_base
	lunge_t[i] = 0.0
	var dx := _t_x[best] - px
	var dz := _t_z[best] - pz
	if dx * dx + dz * dz > 0.0001:
		yaw[i] = atan2(dx, dz)
	if _bite_vfx_used < BITE_VFX_CAP:
		_bite_vfx_used += 1
		Vfx.play(tree, &"bite", Vector3(_t_x[best], 0.0, _t_z[best]), Vector3(dx, 0.0, dz), chunk / 3.0)


func _bite_inside(i: int, cd_base: float, chunk: float, rate: float) -> void:
	var hid := house_idx[i]
	if hid < 0 or hid >= _houses.size():
		return
	var h := _houses[hid]
	if not is_instance_valid(h):
		return
	var living := h.living_occupants()
	if living.is_empty():
		return
	var target := living[_rng.randi() % living.size()]
	var inf := target.get_node_or_null("Infection") as InfectionComponent
	if inf != null and not inf.is_dead():
		inf.bite(chunk, rate)
		bite_cd[i] = cd_base
		h.show_bite()


# ---------------------------------------------------------------------- O(1) enemy spatial queries
## Number of outdoor follower rats within `radius` of `center`, plus their average XZ.
func query_crowd(center: Vector3, radius: float) -> Dictionary:
	var r2 := radius * radius
	var bx := _grid_bounds.position.x
	var bz := _grid_bounds.position.y
	var c0 := clampi(floori((center.x - radius - bx) / HASH_CELL), 0, _g_cols - 1)
	var c1 := clampi(floori((center.x + radius - bx) / HASH_CELL), 0, _g_cols - 1)
	var r0 := clampi(floori((center.z - radius - bz) / HASH_CELL), 0, _g_rows - 1)
	var r1 := clampi(floori((center.z + radius - bz) / HASH_CELL), 0, _g_rows - 1)
	var n := 0
	var sum_x := 0.0
	var sum_z := 0.0
	var best_d2 := INF
	var nearest := Vector3.INF
	for rr in range(r0, r1 + 1):
		var row_off := rr * _g_cols
		for cc in range(c0, c1 + 1):
			var idx := _cell_head[row_off + cc]
			while idx >= 0:
				var dx := pos_x[idx] - center.x
				var dz := pos_z[idx] - center.z
				var d2 := dx * dx + dz * dz
				if d2 <= r2:
					n += 1
					sum_x += pos_x[idx]
					sum_z += pos_z[idx]
					if d2 < best_d2:
						best_d2 = d2
						nearest = Vector3(pos_x[idx], 0.0, pos_z[idx])
				idx = _next_rat[idx]
	return {
		"count": n,
		"centre": Vector3(sum_x / float(n), 0.0, sum_z / float(n)) if n > 0 else center,
		"nearest": nearest,
		"nearest_d2": best_d2,
	}


## Kills outdoor followers inside circle (`pups_only`: only Pups). Returns kills.
func hit_circle(center: Vector3, radius: float, pups_only := false) -> int:
	var r2 := radius * radius
	var hits := 0
	var i := count - 1
	while i >= 0:
		if state[i] < State.FUNNEL_IN:
			if not pups_only or is_pup[i] != 0:
				var dx := pos_x[i] - center.x
				var dz := pos_z[i] - center.z
				if dx * dx + dz * dz <= r2:
					kill_at(i)
					hits += 1
		i -= 1
	if hits > 0:
		_colony._emit_counts_changed()
	return hits


## Kills outdoor followers inside an arc (Rat-catcher sweep). Returns kills.
func hit_arc(origin: Vector3, dir: Vector3, radius: float, half_angle: float, feet_radius: float, pups_only := false) -> int:
	var hits := 0
	var i := count - 1
	while i >= 0:
		if state[i] < State.FUNNEL_IN:
			if not pups_only or is_pup[i] != 0:
				if DangerZone.arc_contains(origin, dir, radius, half_angle, feet_radius, Vector3(pos_x[i], 0.0, pos_z[i])):
					kill_at(i)
					hits += 1
		i -= 1
	if hits > 0:
		_colony._emit_counts_changed()
	return hits


## Shoves Adults away from `from` (kills Pups) inside circle (Incense / knockback).
func knockback_circle(from: Vector3, radius: float, strength: float, kill_pups := true) -> int:
	var r2 := radius * radius
	var affected := 0
	var i := count - 1
	while i >= 0:
		if state[i] < State.FUNNEL_IN:
			var dx := pos_x[i] - from.x
			var dz := pos_z[i] - from.z
			var d2 := dx * dx + dz * dz
			if d2 <= r2:
				if kill_pups and is_pup[i] != 0:
					kill_at(i)
				else:
					var dl := sqrt(d2)
					var nx := dx / dl if dl > 0.01 else sin(phase[i])
					var nz := dz / dl if dl > 0.01 else cos(phase[i])
					var spd := 2.0 * strength / KNOCK_TIME
					knock_vx[i] = nx * spd
					knock_vz[i] = nz * spd
					knock_t[i] = KNOCK_TIME
					if state[i] == State.FEED:
						state[i] = State.FOLLOW
						corpse_ref[i] = null
				affected += 1
		i -= 1
	if affected > 0 and _dirty_counts:
		_colony._emit_counts_changed()
	return affected


## Shoves Adults and kills Pups inside a broom arc. Returns affected count.
func sweep_arc(origin: Vector3, dir: Vector3, radius: float, half_angle: float, feet_radius: float, strength: float) -> int:
	var affected := 0
	var i := count - 1
	while i >= 0:
		if state[i] < State.FUNNEL_IN:
			var p := Vector3(pos_x[i], 0.0, pos_z[i])
			if DangerZone.arc_contains(origin, dir, radius, half_angle, feet_radius, p):
				if is_pup[i] != 0:
					kill_at(i)
				else:
					var dx := pos_x[i] - origin.x
					var dz := pos_z[i] - origin.z
					var dl := sqrt(dx * dx + dz * dz)
					var nx := dx / dl if dl > 0.01 else dir.x
					var nz := dz / dl if dl > 0.01 else dir.z
					var spd := 2.0 * strength / KNOCK_TIME
					knock_vx[i] = nx * spd
					knock_vz[i] = nz * spd
					knock_t[i] = KNOCK_TIME
				affected += 1
		i -= 1
	if affected > 0 and _dirty_counts:
		_colony._emit_counts_changed()
	return affected


## Kills a single outdoor rat closest to `at` within `radius` (Cat pounce / SpringTrap).
func hit_one_near(at: Vector3, radius: float) -> bool:
	var r2 := radius * radius
	var best := -1
	var best_d2 := r2
	for i in count:
		if state[i] >= State.FUNNEL_IN:
			continue
		var dx := pos_x[i] - at.x
		var dz := pos_z[i] - at.z
		var d2 := dx * dx + dz * dz
		if d2 <= best_d2:
			best_d2 = d2
			best = i
	if best >= 0:
		kill_at(best)
		_colony._emit_counts_changed()
		return true
	return false


## Samples up to `max_out` outdoor Adult positions (for Fleas aura).
func sample_adult_positions(max_out := 64) -> PackedVector3Array:
	var out := PackedVector3Array()
	if count == 0:
		return out
	var step_i := maxi(1, count / max_out)
	var i := _rng.randi() % step_i
	while i < count and out.size() < max_out:
		if is_pup[i] == 0 and state[i] < State.FUNNEL_IN:
			out.append(Vector3(pos_x[i], 0.0, pos_z[i]))
		i += step_i
	return out


## Picks a random running outdoor rat's pos & vel for run-dust VFX.
func random_runner() -> Array:
	if count == 0:
		return []
	var i := _rng.randi() % count
	if state[i] >= State.FUNNEL_IN:
		return []
	var v := Vector3(vel_x[i], 0.0, vel_z[i])
	return [Vector3(pos_x[i], 0.0, pos_z[i]), v, is_pup[i] != 0]
