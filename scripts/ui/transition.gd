## Scene changes with an ink blot (autoload "Transition"). Transition.go(path)
## grows a ragged ink blot from the centre of the screen until it covers it
## (0.3 s), changes the scene, then shrinks the blot back to nothing over the
## new scene (0.3 s). With Settings.reduce_motion it is a 0.2 s parchment fade
## instead.
##
## Unpauses the tree first, swallows every input event while it runs, and is
## safe to call twice: a call while one is running is ignored (go() returns
## false). GUI input is disabled meanwhile; autoloads get _input after the
## scene, so screens with their own _input also check is_busy().
## Run.open_tree() / open_map() / start_round() and the title / tree screens
## route their scene changes through here when the autoload exists.
## Without a window (headless) it changes the scene at once.
extends CanvasLayer

signal finished

const COVER_TIME := 0.3
const REVEAL_TIME := 0.3
const FADE_TIME := 0.1          # each half of the reduced-motion fade
const LOBES := 28

var _busy := false
var _cover := 0.0               # 0 = clear, 1 = the screen is covered
var _fade_mode := false
var _veil: Control
var _phase := 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_veil = Control.new()
	_veil.name = "Veil"
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.draw.connect(_draw_veil)
	add_child(_veil)


func is_busy() -> bool:
	return _busy


## Changes to the scene at `path` behind the blot. Returns false (and does
## nothing) while another transition is running or the path does not exist.
func go(path: String) -> bool:
	if _busy:
		return false
	if not ResourceLoader.exists(path):
		push_warning("Transition: no scene at %s" % path)
		return false
	_busy = true
	get_tree().paused = false
	if DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file(path)
		_busy = false
		finished.emit()
		return true
	_play(path)
	return true


## The blot / fade sequence around the scene change (a coroutine; go() returns
## at once).
func _play(path: String) -> void:
	_fade_mode = UiKit.reduce_motion()
	_phase = randf() * TAU
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().gui_disable_input = true
	var t_in := FADE_TIME if _fade_mode else COVER_TIME
	var t_out := FADE_TIME if _fade_mode else REVEAL_TIME
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(_set_cover, 0.0, 1.0, t_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	get_tree().change_scene_to_file(path)
	# The new scene is in place after the frame ends; give it one more to lay out.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	var tw2 := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw2.tween_method(_set_cover, 1.0, 0.0, t_out).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw2.finished
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().gui_disable_input = false
	_busy = false
	finished.emit()


func _input(event: InputEvent) -> void:
	if _busy:
		get_viewport().set_input_as_handled()


func _set_cover(v: float) -> void:
	_cover = v
	_veil.queue_redraw()


func _draw_veil() -> void:
	if _cover <= 0.0:
		return
	var s := _veil.size
	if _fade_mode:
		_veil.draw_rect(Rect2(Vector2.ZERO, s), Color(UiKit.PARCHMENT, _cover))
		return
	# A blot with a ragged, lobed edge; at 1 it reaches past every corner.
	var c := s * 0.5
	var reach := c.length() * 1.18
	var r := reach * _cover
	if r < 12.0:
		_veil.draw_circle(c, r, UiKit.INK)
		return
	var pts := PackedVector2Array()
	for i in LOBES * 6:
		var a := TAU * float(i) / float(LOBES * 6)
		var wob := 1.0 + 0.07 * sin(a * 5.0 + _phase) + 0.045 * sin(a * 11.0 + _phase * 1.7) + 0.03 * sin(a * 23.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r * wob)
	_veil.draw_colored_polygon(pts, UiKit.INK)
	# A few satellite splashes just outside the edge while it grows.
	if _cover < 0.95:
		for k in 9:
			var a := _phase + float(k) * 0.71
			var d := r * (1.12 + 0.05 * float(k % 3))
			_veil.draw_circle(c + Vector2(cos(a), sin(a)) * d, maxf(2.0, r * 0.035 * (1.0 + float(k % 2))), UiKit.INK)
