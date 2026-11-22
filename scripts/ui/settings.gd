## Player settings (autoload "Settings"), saved to user://plaag_settings.cfg,
## apart from the Run save so "New plague" never wipes them.
##
## Also tracks the last input device the player touched (`last_device`), so
## every prompt on screen can show the right glyph (UiKit.prompt()). A short
## grace period stops it flickering when a resting stick drifts.
##
## Everything reads these by property name; `changed` fires after any set().
## Debug: --reduce-motion, --no-numbers and --pad force those for the session
## (not saved), for screenshots.
extends Node

signal changed
signal device_changed(device: int)

enum Device { KEYBOARD_MOUSE, GAMEPAD }

const PATH := "user://plaag_settings.cfg"
## Seconds a new device must keep being used before the prompts switch.
const DEVICE_GRACE := 0.15
const STICK_DEADZONE := 0.35

## 0..1, scales every camera shake. 0 = off.
var screen_shake := 1.0
## Floating Bite numbers over townsfolk.
var damage_numbers := true
## Shorter, smaller UI animations: no punch scales, no shakes, no flying icons
## (they jump straight to the counter), fades kept.
var reduce_motion := false
var fullscreen := false
## Scales the in-Round HUD (0.8 .. 1.4) on top of the window stretch.
var hud_scale := 1.0

var last_device: int = Device.KEYBOARD_MOUSE

var _session_overrides := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	var args := OS.get_cmdline_user_args()
	if args.has("--reduce-motion"):
		_session_overrides["reduce_motion"] = true
		reduce_motion = true
	if args.has("--no-numbers"):
		_session_overrides["damage_numbers"] = false
		damage_numbers = false
	if args.has("--pad"):
		last_device = Device.GAMEPAD
	_apply_window()


func _input(event: InputEvent) -> void:
	var dev := -1
	if event is InputEventJoypadButton and event.pressed:
		dev = Device.GAMEPAD
	elif event is InputEventJoypadMotion and absf(event.axis_value) > STICK_DEADZONE:
		dev = Device.GAMEPAD
	elif event is InputEventKey and event.pressed:
		dev = Device.KEYBOARD_MOUSE
	elif event is InputEventMouseButton and event.pressed:
		dev = Device.KEYBOARD_MOUSE
	elif event is InputEventMouseMotion and event.relative.length() > 4.0:
		dev = Device.KEYBOARD_MOUSE
	if dev >= 0 and dev != last_device:
		last_device = dev
		device_changed.emit(dev)


func is_gamepad() -> bool:
	return last_device == Device.GAMEPAD


## Sets one setting by name, applies it and saves.
func set_value(key: String, value: Variant) -> void:
	if not key in self:
		push_warning("Settings: unknown key %s" % key)
		return
	set(key, value)
	_session_overrides.erase(key)
	if key == "fullscreen":
		_apply_window()
	save_settings()
	changed.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in ["screen_shake", "damage_numbers", "reduce_motion", "fullscreen", "hud_scale"]:
		cfg.set_value("settings", key, get(key))
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	screen_shake = clampf(float(cfg.get_value("settings", "screen_shake", screen_shake)), 0.0, 1.0)
	damage_numbers = bool(cfg.get_value("settings", "damage_numbers", damage_numbers))
	reduce_motion = bool(cfg.get_value("settings", "reduce_motion", reduce_motion))
	fullscreen = bool(cfg.get_value("settings", "fullscreen", fullscreen))
	hud_scale = clampf(float(cfg.get_value("settings", "hud_scale", hud_scale)), 0.8, 1.4)


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and (fullscreen or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
		DisplayServer.window_set_mode(want)
