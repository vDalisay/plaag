## Round HUD, laid out by bullet-heaven conventions (UX pass), all from UiKit:
## * Top centre: the District Infection bar ("The Slums · 34%", red fill, a
##   tick at the Exterminator threshold with a skull and the Warden's name that
##   fades once he has come); under it the Round timer (punches every second of
##   the last 10) and the Vigilance strip (Calm | Wary | Alarmed | Hunting, the
##   current tier inked solid, a sliding marker; it punches and toasts on a
##   tier change); under that, while an Exterminator lives, the boss bar (name
##   in the display font, red fill, the faint ink self-Cleanse band).
## * Top left: the wallet (Pestilence and Bones; the shown value only rises when
##   a flying payout lands, then punches), the Colony's Adults with a "+N" Pup
##   note, the Lead Rat's hit pips and the Year.
## * Bottom centre: one ability slot per unlocked ability (Raid, Hide) with a
##   radial cooldown sweep, a countdown, a prompt under it and a one-time amber
##   ring when it becomes ready; while Hidden, Hide's slot counts down.
## * Right edge: toasts (at most TOAST_MAX; repeats of a kind merge):
##   Vigilance tier, houses fallen, Pups matured (low priority), Raid ready.
## * Centre: the Round title card (District, Year, an objective line for the
##   first Rounds of a Run), the Exterminator's arrival banner, the one-time
##   door hint, and on Round end the ResultsPanel. The `pause` action opens the
##   PauseMenu (never after the Round has ended).
## The WorldOverlay (bars over heads, Bite numbers, flying payouts, the boss
## arrow, the hit vignette) sits under the panels, unscaled; the panel root
## scales by Settings.hud_scale. A Lead Rat hit flashes the vignette, shakes
## the camera (follow_camera.shake), hit-stops (Engine.time_scale) and punches
## the pips. Everything is read by property name; "—" while a source is
## missing. R restarts the Round on the results screen only with --dev.
## Debug: --results-test=<reason> ends the Round after 6 s with that reason,
## --pause-test opens the pause menu after 2 s, --toast-test fires one of each
## toast after 1 s.
extends CanvasLayer

const NONE := "—"
const MARGIN := 24.0
## The door hint shows when the Lead Rat is this close to a door, for this long.
const HINT_RANGE := 3.5
const HINT_TIME := 5.0
## Kept for callers of vigilance_word(); the tiers live in the RoundDirector.
const VIGILANCE_TIERS := RoundDirector.VIGILANCE_TIERS
const TIER_NEWS := ["The town is calm", "The town grows wary", "The town is alarmed", "The town is hunting you"]
## Banner: seconds to fade in, hold and fade out.
const BANNER_TIMES := Vector3(0.6, 2.4, 0.9)
## Round title card: in, hold, out.
const CARD_TIMES := Vector3(0.4, 1.8, 0.6)
## The objective line shows for this many Rounds of a Run.
const OBJECTIVE_ROUNDS := 3
## The boss bar's cleanse band shows this many seconds of self-Cleanse.
const CLEANSE_SHOWN := 3.0
const INFECTION_BAR_WIDTH := 560.0
const VIGILANCE_WIDTH := 420.0
const BOSS_BAR_WIDTH := 480.0
const SLOT_SIZE := 56.0
const TOAST_MAX := 3
const TOAST_IN := 0.2
const TOAST_SHOW := 3.0
const TOAST_OUT := 0.3
const TOAST_WIDTH := 280.0
const TOAST_TOP := 96.0
## kind -> [icon, text for one, text for n (%d)]. "vigilance" gets its text passed in.
const TOASTS := {
	"vigilance": ["eye", "", ""],
	"house": ["house", "A house has fallen", "%d houses have fallen"],
	"pup": ["pup", "A Pup has matured", "%d Pups have matured"],
	"raid": ["raid", "Raid ready", "Raid ready"],
}
const HIT_SHAKE := 0.45
const HITSTOP_SCALE := 0.05
const HITSTOP_TIME := 0.06
const WAY_OPEN := ResultsPanel.WAY_OPEN
const CITY_YOURS := ResultsPanel.CITY_YOURS

## Once per session (survives scene reloads).
static var _hint_done := false

var _director: RoundDirector
var _dev := false
var _overlay: WorldOverlay
var _root: Control
# Top centre
var _top: VBoxContainer
var _infection: _InfectionBar
var _timer: Label
var _last_sec := -1
var _vigilance: _VigilanceStrip
var _boss_box: VBoxContainer
var _boss_title: Label
var _boss_bar: _BossBar
var _boss_hint: Label
var _boss: Node3D
var _bosses_seen := {}        # instance id -> true (one banner each)
var _tick_faded := false
# Wallet
var _pest_icon: IconRect
var _pest_label: Label
var _bones_icon: IconRect
var _bones_label: Label
var _shown_p := -1
var _shown_b := -1
var _colony_label: Label
var _pups_label: Label
var _pips: _Pips
var _year: Label
# Abilities
var _ability_bar: HBoxContainer
var _raid_slot: _AbilitySlot
var _raid_box: VBoxContainer
var _hide_slot: _AbilitySlot
var _hide_box: VBoxContainer
var _raid_cd_prev := 0.0
var _hide_cd_prev := 0.0
# Toasts
var _toast_layer: Control
var _toasts: Array[Dictionary] = []
var _maturings_seen := -1
# Centre
var _hint_panel: PanelContainer
var _hint_left := 0.0
var _banner: PanelContainer
var _banner_label: Label
var _banner_sub: Label
var _banner_tween: Tween
var _card: PanelContainer
var _card_box: VBoxContainer
var _pause: PauseMenu
var _results: ResultsPanel
var _lead: Node
var _hitstop_on := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dev = OS.get_cmdline_user_args().has("--dev")
	_build()
	_apply_scale()
	get_viewport().size_changed.connect(_apply_scale)
	var s := UiKit.settings()
	if s != null and s.has_signal("changed"):
		s.connect("changed", _apply_scale)
	_refresh(0.0)
	_show_title_card.call_deferred()
	_parse_debug_args()


func _exit_tree() -> void:
	if _hitstop_on:
		Engine.time_scale = 1.0


func _process(delta: float) -> void:
	if _director == null or not is_instance_valid(_director):
		_find_director()
	_find_lead()
	_refresh(delta)
	_overlay.top_inset = _top.get_global_rect().end.y


func _unhandled_input(event: InputEvent) -> void:
	if _results.visible:
		if _dev and event is InputEventKey and event.pressed and not event.echo \
				and (event as InputEventKey).keycode == KEY_R:
			get_viewport().set_input_as_handled()
			get_tree().paused = false
			get_tree().reload_current_scene()
		return
	if event.is_action_pressed("pause") and not event.is_echo() and not _pause.is_open() and not _round_over():
		get_viewport().set_input_as_handled()
		open_pause()


## Opens the pause menu (not after the Round has ended).
func open_pause() -> void:
	if _round_over() or _pause.is_open():
		return
	_pause.director = _director
	_pause.open()


func _round_over() -> bool:
	return _director != null and is_instance_valid(_director) and _director.has_ended()


func _find_director() -> void:
	_director = get_tree().get_first_node_in_group("round_director") as RoundDirector
	if _director == null:
		return
	_director.round_ended.connect(_on_round_ended)
	_director.payout.connect(_overlay.add_payout)
	_director.bite_landed.connect(_overlay.add_bite)
	_director.house_fallen.connect(func(_h: Node3D) -> void: toast("house"))
	_director.vigilance_tier_changed.connect(_on_tier_changed)
	_shown_p = _director.pestilence
	_shown_b = _director.bones
	if _director.has_ended():
		_on_round_ended(_director.end_reason)


func _find_lead() -> void:
	if _lead != null and is_instance_valid(_lead):
		return
	_lead = get_tree().get_first_node_in_group("lead_rat")
	if _lead != null and _lead.has_signal("hurt"):
		_lead.connect("hurt", _on_lead_hurt)


func _run() -> Node:
	return get_node_or_null("/root/Run")


## The DistrictDef being played (duck typed), or null.
func _district() -> Object:
	var run := _run()
	if run == null or not run.has_method("current_district_def"):
		return null
	return run.call("current_district_def") as Object


func _district_text(key: String, fallback: String) -> String:
	var d := _district()
	var v: Variant = d.get(key) if d != null else null
	return v if v is String and v != "" else fallback


# ---------------------------------------------------------------------- refresh
func _refresh(delta: float) -> void:
	var d := _director if _director != null and is_instance_valid(_director) else null
	_refresh_wallet(d)
	_refresh_colony()
	_refresh_top(d)
	_refresh_abilities(delta)
	_refresh_boss()
	_refresh_toasts(delta)


func _refresh_wallet(d: RoundDirector) -> void:
	var run := _run()
	var y: Variant = run.get("year") if run != null else null
	_year.text = "Year %d" % y if y is int else "Year " + NONE
	if d == null:
		_pest_label.text = NONE
		_bones_label.text = NONE
		return
	var p := maxi(0, d.pestilence - _overlay.pending("pestilence"))
	var b := maxi(0, d.bones - _overlay.pending("bones"))
	if p != _shown_p:
		if p > _shown_p and _shown_p >= 0:
			UiKit.punch(_pest_label, 0.25)
			UiKit.punch(_pest_icon, 0.3)
		_shown_p = p
	if b != _shown_b:
		if b > _shown_b and _shown_b >= 0:
			UiKit.punch(_bones_label, 0.25)
			UiKit.punch(_bones_icon, 0.3)
		_shown_b = b
	_pest_label.text = str(p)
	_bones_label.text = str(b)


## Adults with the Pup note and the Lead Rat's pips, by property name.
func _refresh_colony() -> void:
	var colony := get_tree().get_first_node_in_group("colony")
	var adults: Variant = colony.get("adult_count") if colony != null else null
	var pups: Variant = colony.get("pup_count") if colony != null else null
	_colony_label.text = str(adults) if adults is int else NONE
	_pups_label.visible = pups is int and pups > 0
	if _pups_label.visible:
		_pups_label.text = "+%d" % pups
	var matured: Variant = colony.get("maturings") if colony != null else null
	if matured is int:
		if _maturings_seen >= 0 and matured > _maturings_seen:
			for i in matured - _maturings_seen:
				toast("pup")
		_maturings_seen = matured
	var rat := _lead if _lead != null and is_instance_valid(_lead) else null
	var left: Variant = rat.get("hits_left") if rat != null else null
	var most: Variant = rat.get("max_hits") if rat != null else null
	_pips.known = left is int
	_pips.left = left if left is int else 0
	_pips.total = most if most is int and most > 0 else 3
	_pips.queue_redraw()


func _refresh_top(d: RoundDirector) -> void:
	_infection.district = _district_text("title", "District")
	_infection.warden = _district_text("exterminator_title", "The Exterminator")
	if d == null:
		_timer.text = NONE
		_infection.known = false
		_vigilance.known = false
		_infection.queue_redraw()
		_vigilance.queue_redraw()
		return
	var secs := int(ceilf(d.time_left))
	_timer.text = "%d:%02d" % [secs / 60, secs % 60]
	if secs != _last_sec:
		if secs <= 10 and secs > 0 and _last_sec > secs and not d.has_ended():
			UiKit.punch(_timer, 0.22, 0.25)
		_last_sec = secs
	_infection.known = true
	_infection.value = d.district_infection()
	_infection.queue_redraw()
	var v: Variant = d.get("vigilance")
	_vigilance.known = v is float or v is int
	if _vigilance.known:
		_vigilance.target = float(v)
	_vigilance.queue_redraw()


## Raid and Hide slots from the Colony (group "colony"), by property name.
func _refresh_abilities(_delta: float) -> void:
	var colony := get_tree().get_first_node_in_group("colony")
	var raid_on: Variant = colony.get("raid_unlocked") if colony != null else null
	var hide_on: Variant = colony.get("hide_unlocked") if colony != null else null
	var hidden_v: Variant = colony.get("is_hidden") if colony != null else null
	var hidden: bool = hidden_v is bool and hidden_v
	var over := _round_over()
	_raid_box.visible = raid_on is bool and raid_on
	_hide_box.visible = hide_on is bool and hide_on
	_ability_bar.visible = (_raid_box.visible or _hide_box.visible) and not over
	if _raid_box.visible:
		var cd := _num(colony.get("raid_cooldown_left"))
		var total := maxf(0.01, _num(colony.get("raid_cooldown"), 10.0))
		var inside: Variant = colony.get("raiders_inside")
		var followers := 1
		if colony.has_method("raid_followers_available"):
			followers = int(colony.call("raid_followers_available"))
		_raid_slot.frac = clampf(cd / total, 0.0, 1.0)
		_raid_slot.count = str(ceili(cd)) if cd > 0.0 else ""
		_raid_slot.dim = hidden or (cd <= 0.0 and followers <= 0)
		_raid_slot.badge = str(inside) if inside is int and inside > 0 else ""
		if _raid_cd_prev > 0.0 and cd <= 0.0 and not over:
			_raid_slot.pulse()
			toast("raid")
		_raid_cd_prev = cd
		_raid_slot.queue_redraw()
	if _hide_box.visible:
		var cd := _num(colony.get("hide_cooldown_left"))
		if hidden:
			var left := _num(colony.get("hidden_time_left"))
			var full := maxf(0.01, _num(colony.get("hide_duration"), 6.0))
			_hide_slot.frac = clampf(left / full, 0.0, 1.0)
			_hide_slot.count = str(ceili(left))
			_hide_slot.active = true
			_hide_slot.dim = false
		else:
			var total := maxf(0.01, _num(colony.get("hide_cooldown"), 3.0))
			_hide_slot.frac = clampf(cd / total, 0.0, 1.0)
			_hide_slot.count = str(ceili(cd)) if cd > 0.0 else ""
			_hide_slot.active = false
			_hide_slot.dim = false
			if _hide_cd_prev > 0.0 and cd <= 0.0 and not over:
				_hide_slot.pulse()
		_hide_cd_prev = cd if not hidden else 1.0
		_hide_slot.queue_redraw()
	_refresh_hint(hide_on is bool and hide_on, hidden)


func _num(v: Variant, fallback := 0.0) -> float:
	return float(v) if (v is float or v is int) else fallback


## One-time hint: Hide unlocked and the Lead Rat standing near a door.
func _refresh_hint(hide_on: bool, hidden: bool) -> void:
	var delta := get_process_delta_time()
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0 or hidden or _round_over():
			_hint_left = 0.0
	elif not _hint_done and hide_on and not hidden and _lead_near_door():
		_hint_done = true
		_hint_left = HINT_TIME
	_hint_panel.visible = _hint_left > 0.0


func _lead_near_door() -> bool:
	var rat := _lead as Node3D if _lead != null and is_instance_valid(_lead) else null
	if rat == null:
		return false
	var p := rat.global_position
	for h: Node in get_tree().get_nodes_in_group("houses"):
		var door: Variant = h.get("door_position")
		if door is Vector3 and Vector2(door.x - p.x, door.z - p.z).length() <= HINT_RANGE:
			return true
	return false


## Finds a new Exterminator (banner once each) and keeps its bar up to date;
## hides the bar while there is none or once it is beaten.
func _refresh_boss() -> void:
	for n: Node in get_tree().get_nodes_in_group("exterminator"):
		var id := n.get_instance_id()
		if not _bosses_seen.has(id) and n is Node3D:
			_bosses_seen[id] = true
			_boss = n as Node3D
			show_banner("%s has come" % boss_title(_boss), "Swarm with your Colony to overwhelm their Cleanse!")
	if not _bosses_seen.is_empty() and not _tick_faded:
		_tick_faded = true
		var tw := create_tween()
		tw.tween_property(_infection, "tick_alpha", 0.0, 0.8)
	var b := _boss if _boss != null and is_instance_valid(_boss) else null
	var gone: bool = b == null or b.get("is_beaten") == true or _round_over()
	var inf: Node = b.get_node_or_null("Infection") if b != null else null
	_boss_box.visible = not gone and inf != null
	if not _boss_box.visible:
		return
	var val := _num(inf.get("value"))
	var cleanse := _num(inf.get("cleanse_rate"))
	var net := float(inf.call("net_rate")) if inf.has_method("net_rate") else (0.0 - cleanse)
	var pressure := float(inf.call("cleanse_pressure")) if inf.has_method("cleanse_pressure") else 0.0
	var overwhelmed := bool(inf.call("is_overwhelmed")) if inf.has_method("is_overwhelmed") else false
	_boss_title.text = "%s  ·  %d%%" % [boss_title(b), roundi(val)]
	_boss_bar.value = val
	_boss_bar.cleanse = cleanse
	_boss_bar.net_rate = net
	_boss_bar.pressure = pressure
	_boss_bar.overwhelmed = overwhelmed
	_boss_bar.queue_redraw()
	if overwhelmed:
		_boss_hint.text = "▲ +%.1f%%/s  —  Cleanse Broken! Keep swarming!" % maxf(net, 0.1)
		_boss_hint.label_settings.font_color = UiKit.RED_DARK
	else:
		_boss_hint.text = "▼ Cleansing (-%.1f%%/s)  ·  Swarm Pressure %d%% — bring more rats!" % [cleanse, roundi(pressure * 100.0)]
		_boss_hint.label_settings.font_color = Color(0.12, 0.28, 0.15)


## An Exterminator's `title`, or "The Exterminator".
static func boss_title(b: Node) -> String:
	var t: Variant = b.get("title") if b != null and is_instance_valid(b) else null
	return t if t is String and t != "" else "The Exterminator"


static func vigilance_word(v: float) -> String:
	return RoundDirector.tier_name(RoundDirector.tier_of(v))


## "<next District> lies open" (see ResultsPanel.next_district_note()).
func next_district_note() -> String:
	var run := _run()
	var cur: Variant = run.get("current_district") if run != null else null
	return ResultsPanel.next_district_note(run, cur if cur is String else "")


# ---------------------------------------------------------------------- events
func _on_tier_changed(tier: int) -> void:
	UiKit.punch(_vigilance, 0.12, 0.3)
	toast("vigilance", TIER_NEWS[clampi(tier, 0, TIER_NEWS.size() - 1)])


func _on_lead_hurt(_hits_left: int) -> void:
	_overlay.flash_hit()
	UiKit.punch(_pips, 0.4, 0.3)
	GameFeel.shake_camera(get_tree(), HIT_SHAKE)
	GameFeel.hitstop(get_tree(), HITSTOP_TIME, HITSTOP_SCALE, 2)


func _hitstop() -> void:
	GameFeel.hitstop(get_tree(), HITSTOP_TIME, HITSTOP_SCALE, 2)


func _on_round_ended(reason: String) -> void:
	_refresh(0.0)
	_overlay.land_all()
	if _pause.is_open():
		_pause.close()
	_hint_panel.visible = false
	_ability_bar.visible = false
	var d := _director
	var run := _run()
	var y: Variant = run.get("year") if run != null else null
	var cur: Variant = run.get("current_district") if run != null else null
	var did: String = cur if cur is String else "slums"
	var title := "The bells toll"
	if reason == "lead_rat_died":
		title = "The Lead Rat is dead"
	elif reason == "exterminator_beaten":
		var b: Node = _boss if _boss != null and is_instance_valid(_boss) else get_tree().get_first_node_in_group("exterminator")
		title = "%s has fallen" % (boss_title(b) if b != null else _district_text("exterminator_title", "The Exterminator"))
	var info := {
		"title": title,
		"district_id": did,
		"district_title": _district_text("title", NONE),
		"year": y if y is int else null,
		"next_note": ResultsPanel.next_district_note(run, did) if reason == "exterminator_beaten" else "",
	}
	_results.open(d.result, info)


## Shows a toast on the right edge; a repeat of a visible `kind` merges into it.
func toast(kind: String, text := "") -> void:
	var spec: Array = TOASTS.get(kind, ["skull", kind, kind])
	for t in _toasts:
		if t["kind"] == kind and t["age"] < TOAST_IN + TOAST_SHOW:
			t["count"] += 1
			_toast_text(t, text)
			t["age"] = TOAST_IN
			UiKit.punch(t["panel"], 0.08)
			return
	if _toasts.size() >= TOAST_MAX:
		var drop := -1
		for i in _toasts.size():
			if _toasts[i]["kind"] == "pup":
				drop = i
				break
		if drop < 0:
			if kind == "pup":
				return  # low priority: never pushes others out
			drop = 0
		(_toasts[drop]["panel"] as Control).queue_free()
		_toasts.remove_at(drop)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_FILL, 2, 8, 3))
	panel.custom_minimum_size = Vector2(TOAST_WIDTH, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	row.add_child(IconRect.make(spec[0], 22))
	var label := UiKit.label("", UiKit.SIZE_BODY)
	row.add_child(label)
	_toast_layer.add_child(panel)
	var t := {"kind": kind, "count": 1, "age": 0.0, "panel": panel, "label": label, "y": -1.0}
	_toast_text(t, text)
	_toasts.append(t)


func _toast_text(t: Dictionary, text: String) -> void:
	var spec: Array = TOASTS.get(t["kind"], ["skull", t["kind"], t["kind"]])
	var s := text
	if s == "":
		s = spec[1] if int(t["count"]) <= 1 else (spec[2] % int(t["count"]) if "%d" in spec[2] else spec[2])
	(t["label"] as Label).text = s


func _refresh_toasts(delta: float) -> void:
	var y := TOAST_TOP
	var w := _toast_layer.size.x
	var calm := UiKit.reduce_motion()
	var i := 0
	while i < _toasts.size():
		var t: Dictionary = _toasts[i]
		t["age"] += delta
		var age: float = t["age"]
		var panel: Control = t["panel"]
		if age >= TOAST_IN + TOAST_SHOW + TOAST_OUT:
			panel.queue_free()
			_toasts.remove_at(i)
			continue
		var slide := clampf(age / TOAST_IN, 0.0, 1.0)
		var fade_in := 1.0
		if calm:
			fade_in = slide   # reduced motion: fade in instead of sliding
			slide = 1.0
		slide = 1.0 - pow(1.0 - slide, 3.0)
		var pw := maxf(panel.size.x, TOAST_WIDTH)
		var x := w - MARGIN - pw + (1.0 - slide) * (pw + MARGIN)
		var ty: float = t["y"]
		ty = y if ty < 0.0 else lerpf(ty, y, 1.0 - exp(-14.0 * delta))
		t["y"] = ty
		panel.position = Vector2(x, ty)
		panel.modulate.a = fade_in * (1.0 - clampf((age - TOAST_IN - TOAST_SHOW) / TOAST_OUT, 0.0, 1.0))
		y += panel.size.y + 8.0
		i += 1


## Fades `text` in at the centre of the screen, holds it, and fades it out.
func show_banner(text: String, subtitle := "") -> void:
	_banner_label.text = text
	_banner_sub.text = subtitle
	_banner_sub.visible = not subtitle.is_empty()
	_banner.visible = true
	_banner.modulate.a = 0.0
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, BANNER_TIMES.x)
	_banner_tween.tween_interval(BANNER_TIMES.y)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, BANNER_TIMES.z)
	_banner_tween.tween_callback(_banner.hide)


## The Risk of Rain stage card: District, Year and (early on) the objective.
func _show_title_card() -> void:
	var run := _run()
	var y: Variant = run.get("year") if run != null else null
	var rounds: Variant = run.get("rounds_played") if run != null else null
	var warden := _district_text("exterminator_title", "the Exterminator")
	if warden.begins_with("The "):
		warden = "the " + warden.substr(4)
	(_card_box.get_child(0) as Label).text = _district_text("title", "The District")
	(_card_box.get_child(1) as Label).text = "Year of Our Lord %s" % (str(y) if y is int else NONE)
	var obj := _card_box.get_child(2) as Label
	obj.text = "Spread the plague. Reach %d%% to draw out %s." % [roundi(Spawner.EXTERMINATOR_AT * 100.0), warden]
	obj.visible = not (rounds is int) or rounds < OBJECTIVE_ROUNDS
	_card.visible = true
	_card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, CARD_TIMES.x)
	tw.tween_interval(CARD_TIMES.y)
	tw.tween_property(_card, "modulate:a", 0.0, CARD_TIMES.z)
	tw.tween_callback(_card.hide)


## The panel root covers the screen at 1 / hud_scale and is scaled back up.
func _apply_scale() -> void:
	var s := UiKit.settings()
	var k := clampf(float(s.get("hud_scale")) if s != null else 1.0, 0.5, 2.0)
	var vp := get_viewport().get_visible_rect().size
	_root.scale = Vector2.ONE * k
	_root.position = Vector2.ZERO
	_root.size = vp / k


# ---------------------------------------------------------------------- debug
func _parse_debug_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--results-test="):
			_debug_results(arg.trim_prefix("--results-test="))
		elif arg == "--pause-test":
			_debug_pause()
		elif arg == "--toast-test":
			_debug_toasts()


func _debug_results(reason: String) -> void:
	await get_tree().create_timer(6.0, false).timeout
	if _director == null or not is_instance_valid(_director):
		return
	if _director.has_method("debug_end"):
		_director.debug_end(reason)
	else:
		_director.end_round(reason)


func _debug_pause() -> void:
	await get_tree().create_timer(2.0, false).timeout
	open_pause()


func _debug_toasts() -> void:
	await get_tree().create_timer(1.0, false).timeout
	toast("pup")
	toast("vigilance", TIER_NEWS[1])
	toast("house")
	toast("house")
	toast("house")
	toast("raid")
	_raid_slot.pulse()
	_hide_slot.pulse()


# ---------------------------------------------------------------------- building
func _build() -> void:
	_overlay = WorldOverlay.new()
	_overlay.name = "WorldOverlay"
	add_child(_overlay)
	_overlay.target_for = _wallet_target

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_top()
	_build_wallet()
	_build_abilities()

	_toast_layer = Control.new()
	_toast_layer.name = "Toasts"
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_toast_layer)

	# Bottom centre, above the ability bar: the one-time door hint.
	_hint_panel = PanelContainer.new()
	_hint_panel.name = "DoorHint"
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_FILL, 2, 10, 3))
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	_hint_panel.add_child(hrow)
	hrow.add_child(IconRect.make("door", 22))
	hrow.add_child(UiKit.label("Press [%s] at a door to Hide" % UiKit.prompt("hide"), UiKit.SIZE_BODY))
	_root.add_child(_hint_panel)
	_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_panel.offset_top -= 120.0
	_hint_panel.offset_bottom -= 120.0
	_hint_panel.visible = false

	# Centre: the Exterminator's arrival banner, cleanly below the top boss bar.
	_banner = PanelContainer.new()
	_banner.name = "BossBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel", UiKit.panel_box(Color(UiKit.PARCHMENT, 0.96), 3, 18, 4))
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 4)
	_banner.add_child(bcol)
	_banner_label = UiKit.label("", UiKit.SIZE_TITLE, UiKit.INK, 0, true)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bcol.add_child(_banner_label)
	_banner_sub = UiKit.label("", UiKit.SIZE_BODY, UiKit.RED_DARK, 0, false)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.visible = false
	bcol.add_child(_banner_sub)
	_root.add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.offset_top += 10.0
	_banner.offset_bottom += 10.0
	_banner.visible = false

	# Centre: the Round title card.
	_card = PanelContainer.new()
	_card.name = "TitleCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wash := StyleBoxFlat.new()
	wash.bg_color = Color(UiKit.PARCHMENT_LIGHT, 0.55)
	wash.set_corner_radius_all(18)
	wash.content_margin_left = 36
	wash.content_margin_right = 36
	wash.content_margin_top = 6
	wash.content_margin_bottom = 12
	_card.add_theme_stylebox_override("panel", wash)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 2)
	_card.add_child(_card_box)
	for spec: Array in [[UiKit.SIZE_HUGE, true], [UiKit.SIZE_LARGE, false], [UiKit.SIZE_BODY, false]]:
		var l := UiKit.label("", spec[0], UiKit.INK, 6, spec[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_card_box.add_child(l)
	_root.add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.offset_top -= 110.0
	_card.offset_bottom -= 110.0
	_card.visible = false

	# Full screen, unscaled: the pause menu and the results screen.
	_results = ResultsPanel.new()
	_results.name = "Results"
	add_child(_results)
	_pause = PauseMenu.new()
	_pause.name = "PauseMenu"
	add_child(_pause)


func _wallet_target(kind: String) -> Vector2:
	var icon: Control = _pest_icon if kind == "pestilence" else _bones_icon
	if icon == null or not icon.is_inside_tree():
		return Vector2.INF
	return icon.get_global_rect().get_center()


func _build_top() -> void:
	var top := VBoxContainer.new()
	_top = top
	top.name = "Top"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 2)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	_root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(MARGIN) - 8)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_infection = _InfectionBar.new()
	_infection.name = "InfectionBar"
	_infection.custom_minimum_size = Vector2(INFECTION_BAR_WIDTH, 42)
	_infection.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(_infection)
	_timer = UiKit.label(NONE, UiKit.SIZE_TITLE, UiKit.INK, 6)
	_timer.name = "Timer"
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_timer.custom_minimum_size.x = 110
	top.add_child(_timer)
	_vigilance = _VigilanceStrip.new()
	_vigilance.name = "Vigilance"
	_vigilance.custom_minimum_size = Vector2(VIGILANCE_WIDTH, 32)
	_vigilance.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(_vigilance)
	_boss_box = VBoxContainer.new()
	_boss_box.name = "Boss"
	_boss_box.add_theme_constant_override("separation", 0)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_boss_box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_boss_box.add_child(gap)
	_boss_title = UiKit.label("", UiKit.SIZE_LARGE, UiKit.INK, 5, true)
	_boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_title)
	_boss_bar = _BossBar.new()
	_boss_bar.name = "BossBar"
	_boss_bar.custom_minimum_size = Vector2(BOSS_BAR_WIDTH, 28)
	_boss_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_boss_box.add_child(_boss_bar)
	var hint_pill := PanelContainer.new()
	hint_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var hpb := UiKit.panel_box(Color(UiKit.PANEL_FILL, 0.88), 1, 4, 2)
	hpb.content_margin_left = 10
	hpb.content_margin_right = 10
	hpb.content_margin_top = 2
	hpb.content_margin_bottom = 3
	hint_pill.add_theme_stylebox_override("panel", hpb)
	_boss_hint = UiKit.label("", UiKit.SIZE_SMALL, Color(0.12, 0.28, 0.15), 0)
	_boss_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_pill.add_child(_boss_hint)
	_boss_box.add_child(hint_pill)
	_boss_box.visible = false


func _build_wallet() -> void:
	var panel := PanelContainer.new()
	panel.name = "Wallet"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pb := UiKit.panel_box(Color(UiKit.PANEL_FILL, 0.78), 2, 8, 3)
	pb.content_margin_left = 12
	pb.content_margin_right = 14
	panel.add_theme_stylebox_override("panel", pb)
	_root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var r1 := _row(box, 8)
	_pest_icon = IconRect.make("pestilence", 28)
	r1.add_child(_pest_icon)
	_pest_label = UiKit.label(NONE, UiKit.SIZE_LARGE + 4, UiKit.INK, 5)
	_pest_label.custom_minimum_size.x = 60
	r1.add_child(_pest_label)
	var r2 := _row(box, 8)
	_bones_icon = IconRect.make("bones", 28)
	r2.add_child(_bones_icon)
	_bones_label = UiKit.label(NONE, UiKit.SIZE_LARGE + 4, UiKit.INK, 5)
	_bones_label.custom_minimum_size.x = 60
	r2.add_child(_bones_label)
	var r3 := _row(box, 8)
	r3.add_child(IconRect.make("rat", 28))
	_colony_label = UiKit.label(NONE, UiKit.SIZE_LARGE, UiKit.INK, 5)
	r3.add_child(_colony_label)
	_pups_label = UiKit.label("", UiKit.SIZE_BODY, UiKit.SEPIA, 5)
	_pups_label.tooltip_text = "Pups"
	r3.add_child(_pups_label)
	var pup_icon := IconRect.make("pup", 18, UiKit.SEPIA)
	r3.add_child(pup_icon)
	_pups_label.visibility_changed.connect(func() -> void: pup_icon.visible = _pups_label.visible)
	var r4 := _row(box, 8)
	r4.add_child(UiKit.label("Lead Rat", UiKit.SIZE_SMALL, UiKit.INK, 4))
	_pips = _Pips.new()
	_pips.custom_minimum_size = Vector2(60, 20)
	r4.add_child(_pips)
	var r5 := _row(box, 6)
	r5.add_child(IconRect.make("hourglass", 16))
	_year = UiKit.label(NONE, UiKit.SIZE_SMALL, UiKit.INK, 4)
	r5.add_child(_year)


func _row(parent: Control, sep: int) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_constant_override("separation", sep)
	parent.add_child(r)
	return r


func _build_abilities() -> void:
	_ability_bar = HBoxContainer.new()
	_ability_bar.name = "Abilities"
	_ability_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_bar.add_theme_constant_override("separation", 22)
	_root.add_child(_ability_bar)
	_ability_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_ability_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ability_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_raid_box = _slot_box("raid")
	_raid_slot = _raid_box.get_child(0) as _AbilitySlot
	_raid_box.add_child(PromptHint.make("raid", "Raid", UiKit.SIZE_SMALL, 4))
	_hide_box = _slot_box("door")
	_hide_slot = _hide_box.get_child(0) as _AbilitySlot
	_hide_box.add_child(PromptHint.make("hide", "Hide", UiKit.SIZE_SMALL, 4))
	_ability_bar.visible = false


func _slot_box(icon: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_ability_bar.add_child(box)
	var slot := _AbilitySlot.new()
	slot.icon = icon
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(slot)
	box.visible = false
	return box


# ---------------------------------------------------------------------- widgets
## The wide District Infection bar with the Exterminator tick.
class _InfectionBar extends Control:
	var value := 0.0          # 0..1
	var known := false
	var district := ""
	var warden := ""
	var tick_at := Spawner.EXTERMINATOR_AT
	var tick_alpha := 1.0:
		set(v):
			tick_alpha = v
			queue_redraw()

	func _draw() -> void:
		var f := UiKit.body_font()
		var r := Rect2(0, 18, size.x, size.y - 18)
		draw_rect(r, Color(UiKit.PARCHMENT_LIGHT, 0.85))
		if known:
			draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(value, 0.0, 1.0), r.size.y)), UiKit.RED)
		draw_rect(r, UiKit.INK, false, 2.0)
		if tick_alpha > 0.01:
			var x := r.position.x + r.size.x * tick_at
			var ink := Color(UiKit.INK, tick_alpha)
			draw_line(Vector2(x, r.position.y - 4), Vector2(x, r.end.y + 4), ink, 2.0)
			UiIcons.draw(self, "skull", Vector2(x, 8), 14, ink)
			var fs := UiKit.SIZE_SMALL
			var at := Vector2(x + 10, 13)
			draw_string_outline(f, at, warden, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(UiKit.OUTLINE, UiKit.OUTLINE.a * tick_alpha))
			draw_string(f, at, warden, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		var text := "%s  ·  %s" % [district, ("%d%%" % roundi(value * 100.0)) if known else "—"]
		var fs2 := UiKit.SIZE_BODY
		var base := Vector2(r.position.x + 10, r.position.y + r.size.y * 0.5 + fs2 * 0.36)
		draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 5, UiKit.OUTLINE)
		draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UiKit.INK)


## Risk of Rain difficulty strip: four named tiers, the current one inked solid,
## and a marker sliding along under it.
class _VigilanceStrip extends Control:
	var target := 0.0
	var known := false
	var _shown := -1.0

	func _process(delta: float) -> void:
		if known:
			_shown = target if _shown < 0.0 else lerpf(_shown, target, 1.0 - exp(-4.0 * delta))

	func _draw() -> void:
		var f := UiKit.body_font()
		var tiers := RoundDirector.VIGILANCE_TIERS
		var n := tiers.size()
		var h := 22.0
		var seg := size.x / float(n)
		var cur := RoundDirector.tier_of(maxf(_shown, 0.0)) if known else -1
		draw_rect(Rect2(0, 0, size.x, h), Color(UiKit.PARCHMENT_LIGHT, 0.85))
		for i in n:
			var r := Rect2(seg * i, 0, seg, h)
			var col := UiKit.INK_FADED
			if i == cur:
				draw_rect(r, UiKit.INK)
				col = UiKit.PARCHMENT_LIGHT
			elif i < cur:
				col = UiKit.INK
			var word := str(tiers[i][1])
			var fs := UiKit.SIZE_SMALL
			var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(r.get_center().x - w * 0.5, h * 0.5 + fs * 0.36), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			if i > 0:
				draw_line(Vector2(seg * i, 0), Vector2(seg * i, h), UiKit.INK, 1.0)
		draw_rect(Rect2(0, 0, size.x, h), UiKit.INK, false, 2.0)
		if cur < 0:
			return
		var lo := 0.0 if cur == 0 else float(tiers[cur - 1][0])
		var hi := float(tiers[cur][0])
		if is_inf(hi):
			hi = lo + 1.0
		var x := seg * (float(cur) + clampf((_shown - lo) / (hi - lo), 0.0, 1.0))
		var tri := PackedVector2Array([Vector2(x, h - 1), Vector2(x - 6, h + 9), Vector2(x + 6, h + 9)])
		draw_colored_polygon(tri, UiKit.INK)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), UiKit.OUTLINE, 1.0, true)


## The Exterminator's Infection bar + Cleanse Overwhelm pressure gauge beneath.
class _BossBar extends Control:
	var value := 0.0        # 0..100
	var cleanse := 0.0      # %/s
	var net_rate := 0.0     # %/s (positive = winning, negative = Cleansing)
	var pressure := 0.0     # 0..1 (Swarm Bite rate / Cleanse rate)
	var overwhelmed := false

	func _draw() -> void:
		var main_h := size.y * 0.66
		var r := Rect2(0, 0, size.x, main_h)
		draw_rect(r, Color(UiKit.PARCHMENT_LIGHT, 0.88))
		var w := r.size.x * clampf(value / 100.0, 0.0, 1.0)
		draw_rect(Rect2(r.position, Vector2(w, r.size.y)), UiKit.RED)
		if cleanse > 0.0 and value > 0.0 and not overwhelmed:
			var lo := clampf(value - cleanse * CLEANSE_SHOWN, 0.0, 100.0)
			var x0 := r.size.x * lo / 100.0
			draw_rect(Rect2(x0, 0, maxf(3.0, w - x0), r.size.y), Color(UiKit.SAGE, 0.55))
		draw_rect(r, UiKit.RED if overwhelmed else UiKit.INK, false, 2.5 if overwhelmed else 2.0)
		# Lower strip: Cleanse Pressure tug-of-war meter (fills sage -> amber -> crimson when broken).
		var pr := Rect2(0, main_h + 2.0, size.x, size.y - main_h - 2.0)
		draw_rect(pr, Color(UiKit.PARCHMENT_DARK, 0.8))
		var pw := pr.size.x * clampf(pressure, 0.0, 1.0)
		var pcol := UiKit.RED if overwhelmed else UiKit.SAGE.lerp(UiKit.AMBER, clampf(pressure, 0.0, 1.0))
		draw_rect(Rect2(pr.position, Vector2(pw, pr.size.y)), pcol)
		draw_rect(pr, UiKit.INK, false, 1.2)


## The Lead Rat's hits left as ink pips.
class _Pips extends Control:
	var left := 0
	var total := 3
	var known := false

	func _draw() -> void:
		var r := 7.0
		for i in total:
			var c := Vector2(r + 2 + i * (r * 2 + 6), size.y * 0.5)
			draw_circle(c, r + 1.5, Color(UiKit.OUTLINE, 0.9))
			if known and i < left:
				draw_circle(c, r, UiKit.INK)
			else:
				draw_arc(c, r - 1, 0, TAU, 20, UiKit.INK_FADED if not known else UiKit.INK, 2.0, true)


## One ability slot: parchment square, icon, radial ink cooldown sweep,
## countdown, an optional badge and a one-time amber ring when ready.
class _AbilitySlot extends Control:
	const PULSE_TIME := 0.5
	var icon := "raid"
	var frac := 0.0
	var count := ""
	var dim := false
	var active := false
	var badge := ""
	var _pulse := 0.0

	func pulse() -> void:
		_pulse = PULSE_TIME
		UiKit.punch(self, 0.12)

	func _process(delta: float) -> void:
		if _pulse > 0.0:
			_pulse = maxf(0.0, _pulse - delta)
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var c := r.get_center()
		draw_rect(r, UiKit.PARCHMENT_DARK if active else UiKit.PARCHMENT_LIGHT)
		UiIcons.draw(self, icon, c, size.x * 0.6, Color(UiKit.INK, 0.4 if dim else 1.0))
		if frac > 0.0:
			var pts := PackedVector2Array([c])
			var steps := 48
			var half := size.x * 0.5
			for i in steps + 1:
				var a := -PI * 0.5 + TAU * frac * float(i) / float(steps)
				var d := Vector2(cos(a), sin(a))
				pts.append(c + d * (half / maxf(absf(d.x), absf(d.y))))
			if pts.size() >= 3:
				draw_colored_polygon(pts, Color(UiKit.INK, 0.5))
		draw_rect(r, UiKit.INK, false, 3.0 if active else 2.0)
		var f := UiKit.body_font()
		if count != "":
			var fs := UiKit.SIZE_LARGE
			var w := f.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := c + Vector2(-w * 0.5, fs * 0.36)
			draw_string_outline(f, at, count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, UiKit.OUTLINE)
			draw_string(f, at, count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK)
		if badge != "":
			var bc := Vector2(size.x - 2, 2)
			draw_circle(bc, 10, UiKit.INK)
			var fs3 := UiKit.SIZE_SMALL
			var bw := f.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3).x
			draw_string(f, bc + Vector2(-bw * 0.5, fs3 * 0.36), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3, UiKit.PARCHMENT_LIGHT)
		if _pulse > 0.0:
			var k := 1.0 - _pulse / PULSE_TIME
			var grow := 2.0 + (0.0 if UiKit.reduce_motion() else 10.0 * k)
			draw_rect(r.grow(grow), Color(UiKit.AMBER, 1.0 - k), false, 3.0)
