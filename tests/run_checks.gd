extends SceneTree
## Quick contracts: boots the main scene and checks small real-state invariants.

const MAIN_SCENE := "res://scenes/main.tscn"

var failures := 0
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_msec()
	await check_main_scene_boots()
	print("CHECKS_QUICK checks=%d failures=%d elapsed_ms=%d" % [checks, failures, Time.get_ticks_msec() - started])
	quit(failures)


func check_main_scene_boots() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	check(packed != null, "main scene loads")
	if packed == null:
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	check(main.is_inside_tree(), "main scene stays in the tree after two frames")
	main.queue_free()
	await process_frame


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
