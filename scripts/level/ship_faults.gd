class_name ShipFaults
extends Node

# The drive fails, as a table (TODO 21b). The counterpart to ShipSupplies: that one says where
# the consumables are, this one says what breaks and how hard.
#
# WHY IN CODE. Three of these are `Malfunction` nodes already standing in `game.tscn`, and this
# does not replace them — it OVERRIDES their numbers and, where a system has geometry of its
# own, hands the repair to that geometry. Two reasons for doing it here rather than editing the
# scene: the scene is being dressed continuously and every edit is a merge conflict waiting to
# happen, and the four fails only make sense read side by side. Their initial and maximum costs
# are a balance table, and a balance table scattered across five nodes in a 700-line .tscn is
# a balance table nobody will ever tune.
#
# When the scene settles, these numbers can move into it and this file becomes a deletion.

const REPAIR_SCRIPT := preload("res://scripts/game/repair_point.gd")
const WALL_SOCKET_SCENE := preload("res://scenes/props/wall_socket.tscn")
const POWER_REPAIR_SCRIPT := preload("res://scripts/game/socket_power_repair.gd")
const SILO_SCRIPT := preload("res://scripts/game/silo.gd")

## Each row names a fault already in the scene (`system`) and what to make of it. `adopt` is a
## prop whose model becomes the repair point; without one the fault keeps its RepairPanel.
const FAULTS := [
	{
		# THE OPENING FAULT, and the tutorial (TODO 18). Cheapest of the four on purpose: the
		# first problem should teach the loop, not punish it.
		#
		# It takes over from NAV ARRAY, which sat in the CRYO BAY with no repair panel at all —
		# an unfixable permanent -20%. See `RETIRE` below.
		"system": "NAV ARRAY",
		"rename": "NAV COMPUTER",
		"fault_text": "nav plot drifting",
		"initial": 0.05,
		"max": 0.10,
		"decay_per_day": 0.012,
		"starts_broken": true,
		"fire_at_distance": 0.0,
		"critical": true,
		"refire_every": 11.0,
		"vo_line": &"nav_off",
		# The bridge computer IS the repair point — see ComputerTerminal.bind_malfunction().
		# Not adopted by RepairPoint, because that node already has a script and an interaction
		# of its own; the terminal borrows the repair logic instead of being replaced by it.
		"computer": ^"Computer",
		"patch_text": "Bash the nav plot back into line",
		"fit_text": "Fit a spare nav module",
	},
	{
		# The two panels in the engine room. Both hurt harder than the nav computer — they are
		# the drive itself — and both take a hammer or a spare part.
		"system": "DRIVE REGULATOR",
		"fault_text": "output regulator stuck open",
		# NO VOICE LINE, stated rather than omitted. The scene had this fault saying
		# `need_oil` — "them robots in the garage need oil" — which belongs to the CRAWLERS
		# fault below and described a puzzle that did not exist yet. An absent key here leaves
		# whatever the scene happens to carry, so the silence is written down.
		"vo_line": &"",
		"initial": 0.10,
		"max": 0.20,
		"decay_per_day": 0.03,
		# Only ONE fault opens the run, and it is the nav computer now.
		"starts_broken": false,
		"fire_at_distance": 79.0,
		"critical": true,
		# THE NAG. One of the four has to keep coming back, or a run settles into long stretches
		# of nothing happening — you sleep, you arrive. This is the one: repaired or bodged, it
		# returns every few million miles, and because it recurs on DISTANCE it lands hardest
		# during stasis, when the ship covers ground fastest. Being woken by it IS the loop.
		"refire_every": 6.0,
	},
	{
		"system": "MAIN DRIVE",
		"rename": "DRIVE COUPLER",
		"fault_text": "coupler slipping",
		"initial": 0.10,
		"max": 0.20,
		"decay_per_day": 0.03,
		"fire_at_distance": 74.0,
		"critical": true,
		"refire_every": 9.0,
	},
	{
		# THE CO2 SCRUBBER, moved out of the spine corridor and into life support where it
		# belongs — beside the oxygen tank it is supposed to be keeping breathable.
		#
		# The one critical fault that costs no DRIVE. It attacks the other clock instead: while
		# it is broken you burn air 1.6x as fast, so the cost is measured in the currency the
		# whole game is priced in, and a long repair trip while it is down is its own punishment.
		"system": "O2 SCRUBBER",
		"fault_text": "CO2 saturating, you are breathing harder",
		# On the DOOR WALL (x = 16), facing +X into the room — so it is the first thing you see
		# on the way in rather than something to hunt for round a corner. Clear of the doorway
		# itself, which spans z -15.4 to -13.6, and of the pipes dressed in at x 19 and 20.
		# The 0.17 stand-off from the wall is what every other panel on the ship uses.
		"at": Vector3(16.17, 1.3, -12.5),
		"yaw": 90.0,
		"initial": 0.0,
		"max": 0.0,
		"decay_per_day": 0.0,
		"oxygen_multiplier": 1.6,
		"critical": true,
		"fire_at_distance": 76.0,
		"refire_every": 14.0,
		"vo_line": &"life_support",
		"patch_text": "Bleed the scrubber",
		"fit_text": "Fit a spare cartridge",
	},
	{
		# The fourth panel, already dressed into the engine room and until now firing once and
		# staying fixed. A run with one recurring fault and three one-shots goes quiet in its
		# back half; four recurring ones keep the pod from being a place you simply sleep.
		"system": "COOLANT LOOP",
		"initial": 0.08,
		"max": 0.18,
		"decay_per_day": 0.04,
		"fire_at_distance": 70.0,
		"critical": true,
		"refire_every": 12.0,
	},
]

## THE ENGINE CORE (TODO 21c). Not a part-or-bodge fault and so not in the table above: the
## drive runs flat and the only fix is power. You carry a battery to the engine bay, charge it
## at the wall socket, and run a cable from it into the engine.
##
## Built rather than placed because the two things it needs are EMPTIES INSIDE THE MODEL —
## `socket` and `Indicator` — and a node in the scene file cannot be positioned against those
## without copying their coordinates out and letting the copy rot.
const ENGINE := {
	"prop": ^"CD_Engine_v4_2",
	"system_name": "ENGINE CORE",
	"fault_text": "core depleted",
	# -100%, immediately and permanently until it is fed. This is the one fault that stops the
	# ship rather than slowing it; RunState's speed floor is what keeps that survivable.
	"initial": 1.0,
	"max": 1.0,
	"vo_line": &"power_off",
	# Never fires on a schedule: it fires when the FUEL runs out, below.
	"fire_at_distance": 0.0,
	# --- the fuel behind it --------------------------------------------------
	# The core is not a fault that arrives out of nowhere — it is the end of a gauge the player
	# has been able to watch. Fuel drains on the SHIP's clock, so stasis burns it, and the
	# engine's indicator tells the story in three states:
	#
	#   green   plenty
	#   ORANGE  below `warn_at` — go and charge a battery, you have time
	#   RED     empty, the core fault is live and the drive reads zero
	#
	# 0.055/day against a ~31-day crossing is a tank that needs charging three or four times.
	"fuel_drain_per_day": 0.14,
	"fuel_warn_at": 0.10,
}


## THE CARGO CRAWLERS. The one fault on the ship that is not an emergency: two loader machines
## in the cargo bay seize up, and a can of oil frees them.
##
## AMBER, NOT RED. Everything else that breaks is CRITICAL — klaxon, red alert, the lot — and a
## run where every single fault screams has no register left to say "this one actually matters".
## DEGRADING gives the indicator an amber light and no alarm, and the drive cost is small enough
## that this is a job you do because you are passing rather than because you must.
##
## Built rather than placed, and adopted onto the crawler MODELS: `Interactor` walks UP from
## whatever collider the ray hits, so a repair panel standing beside a crawler that has its own
## collision would simply never be seen. Same reason the silos and the vending machine are
## adopted. See ShipSupplies for the pattern.
##
## BOTH crawlers repair the SAME fault. One seizure, two machines it could be — you oil whichever
## one you reach first, and both lights go green. Two separate faults would double a chore that
## is meant to be a small one.
const CRAWLERS := {
	"props": [^"Decor/CargoCrawlerA", ^"Decor/CargoCrawlerB"],
	"system_name": "CARGO CRAWLERS",
	"fault_text": "loader bearings seized",
	# "Them robots in the garage need oil!" — the line that was mis-wired to DRIVE REGULATOR
	# and described this puzzle before it existed.
	"vo_line": &"need_oil",
	# Small, and it does not ramp. A seized cargo loader is drag on ship operations, not a hole
	# in the drive — the number is here so the fault is worth clearing, not so it hurts.
	"initial": 0.03,
	"max": 0.06,
	"decay_per_day": 0.01,
	# Mid-crossing, after the first wave of real emergencies has taught the loop.
	"fire_at_distance": 72.0,
	# Bearings dry out again. Rarely, because the can is kept and re-oiling costs only the walk.
	"refire_every": 15.0,
	"fit_text": "Oil the bearings",
	# The crawler is 7.8m wide and 5.1m tall at its dressed 0.71, and carries no `Indicator`
	# empty, so the light is placed by hand: above the body, on the near face. In the crawler's
	# LOCAL units, which are scaled — hence the division in _build_crawler_fault().
	"indicator_at": Vector3(0.0, 2.9, 1.6),
}


## Faults the plan supersedes and that should simply not be in the run. Freed rather than
## quietly neutralised: a `Malfunction` left in the group with nothing that can fix it is what
## `smoke_run_state`'s "every malfunction is fixable" exists to catch, and hiding it from that
## check by zeroing its numbers would be defeating the test rather than the problem.
##
## Empty for now — NAV ARRAY is renamed rather than retired, since it is the same fault in a
## better place. Kept as the seam for when a fail genuinely goes.
const RETIRE: Array[String] = []


func apply() -> void:
	for row in FAULTS:
		var fault := _find(row["system"])
		if fault == null:
			push_warning("ShipFaults: no malfunction named %s to configure" % row["system"])
			continue
		_configure(fault, row)

	_build_engine_core()
	_build_crawler_fault()

	for name in RETIRE:
		var doomed := _find(name)
		if doomed != null:
			doomed.queue_free()


func _configure(fault: Malfunction, row: Dictionary) -> void:
	if row.has("rename"):
		fault.system_name = row["rename"]
	if row.has("fault_text"):
		fault.fault_text = row["fault_text"]
	if row.has("vo_line"):
		fault.vo_line = row["vo_line"]
	if row.has("critical"):
		fault.severity = Malfunction.Severity.CRITICAL if row["critical"] \
			else Malfunction.Severity.DEGRADING
	fault.initial_speed_penalty = row.get("initial", 0.0)
	fault.speed_penalty = row.get("max", fault.speed_penalty)
	fault.speed_decay_per_day = row.get("decay_per_day", fault.speed_decay_per_day)
	if row.has("starts_broken"):
		fault.starts_broken = row["starts_broken"]
	if row.has("fire_at_distance"):
		fault.fire_at_distance = row["fire_at_distance"]
	if row.has("oxygen_multiplier"):
		fault.oxygen_drain_multiplier = row["oxygen_multiplier"]
	# Moving a fault moves its panel with it — the panel is a child, so one transform does both
	# and the HUD, the ship map and the klaxon all agree about which room the problem is in.
	#
	# The FACING has to move too, and forgetting it is a silent break: a panel keeps whichever
	# wall it used to be bolted to, so on its new wall it faces into open air with nothing
	# behind it. smoke_navigation catches exactly that — "backed by geometry" — because a panel
	# mounted backwards is invisible to every other test.
	if row.has("at"):
		fault.global_transform = Transform3D(
			Basis(Vector3.UP, deg_to_rad(row.get("yaw", 0.0))), row["at"])
	fault.refire_every = row.get("refire_every", 0.0)

	var panel := _panel_of(fault)
	# A fault repaired at a screen still needs a RepairPoint — it is where hammer-versus-part
	# lives, and `smoke_run_state` rightly refuses to let a fault exist with no way to fix it.
	# Logic only: no geometry, no indicator, never a ray target. The terminal is all three.
	if panel == null and row.has("computer"):
		var helper := Node3D.new()
		helper.name = "RepairLogic"
		helper.set_script(REPAIR_SCRIPT)
		panel = helper as RepairPoint
		panel.show_indicator = false
		fault.add_child(helper)
		panel.setup()
		panel.bind(fault)
	if panel != null:
		if row.has("patch_text"):
			panel.patch_text = row["patch_text"]
		if row.has("fit_text"):
			panel.fit_text = row["fit_text"]

	# A system with a screen of its own repairs AT that screen.
	if row.has("computer"):
		var terminal := _scene_root().get_node_or_null(row["computer"]) as ComputerTerminal
		if terminal == null:
			push_warning("ShipFaults: no ComputerTerminal at %s for %s"
				% [row["computer"], fault.system_name])
			return
		# Move the fault to the screen, so the HUD, the ship map and the klaxon all agree about
		# which room the problem is in — they all read `Malfunction.global_position`.
		fault.global_position = terminal.global_position
		terminal.bind_malfunction(fault)
		if panel != null:
			# The terminal borrows the panel's repair logic; it must not also be a ray target
			# floating beside the screen.
			terminal._repair = panel
			panel.is_enabled = false
			(panel as Node3D).visible = false


func _panel_of(fault: Malfunction) -> RepairPoint:
	for child in fault.get_children():
		if child is RepairPoint:
			return child
	return null


func _find(system_name: String) -> Malfunction:
	for node in get_tree().get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var fault := node as Malfunction
		if fault != null and fault.system_name == system_name:
			return fault
	return null


func _scene_root() -> Node:
	return get_parent()


## The seized cargo crawlers, oiled rather than repaired. See CRAWLERS.
##
## The fault hangs off the FIRST crawler so it has a position (the HUD, the ship map and the
## room voice all ask a fault which room it is in), and BOTH crawler models are adopted as
## repair points bound to it. Adoption means attaching the script to the model itself: the model
## brings its own collision, and Interactor resolves a hit by walking UP from the collider, so a
## separate panel node standing beside it would never be the thing the ray finds.
func _build_crawler_fault() -> void:
	var crawlers: Array[Node3D] = []
	for path in CRAWLERS["props"]:
		var crawler := _scene_root().get_node_or_null(path) as Node3D
		if crawler == null:
			push_warning("ShipFaults: no crawler at %s" % path)
			continue
		crawlers.append(crawler)
	if crawlers.is_empty():
		return
	if crawlers[0].get_node_or_null("CrawlerSeizure") != null:
		return

	var fault := Malfunction.new()
	fault.name = "CrawlerSeizure"
	fault.system_name = CRAWLERS["system_name"]
	fault.fault_text = CRAWLERS["fault_text"]
	# AMBER. The only fault on the ship that is not CRITICAL — no klaxon, no red alert, an amber
	# indicator and a HUD row. See the comment on CRAWLERS.
	fault.severity = Malfunction.Severity.DEGRADING
	fault.vo_line = CRAWLERS["vo_line"]
	fault.initial_speed_penalty = CRAWLERS["initial"]
	fault.speed_penalty = CRAWLERS["max"]
	fault.speed_decay_per_day = CRAWLERS["decay_per_day"]
	fault.fire_at_distance = CRAWLERS["fire_at_distance"]
	fault.refire_every = CRAWLERS["refire_every"]
	crawlers[0].add_child(fault)

	for crawler in crawlers:
		_adopt_crawler(crawler, fault)


## Turn one crawler model into a repair point for `fault`.
func _adopt_crawler(crawler: Node3D, fault: Malfunction) -> void:
	crawler.set_script(REPAIR_SCRIPT)
	var point := crawler as Node as RepairPoint
	point.bind(fault)
	# OIL ONLY, and no bodge. `tool_group` empty means is_tool() is false for everything, so the
	# hammer offers nothing here — you cannot bash a dry bearing back to life. The can is matched
	# by its own group rather than by `spare_parts`, so a generic spare will not do either: this
	# is the one fault with a bespoke fix.
	point.required_part_group = &"oil_cans"
	point.tool_group = &""
	# ...and the can is KEPT. There is exactly one on the ship and the fault recurs.
	point.consumes_part = false
	point.fit_text = CRAWLERS["fit_text"]
	# The model has no `Indicator` empty, so the light is positioned by hand — in the crawler's
	# LOCAL space, which is scaled at 0.71, so a figure written in metres has to be divided by
	# that or the lamp lands short of where it was meant to sit.
	var host_scale: float = maxf(crawler.global_transform.basis.get_scale().y, 0.0001)
	point.indicator_offset = (CRAWLERS["indicator_at"] as Vector3) / host_scale
	point.setup()
	# setup() binds to the PARENT when it is a Malfunction, and here it is not — the second
	# crawler is nowhere near the fault in the tree. Rebound explicitly afterwards.
	point.bind(fault)
	fault.register_repair_point(point)


## The engine core fault, hung off the engine model and fed through a socket at its own
## `socket` empty. Reuses SocketPowerRepair — the "feed the inlet" repair route already built
## for the aux-power device — rather than inventing a second way to say the same thing.
func _build_engine_core() -> void:
	var engine := _scene_root().get_node_or_null(ENGINE["prop"]) as Node3D
	if engine == null:
		push_warning("ShipFaults: no engine at %s for the core fault" % ENGINE["prop"])
		return
	if engine.get_node_or_null("EngineCore") != null:
		return

	var fault := Malfunction.new()
	fault.name = "EngineCore"
	fault.system_name = ENGINE["system_name"]
	fault.fault_text = ENGINE["fault_text"]
	# CRITICAL: the ship-wide red alert, the klaxon, the lot. A drive with no power is the
	# worst thing that can happen short of running out of air — the ship is not merely slow,
	# it has stopped and the arrival clock reads infinity.
	fault.severity = Malfunction.Severity.CRITICAL
	fault.halts_drive = true
	fault.initial_speed_penalty = ENGINE["initial"]
	fault.speed_penalty = ENGINE["max"]
	fault.speed_decay_per_day = 0.0
	fault.vo_line = ENGINE["vo_line"]
	fault.fire_at_distance = ENGINE["fire_at_distance"]
	engine.add_child(fault)

	# The inlet, at the empty the modeller put there. Parented to it, so it tracks the engine —
	# and scale-compensated, because the engine is dressed at 0.5 and a socket built in the
	# model's local units would come out half size.
	var mount := _find_child_named(engine, "socket")
	if mount == null:
		push_warning("ShipFaults: the engine has no `socket` empty")
		return
	var inlet := WALL_SOCKET_SCENE.instantiate()
	mount.add_child(inlet)
	var inlet_body := inlet as Node3D
	inlet_body.name = "CoreInlet"
	var host_scale: float = maxf(mount.global_transform.basis.get_scale().y, 0.0001)
	inlet_body.scale = Vector3.ONE / host_scale
	inlet_body.position = Vector3.ZERO
	(inlet as WallSocket).is_power_source = false

	# Powered inlet -> fault repaired. The same wiring powered_device.tscn does in the scene.
	#
	# The paths are set BEFORE add_child and written out literally rather than via
	# get_path_to(): SocketPowerRepair resolves them in its own _ready(), which fires the
	# instant it is parented, and get_path_to() needs the node to be in the tree already. Set
	# them afterwards and it has already complained that it cannot find either end.
	#
	# From engine/EngineCore/CoreRepair: `..` is the fault, and the inlet hangs off the model's
	# own `socket` empty two levels up.
	var repair := Node.new()
	repair.name = "CoreRepair"
	repair.set_script(POWER_REPAIR_SCRIPT)
	repair.set("malfunction_path", NodePath(".."))
	repair.set("socket_path", NodePath("../../socket/CoreInlet/Port"))
	fault.add_child(repair)

	# THE FUEL GAUGE. A Silo on the engine, draining on the ship's clock, whose running out is
	# what fires the core fault — and whose being refilled clears it. Reusing Silo rather than
	# inventing a level: it already drains per ship-day, already warns at a threshold, and
	# already knows how to be exhausted.
	var fuel := StaticBody3D.new()
	fuel.name = "CoreFuel"
	fuel.set_script(SILO_SCRIPT)
	engine.add_child(fuel)
	# Via a Node3D view: Silo is an Interactable and so extends Node3D, a sibling branch of
	# StaticBody3D as far as the parser is concerned. See docs/debugging-gotchas.md.
	var fuel_view: Node3D = fuel
	var tank := fuel_view as Silo
	tank.silo_id = &"power"
	tank.display_name = "DRIVE FUEL"
	tank.accepts = &"battery"
	tank.level = 1.0
	tank.use_amount = 0.0
	tank.drain_per_day = ENGINE["fuel_drain_per_day"]
	tank.warn_at = ENGINE["fuel_warn_at"]
	tank.empty_is_critical = true
	tank.show_lamp = false  # the engine's own Indicator does the talking, below
	tank.setup()

	# And the light, on the engine's own Indicator empty. Green, orange below the warning line,
	# red once the core is out — the gauge and the fault are one readout.
	var light := IndicatorLight.attach(engine)
	var refresh := func() -> void:
		if light == null:
			return
		var color := IndicatorLight.COLOR_OK
		if fault.is_active:
			color = IndicatorLight.COLOR_CRIT
		elif tank.is_pressing():
			color = IndicatorLight.COLOR_WARN
		light.set_state(color, fault.is_active)

	# Empty tank -> the core dies. Charged -> back to a full tank and a live drive.
	tank.exhausted.connect(func(_s: Silo) -> void:
		fault.break_now(false)
		refresh.call())
	tank.level_changed.connect(func(_s: Silo, _l: float) -> void: refresh.call())
	fault.broke.connect(func(_m: Malfunction, _f: bool) -> void: refresh.call())
	fault.repaired.connect(func(_m: Malfunction, _permanent: bool) -> void:
		# Charging is all-or-nothing: a battery run into the core fills it, it does not top it
		# up. Half-charging would mean walking the same cable back a minute later.
		tank.level = 1.0
		refresh.call())
	refresh.call()


## Depth-first by name — the empties live inside the imported model.
func _find_child_named(node: Node, wanted: String) -> Node3D:
	if node.name == wanted:
		return node as Node3D
	for child in node.get_children():
		var found := _find_child_named(child, wanted)
		if found != null:
			return found
	return null
