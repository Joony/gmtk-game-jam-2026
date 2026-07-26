class_name ComputerTerminal
extends Interactable

# The nav console, in the spirit of GMTK 2025's computer: a Control rendered into a
# SubViewport and mapped onto a quad, so it is a real screen in the room rather than a
# texture of one.
#
# TWO PAGES, and which one is up is normally not the player's decision:
#
#   NAV PLOT      where the ship is, how long is left. NavChart.
#   DAMAGE PLAN   where the problems are. StatusMap — see TODO 19.
#
# THE SCREEN SHOWS THE DAMAGE PLAN WHENEVER ANYTHING IS WRONG, and the nav plot when nothing
# is. That is the whole of the page logic, and it is the reason there is no menu: walk past the
# console with a fault running and the damage is already on it. A screen in a corridor that
# needed operating would not be doing a screen's job.
#
# The player can override it with left/right while reading, and that choice is dropped the
# moment they step away (see clear_manual_page) — otherwise a glance at the nav plot would
# silently switch the console off for the rest of the run.
#
# The chart is pushed data on a timer rather than every frame. Nothing on it moves fast —
# the ship crosses a pixel every few seconds — and redrawing a few hundred jittered line
# segments at 60Hz to show a number that has not changed would be silly. BOTH pages are pushed
# on that timer even though only one is visible: it costs a dictionary or two per quarter
# second, and it means the hidden page can never be stale at the instant it is shown.

## Emitted when the player asks for the full-screen chart.
signal opened
## Emitted when the visible page changes, so the reading prompt can name the other one.
signal page_changed(page: int)

enum Page { NAV, STATUS }

## Seconds between chart updates. Fast enough to feel live while asleep at 24x.
@export var refresh_interval: float = 0.25
@export var chart_path: NodePath = NodePath("SubViewport/NavChart")
@export var map_path: NodePath = NodePath("SubViewport/StatusMap")
@export var view_path: NodePath = NodePath("ViewPoint")

## Pulse rate floor for a fault that has only just broken. A bleeding fault reports how far it
## has got toward its own ceiling, which is 0 the instant it fires — and the newest problem on
## the ship being the calmest thing on the map is the wrong first impression.
const FRESH_CRITICAL := 0.35
## Fixed urgency for faults with no bleed to measure. A critical one is worth hurrying for; a
## degrading one is a toll you can choose to keep paying.
const CRITICAL_URGENCY := 0.85
const DEGRADING_URGENCY := 0.45
## Floor for a need that can kill you. CO2 narcosis and the septic tank do not pulse gently.
const LETHAL_FLOOR := 0.6

var page: Page = Page.NAV

var _chart: NavChart
var _map: StatusMap
var _run: RunState = null
var _ship: RoomBuilder = null
var _player: Node3D = null
var _since_refresh: float = 0.0
## Set when the player picks a page for themselves, cleared when they step away from the
## console. While it is set, the automatic choice above is suspended.
var _manual: bool = false


func _ready() -> void:
	super()
	interaction_type = InteractionType.ACTIVATE
	interaction_text = "Read the nav plot"
	_chart = get_node_or_null(chart_path) as NavChart
	_map = get_node_or_null(map_path) as StatusMap
	_apply_page()


## `ship` and `player` are what the damage plan needs and the nav plot does not: which room a
## fault is in, and which room the player is in. Optional, and without them the console is
## simply the nav plot it has always been — a terminal that has not been told about the ship
## should show the page it can actually fill in.
func bind(run: RunState, ship: RoomBuilder = null, player: Node3D = null) -> void:
	_run = run
	_ship = ship
	_player = player
	if _map != null and _ship != null:
		_map.set_plan(ShipPlan.from_builder(_ship))
	_refresh()


func get_interaction_text(_held_item: Node3D = null) -> String:
	# Names the page that is actually up, so the prompt is never an invitation to read something
	# the screen is not showing.
	return "Read the %s" % page_name().to_lower()


# Usable with your hands full: reading a screen does not require putting the spare down,
# and making the player drop it first would be pure friction.
func can_act_on(_held_item: Node3D = null) -> bool:
	return is_enabled


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < refresh_interval:
		return
	_since_refresh = 0.0
	_refresh()


func _refresh() -> void:
	if _run == null:
		return
	var problems := collect_problems()
	if not _manual:
		# The automatic choice. Note it reads `problems`, not "is any fault active" — a tank
		# about to run dry is a reason to put the plan up too.
		_set_page(Page.STATUS if not problems.is_empty() else Page.NAV)
	push_to(_chart)
	push_status_to(_map, problems)


# --- pages ------------------------------------------------------------------

## Choose a page. `by_player` marks the choice as a manual override that survives until they
## step away from the console.
func set_page(to: Page, by_player: bool = true) -> void:
	if by_player:
		_manual = true
	_set_page(to)


func flip_page() -> void:
	set_page(Page.NAV if page == Page.STATUS else Page.STATUS, true)


## Hand the console back to its own judgement. Called when the player stops reading.
func clear_manual_page() -> void:
	if not _manual:
		return
	_manual = false
	_refresh()


func is_page_manual() -> bool:
	return _manual


func page_name() -> String:
	return "DAMAGE PLAN" if page == Page.STATUS else "NAV PLOT"


## What flipping would get you. The reading prompt says this rather than "FLIP", so the player
## knows what the other page is before spending the keypress on finding out.
func other_page_name() -> String:
	return "NAV PLOT" if page == Page.STATUS else "DAMAGE PLAN"


func _set_page(to: Page) -> void:
	if page == to:
		return
	page = to
	_apply_page()
	page_changed.emit(int(page))


func _apply_page() -> void:
	if _chart != null:
		_chart.visible = page == Page.NAV
	if _map != null:
		_map.visible = page == Page.STATUS


# --- what is wrong, and where -----------------------------------------------

## Every problem worth a blob, as plain dictionaries. StatusMap knows nothing about RunState and
## this is the seam: faults, tanks and body clocks all arrive as {room, kind, urgency, label}.
##
## A problem whose room cannot be resolved is DROPPED rather than guessed at. `room_at()` returns
## "" for a doorway gap or a spot outside the hull, and a blob placed on the nearest room instead
## would be the map telling a confident lie about where to walk.
func collect_problems() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _run == null or _ship == null:
		return out

	for fault in _run.active_malfunctions():
		var fault_room := _room_of(fault)
		if fault_room == "":
			continue
		out.append({
			"room": fault_room,
			"kind": StatusMap.Kind.FAULT,
			"urgency": fault_urgency(fault),
			"label": fault.system_name,
		})

	# WARNINGS ARE DEDUPED BY SILO, and that is the one piece of real logic in here. A pressing
	# CO2 clock and a life-support tank running low are two rows on the HUD but ONE errand: walk
	# to the same tank, with the same canister. Two blobs on one room would say there were two
	# places to go.
	var warnings := {}
	for silo in _run.pressing_silos():
		var silo_room := _room_of(silo)
		if silo_room == "":
			continue
		warnings[silo.get_instance_id()] = {
			"room": silo_room,
			"kind": StatusMap.Kind.WARNING,
			"urgency": silo_urgency(silo),
			"label": silo.display_name,
		}

	for need in _run.pressing_needs():
		# A need has no position of its own — it is a clock attached to the player's body — but
		# it has a DESTINATION, and that is the answer to "where do I go".
		#
		# A need with no silo is skipped, and nothing is lost by it: the only one is the septic
		# countdown, which is started by the crap tank being full — and a full tank is a pressing
		# silo, so the bathroom already has its blob from the loop above.
		var host := _run.silo_by_id(need.silo_id)
		if host == null:
			continue
		var need_room := _room_of(host)
		if need_room == "":
			continue
		var key := host.get_instance_id()
		if warnings.has(key):
			# One blob, pulsing at whichever of the two is more pressing.
			warnings[key]["urgency"] = maxf(float(warnings[key]["urgency"]), need_urgency(need))
		else:
			warnings[key] = {
				"room": need_room,
				"kind": StatusMap.Kind.WARNING,
				"urgency": need_urgency(need),
				"label": need.display_name,
			}

	for key in warnings:
		out.append(warnings[key])
	return out


## How hard a fault's blob breathes, 0..1.
##
## A bleeding critical fault reports HOW FAR IT HAS ALREADY GOT toward its own ceiling — the same
## number the HUD row shows, and the one the player is weighing the walk against. So the drive's
## blob visibly speeds up the longer it is left, which is the fault's whole character rendered
## without a word of text.
static func fault_urgency(fault: Malfunction) -> float:
	if fault.speed_decay_per_day > 0.0 and fault.speed_penalty > 0.0:
		return lerpf(FRESH_CRITICAL, 1.0, clampf(fault.speed_decay / fault.speed_penalty, 0.0, 1.0))
	return CRITICAL_URGENCY if fault.severity == Malfunction.Severity.CRITICAL else DEGRADING_URGENCY


## Empty is 1.0. Between the warning line and empty it ramps, so a tank you have just noticed
## breathes and one that is dry races.
static func silo_urgency(silo: Silo) -> float:
	if silo.is_exhausted() or silo.warn_at <= 0.0:
		return 1.0
	return clampf(1.0 - silo.headroom() / silo.warn_at, 0.0, 1.0)


## Rescaled onto the TAIL of the clock rather than the whole of it: a need only earns a blob once
## it is past `warn_at`, so measuring from full would make every blob appear already half-lit and
## then barely change. Measured from the warning line, it appears calm and races as it runs out.
static func need_urgency(need: Need) -> float:
	var spent := 1.0 - need.fraction()
	if need.warn_at > 0.0:
		spent = clampf((need.warn_at - need.fraction()) / need.warn_at, 0.0, 1.0)
	return maxf(spent, LETHAL_FLOOR) if need.lethal else spent


## Which room a thing is in, "" if it is nowhere the map can draw.
func _room_of(what: Node3D) -> String:
	if _ship == null or what == null:
		return ""
	return _ship.room_at(what.global_position)


# --- pushing to the screens -------------------------------------------------

## Fill in a chart from the run. Used for the console and for the full-screen copy.
func push_to(chart: NavChart) -> void:
	if _run == null or chart == null:
		return
	var total: float = maxf(_run.total_distance, 0.001)
	chart.set_voyage(
		1.0 - _run.distance_remaining / total,
		_run.eta_days(),
		_run.distance_remaining,
		_run.speed_fraction()
	)


## The damage plan's counterpart. Takes the problem list rather than collecting its own, so the
## page logic above and the page itself cannot end up disagreeing about what is wrong.
func push_status_to(map: StatusMap, problems: Array[Dictionary]) -> void:
	if map == null:
		return
	map.set_problems(problems)
	map.set_player_room(_room_of(_player))


## Where the player is placed to read the screen. Falls back to the terminal's own
## transform so a missing marker cannot drop the camera inside the console.
func view_transform() -> Transform3D:
	var marker := get_node_or_null(view_path) as Node3D
	return marker.global_transform if marker != null else global_transform


func interact() -> void:
	if not is_enabled:
		return
	opened.emit()
	interacted_with.emit(self)
