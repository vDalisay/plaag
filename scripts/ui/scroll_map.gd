## The Scroll Map between the Upgrade Tree and the next Round: a parchment
## scroll (rolled ends top and bottom, on a dark table) with the city drawn in
## ink. Each District (Run.district_defs()) is a walled quarter placed at its
## DistrictDef.map_position: a visited one shows its house footprints
## (Run.layout_of) with the houses of its best Round (Run.best_dead_houses)
## crossed out; an open, unvisited one a sketchy placeholder; a locked one is
## faint with a lock and "Unknown". Beaten Districts are hatched over in ink.
## The header shows the Year, the wallet and "Choose where the plague goes next".
##
## Input: click a District to select it, click it again (or Begin Round) to
## play it. Left / right (arrows, A / D, d-pad, stick) select, Enter / A
## begins, Esc / B goes back to the Upgrade Tree. Beginning sets
## Run.current_district and calls Run.start_round().
##
## Every Run call is duck typed (get_node_or_null("/root/Run")) so the scene
## opens without the autoload. Debug flags (after `--`): --screenshot=<path>
## (saves a frame after --screenshot-delay=<s>, default 1 s, and quits),
## --dev-select=<id>; with --dev also (in memory only, never saved)
## --dev-map=fresh (nothing visited or beaten) or --dev-map=progress (the
## first District visited, beaten and half crossed out) and
## --dev-layout[=<json>] (layouts for the visited Districts: a JSON file of
## {id: [[index, cx, cz, sx, sz, rot], ...]}, else a made-up grid).
extends Control

const PARCHMENT := Color(0.93, 0.88, 0.76)
const PARCHMENT_DARK := Color(0.84, 0.77, 0.62)
const INK := Color(0.13, 0.10, 0.08)
const SEPIA := Color(0.36, 0.25, 0.15)
const TABLE := Color(0.17, 0.11, 0.07)
const WOOD := Color(0.33, 0.21, 0.11)
## District ground half-size (District.bounds is 44 x 44 u around the origin).
const DISTRICT_HALF := 22.0
## Extra ground units round the bounds inside a quarter's wall.
const REGION_MARGIN := 1.5
const ROLLER_H := 38.0
const PAPER_INSET := 118.0
const PANEL_W := 280.0
const HEADER_H := 74.0
const LOCKED_ALPHA := 0.32
## map_position (-1..1) times this times the map size = offset from its centre.
const MAP_SPREAD := 0.62
## Superellipse exponent of the city wall (2 = ellipse, higher = squarer).
const WALL_ROUNDNESS := 3.2
## Smallest screen the page is laid out for.
const MIN_SIZE := Vector2(720, 420)
const YEAR_TABLE := "res://data/year_table.tres"
## What the streets look like at each YearTable visual_stage.
const STAGE_TEXT: Array[String] = ["mud and refuse", "partly cobbled", "cobbled and lime-washed"]

var _run: Node
var _defs: Array = []              # DistrictDefs (or look-alikes), unlock order
var _regions: Array[Dictionary] = []   # {def, xf: Transform2D, px: float, half: float}
var _selected := 0
var _hover := -1
var _time := 0.0
var _shake := {}                   # district id -> seconds left
var _font: Font
var _title_font: Font
var _blot: Texture2D
var _vignette: Texture2D
var _paper := Rect2()
var _map := Rect2()
var _panel := Rect2()
var _wall_c := Vector2.ZERO
var _wall_r := Vector2.ONE
var _begin: Button
var _back: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_run = get_node_or_null("/root/Run")
	_font = _make_font(["Georgia", "Garamond", "Times New Roman", "serif"])
	_title_font = _make_font(["Old English Text MT", "UnifrakturMaguntia", "Gabriola", "Georgia", "serif"])
	_blot = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)], [0.0, 0.55, 1.0])
	_vignette = _radial([Color(1, 1, 1, 0), Color(1, 1, 1, 0.12), Color(1, 1, 1, 1)], [0.0, 0.7, 1.42])
	theme = _make_theme()
	_defs = _load_defs()
	_build_buttons()
	_apply_debug_args()
	_selected = _start_index()
	_layout()
	resized.connect(_layout)
	if _run != null and _run.has_signal("wallet_changed"):
		_run.connect("wallet_changed", queue_redraw)


func _process(delta: float) -> void:
	_time += delta
	for id: String in _shake.keys():
		_shake[id] = float(_shake[id]) - delta
		if float(_shake[id]) <= 0.0:
			_shake.erase(id)
	queue_redraw()


# ---------------------------------------------------------------------- Run access
func _load_defs() -> Array:
	if _run != null and _run.has_method("district_defs"):
		return _run.call("district_defs")
	return []


func _id(i: int) -> String:
	return str(_defs[i].get("id"))


func _is_open(i: int) -> bool:
	if _run != null and _run.has_method("is_district_open"):
		return bool(_run.call("is_district_open", _id(i)))
	return str(_defs[i].get("requires")).is_empty()


func _is_beaten(i: int) -> bool:
	if _run != null and _run.has_method("is_district_beaten"):
		return bool(_run.call("is_district_beaten", _id(i)))
	return false


func _layout_of(i: int) -> Array:
	if _run != null and _run.has_method("layout_of"):
		return _run.call("layout_of", _id(i))
	return []


func _dead_houses(i: int) -> Array:
	if _run == null:
		return []
	var best: Variant = _run.get("best_dead_houses")
	if best is Dictionary:
		return (best as Dictionary).get(_id(i), [])
	return []


## The Year's visual_stage (0..2) for this District, or -1 without a YearTable.
func _visual_stage(i: int) -> int:
	if not ResourceLoader.exists(YEAR_TABLE):
		return -1
	var table := load(YEAR_TABLE)
	if table == null or not table.has_method("entry_for"):
		return -1
	var e: Variant = table.call("entry_for", _year(), _id(i))
	return int((e as Object).get("visual_stage")) if e != null else -1


func _year() -> int:
	return int(_run.get("year")) if _run != null else 1347


func _wallet() -> Vector2i:
	if _run == null:
		return Vector2i.ZERO
	return Vector2i(int(_run.get("pestilence")), int(_run.get("bones")))


## The Run's current District if it is open, else the first open unbeaten one.
func _start_index() -> int:
	if _defs.is_empty():
		return 0
	var cur := str(_run.get("current_district")) if _run != null else ""
	var fallback := -1
	for i in _defs.size():
		if _id(i) == cur and _is_open(i):
			return i
		if fallback < 0 and _is_open(i) and not _is_beaten(i):
			fallback = i
	return maxi(fallback, 0)


# ---------------------------------------------------------------------- actions
func _select(i: int) -> void:
	if i < 0 or i >= _defs.size():
		return
	_selected = i
	_update_buttons()


## Left / right: the next District by map position (locked ones included,
## so their requirement can be read).
func _step(dir: int) -> void:
	if _defs.is_empty():
		return
	var order: Array[int] = []
	for i in _defs.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return _map_pos(a).x < _map_pos(b).x)
	var at := order.find(_selected)
	_select(order[posmod(at + dir, order.size())])


func _begin_round() -> void:
	if _defs.is_empty():
		if _run != null and _run.has_method("start_round"):
			_run.call("start_round")
		return
	if not _is_open(_selected):
		_shake[_id(_selected)] = 0.4
		return
	if _run == null:
		push_warning("ScrollMap: no Run autoload, can't begin a Round")
		return
	_run.set("current_district", _id(_selected))
	print("scroll map: begin round in ", _id(_selected))
	_run.call("start_round")


func _go_back() -> void:
	if _run != null and _run.has_method("open_tree"):
		_run.call("open_tree")


func _unhandled_input(event: InputEvent) -> void:
	var act := ""
	if _pressed(event, ["ui_left", "move_left"]):
		act = "left"
	elif _pressed(event, ["ui_right", "move_right"]):
		act = "right"
	elif _pressed(event, ["ui_accept"]):
		act = "begin"
	elif _pressed(event, ["ui_cancel"]):
		act = "back"
	if act.is_empty():
		return
	# Handled first: begin / back change the scene and take this node away.
	get_viewport().set_input_as_handled()
	match act:
		"left":
			_step(-1)
		"right":
			_step(1)
		"begin":
			_begin_round()
		"back":
			_go_back()


func _pressed(event: InputEvent, actions: Array[String]) -> bool:
	for a in actions:
		if InputMap.has_action(a) and event.is_action_pressed(a, false, true):
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _region_at((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var i := _region_at(mb.position)
			if i < 0:
				return
			accept_event()
			if i == _selected:
				_begin_round()
			else:
				_select(i)
				if not _is_open(i):
					_shake[_id(i)] = 0.4


## The District whose quarter (or its label) is under `p`, or -1.
func _region_at(p: Vector2) -> int:
	for i in _regions.size():
		var r := _regions[i]
		var local: Vector2 = (r["xf"] as Transform2D).affine_inverse() * p
		var h: float = r["half"]
		if absf(local.x) <= h and local.y >= -h - 10.0 and local.y <= h:
			return i
	return -1


# ---------------------------------------------------------------------- layout
func _map_pos(i: int) -> Vector2:
	var v: Variant = _defs[i].get("map_position")
	return v if v is Vector2 else Vector2.ZERO


func _layout() -> void:
	var s := size
	if s.x < MIN_SIZE.x or s.y < MIN_SIZE.y:
		return   # not laid out yet (or a tiny window): keep the last layout
	_paper = Rect2(PAPER_INSET, 30.0, s.x - PAPER_INSET * 2.0, s.y - 60.0)
	var top := _paper.position.y + ROLLER_H * 0.5 + HEADER_H
	var bottom := _paper.end.y - ROLLER_H * 0.5 - 22.0
	_panel = Rect2(_paper.end.x - PANEL_W - 30.0, top, PANEL_W, bottom - top)
	_map = Rect2(_paper.position.x + 30.0, top, _panel.position.x - _paper.position.x - 50.0, bottom - top)
	_regions.clear()
	var region_px := minf(_map.size.x, _map.size.y) * 0.37
	var half := DISTRICT_HALF + REGION_MARGIN
	var px := region_px / (half * 2.0)
	var box := Rect2()
	for i in _defs.size():
		var c := _map.get_center() + _map_pos(i) * _map.size * MAP_SPREAD
		var rot := (float(hash(_id(i)) % 1000) / 1000.0 - 0.5) * 0.16
		var xf := Transform2D(rot, Vector2(px, px), 0.0, c)
		_regions.append({"xf": xf, "px": px, "half": half})
		var r := Rect2(c - Vector2.ONE * region_px * 0.5, Vector2.ONE * region_px)
		box = r if i == 0 else box.merge(r)
	if _defs.is_empty():
		box = Rect2(_map.get_center() - Vector2(80, 60), Vector2(160, 120))
	_wall_c = box.get_center()
	_wall_r = box.size * 0.5 + Vector2(40, 44)
	_wall_r.x = minf(_wall_r.x, _map.size.x * 0.5 - 14.0)
	_wall_r.y = minf(_wall_r.y, _map.size.y * 0.5 - 14.0)
	_wall_c.x = clampf(_wall_c.x, _map.position.x + _wall_r.x + 12.0, _map.end.x - _wall_r.x - 12.0)
	_wall_c.y = clampf(_wall_c.y, _map.position.y + _wall_r.y + 12.0, _map.end.y - _wall_r.y - 12.0)
	var bw := (_panel.size.x - 36.0) * 0.5
	_begin.position = Vector2(_panel.position.x + 12.0, _panel.end.y - 54.0)
	_begin.size = Vector2(bw, 40)
	_back.position = Vector2(_panel.position.x + 24.0 + bw, _panel.end.y - 54.0)
	_back.size = Vector2(bw, 40)
	_update_buttons()
	queue_redraw()


func _build_buttons() -> void:
	_begin = Button.new()
	_begin.name = "BeginRound"
	_begin.text = "Begin Round"
	_begin.focus_mode = Control.FOCUS_NONE
	_begin.add_theme_font_size_override("font_size", 18)
	_begin.pressed.connect(_begin_round)
	add_child(_begin)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "To the Tree"
	_back.focus_mode = Control.FOCUS_NONE
	_back.add_theme_font_size_override("font_size", 18)
	_back.pressed.connect(_go_back)
	add_child(_back)


func _update_buttons() -> void:
	_begin.disabled = not _defs.is_empty() and not _is_open(_selected)


# ---------------------------------------------------------------------- drawing
func _draw() -> void:
	if not _map.has_area():
		return
	_draw_table()
	_draw_paper()
	_draw_header()
	_draw_map_frame()
	_draw_country()
	_draw_wall()
	_draw_town()
	_draw_roads()
	for i in _regions.size():
		_draw_region(i)
	_draw_compass(Vector2(_map.position.x + 46.0, _map.end.y - 50.0), 30.0)
	_draw_scale_bar(Vector2(_map.end.x - 150.0, _map.end.y - 18.0))
	_draw_panel()
	_draw_rollers()


func _draw_table() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), TABLE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Wood grain: long faint wavy lines.
	for i in 46:
		var y := rng.randf() * size.y
		var pts := PackedVector2Array()
		var ph := rng.randf() * TAU
		var amp := rng.randf_range(1.0, 5.0)
		for k in 33:
			var x := float(k) / 32.0 * size.x
			pts.append(Vector2(x, y + sin(x * 0.006 + ph) * amp + sin(x * 0.031 + ph) * 1.2))
		draw_polyline(pts, Color(0, 0, 0, rng.randf_range(0.10, 0.28)), rng.randf_range(1.0, 2.5), true)
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(0, 0, 0, 0.6))


func _draw_paper() -> void:
	var p := _paper
	# Drop shadow on the table.
	draw_rect(Rect2(p.position + Vector2(8, 10), p.size), Color(0, 0, 0, 0.35))
	# The sheet, its long edges a little ragged.
	var poly := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1348
	for k in 41:
		var y := lerpf(p.position.y, p.end.y, float(k) / 40.0)
		poly.append(Vector2(p.position.x + rng.randf_range(-1.5, 1.5), y))
	for k in 41:
		var y := lerpf(p.end.y, p.position.y, float(k) / 40.0)
		poly.append(Vector2(p.end.x + rng.randf_range(-1.5, 1.5), y))
	draw_colored_polygon(poly, PARCHMENT)
	for i in 30:
		var c := Vector2(rng.randf_range(p.position.x, p.end.x), rng.randf_range(p.position.y, p.end.y))
		var r := rng.randf_range(40.0, 220.0)
		var rect := Rect2(c - Vector2(r, r * 0.8), Vector2(r, r * 0.8) * 2.0).intersection(p)
		if rect.has_area():
			var col := SEPIA
			col.a = rng.randf_range(0.04, 0.12)
			draw_texture_rect_region(_blot, rect, Rect2((rect.position - (c - Vector2(r, r * 0.8))) / (Vector2(r, r * 0.8) * 2.0) * 256.0, rect.size / (Vector2(r, r * 0.8) * 2.0) * 256.0), col)
	for i in 80:
		var col := SEPIA
		col.a = rng.randf_range(0.05, 0.14)
		draw_circle(Vector2(rng.randf_range(p.position.x, p.end.x), rng.randf_range(p.position.y, p.end.y)), rng.randf_range(0.8, 2.4), col)
	draw_texture_rect(_vignette, p, false, Color(SEPIA, 0.45))
	# Where the sheet curls into the rollers it darkens.
	for k in 10:
		var a := 0.16 * (1.0 - float(k) / 10.0)
		draw_rect(Rect2(p.position.x, p.position.y + ROLLER_H * 0.5 + k * 2.0, p.size.x, 2.0), Color(SEPIA, a))
		draw_rect(Rect2(p.position.x, p.end.y - ROLLER_H * 0.5 - (k + 1) * 2.0, p.size.x, 2.0), Color(SEPIA, a))
	_wobbly_line(Vector2(p.position.x, p.position.y), Vector2(p.position.x, p.end.y), Color(SEPIA, 0.6), 1.2, 3)
	_wobbly_line(Vector2(p.end.x, p.position.y), Vector2(p.end.x, p.end.y), Color(SEPIA, 0.6), 1.2, 4)


func _draw_rollers() -> void:
	_draw_roller(_paper.position.y)
	_draw_roller(_paper.end.y)


## One rolled end: a cylinder across the sheet with the paper's spiral at both
## ends and a turned wooden handle sticking out.
func _draw_roller(cy: float) -> void:
	var x0 := _paper.position.x - 16.0
	var x1 := _paper.end.x + 16.0
	var h := ROLLER_H
	var r := Rect2(x0, cy - h * 0.5, x1 - x0, h)
	# Shadow under it.
	draw_rect(Rect2(r.position + Vector2(4, 8), r.size), Color(0, 0, 0, 0.3))
	# Shaded body: light band on top, darker underneath.
	var bands := 12
	for k in bands:
		var t := float(k) / float(bands - 1)
		var shade := 1.0 - absf(t - 0.32) * 1.25
		var col := PARCHMENT_DARK.lerp(PARCHMENT.lightened(0.1), clampf(shade, 0.0, 1.0)).darkened(0.12 * t)
		draw_rect(Rect2(x0, r.position.y + h * float(k) / float(bands), x1 - x0, h / float(bands) + 0.6), col)
	# Hatching on the shadow side, like the 3D shader's tone bands.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cy)
	var x := x0 + 6.0
	while x < x1 - 6.0:
		var top := cy + h * rng.randf_range(0.02, 0.14)
		draw_line(Vector2(x, top), Vector2(x + 2.0, cy + h * 0.47), Color(INK, 0.35), 1.0, true)
		x += rng.randf_range(4.0, 6.5)
	# The edge of the outer turn of paper.
	_wobbly_line(Vector2(x0 + 10.0, cy + h * 0.18), Vector2(x1 - 10.0, cy + h * 0.2), Color(INK, 0.35), 1.0, int(cy) + 1)
	_wobbly_line(Vector2(x0, r.position.y), Vector2(x1, r.position.y), INK, 2.0, int(cy) + 2)
	_wobbly_line(Vector2(x0, r.end.y), Vector2(x1, r.end.y), INK, 2.0, int(cy) + 3)
	for side: float in [-1.0, 1.0]:
		var ex: float = x0 if side < 0.0 else x1
		# Handle: a dowel and a knob.
		var dowel := Rect2(ex if side > 0.0 else ex - 30.0, cy - 6.0, 30.0, 12.0)
		draw_rect(dowel, WOOD)
		draw_rect(Rect2(dowel.position, Vector2(dowel.size.x, 4.0)), WOOD.lightened(0.25))
		draw_rect(dowel, INK, false, 1.5)
		var knob := Vector2(ex + side * 36.0, cy)
		_ellipse_fill(knob, Vector2(10.0, 15.0), WOOD)
		_ellipse_fill(knob + Vector2(-side * 2.0, -4.0), Vector2(5.0, 6.0), WOOD.lightened(0.3))
		_ellipse_line(knob, Vector2(10.0, 15.0), INK, 1.8)
		# End of the roll: an ellipse with the paper's spiral inside.
		_ellipse_fill(Vector2(ex, cy), Vector2(8.0, h * 0.5), PARCHMENT_DARK.darkened(0.05))
		_ellipse_line(Vector2(ex, cy), Vector2(8.0, h * 0.5), INK, 2.0)
		for k in 3:
			var f := 0.75 - float(k) * 0.22
			_ellipse_line(Vector2(ex + side * 0.5, cy + 1.0), Vector2(8.0 * f, h * 0.5 * f), Color(INK, 0.55), 1.0, 0.25 * TAU, 1.9 * TAU)


func _draw_header() -> void:
	var y := _paper.position.y + ROLLER_H * 0.5 + 44.0
	var title := "Choose where the plague goes next"
	_text_centered(_title_font, 34, Vector2(_paper.get_center().x, y), title, INK)
	var w := _wallet()
	_text_left(_font, 19, Vector2(_paper.position.x + 34.0, y - 4.0), "Year of Our Lord %d" % _year(), INK)
	var wallet := "Pestilence  %d     Bones  %d" % [w.x, w.y]
	var ws := _font.get_string_size(wallet, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	_text_left(_font, 19, Vector2(_paper.end.x - 34.0 - ws.x, y - 4.0), wallet, INK)
	# A flourished rule under the header.
	var ry := y + 16.0
	var cx := _paper.get_center().x
	_wobbly_line(Vector2(_paper.position.x + 34.0, ry), Vector2(cx - 18.0, ry), Color(INK, 0.7), 1.4, 21)
	_wobbly_line(Vector2(cx + 18.0, ry), Vector2(_paper.end.x - 34.0, ry), Color(INK, 0.7), 1.4, 22)
	_diamond(Vector2(cx, ry), 6.0, INK)
	_diamond(Vector2(cx - 12.0, ry), 2.5, INK)
	_diamond(Vector2(cx + 12.0, ry), 2.5, INK)


func _draw_map_frame() -> void:
	draw_rect(_map, Color(INK, 0.85), false, 2.0)
	draw_rect(_map.grow(-5.0), Color(INK, 0.45), false, 1.0)


## Fields, hills and trees outside the city wall, and the river.
func _draw_country() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1350
	var inner := _map.grow(-14.0)
	var river := _river_points()
	# Ploughed fields.
	for i in 14:
		var c := Vector2(rng.randf_range(inner.position.x + 36.0, inner.end.x - 36.0), rng.randf_range(inner.position.y + 30.0, inner.end.y - 30.0))
		if _in_wall(c, 30.0) or _near_river(c, river, 34.0) or _near_compass(c):
			continue
		var rot := rng.randf_range(-0.6, 0.6)
		var sz := Vector2(rng.randf_range(34.0, 56.0), rng.randf_range(22.0, 34.0))
		var xf := Transform2D(rot, c)
		var corners := PackedVector2Array([xf * Vector2(-sz.x, -sz.y) * 0.5, xf * Vector2(sz.x, -sz.y) * 0.5,
			xf * Vector2(sz.x, sz.y) * 0.5, xf * Vector2(-sz.x, sz.y) * 0.5])
		_wobbly_poly(corners, Color(INK, 0.4), 1.0, i)
		var rows := int(sz.y / 5.0)
		for k in range(1, rows):
			var t := float(k) / float(rows) - 0.5
			draw_line(xf * Vector2(-sz.x * 0.45, t * sz.y), xf * Vector2(sz.x * 0.45, t * sz.y), Color(INK, 0.22), 1.0, true)
	# Hills: humps hatched on one side.
	for i in 9:
		var c := Vector2(rng.randf_range(inner.position.x + 20.0, inner.end.x - 20.0), rng.randf_range(inner.position.y + 14.0, inner.end.y - 10.0))
		if _in_wall(c, 26.0) or _near_river(c, river, 26.0) or _near_compass(c):
			continue
		_hill(c, rng.randf_range(16.0, 26.0))
	# Trees.
	for i in 110:
		var c := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y + 6.0, inner.end.y))
		if _in_wall(c, 12.0) or _near_river(c, river, 14.0) or _near_compass(c):
			continue
		_tree(c, rng.randf_range(3.5, 6.0), i)
	_draw_river(river)


func _river_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var top := _wall_c.y - _wall_r.y
	var base := clampf(top - 26.0, _map.position.y + 18.0, _map.position.y + 60.0)
	for k in 41:
		var t := float(k) / 40.0
		var x := lerpf(_map.position.x + 6.0, _map.end.x - 6.0, t)
		pts.append(Vector2(x, base + sin(t * 5.2 + 0.6) * 9.0 + t * 6.0))
	return pts


func _draw_river(pts: PackedVector2Array) -> void:
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for k in pts.size():
		var p := pts[k]
		var q := pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]
		var n := q.normalized().orthogonal()
		var w := 7.0 + sin(float(k) * 0.7) * 1.5
		a.append(p + n * w)
		b.append(p - n * w)
	var poly := a.duplicate()
	var rb := b.duplicate()
	rb.reverse()
	poly.append_array(rb)
	draw_colored_polygon(poly, PARCHMENT.lightened(0.12))
	draw_polyline(a, INK, 1.6, true)
	draw_polyline(b, INK, 1.6, true)
	# Ripples.
	for k in range(1, pts.size() - 1, 2):
		var d := (pts[k + 1] - pts[k - 1]).normalized()
		var off := d.orthogonal() * (2.5 if k % 4 == 1 else -2.5)
		draw_line(pts[k] + off - d * 4.0, pts[k] + off + d * 4.0, Color(INK, 0.45), 1.0, true)


func _near_river(c: Vector2, river: PackedVector2Array, d: float) -> bool:
	for p in river:
		if p.distance_squared_to(c) < d * d:
			return true
	return false


func _near_compass(c: Vector2) -> bool:
	return c.distance_to(Vector2(_map.position.x + 46.0, _map.end.y - 50.0)) < 50.0 \
		or Rect2(_map.end.x - 160.0, _map.end.y - 36.0, 160.0, 36.0).has_point(c)


## Inside the wall's superellipse grown by `margin` px.
func _in_wall(c: Vector2, margin: float) -> bool:
	var d := (c - _wall_c) / (_wall_r + Vector2.ONE * margin)
	return pow(absf(d.x), WALL_ROUNDNESS) + pow(absf(d.y), WALL_ROUNDNESS) <= 1.0


## A point on the wall at angle `a`: a squarish superellipse, slightly wobbly.
func _wall_point(a: float) -> Vector2:
	var wob := 1.0 + sin(a * 3.0 + 1.0) * 0.02 + sin(a * 7.0) * 0.01
	var e := 2.0 / WALL_ROUNDNESS
	var v := Vector2(signf(cos(a)) * pow(absf(cos(a)), e), signf(sin(a)) * pow(absf(sin(a)), e))
	return _wall_c + v * _wall_r * wob


## The city wall: a thick ink ring with crenels, round towers and a south gate.
func _draw_wall() -> void:
	var gate := PI * 0.5
	var gap := 0.09
	var pts := PackedVector2Array()
	var inner := PackedVector2Array()
	var steps := 160
	for k in steps + 1:
		var a := gate + gap + float(k) / float(steps) * (TAU - gap * 2.0)
		var p := _wall_point(a)
		pts.append(p)
		inner.append(_wall_c + (p - _wall_c) * (1.0 - 5.0 / _wall_r.length() * 1.4))
	draw_polyline(pts, INK, 3.0, true)
	draw_polyline(inner, Color(INK, 0.6), 1.2, true)
	for k in range(0, steps, 2):
		var p := pts[k]
		var out := (p - _wall_c).normalized()
		draw_line(p, p + out * 3.5, INK, 2.0)
	# Towers.
	var n_towers := 14
	for k in n_towers:
		var a := gate + gap + float(k) / float(n_towers - 1) * (TAU - gap * 2.0)
		var p := _wall_point(a)
		var r := 7.0 if k == 0 or k == n_towers - 1 else 5.0
		draw_circle(p, r, PARCHMENT.lightened(0.1))
		_wobbly_circle(p, r, INK, 1.8, float(k))
		draw_arc(p, r - 2.5, PI * 0.1, PI * 0.9, 8, Color(INK, 0.5), 1.0, true)


## The rest of the city inside the wall: small blocks of houses and a
## church, all kept clear of the playable quarters.
func _draw_town() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1352
	var placed: Array[Rect2] = []
	for i in 260:
		if placed.size() >= 34:
			break
		var c := _wall_c + Vector2(rng.randf_range(-1, 1) * _wall_r.x, rng.randf_range(-1, 1) * _wall_r.y) * 0.9
		var sz := Vector2(rng.randf_range(16.0, 30.0), rng.randf_range(10.0, 18.0))
		var r := Rect2(c - sz * 0.5, sz)
		if not _in_wall(c, -20.0) or _near_region(r.grow(10.0)):
			continue
		var clash := false
		for o in placed:
			if o.grow(7.0).intersects(r):
				clash = true
				break
		if clash:
			continue
		placed.append(r)
		var xf := Transform2D(rng.randf_range(-0.15, 0.15), c)
		var corners := PackedVector2Array([xf * (-sz * 0.5), xf * (Vector2(sz.x, -sz.y) * 0.5), xf * (sz * 0.5), xf * (Vector2(-sz.x, sz.y) * 0.5)])
		draw_colored_polygon(corners, Color(PARCHMENT_DARK, 0.6))
		# Split into a few houses with short party walls.
		var n := maxi(2, int(sz.x / 8.0))
		for k in range(1, n):
			var x := -sz.x * 0.5 + sz.x * float(k) / float(n)
			draw_line(xf * Vector2(x, -sz.y * 0.5), xf * Vector2(x, sz.y * 0.5), Color(INK, 0.4), 1.0, true)
		corners.append(corners[0])
		draw_polyline(corners, Color(INK, 0.6), 1.1, true)


func _near_region(r: Rect2) -> bool:
	for reg in _regions:
		var xf: Transform2D = reg["xf"]
		var h: float = float(reg["half"]) * float(reg["px"]) * 1.1
		if Rect2(xf.origin - Vector2(h, h + 30.0), Vector2(h * 2.0, h * 2.0 + 30.0)).intersects(r):
			return true
	return false


## Roads: from the gate to the nearest quarter, and between the quarters.
func _draw_roads() -> void:
	var gate := _wall_point(PI * 0.5)
	var outside := Vector2(gate.x, minf(gate.y + 40.0, _map.end.y - 6.0))
	var col := Color(INK, 0.5)
	_road(outside, gate, col)
	if _regions.is_empty():
		return
	var nearest := 0
	for i in _regions.size():
		if _region_center(i).distance_to(gate) < _region_center(nearest).distance_to(gate):
			nearest = i
	_road(gate, _region_center(nearest), col)
	for i in range(1, _regions.size()):
		_road(_region_center(i - 1), _region_center(i), col)


func _road(a: Vector2, b: Vector2, col: Color) -> void:
	var n := (b - a).normalized().orthogonal() * 3.5
	_wobbly_line(a + n, b + n, col, 1.1, int(a.x))
	_wobbly_line(a - n, b - n, col, 1.1, int(b.y))


func _region_center(i: int) -> Vector2:
	return (_regions[i]["xf"] as Transform2D).origin


## One District quarter: ground, contents, hatching when beaten, wall, label,
## selection ring.
func _draw_region(i: int) -> void:
	var r := _regions[i]
	var xf: Transform2D = r["xf"]
	var id := _id(i)
	if _shake.has(id):
		var t := float(_shake[id])
		xf.origin += Vector2(sin(t * 60.0) * 6.0 * t / 0.4, 0)
	var px: float = r["px"]
	var half: float = r["half"]
	var open := _is_open(i)
	var beaten := _is_beaten(i)
	var layout := _layout_of(i)
	var alpha := 1.0 if open else LOCKED_ALPHA
	var shape := xf * _octagon(half, 4.0)
	draw_colored_polygon(shape, Color(PARCHMENT.lightened(0.14), 0.92 if open else 0.75))
	if not open:
		_draw_locked(xf, half)
	elif layout.is_empty():
		_draw_placeholder(xf, half, i)
	else:
		_draw_houses(xf, layout)
	if beaten:
		_hatch(xf, _octagon(half, 4.0), px, 0.785, 4.5, Color(INK, 0.5), 1.0, i)
		_hatch(xf, _octagon(half, 4.0), px, -0.785, 8.0, Color(INK, 0.3), 1.0, i + 50)
		if not layout.is_empty():
			_outline_houses(xf, layout)
	if open and not layout.is_empty():
		_draw_crosses(xf, layout, _dead_houses(i))
	# Quarter wall, drawn twice for the double ink line.
	var line := Color(INK, alpha)
	_wobbly_poly(shape, line, 2.4 if open else 1.4, i * 7 + 1)
	if open:
		_wobbly_poly(xf * _octagon(half + 1.0, 4.4), Color(INK, 0.35), 1.0, i * 7 + 2)
	# Corner towers.
	if open:
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector2 = xf * ((c as Vector2) * (half - 1.2))
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), PARCHMENT.lightened(0.1))
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), INK, false, 1.5)
	# Label above the quarter.
	var label_at := xf * Vector2(0, -half) + Vector2(0, -10.0)
	var title := str(_defs[i].get("title")) if open else "Unknown"
	var fs := 28
	var tw := _title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_rect(Rect2(label_at - Vector2(tw * 0.5 + 8.0, 22.0), Vector2(tw + 16.0, 28.0)), Color(PARCHMENT.lightened(0.08), 0.85 * alpha + 0.1))
	_text_centered(_title_font, fs, label_at, title, Color(INK, alpha if open else 0.55))
	if beaten:
		_text_centered(_font, 13, xf * Vector2(0, half) + Vector2(0, 16.0), "— taken —", Color(INK, 0.8))
	# Selection: a dashed ring that breathes, and a hand pointing at it.
	if i == _selected or i == _hover:
		var pulse := 0.55 + 0.35 * sin(_time * 3.0) if i == _selected else 0.35
		_dashed_poly(xf * _octagon(half + 3.2, 5.0), Color(INK, pulse), 2.0, 9.0)
	if i == _selected:
		var u := label_at + Vector2(0, 8.0)
		_wobbly_line(u - Vector2(tw * 0.5, 0), u + Vector2(tw * 0.5, 0), INK, 1.6, i + 90)


func _octagon(h: float, c: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-h + c, -h), Vector2(h - c, -h), Vector2(h, -h + c), Vector2(h, h - c),
		Vector2(h - c, h), Vector2(-h + c, h), Vector2(-h, h - c), Vector2(-h, -h + c)])


## House footprints: a sepia-washed block, an ink outline and the roof ridge
## with its shaded half hatched.
func _draw_houses(xf: Transform2D, layout: Array) -> void:
	for h: Dictionary in layout:
		var hx := xf * Transform2D(float(h.get("rot", 0.0)), h.get("center", Vector2.ZERO) as Vector2)
		var s: Vector2 = (h.get("size", Vector2.ONE) as Vector2) * 0.5
		var corners := PackedVector2Array([hx * Vector2(-s.x, -s.y), hx * Vector2(s.x, -s.y), hx * Vector2(s.x, s.y), hx * Vector2(-s.x, s.y)])
		draw_colored_polygon(corners, PARCHMENT_DARK)
		var ridge_a := hx * Vector2(-s.x, 0)
		var ridge_b := hx * Vector2(s.x, 0)
		# Shaded roof half.
		var k := 6
		for j in range(1, k):
			var t := float(j) / float(k)
			var a := hx * Vector2(lerpf(-s.x, s.x, t), 0)
			draw_line(a, hx * Vector2(lerpf(-s.x, s.x, t) - s.y * 0.35, s.y), Color(INK, 0.45), 1.0, true)
		draw_line(ridge_a, ridge_b, Color(INK, 0.8), 1.0, true)
		corners.append(corners[0])
		draw_polyline(corners, INK, 1.3, true)


## The house outlines again, over the hatching of a taken District.
func _outline_houses(xf: Transform2D, layout: Array) -> void:
	for h: Dictionary in layout:
		var hx := xf * Transform2D(float(h.get("rot", 0.0)), h.get("center", Vector2.ZERO) as Vector2)
		var s: Vector2 = (h.get("size", Vector2.ONE) as Vector2) * 0.5
		draw_polyline(PackedVector2Array([hx * Vector2(-s.x, -s.y), hx * Vector2(s.x, -s.y), hx * Vector2(s.x, s.y),
			hx * Vector2(-s.x, s.y), hx * Vector2(-s.x, -s.y)]), INK, 1.3, true)


## Ink Xs over the houses that died in the best Round there, corner to corner
## and a little past, with a parchment halo so they read over the hatching.
func _draw_crosses(xf: Transform2D, layout: Array, dead: Array) -> void:
	if dead.is_empty():
		return
	var lookup := {}
	for d: Variant in dead:
		lookup[int(d)] = true
	for h: Dictionary in layout:
		if not lookup.has(int(h.get("index", -1))):
			continue
		var hx := xf * Transform2D(float(h.get("rot", 0.0)), h.get("center", Vector2.ZERO) as Vector2)
		var s: Vector2 = (h.get("size", Vector2.ONE) as Vector2) * 0.5 * 1.15
		var seed_value := int(h.get("index", 0))
		var a1 := hx * Vector2(-s.x, -s.y)
		var b1 := hx * Vector2(s.x, s.y)
		var a2 := hx * Vector2(s.x, -s.y)
		var b2 := hx * Vector2(-s.x, s.y)
		for pass_i in 2:
			var col := Color(PARCHMENT.lightened(0.1), 0.9) if pass_i == 0 else INK
			var w := 5.0 if pass_i == 0 else 2.4
			_wobbly_line(a1, b1, col, w, seed_value * 3)
			_wobbly_line(a2, b2, col, w, seed_value * 3 + 1)


## Open but never visited: loose, unfinished blocks and a question mark.
func _draw_placeholder(xf: Transform2D, half: float, i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_id(i))
	var col := Color(INK, 0.4)
	var cells := 3
	var street := 3.2
	var span := (half * 2.0 - 4.0 - street * float(cells - 1)) / float(cells)
	for gx in cells:
		for gy in cells:
			var x0 := -half + 2.0 + float(gx) * (span + street)
			var y0 := -half + 2.0 + float(gy) * (span + street)
			var j := Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8))
			var block := PackedVector2Array([Vector2(x0, y0) + j, Vector2(x0 + span, y0) - j,
				Vector2(x0 + span, y0 + span) + j * 0.5, Vector2(x0, y0 + span) - j * 0.5])
			_dashed_poly(xf * block, col, 1.1, 5.0)
			# A few quick scribbles inside, as if only sketched in.
			for k in rng.randi_range(2, 4):
				var a := Vector2(rng.randf_range(x0 + 1.0, x0 + span - 1.0), rng.randf_range(y0 + 1.0, y0 + span - 1.0))
				var b := a + Vector2(rng.randf_range(2.0, 5.0), rng.randf_range(-3.0, -1.0))
				var c := b + Vector2(rng.randf_range(-3.0, -1.0), rng.randf_range(2.0, 4.0))
				draw_polyline(PackedVector2Array([xf * a, xf * b, xf * c, xf * (c + (b - a) * 0.8)]), Color(INK, 0.22), 1.0, true)
	var q := xf.origin
	draw_circle(q, 20.0, Color(PARCHMENT.lightened(0.14), 0.9))
	_text_centered(_title_font, 40, q + Vector2(0, 13.0), "?", Color(INK, 0.7))
	_text_centered(_font, 13, xf * Vector2(0, half) + Vector2(0, -6.0), "not yet surveyed", Color(INK, 0.55))


## Locked: faint dashed blocks and a padlock.
func _draw_locked(xf: Transform2D, half: float) -> void:
	var col := Color(INK, LOCKED_ALPHA * 0.8)
	_dashed_poly(xf * _octagon(half * 0.7, 3.0), col, 1.0, 6.0)
	var c := xf.origin
	var body := Rect2(c + Vector2(-13, -4), Vector2(26, 21))
	draw_arc(c + Vector2(0, -4), 9.0, PI, TAU, 14, Color(INK, 0.55), 3.0, true)
	draw_rect(body, PARCHMENT.lightened(0.1))
	draw_rect(body, Color(INK, 0.6), false, 2.0)
	draw_circle(c + Vector2(0, 5), 3.0, Color(INK, 0.6))
	draw_line(c + Vector2(0, 6), c + Vector2(0, 12), Color(INK, 0.6), 2.0)


## Parallel ink lines across a convex local polygon (`poly` in ground units),
## `angle` from the local x axis, `gap_px` screen pixels apart.
func _hatch(xf: Transform2D, poly: PackedVector2Array, px: float, angle: float, gap_px: float, col: Color, width: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var d := Vector2(cos(angle), sin(angle))
	var n := d.orthogonal()
	var reach := 0.0
	for p in poly:
		reach = maxf(reach, p.length())
	var gap := gap_px / px
	var segs := PackedVector2Array()
	var o := -reach
	while o <= reach:
		var a := n * o - d * reach * 1.2
		var b := n * o + d * reach * 1.2
		var clip := _clip_convex(a, b, poly)
		if clip.size() == 2:
			var j0 := rng.randf_range(-0.4, 0.3)
			var j1 := rng.randf_range(-0.4, 0.3)
			segs.append(xf * (clip[0] - d * j0))
			segs.append(xf * (clip[1] + d * j1))
		o += gap * rng.randf_range(0.85, 1.15)
	if not segs.is_empty():
		draw_multiline(segs, col, width, true)


## Cyrus-Beck: the part of segment a-b inside the convex polygon (any winding).
func _clip_convex(a: Vector2, b: Vector2, poly: PackedVector2Array) -> PackedVector2Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var centre := Vector2.ZERO
	for p in poly:
		centre += p
	centre /= float(poly.size())
	for k in poly.size():
		var p0 := poly[k]
		var p1 := poly[(k + 1) % poly.size()]
		var nrm := (p1 - p0).orthogonal()
		if nrm.dot(centre - p0) < 0.0:
			nrm = -nrm       # inward
		var num := nrm.dot(a - p0)
		var den := nrm.dot(d)
		if is_zero_approx(den):
			if num < 0.0:
				return PackedVector2Array()
			continue
		var t := -num / den
		if den > 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])


## The selected District's card: title, Exterminator, state, fallen houses,
## a legend and the buttons.
func _draw_panel() -> void:
	var p := _panel
	draw_rect(p, Color(PARCHMENT.lightened(0.1), 0.6))
	draw_rect(p, Color(INK, 0.85), false, 2.0)
	draw_rect(p.grow(-5.0), Color(INK, 0.45), false, 1.0)
	var x := p.position.x + 18.0
	var cx := p.get_center().x
	var y := p.position.y + 44.0
	if _defs.is_empty():
		_text_centered(_font, 18, Vector2(cx, y), "No Districts known.", INK)
		return
	var i := _selected
	var open := _is_open(i)
	var beaten := _is_beaten(i)
	var layout := _layout_of(i)
	var title := str(_defs[i].get("title")) if open else "Unknown District"
	_text_centered(_title_font, 32, Vector2(cx, y), title, INK)
	y += 14.0
	_wobbly_line(Vector2(x + 20.0, y), Vector2(p.end.x - 38.0, y), Color(INK, 0.6), 1.2, 31)
	_diamond(Vector2(cx, y), 3.5, INK)
	y += 30.0
	var lines: Array[String] = []
	if not open:
		var req := str(_defs[i].get("requires"))
		var req_title := req
		for k in _defs.size():
			if _id(k) == req:
				req_title = str(_defs[k].get("title"))
		lines.append("Locked. Its gates open once")
		lines.append("%s is taken." % req_title)
	else:
		lines.append("Warden: %s" % str(_defs[i].get("exterminator_title")))
		if beaten:
			lines.append("Taken: the Warden has fallen.")
		elif layout.is_empty():
			lines.append("Not yet visited.")
		else:
			lines.append("Still holding out.")
		if not layout.is_empty():
			var dead := _dead_houses(i).size()
			lines.append("Houses fallen: %d of %d" % [dead, layout.size()])
		lines.append("Townsfolk: about %d abroad" % int(_defs[i].get("wanderers")))
		var stage := _visual_stage(i)
		if stage >= 0:
			lines.append("Streets: %s" % STAGE_TEXT[clampi(stage, 0, STAGE_TEXT.size() - 1)])
	for l in lines:
		_text_left(_font, 17, Vector2(x, y), l, INK)
		y += 25.0
	# Legend.
	y = maxf(y + 12.0, p.end.y - 190.0)
	_text_left(_font, 14, Vector2(x, y), "Legend", SEPIA)
	y += 12.0
	var lx := x + 4.0
	var house := Transform2D(0.0, Vector2(lx + 12.0, y + 12.0))
	var entry := [{"index": 0, "center": Vector2.ZERO, "size": Vector2(20, 13), "rot": 0.0}]
	_draw_houses(house, entry)
	_text_left(_font, 14, Vector2(lx + 34.0, y + 17.0), "a house", INK)
	y += 28.0
	house = Transform2D(0.0, Vector2(lx + 12.0, y + 12.0))
	_draw_houses(house, entry)
	_draw_crosses(house, entry, [0])
	_text_left(_font, 14, Vector2(lx + 34.0, y + 17.0), "died in your best Round", INK)
	y += 28.0
	var sw := PackedVector2Array([Vector2(-10, -7), Vector2(10, -7), Vector2(10, 7), Vector2(-10, 7)])
	var swx := Transform2D(0.0, Vector2(lx + 12.0, y + 12.0))
	draw_colored_polygon(swx * sw, PARCHMENT.lightened(0.14))
	_hatch(swx, sw, 1.0, 0.785, 4.0, Color(INK, 0.62), 1.0, 3)
	_hatch(swx, sw, 1.0, -0.785, 7.0, Color(INK, 0.4), 1.0, 4)
	var closed := swx * sw
	closed.append(closed[0])
	draw_polyline(closed, INK, 1.2)
	_text_left(_font, 14, Vector2(lx + 34.0, y + 17.0), "a District taken", INK)
	y += 30.0
	_text_left(_font, 12, Vector2(x, y + 6.0), "Click: select, again to begin.  ← →: select", SEPIA)
	_text_left(_font, 12, Vector2(x, y + 22.0), "Enter / A: begin.   Esc / B: the Tree", SEPIA)


func _draw_compass(c: Vector2, r: float) -> void:
	draw_circle(c, r * 0.95, Color(PARCHMENT.lightened(0.1), 0.6))
	_wobbly_circle(c, r * 0.95, Color(INK, 0.6), 1.0, 1.0)
	_wobbly_circle(c, r * 0.6, Color(INK, 0.4), 1.0, 2.0)
	for k in 8:
		var a := float(k) / 8.0 * TAU - PI * 0.5
		var long := k % 2 == 0
		var tip := c + Vector2(cos(a), sin(a)) * (r * (1.1 if long else 0.7))
		var side := Vector2(cos(a + PI * 0.5), sin(a + PI * 0.5)) * (r * (0.16 if long else 0.1))
		var left := PackedVector2Array([c, c + side, tip])
		var right := PackedVector2Array([c, tip, c - side])
		draw_colored_polygon(left, INK)
		draw_colored_polygon(right, PARCHMENT.lightened(0.1))
		draw_polyline(PackedVector2Array([c + side, tip, c - side]), INK, 1.0, true)
	_text_centered(_title_font, 20, c + Vector2(0, -r * 1.2), "N", INK)


func _draw_scale_bar(at: Vector2) -> void:
	var w := 24.0
	for k in 5:
		var r := Rect2(at + Vector2(w * k, -6.0), Vector2(w, 6.0))
		if k % 2 == 0:
			draw_rect(r, INK)
		draw_rect(r, INK, false, 1.0)
	_text_left(_font, 12, at + Vector2(0, -10.0), "Perches", SEPIA)


func _tree(c: Vector2, r: float, i: int) -> void:
	draw_line(c + Vector2(0, r * 0.6), c + Vector2(0, r * 1.7), Color(INK, 0.7), 1.2)
	draw_circle(c, r, PARCHMENT.lightened(0.05))
	_wobbly_circle(c, r, Color(INK, 0.75), 1.1, float(i))
	for k in 3:
		var x := c.x + r * (0.05 + 0.25 * k)
		draw_line(Vector2(x, c.y - r * 0.3), Vector2(x + r * 0.15, c.y + r * 0.6), Color(INK, 0.45), 1.0, true)


func _hill(c: Vector2, w: float) -> void:
	var pts := PackedVector2Array()
	for k in 13:
		var t := float(k) / 12.0
		pts.append(c + Vector2((t - 0.5) * w * 2.0, -sin(t * PI) * w * 0.6))
	draw_polyline(pts, Color(INK, 0.6), 1.3, true)
	for k in range(7, 12):
		var t := float(k) / 12.0
		var p := c + Vector2((t - 0.5) * w * 2.0, -sin(t * PI) * w * 0.6)
		draw_line(p, p + Vector2(-2.0, w * 0.25), Color(INK, 0.4), 1.0, true)


# ---------------------------------------------------------------------- ink helpers
func _wobbly_line(a: Vector2, b: Vector2, c: Color, width: float, seed_value: int) -> void:
	var pts := PackedVector2Array()
	var steps := maxi(4, int(a.distance_to(b) / 12.0))
	var normal := (b - a).normalized().orthogonal()
	var ph := float(absi(seed_value) % 1000) * 0.01
	for i in steps + 1:
		var t := float(i) / float(steps)
		var off := sin(t * 7.0 + ph) * 1.1 + sin(t * 17.0 + ph * 2.0) * 0.5
		pts.append(a.lerp(b, t) + normal * off * sin(t * PI))
	draw_polyline(pts, c, width, true)


func _wobbly_poly(pts: PackedVector2Array, c: Color, width: float, seed_value: int) -> void:
	for k in pts.size():
		_wobbly_line(pts[k], pts[(k + 1) % pts.size()], c, width, seed_value * 13 + k)


func _wobbly_circle(centre: Vector2, r: float, c: Color, width: float, ph: float) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := float(i) / 32.0 * TAU
		var rr := r + sin(a * 2.0 + ph) * 0.4 + sin(a * 5.0 + ph * 1.7) * 0.2
		pts.append(centre + Vector2(cos(a), sin(a)) * rr)
	draw_polyline(pts, c, width, true)


func _dashed_poly(pts: PackedVector2Array, c: Color, width: float, dash: float) -> void:
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		var seg_len := a.distance_to(b)
		var t := 0.0
		while t < seg_len:
			draw_line(a.lerp(b, t / seg_len), a.lerp(b, minf(t + dash * 0.6, seg_len) / seg_len), c, width, true)
			t += dash


func _ellipse_fill(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 24:
		var a := float(k) / 24.0 * TAU
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)


func _ellipse_line(c: Vector2, r: Vector2, col: Color, width: float, from := 0.0, to := TAU) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		var a := lerpf(from, to, float(k) / 24.0)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_polyline(pts, col, width, true)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


func _text_left(f: Font, fs: int, at: Vector2, s: String, col: Color) -> void:
	draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_centered(f: Font, fs: int, at: Vector2, s: String, col: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(at.x - w * 0.5, at.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _make_font(names: Array[String]) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	return f


## A radial gradient texture (centre to corner) in white, tinted when drawn.
func _radial(colors: Array[Color], offsets: Array[float]) -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t


func _box(fill: Color, border: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = INK
	s.set_border_width_all(border)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


## Ink-on-parchment buttons and the serif font (as on the Upgrade Tree).
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font
	var normal := _box(PARCHMENT.lightened(0.2), 2)
	var hover := _box(PARCHMENT_DARK, 2)
	var pressed := _box(INK, 2)
	var disabled := _box(Color(PARCHMENT, 0.5), 1)
	disabled.border_color = Color(INK, 0.35)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_pressed_color", "Button", PARCHMENT)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.4))
	return t


# ---------------------------------------------------------------------- debug
func _apply_debug_args() -> void:
	var args := OS.get_cmdline_user_args()
	var dev := _run != null and bool(_run.get("dev_mode"))
	var shot := ""
	var delay := 1.0
	var map_mode := ""
	var layout_arg := ""
	var select_id := ""
	for arg in args:
		if arg.begins_with("--screenshot="):
			shot = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-delay="):
			delay = float(arg.trim_prefix("--screenshot-delay="))
		elif arg.begins_with("--dev-select="):
			select_id = arg.trim_prefix("--dev-select=")
		elif dev and arg.begins_with("--dev-map="):
			map_mode = arg.trim_prefix("--dev-map=")
		elif dev and (arg == "--dev-layout" or arg.begins_with("--dev-layout=")):
			layout_arg = arg.trim_prefix("--dev-layout").trim_prefix("=")
			if layout_arg.is_empty():
				layout_arg = "*"
	if map_mode == "fresh":
		_run.set("beaten", {})
		_run.set("best_dead_houses", {})
		_run.set("layouts", {})
		_run.set("current_district", _id(0) if not _defs.is_empty() else "slums")
	elif map_mode == "progress" and not _defs.is_empty():
		_run.set("beaten", {_id(0): true})
		_run.set("layouts", {_id(0): []})
		_run.set("best_dead_houses", {})
		if _defs.size() > 1:
			_run.set("current_district", _id(1))
		if layout_arg.is_empty():
			layout_arg = "*"
	if not layout_arg.is_empty():
		_dev_layouts(layout_arg, map_mode == "progress")
	if not select_id.is_empty():
		if _run != null:
			_run.set("current_district", select_id)
	if not shot.is_empty():
		_screenshot(shot, delay)


## Puts layouts into the Run (memory only) for the Districts that have one
## stored already (all open ones without a --dev-map), from a JSON file or
## made up; with `cross` about half the houses are marked dead.
func _dev_layouts(source: String, cross: bool) -> void:
	var data := {}
	if source != "*" and FileAccess.file_exists(source):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
		if parsed is Dictionary:
			data = parsed
	var layouts: Dictionary = (_run.get("layouts") as Dictionary).duplicate()
	var dead: Dictionary = (_run.get("best_dead_houses") as Dictionary).duplicate()
	for i in _defs.size():
		var id := _id(i)
		if not layouts.has(id) and not (layouts.is_empty() and _is_open(i)):
			continue
		var entries: Array = []
		if data.has(id):
			for row: Array in data[id]:
				entries.append({"index": int(row[0]), "center": Vector2(row[1], row[2]),
					"size": Vector2(row[3], row[4]), "rot": float(row[5])})
		else:
			entries = _fake_layout(hash(id))
		layouts[id] = entries
		if cross:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(id) + 5
			var ids: Array[int] = []
			for e: Dictionary in entries:
				if rng.randf() < 0.45:
					ids.append(int(e["index"]))
			dead[id] = ids
	_run.set("layouts", layouts)
	_run.set("best_dead_houses", dead)


## Rows of houses along four streets, roughly like the slums.
static func _fake_layout(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	for z: float in [-19.5, -6.0, 6.0, 19.5]:
		var x := -20.0
		while x < 19.0:
			var w := rng.randf_range(5.0, 7.5)
			if x + w > 21.0:
				break
			if absf(x + w * 0.5) > 3.0:
				out.append({"index": out.size(), "center": Vector2(x + w * 0.5, z + rng.randf_range(-0.4, 0.4)),
					"size": Vector2(w - 0.6, rng.randf_range(4.2, 5.0)), "rot": rng.randf_range(-0.04, 0.04)})
			x += w + rng.randf_range(0.3, 1.2)
	return out


func _screenshot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot saved to ", path)
	get_tree().quit()
