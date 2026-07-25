extends SceneTree
# TODO 17 Phase 2: the CO2 countdown, end to end in the real game scene.
#
# smoke_needs.gd owns the component logic in isolation. This owns the WIRING — that a run
# actually has a life-support silo standing where the player can see one, canisters in the
# cargo bay to charge it with, a CO2 clock that starts when the scrubber fails, and a death
# that says what killed you.
#
# It leans on game.tscn deliberately, unlike smoke_needs: the whole question here is whether
# the pieces find each other inside the real scene, which is exactly what a hand-built fixture
# cannot answer.
#
# Run: godot --headless --path . -s tests/smoke_supplies.gd

const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []


func _init() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("supplies test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	_check("the opening stasis lets go", await Opening.wake(self, game))

	var run: RunState = game.get_node("Run")
	var ship: RoomBuilder = game.get_node("Ship")

	# --- the supplies are actually in the ship -------------------------------
	var supplies: ShipSupplies = game.get_node_or_null("Supplies")
	_check("the run builds its supplies", supplies != null)
	if supplies == null:
		return _finish()

	# Declared and landed. A silo whose decor host went missing warns and returns null, so
	# this is the assertion that stops the whole system quietly not being there.
	_check("every declared silo found its home (%d of %d)"
		% [supplies.silos().size(), ShipSupplies.SILOS.size()],
		supplies.silos().size() == ShipSupplies.SILOS.size())

	var silo := run.silo_by_id(&"life_support")
	_check("RunState found the life-support silo by id", silo != null)
	if silo == null:
		return _finish()
	_check("which is in life support, not floating in the hull (%s)"
		% ship.room_at(silo.global_position),
		ship.room_at(silo.global_position) == "life_support")
	_check("and it is full to start with (%.2f)" % silo.level, silo.level >= 1.0)

	var cans := supplies.canisters()
	_check("there are canisters to fetch (%d)" % cans.size(), cans.size() >= 2)
	if cans.is_empty():
		# Bail rather than index into nothing: a crash here reports as a timeout and buries
		# the one assertion that actually explains what went wrong.
		return _finish()
	var in_cargo := 0
	for can in cans:
		if ship.room_at(can.global_position) == "cargo_bay":
			in_cargo += 1
	_check("and they are in the cargo bay (%d of %d)" % [in_cargo, cans.size()],
		in_cargo == cans.size())
	_check("stocked with what the scrubber takes (%s)" % cans[0].kind,
		cans[0].matches(silo.accepts))

	# --- the CO2 clock is not running yet ------------------------------------
	var co2: Need = null
	for need in run.needs():
		if need.id == &"co2":
			co2 = need
	_check("the run has a CO2 need", co2 != null)
	if co2 == null:
		return _finish()
	_check("which is NOT in play while the scrubber is fine", not co2.active)
	_check("so nothing is on the HUD yet", run.pressing_needs().is_empty())

	# The scrubber's old job was to slow the drive and make you breathe harder. Per 17b it now
	# starts this countdown instead, and until game.tscn can be edited the run strips those
	# effects at load. Both would otherwise apply at once.
	var scrubber: Malfunction = null
	for node in game.get_tree().get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		if (node as Malfunction).system_name == "O2 SCRUBBER":
			scrubber = node
	_check("the O2 SCRUBBER is still in the ship", scrubber != null)
	if scrubber == null:
		return _finish()
	_check("and no longer costs drive (%.2f)" % scrubber.speed_penalty,
		is_zero_approx(scrubber.speed_penalty))
	_check("nor makes you breathe harder (%.2f)" % scrubber.oxygen_drain_multiplier,
		is_equal_approx(scrubber.oxygen_drain_multiplier, 1.0))

	# --- breaking it starts the clock ----------------------------------------
	scrubber.break_now(false)
	await _frames(2)
	_check("breaking the scrubber starts the CO2 countdown", co2.active)

	# --- it runs while you are awake -----------------------------------------
	co2.remaining = 30.0
	await _frames(20)
	_check("and it runs down while you are out of the pod (%.2f)" % co2.remaining,
		co2.remaining < 30.0)

	# ...and NOT in the pod. The one rule 17e is emphatic about: sleeping through a long haul
	# is the correct play and must not kill you.
	run.enter_stasis()
	await _frames(2)
	var asleep := co2.remaining
	await _frames(30)
	_check("but stops dead in stasis (%.3f -> %.3f)" % [asleep, co2.remaining],
		is_equal_approx(asleep, co2.remaining))
	run.exit_stasis()
	await _frames(2)

	# --- the HUD row appears only once it is pressing -------------------------
	# satisfy() rather than writing `remaining`: the row is driven by a latch that only a
	# genuine reset clears, and poking the number behind it would test nothing.
	co2.satisfy()
	await _frames(2)
	_check("a fresh countdown is not on the HUD", run.pressing_needs().is_empty())
	co2.advance(co2.seconds * (1.0 - co2.warn_at) + 1.0)
	_check("crossing the warning line puts it there", run.pressing_needs().size() == 1)

	# --- using the silo clears it, and costs a charge -------------------------
	var before := silo.level
	var pressing := co2.fraction()
	_check("the silo can be used", silo.use())
	await _frames(2)
	# Not `== 1.0`: the clock is running again the moment it is reset, so a frame later it is
	# already fractionally down. What matters is that it jumped back up.
	_check("which resets the countdown (%.2f -> %.2f)" % [pressing, co2.fraction()],
		co2.fraction() > pressing + 0.4)
	_check("and it is off the HUD again", run.pressing_needs().is_empty())
	_check("and costs a charge (%.2f -> %.2f)" % [before, silo.level], silo.level < before)

	# --- and a canister recharges the silo ------------------------------------
	while silo.use():
		pass
	_check("four charges empties it", silo.is_exhausted())
	var can: Consumable = cans[0]
	_check("a fetched canister recharges it", silo.service(can))
	_check("the silo has air again (%.2f)" % silo.level, silo.level > 0.0)
	_check("and you are left holding an empty (%s)" % can.kind, can.kind == &"empty")
	_check("which the game does not take off you", not silo.consumed_last_item())

	# --- running out is lethal, and says so -----------------------------------
	# The whole point of the CO2 need: it is the one NEW way to die (17b), and the end screen
	# has only ever known how to say "OUT OF AIR".
	_check("the run is still going", not run.finished)
	co2.remaining = 0.05
	await _frames(30)
	_check("letting CO2 run out ends the run", run.finished)
	var summary := run.summary()
	_check("named for what actually killed you (%s)" % summary.get("end_title", ""),
		summary.get("end_title", "") == "CO2 NARCOSIS")
	_check("with air still in the tank, so it was not suffocation (%.1f)"
		% run.oxygen_remaining, run.oxygen_remaining > 0.0)

	# --- a fault that is ALREADY broken when the run opens ---------------------
	# The other way a need can begin. A `starts_broken` fault never fires `broke` — RunState
	# breaks it before connecting the signal, deliberately, so the cold open is silent — so a
	# need triggered by one has to be picked up at collection time instead.
	#
	# Restarting the finished run is how this gets exercised, and it is worth doing for its own
	# sake: `finished` has to be cleared before the needs are spawned or a second run opens
	# with its need switched off. That ordering was wrong until this test caught it.
	scrubber.starts_broken = true
	run.running = false
	run.start()
	await _frames(2)
	var reborn: Need = null
	for need in run.needs():
		if need.id == &"co2":
			reborn = need
	_check("a restarted run gets a fresh CO2 need", reborn != null and reborn != co2)
	if reborn != null:
		_check("which is in play from the off, because the scrubber is already broken",
			reborn.active)
		_check("and full (%.2f)" % reborn.fraction(), reborn.fraction() > 0.9)
	_check("the restarted run is not still marked finished", not run.finished)

	_finish()


func _finish() -> void:
	paused = false
	if _failures.is_empty():
		print("SUPPLIES TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("SUPPLIES TEST FAIL")
		quit(1)
