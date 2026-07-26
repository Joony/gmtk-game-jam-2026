extends SceneTree
# TODO 19 Phase 2: the damage plan wired to the run.
#
# Phase 1's suite tests the DRAWING against a hand-written problem list. This one tests the
# COLLECTION — that what the ship is actually doing turns into the right blobs, in the right
# rooms, and that the console decides for itself which page to show.
#
# Loads the REAL `scenes/game.tscn`, unlike smoke_status_map which builds a bare ship: the thing
# under test is whether faults and silos as they are actually placed resolve to rooms the map can
# draw, and a fixture ship would answer a question nobody asked. That is also what makes this
# suite worth having — a fault sitting in a doorway gap, or a silo spawned outside the hull,
# is invisible to every other test in the project.
#
# Run: godot --headless --path . -s tests/smoke_status_console.gd

## The suite must not be allowed to call itself green off half a run.
const MIN_CHECKS := 40

var _failures: Array[String] = []
var _checks: int = 0
var _game: Node3D
var _run: RunState
var _computer: ComputerTerminal
## The deck plan's own screen, on the bridge terminal bank. Since the pod bay console became
## nav-only this is where every blob in this suite actually lands.
var _bridge: ComputerTerminal
var _ship: RoomBuilder


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("status console test timed out")
		quit(1))
	_go.call_deferred()


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Force a refresh now rather than waiting out `refresh_interval`, which would make every
## assertion below a timing question.
func _settle() -> void:
	_computer._refresh()
	_bridge._refresh()
	await process_frame


func _go() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await _frames(6)

	_run = _game.get_node("Run")
	_computer = _game.get_node("Computer")
	_bridge = _game.get_node("Displays").bridge_display
	_ship = _game.get_node("Ship") as RoomBuilder
	_check("the bridge deck plan got built", _bridge != null)
	if _bridge == null:
		print("STATUS CONSOLE TEST FAIL")
		quit(1)
		return

	await _test_placement()
	await _test_faults()
	await _test_silos_and_needs()
	await _test_pages()
	await _test_player_marker()

	if _checks < MIN_CHECKS:
		_failures.append("only %d of the expected %d checks ran — a section died early"
			% [_checks, MIN_CHECKS])

	if _failures.is_empty():
		print("STATUS CONSOLE TEST PASS (%d checks)" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("STATUS CONSOLE TEST FAIL")
		quit(1)


# --- everything the map has to point at is somewhere it can draw --------------

## The check no other suite makes, and the one most likely to catch a real placement bug: every
## fault and every silo on the actual ship has to resolve to a room the diagram has a node for.
## A prop in a doorway gap or a metre outside the hull resolves to "" and its blob is silently
## dropped — the map would just not mention it.
func _test_placement() -> void:
	var faults := get_nodes_in_group(Malfunction.GROUP_MALFUNCTION)
	_check("the ship has faults to place (%d)" % faults.size(), faults.size() >= 5)
	for node in faults:
		var fault := node as Malfunction
		if fault == null:
			continue
		var room := _ship.room_at(fault.global_position)
		_check("%s is in a room (%s at %v)" % [fault.system_name, room, fault.global_position],
			room != "")
		_check("%s is in a room the map can draw (%s)" % [fault.system_name, room],
			ShipPlan.has_node(room))

	var silos := get_nodes_in_group(Silo.GROUP_SILO)
	_check("the ship has silos to place (%d)" % silos.size(), silos.size() >= 4)
	for node in silos:
		var silo := node as Silo
		if silo == null:
			continue
		var room := _ship.room_at(silo.global_position)
		_check("%s is in a room (%s at %v)" % [silo.display_name, room, silo.global_position],
			room != "")
		_check("%s is in a room the map can draw (%s)" % [silo.display_name, room],
			ShipPlan.has_node(room))


# --- faults ------------------------------------------------------------------

func _test_faults() -> void:
	var drive := _game.get_node("MainDrive") as Malfunction
	var room := _ship.room_at(drive.global_position)

	# Clear the board first: the run opens on an already-broken fault (the opening tutorial),
	# so "no problems" is a state this suite has to create rather than assume.
	for node in get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var fault := node as Malfunction
		if fault != null and fault.is_active:
			fault.repair(true, _run.distance_remaining)
	await _settle()
	var faults_now := _faults_in(_bridge.collect_problems())
	_check("with everything repaired there are no fault blobs (%d)" % faults_now.size(),
		faults_now.is_empty())

	drive.break_now()
	await _settle()
	var problems := _bridge.collect_problems()
	faults_now = _faults_in(problems)
	_check("breaking a fault makes exactly one fault blob (%d)" % faults_now.size(),
		faults_now.size() == 1)
	if faults_now.size() == 1:
		_check("...in the room the fault stands in (%s vs %s)" % [faults_now[0]["room"], room],
			faults_now[0]["room"] == room)
		_check("...named after the system", faults_now[0]["label"] == drive.system_name)
		_check("...and it is a FAULT, not a warning",
			int(faults_now[0]["kind"]) == StatusMap.Kind.FAULT)

	# A bleeding fault's blob speeds up as the damage accumulates — the fault's whole character,
	# rendered without a word of text. Measured, because it is the one urgency that MOVES.
	var fresh := ComputerTerminal.fault_urgency(drive)
	drive.speed_decay = drive.speed_penalty
	var bled := ComputerTerminal.fault_urgency(drive)
	_check("a bleeding fault pulses harder the longer it is left (%.2f -> %.2f)" % [fresh, bled],
		bled > fresh)
	_check("a fault that has only just broken is not the calmest thing on the map (%.2f)" % fresh,
		fresh >= ComputerTerminal.FRESH_CRITICAL - 0.001)
	drive.speed_decay = 0.0

	# PATCHED FAULTS ARE NOT ON THIS MAP. A patch is not somewhere you have to go.
	drive.repair(false, _run.distance_remaining)
	await _settle()
	_check("a patched fault is running on a patch", drive.is_patched)
	_check("...and has no blob (%d)" % _faults_in(_bridge.collect_problems()).size(),
		_faults_in(_bridge.collect_problems()).is_empty())

	drive.break_now()
	await _settle()
	_check("a patch giving out puts the blob back",
		_faults_in(_bridge.collect_problems()).size() == 1)
	drive.repair(true, _run.distance_remaining)
	await _settle()
	_check("a proper repair clears it",
		_faults_in(_bridge.collect_problems()).is_empty())


# --- silos and needs ---------------------------------------------------------

func _test_silos_and_needs() -> void:
	var life := _run.silo_by_id(&"life_support")
	_check("the life support silo exists", life != null)
	if life == null:
		return
	var room := _ship.room_at(life.global_position)

	_check("a full tank is not pressing", not life.is_pressing())
	_check("...and has no blob", _warnings_for(room).is_empty())

	# Drain it past its warning line.
	while not life.is_exhausted():
		life.use()
	await _settle()
	var warnings := _warnings_for(room)
	_check("an empty tank makes one warning blob in its own room (%d)" % warnings.size(),
		warnings.size() == 1)
	if warnings.size() == 1:
		_check("...and it is a WARNING, not a fault",
			int(warnings[0]["kind"]) == StatusMap.Kind.WARNING)
		_check("...pulsing at the top of the range (%.2f)" % float(warnings[0]["urgency"]),
			absf(float(warnings[0]["urgency"]) - 1.0) < 0.001)

	# THE MERGE. The CO2 clock is cleared at this same tank, so a pressing need and a pressing
	# silo are ONE errand — one walk, one canister — and must be ONE blob. Two would say there
	# were two places to go.
	var co2 := _run.need_by_id(&"co2")
	_check("the CO2 need exists", co2 != null)
	if co2 != null:
		co2.start()
		# Past its warning line, so it earns a row of its own on the HUD.
		co2.advance(co2.seconds * (1.0 - co2.warn_at) + 1.0)
		_check("the CO2 need is pressing", co2.is_pressing())
		_check("and the tank still is", life.is_pressing())
		await _settle()
		warnings = _warnings_for(room)
		_check("a need and its own tank are ONE blob, not two (%d)" % warnings.size(),
			warnings.size() == 1)

		# ...and the need alone still puts a blob on the tank's room, because the tank is where
		# you have to walk even when the tank itself is fine.
		var canister := Consumable.new()
		canister.kind = &"o2"
		canister.amount = 1.0
		_game.add_child(canister)
		life.service(canister)
		await _settle()
		_check("refilling the tank leaves the need's own blob behind (%d)"
			% _warnings_for(room).size(), _warnings_for(room).size() == 1)
		_check("the tank itself is no longer pressing", not life.is_pressing())
		co2.stop()
		canister.queue_free()

	await _settle()


# --- which page is up --------------------------------------------------------

func _test_pages() -> void:
	for node in get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var fault := node as Malfunction
		if fault != null and fault.is_active:
			fault.repair(true, _run.distance_remaining)
	await _settle()
	_check("the ship can be made clean for this section", _bridge.collect_problems().is_empty())

	# ONE DISPLAY, ONE JOB. The pod bay console is the nav plot and the bridge bank is the deck
	# plan, and neither can become the other — so "which screen am I looking at" is something the
	# player reads rather than something they have to work out.
	_check("the console shows the nav plot", _computer.page == ComputerTerminal.Page.NAV)
	_check("...and only the nav plot", not _computer.has_page(ComputerTerminal.Page.STATUS))
	_check("the bridge display shows the deck plan", _bridge.page == ComputerTerminal.Page.STATUS)
	_check("...and only the deck plan", not _bridge.has_page(ComputerTerminal.Page.NAV))

	# A single-page screen has nowhere to flip to, so left/right does nothing and the reading
	# prompt does not advertise a key that would.
	_computer.flip_page()
	_bridge.flip_page()
	_check("flipping the console does nothing", _computer.page == ComputerTerminal.Page.NAV)
	_check("flipping the bridge display does nothing",
		_bridge.page == ComputerTerminal.Page.STATUS)
	_check("neither reports a page to flip to",
		_computer.other_page_name() == "" and _bridge.other_page_name() == "")
	_check("and neither counts as a manual override",
		not _computer.is_page_manual() and not _bridge.is_page_manual())

	# Each prompt names what is actually on its own glass.
	_check("the console prompt names the nav plot",
		_computer.get_interaction_text().to_lower().contains("nav plot"))
	_check("the bridge prompt names the deck plan",
		_bridge.get_interaction_text().to_lower().contains("deck plan"))

	# A screen that cannot show the plan does not go looking for problems either.
	var nav := _game.get_node("NavArray") as Malfunction
	nav.break_now()
	await _settle()
	_check("the console still shows the nav plot with the ship on fire",
		_computer.page == ComputerTerminal.Page.NAV)
	# The guard is on the WORK, not on the collector: `_refresh()` skips collecting entirely on a
	# screen with no STATUS page, and there is no map under the console to push to if it did.
	_check("the console has no deck plan to draw on",
		_computer.find_child("StatusMap", true, false) == null)
	_check("while the bridge display has the fault",
		_faults_in(_bridge.collect_problems()).size() == 1)
	nav.repair(true, _run.distance_remaining)
	await _settle()


# --- you are here ------------------------------------------------------------

func _test_player_marker() -> void:
	var player: Node3D = _game.get_node("Player")
	var map := _bridge.find_child("StatusMap", true, false) as StatusMap
	_check("the bridge display has a map to mark", map != null)
	if map == null:
		return

	# The cryo bay, where the console is bolted and where the player therefore is whenever they
	# can read this.
	player.global_position = Vector3(0.0, 0.9, 6.0)
	await _settle()
	_check("the marker follows the player into the pod bay (%s)" % map.player_room(),
		map.player_room() == "cryo_bay")

	player.global_position = Vector3(-19.5, 0.9, 2.5)
	await _settle()
	_check("...and out to the engine room (%s)" % map.player_room(),
		map.player_room() == "engine_room")

	# Outside the hull is a real answer, not an error, and it must hide the marker rather than
	# pin it to whichever room happens to be nearest.
	player.global_position = Vector3(200.0, 0.9, 200.0)
	await _settle()
	_check("a player outside the ship is not pointed at (%s)" % map.player_room(),
		map.player_room() == "")
	_check("and the map agrees there is nothing to draw", map.here_layout().is_empty())


# --- helpers -----------------------------------------------------------------

func _faults_in(problems: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for problem in problems:
		if int(problem["kind"]) == StatusMap.Kind.FAULT:
			out.append(problem)
	return out


func _warnings_for(room: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for problem in _bridge.collect_problems():
		if int(problem["kind"]) == StatusMap.Kind.WARNING and problem["room"] == room:
			out.append(problem)
	return out
