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

## Emitted when the player asks to read this screen. Carries the screen, because there is more
## than one of them on the ship now and Game has to know which one it walked the player up to.
signal opened(terminal: ComputerTerminal)
## Emitted when the visible page changes, so the reading prompt can name the other one.
signal page_changed(page: int)

enum Page { NAV, STATUS }

## WHICH PAGES THIS SCREEN CAN SHOW, and therefore what kind of screen it is.
##
## One page: no flip, no automatic choice, and the prompt names it. Two: the automatic choice and
## the left/right flip described above. So "the nav console in the pod bay" and "the deck plan on
## the bridge" are the same script with a different row here, rather than two classes or a branch.
##
## Godot cannot export a typed array of a local enum, so it is Array[int] holding Page values.
@export var pages: Array[int] = [Page.NAV, Page.STATUS]

## Can the player walk up and read this screen close to? OFF makes it a screen and nothing more:
## no [E] prompt, no reticle, no lean-in — it is simply legible from where you stand, and glancing
## at it costs nothing.
##
## The nav plot is the case for that. It is four numbers and an arc, all of them readable across
## the bridge, and leaning in shows exactly the same four numbers a second later. The deck plan is
## the opposite: it is a chart lying flat on a table, and reading a chart means standing over it.
@export var lean_in: bool = true

## Seconds between chart updates. Fast enough to feel live while asleep at 24x.
@export var refresh_interval: float = 0.25
@export var chart_path: NodePath = NodePath("SubViewport/NavChart")
@export var map_path: NodePath = NodePath("SubViewport/StatusMap")
@export var view_path: NodePath = NodePath("ViewPoint")
## Where the fault light goes if the prop carries no `Indicator` empty, in metres.
@export var indicator_offset: Vector3 = Vector3(0.0, 1.05, 0.2)

## The fault that takes this screen out of service, and the repair logic it borrows. `_repair`
## is a RepairPoint used purely as a HELPER — it owns the hammer-versus-part dispatch and the
## prompt wording, so the computer does not reimplement either. It is not a ray target itself.
var _fault: Malfunction = null
var _repair: RepairPoint = null
var _indicator: IndicatorLight = null

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
## Set by attach(); otherwise resolved from `view_path`.
var _view: Node3D = null
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
	if _chart == null:
		_chart = get_node_or_null(chart_path) as NavChart
	if _map == null:
		_map = get_node_or_null(map_path) as StatusMap
	# `is_enabled` is what Interactor.\_cast() tests, and a screen that fails it is not merely
	# un-actionable — it never becomes the focus at all, so there is no prompt to suppress
	# separately and no half-lit reticle over it.
	if not lean_in:
		is_enabled = false
	if pages.is_empty():
		pages = [Page.NAV]
	if not has_page(page):
		page = first_page()
	_apply_page()


## Wire the pages directly, for a screen ASSEMBLED IN CODE — where a NodePath would have to name
## its way down through an imported model and would break the moment the model changed. The
## exported paths stay for screens that are whole scenes of their own, like the pod bay console.
##
## Call before the node enters the tree, or _ready() will resolve the paths over the top.
func attach(chart: NavChart, map: StatusMap, view: Node3D) -> void:
	_chart = chart
	_map = map
	_view = view


func has_page(which: int) -> bool:
	return pages.has(which)


func first_page() -> Page:
	return pages[0] as Page if not pages.is_empty() else Page.NAV


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


func get_interaction_text(held_item: Node3D = null) -> String:
	if _repair != null and (is_broken() or is_patched()):
		return _repair.get_interaction_text(held_item)
	# Names the page that is actually up, so the prompt is never an invitation to read something
	# the screen is not showing.
	return "Read the %s" % page_name().to_lower()


func get_interaction_type(held_item: Node3D = null) -> InteractionType:
	if not is_enabled:
		return InteractionType.DISABLED
	# USE_ITEM while broken, so Interactor routes the hammer and the spare part here instead of
	# dropping whatever is in your hands.
	if _repair != null and (is_broken() or is_patched()):
		return InteractionType.USE_ITEM
	return super(held_item)


func use_with_item(item: Node3D) -> void:
	if _repair == null or not (is_broken() or is_patched()):
		return
	_repair.use_with_item(item)
	if _repair.consumed_last_item():
		used_with_item.emit(self, item)


func consumed_last_item() -> bool:
	return _repair != null and _repair.consumed_last_item()


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
	# A screen that cannot show the plan has no reason to work out what is wrong with the ship.
	var problems: Array[Dictionary] = []
	if has_page(Page.STATUS):
		problems = collect_problems()
	# The automatic choice, and only a screen with BOTH pages has one to make. Note it reads
	# `problems`, not "is any fault active" — a tank about to run dry is a reason to put the plan
	# up too.
	if not _manual and pages.size() > 1:
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


## No-op on a single-page screen, which is what makes left/right harmless there rather than
## something Game has to know not to send.
func flip_page() -> void:
	if pages.size() < 2:
		return
	set_page(Page.NAV if page == Page.STATUS else Page.STATUS, true)


## Hand the console back to its own judgement. Called when the player stops reading.
func clear_manual_page() -> void:
	if not _manual:
		return
	_manual = false
	_refresh()


func is_page_manual() -> bool:
	return _manual


## DECK PLAN, matching the title the page draws on itself — "DAMAGE CONTROL — DECK PLAN". A
## prompt that called it something the screen does not is a prompt for a different screen.
func page_name() -> String:
	return "DECK PLAN" if page == Page.STATUS else "NAV PLOT"


## What flipping would get you, or "" on a screen with nowhere to flip to. The reading prompt says
## this rather than "FLIP", so the player knows what the other page is before spending the keypress
## on finding out.
func other_page_name() -> String:
	if pages.size() < 2:
		return ""
	return "NAV PLOT" if page == Page.STATUS else "DECK PLAN"


func _set_page(to: Page) -> void:
	if page == to or not has_page(to):
		return
	page = to
	_apply_page()
	page_changed.emit(int(page))


## A DEAD SCREEN when the computer itself is the thing that is broken. Both pages go dark —
## the nav plot is the thing that has failed, and a status map drawn by a broken computer would
## be quietly lying about the rest of the ship.
func _apply_page() -> void:
	var lit := not is_broken()
	if _chart != null:
		_chart.visible = lit and page == Page.NAV
	if _map != null:
		_map.visible = lit and page == Page.STATUS


# --- being the repair point --------------------------------------------------
#
# The computer already had an interaction — lean in and read the screen — and the fault gives it
# a second one. They must not compete for the same press, so the prop does not get two
# Interactables: it gets ONE that changes role. Broken, the screen is dark and there is nothing
# to read, so "read the map" is not a thing the player can want; the hammer and the spare part
# are. Fixed, the reverse. The same shape Silo uses when its machine jams.

## Take the computer out of service while `fault` is active, and make it repairable instead.
func bind_malfunction(fault: Malfunction) -> void:
	_fault = fault
	if fault == null:
		return
	if _indicator == null:
		_indicator = IndicatorLight.attach(self, indicator_offset)
	if not fault.broke.is_connected(_on_fault_changed):
		fault.broke.connect(_on_fault_changed)
	if not fault.repaired.is_connected(_on_fault_changed):
		fault.repaired.connect(_on_fault_changed)
	_refresh_fault()


func is_broken() -> bool:
	return _fault != null and _fault.is_active


## True while running on a bodge — still down on power, still worth a spare part.
func is_patched() -> bool:
	return _fault != null and _fault.is_patched


func _on_fault_changed(_fault_ref: Malfunction, _flag: bool) -> void:
	_refresh_fault()


func _refresh_fault() -> void:
	_apply_page()
	# A BROKEN screen has to be a ray target even when a healthy one is not. This prop has
	# `lean_in` off — it is a display you read from where you stand, not something you walk up
	# to — and `is_enabled` is what Interactor tests before a thing can become the focus at
	# all. Leave it off while the fault is live and the player can see a red flashing computer
	# and be unable to touch it.
	if is_broken() or is_patched():
		is_enabled = true
	elif not lean_in:
		is_enabled = false
	if _indicator == null:
		return
	var color := IndicatorLight.COLOR_OK
	if is_broken():
		color = IndicatorLight.COLOR_CRIT
	elif is_patched():
		color = IndicatorLight.COLOR_WARN
	_indicator.set_state(color, is_broken() and _fault.is_critical())


# --- what is wrong, and where -----------------------------------------------

## Every problem worth a blob, as plain dictionaries. StatusMap knows nothing about RunState and
## this is the seam: faults, tanks and body clocks all arrive as {room, kind, urgency, label}.
##
## A problem whose room cannot be resolved is DROPPED rather than guessed at. `room_at()` returns
## "" for a doorway gap or a spot outside the hull, and a blob placed on the nearest room instead
## would be the map telling a confident lie about where to walk.
## The life-support tank, so a spent canister shows on the ship map as somewhere to walk.
var _oxygen: OxygenSilo = null


func bind_oxygen(silo: OxygenSilo) -> void:
	_oxygen = silo


func collect_problems() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _run == null or _ship == null:
		return out
	# Low air is a place on the map, not just a line on the HUD: the whole point of the map is
	# that a problem tells you which room to walk to.
	if _oxygen != null and _oxygen.is_low():
		var room := _ship.room_at(_oxygen.global_position)
		if room != "":
			out.append({
				"room": room,
				"kind": "supply",
				"urgency": "warn",
				"label": "OXYGEN LOW — REPLACE O2 CANISTER",
			})

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


## Where the player is placed to read the screen, AND WHICH WAY THEY LOOK — the basis carries the
## pitch as well as the yaw, which matters the moment a screen is not at eye height. Falls back to
## the terminal's own transform so a missing marker cannot drop the camera inside the console.
func view_transform() -> Transform3D:
	var marker := _view if _view != null else get_node_or_null(view_path) as Node3D
	return marker.global_transform if marker != null else global_transform


func interact() -> void:
	if not is_enabled:
		return
	# Nothing to read on a dead screen. Refusing with a reason beats opening a blank panel.
	if is_broken():
		return
	opened.emit(self)
	interacted_with.emit(self)
