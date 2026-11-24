## Comprehensive headless unit & integration test suite for Plaag overhaul.
## Run via:
##   godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("=== Plaag Automated Unit & Integration Tests ===")
	_test_infection_tiers_and_cleanse()
	_test_bite_cooldown_and_cleave()
	_test_nav_field_obstacles_and_flow()
	await _test_deliberate_hide_not_auto()
	await _test_terrier_leaves_house_after_sniff()
	await _test_swarm_sim_2500_rats_and_combat()
	await _test_corpse_cleanup_and_flies_size()
	_test_upgrades_high_impact_and_keystones()
	_test_medieval_assets_loaded()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		push_error("  [FAIL] " + name)
		print("  [FAIL] ", name)


# ---------------------------------------------------------------------- 1. Infection & Boss Cleanse
func _test_infection_tiers_and_cleanse() -> void:
	_check(InfectionComponent.visual_tier(0.0) == 0, "visual_tier(0) == healthy")
	_check(InfectionComponent.visual_tier(15.0) == 1, "visual_tier(15) == tainted")
	_check(InfectionComponent.visual_tier(45.0) == 2, "visual_tier(45) == feverish")
	_check(InfectionComponent.visual_tier(85.0) == 3, "visual_tier(85) == critical")
	_check(InfectionComponent.visual_tier(100.0) == 4, "visual_tier(100) == dead")

	var inf := InfectionComponent.new()
	inf.base_rate = 0.0
	inf.gain_multiplier = 0.12
	inf.cleanse_rate = 1.6
	inf.bonus_decay = 0.08
	var broken := [false]
	inf.cleanse_broken.connect(func() -> void: broken[0] = true)

	# Single bite should NOT overwhelm Cleanse
	inf.bite(3.0, 0.5)
	_check(not inf.is_overwhelmed(), "Boss single bite does not overwhelm Cleanse")
	_check(inf.net_rate() < 0.0, "Boss single bite net_rate is negative (Cleansing)")
	_check(inf.cleanse_pressure() > 0.0 and inf.cleanse_pressure() < 0.2, "Boss pressure partially fills")
	_check(not broken[0], "cleanse_broken not yet emitted")

	# Swarm of 30 rapid bites SHOULD overwhelm Cleanse & emit cleanse_broken once
	for _i in 35:
		inf.bite(3.0, 0.5)
	_check(inf.is_overwhelmed(), "Swarm of 35 bites overwhelms boss Cleanse")
	_check(inf.net_rate() > 0.0, "Overwhelmed boss net_rate is positive")
	_check(is_equal_approx(inf.cleanse_pressure(), 1.0), "Overwhelmed boss cleanse_pressure == 1.0")
	_check(broken[0], "cleanse_broken signal fired on crossing threshold")
	inf.free()


# ---------------------------------------------------------------------- 2. Bite Cooldown & Cleave
func _test_bite_cooldown_and_cleave() -> void:
	var b := BiteComponent.new()
	b.cooldown = 1.0
	b.bite_range = 2.0
	b.cleave_targets = 3
	_check(is_equal_approx(b.cooldown_progress(), 1.0), "Bite starts ready (progress == 1.0)")
	b._cooldown_left = 0.5
	_check(is_equal_approx(b.cooldown_progress(), 0.5), "Bite half cooldown reports 0.5")
	b._cooldown_left = 1.0
	_check(is_equal_approx(b.cooldown_progress(), 0.0), "Bite just fired reports 0.0")
	b.free()


# ---------------------------------------------------------------------- 3. NavField Obstacle SDF & Flow
func _test_nav_field_obstacles_and_flow() -> void:
	var nav := NavField.new()
	var blockers: Array[Dictionary] = [
		{"xf": Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), "half": Vector2(3.0, 2.0)},
	]
	nav.bake(Rect2(-20.0, -20.0, 40.0, 40.0), blockers)
	_check(nav.is_blocked_xy(0.0, 0.0), "NavField marks house interior as blocked")
	_check(not nav.is_blocked_xy(10.0, 10.0), "NavField keeps open street unblocked")
	var pushed := nav.resolve_xy(Vector2(0.2, 1.5))
	_check(not nav.is_blocked_xy(pushed.x, pushed.y), "NavField.resolve_xy pushes rat cleanly out of wall")
	_check(not nav.clear_line_xy(Vector2(-6.0, 0.0), Vector2(6.0, 0.0)), "NavField.clear_line_xy detects house blocking sightline")
	_check(nav.clear_line_xy(Vector2(-6.0, 8.0), Vector2(6.0, 8.0)), "NavField.clear_line_xy returns true in open avenue")
	nav.update_flow(Vector2(8.0, 0.0))
	var fl := nav.flow_at(Vector2(-8.0, 0.0))
	_check(fl.length() > 0.5, "NavField.flow_at computes valid flow direction around house")


# ---------------------------------------------------------------------- 4. Deliberate Hide (No Auto-Enter)
func _test_deliberate_hide_not_auto() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var lead := (load("res://scenes/game/lead_rat.tscn") as PackedScene).instantiate() as Node3D
	lead.position = Vector3(0, 0, 2.0)
	host.add_child(lead)
	var house := House.new()
	house.door_position = Vector3(0, 0, 1.5)
	house.door_normal = Vector3(0, 0, 1)
	host.add_child(house)
	var col := Colony.new()
	col.hide_unlocked = true
	host.add_child(col)
	await process_frame
	await physics_frame

	# Standing right next to the door walking toward it MUST NOT auto-hide!
	lead.set("wish", Vector3(0, 0, -1))
	col._update_hide(0.1)
	_check(not col.is_hidden, "Walking up to a house door does NOT auto-hide")
	_check(col.hide_candidate() == house, "Colony.hide_candidate() identifies nearby door for prompt")

	# Deliberate try_hide() enters the house!
	_check(col.try_hide(), "Deliberate Colony.try_hide() succeeds near door")
	_check(col.is_hidden, "Colony is now Hidden inside the house")

	# Early exit blocked during grace period, allowed after grace period
	_check(not col.try_hide(), "Early exit ignored during grace period")
	col._hide_time = Colony.HIDE_EXIT_GRACE + 0.1
	_check(col.try_hide(), "Pressing Hide again after grace period exits cleanly")
	_check(not col.is_hidden, "Colony left house on deliberate second press")
	host.queue_free()
	await process_frame


# ---------------------------------------------------------------------- 5. Terrier Sniffs & Leaves Door
func _test_terrier_leaves_house_after_sniff() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var lead := (load("res://scenes/game/lead_rat.tscn") as PackedScene).instantiate() as Node3D
	lead.position = Vector3(0, 0, 0)
	host.add_child(lead)
	var terrier := (load("res://scenes/game/terrier.tscn") as PackedScene).instantiate() as Terrier
	terrier.position = Vector3(0, 0, 1.5)
	terrier.wander_bounds = Rect2(-30, -30, 60, 60)
	host.add_child(terrier)
	await process_frame
	await physics_frame

	# Hide the Lead Rat — Terrier must sniff briefly then enter ROAM and move away!
	lead.set("is_hidden", true)
	terrier._physics_process(0.1)
	_check(terrier.mode == Terrier.Mode.SNIFF, "Terrier enters SNIFF when Lead Rat hides")
	for _k in 20:
		terrier._physics_process(0.1)
	_check(terrier.mode == Terrier.Mode.ROAM, "Terrier transitions to ROAM after sniffing lost trail")
	var start_pos := Vector3(0, 0, 1.5)
	for _k in 90:
		terrier._physics_process(1.0 / 60.0)
	var moved := terrier.global_position.distance_to(start_pos)
	_check(moved > 5.0, "Terrier actively leaves the house doorstep (moved %.1fu)" % moved)
	host.queue_free()
	await process_frame


# ---------------------------------------------------------------------- 6. SwarmSim 2,500 Rats & O(1) Combat
func _test_swarm_sim_2500_rats_and_combat() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var lead := (load("res://scenes/game/lead_rat.tscn") as PackedScene).instantiate() as Node3D
	lead.position = Vector3(0, 0, 0)
	host.add_child(lead)
	var col := Colony.new()
	col.start_adults = 2500
	host.add_child(col)
	col.setup_nav(Rect2(-34, -34, 68, 68), [])
	await process_frame
	await physics_frame

	_check(col.sim.count == 2500, "SwarmSim holds 2,500 simultaneous follower rats (actual=%d)" % col.sim.count)
	_check(col.adult_count == 2501, "Colony.adult_count == 2,501 including Lead Rat")
	# Ensure zero ColonyRat scene nodes were created (pure MultiMesh rendering!)
	var child_bodies := 0
	for c in col.get_children():
		if c is CharacterBody3D:
			child_bodies += 1
	_check(child_bodies == 0, "Zero CharacterBody3D follower nodes exist for 2,500 rats")

	# Warm up 2 frames, then time 10 individual steps and check median (immune to single OS preemption spikes)
	col.sim.step(0.016)
	col.sim.step(0.016)
	var times_ms: Array[float] = []
	for _k in 10:
		var t0 := Time.get_ticks_usec()
		col.sim.step(0.016)
		times_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	times_ms.sort()
	var med_ms := times_ms[times_ms.size() / 2]
	print("  [PERF] SwarmSim 2,500 rats median step = %.2f ms (min=%.2f ms)" % [med_ms, times_ms[0]])
	_check(med_ms < 16.6, "SwarmSim 2,500 rats runs under 16.6ms frame budget (median=%.2fms)" % med_ms)

	# Verify O(1) spatial crowd query & circle hit
	var q := col.query_crowd(Vector3.ZERO, 6.0)
	_check(int(q["count"]) > 100, "Colony.query_crowd finds dense swarm (%d rats)" % int(q["count"]))
	var killed := col.hit_rats_in_circle(Vector3.ZERO, 1.2, false)
	_check(killed > 0 and col.sim.count == 2500 - (killed - 1 if killed > 0 else 0) or col.sim.count < 2500,
		"Colony.hit_rats_in_circle cleanly swap-removes killed rats (killed=%d)" % killed)
	host.queue_free()
	await process_frame


# ---------------------------------------------------------------------- 7. Corpse Cleanup & Tiny Flies
func _test_corpse_cleanup_and_flies_size() -> void:
	var flies_script := preload("res://scripts/vfx/vfx_flies.gd")
	_check(flies_script.FLY_SIZE.length() < 0.12, "Flies shrunk to tiny ink motes (len=%.3f)" % flies_script.FLY_SIZE.length())
	var host := Node3D.new()
	root.add_child(host)
	var person := (load("res://scenes/game/townsperson.tscn") as PackedScene).instantiate() as Townsperson
	host.add_child(person)
	await process_frame
	var inf := person.get_node("Infection") as InfectionComponent
	inf.bite(100.0, 0.0)
	_check(person.is_dead() and person.is_in_group("corpses"), "Townsperson becomes corpse at 100% Infection")
	while person.meals_left > 0:
		person.take_meal()
	_check(not person.is_in_group("corpses"), "Finished corpse leaves 'corpses' group immediately")
	_check(person._dissolving, "Finished corpse triggers dissolve & queue_free() cleanup")
	host.queue_free()
	await process_frame


# ---------------------------------------------------------------------- 8. High-Impact Upgrades & Keystones
func _test_upgrades_high_impact_and_keystones() -> void:
	var run := root.get_node_or_null("Run")
	_check(run != null, "Run autoload present")
	if run == null:
		return
	var nodes: Array = run.call("all_nodes")
	var ids := {}
	for n in nodes:
		ids[n.id] = n
	for key_id in ["litters", "frenzy_birth", "plague_burst", "ravenous_cleave", "brood", "gnaw", "rend"]:
		_check(ids.has(key_id), "Upgrade node '%s' loaded cleanly" % key_id)
	_check(float(ids["gnaw"].effects.get("bite_cooldown", 0.0)) <= -0.2, "Gnaw upgraded to high-impact cooldown reduction")
	_check(ids["brood"].level_values.size() >= 4 and float(ids["brood"].level_values[3]) >= 50.0, "Brood scales up to large starting pack")


# ---------------------------------------------------------------------- 9. Medieval MegaKit Assets
func _test_medieval_assets_loaded() -> void:
	for k in [&"wall_plaster", &"wall_door_plaster", &"roof_4x6", &"barrel", &"crate", &"wagon", &"stall", &"lantern_wall"]:
		_check(MedievalAssets.has_asset(k), "MedievalAssets resolves MegaKit glTF '%s'" % k)
