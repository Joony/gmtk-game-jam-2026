extends SceneTree
# TODO 17c, in the real ship: drink the beer -> you need the toilet -> the tank fills -> it goes
# off unless you walk empties to it.
#
# This is the only place in the game where SOLVING a problem is what CREATES the next one, which
# is why the spec says that if any of section 17 has to be cut, cut around this chain rather
# than through it. It gets its own suite for the same reason: buried as a section inside
# smoke_supplies it would be the thing quietly deleted to make a failing file pass.
#
# smoke_needs already proves the chain can be ASSEMBLED from the three components. What is new
# here is that the ship actually has a beer silo in the mess and a toilet in the bathroom, that
# the cargo bay stocks both halves, and that the run wires the links.
#
# Run: godot --headless --path . -s tests/smoke_chain.gd

const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []


func _init() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("chain test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _stock(supplies: ShipSupplies, kind: StringName) -> int:
	var n := 0
	for item in supplies.canisters():
		if item.kind == kind:
			n += 1
	return n


func _run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	_check("the opening stasis lets go", await Opening.wake(self, game))

	var run: RunState = game.get_node("Run")
	var ship: RoomBuilder = game.get_node("Ship")
	var supplies: ShipSupplies = game.get_node("Supplies")

	# --- both ends of the chain are standing in the ship ----------------------
	var beer := run.silo_by_id(&"beer")
	var toilet := run.silo_by_id(&"crap")
	_check("there is a beer silo", beer != null)
	_check("and a toilet", toilet != null)
	if beer == null or toilet == null:
		return _finish()

	_check("the beer is in the mess (%s)" % ship.room_at(beer.global_position),
		ship.room_at(beer.global_position) == "kitchen")
	_check("the toilet is in the bathroom (%s)" % ship.room_at(toilet.global_position),
		ship.room_at(toilet.global_position) == "bathroom")
	_check("the toilet FILLS rather than empties", toilet.mode == Silo.Mode.WASTE)
	_check("and it starts empty (%.2f)" % toilet.level, toilet.level <= 0.0)
	_check("it takes empty canisters", toilet.accepts == &"empty")
	# Deliberately fewer empties than beers: running the mess dry and running out of empties
	# are the same mistake seen from two ends.
	_check("the cargo bay stocks beer (%d)" % _stock(supplies, &"beer"),
		_stock(supplies, &"beer") >= 2)
	_check("and empties (%d)" % _stock(supplies, &"empty"), _stock(supplies, &"empty") >= 2)

	# --- THE CHAIN IS PARKED --------------------------------------------------
	# This suite used to walk it end to end: thirst arrives on a schedule, drinking starts the
	# bladder, the toilet fills the septic tank, a full tank is a lethal countdown, and empties
	# from the cargo bay are the way out. Thirst has been removed, so nothing starts any of it,
	# and the beer silo / septic tank are out of scope (TODO 21 scope note).
	#
	# None of it was deleted — the needs, the waste silo and the canister cycle all still exist
	# and are still covered by smoke_needs, which builds its own fixtures. Put this back when
	# thirst does.
	_check("thirst really is gone, not half-wired", run.need_by_id(&"thirst") == null)
	_check("so the bladder is dormant, not running",
		run.need_by_id(&"bladder") == null or not run.need_by_id(&"bladder").active)

	# --- hunger: the sixth system, and the proof that none of this is special-cased ----
	# TODO 17e worried hunger had "an extra hop" — hungry, vending machine, food crate. It does
	# not: every other need is need, silo in a room, canister from cargo. Same three steps. So
	# the vending machine is a Silo and a food crate is a Consumable, and hunger needed no new
	# script, no new field and no branch anywhere. If any of the assertions below had required
	# one, 17a's "it is one mechanic six times over" would have been wrong.
	var vending := run.silo_by_id(&"food")
	var hunger := run.need_by_id(&"hunger")
	_check("there is a vending machine", vending != null)
	_check("and a hunger countdown", hunger != null)
	if vending != null and hunger != null:
		_check("the machine is in the mess (%s)" % ship.room_at(vending.global_position),
			ship.room_at(vending.global_position) == "kitchen")
		_check("it takes food crates", vending.accepts == &"food")
		_check("which the cargo bay stocks (%d)" % _stock(supplies, &"food"),
			_stock(supplies, &"food") >= 2)

		_check("hunger arrives well into the voyage rather than at minute zero (%.0f days)"
			% hunger.starts_after_days, hunger.starts_after_days > 5.0)
		run.days_elapsed = hunger.starts_after_days + 0.1
		await _frames(2)
		_check("and it does arrive", hunger.active)

		# THE PROP IS THE SILO. Not a body standing invisibly beside it: adoption attaches the
		# script to the dressed-in machine itself, so the thing the player can see is the thing
		# they can use, with no second collider to fight and no alignment to keep. It also
		# means Interactor's walk UP from whatever the ray hits lands on a real Interactable —
		# which is what stopped working when the tanks were redressed with a model that brings
		# its own collision.
		_check("the functional machine IS the dressed-in prop",
			vending == game.get_node("Decor/MessVending"))

		# Run it down FIRST. Eating while already full proves nothing — the earlier version of
		# this assertion passed with hunger wired to a silo that does not exist.
		hunger.advance(hunger.seconds * 0.8)
		var starving := hunger.fraction()
		_check("hunger can be run down (%.2f)" % starving, starving < 0.3)
		# --- the nine pigeonholes ---------------------------------------------
		# The machine is counted in slots you can SEE, so the display and the silo must not be
		# able to disagree. VendingStock is a view over `level` rather than a second tally,
		# which is what makes that structurally true; these check it holds in practice.
		var display: VendingStock = vending.get_node_or_null("Stock")
		_check("the machine shows what is in it", display != null)
		if display != null:
			_check("with nine pigeonholes (%d)" % display.slot_count(),
				display.slot_count() == 9)
			_check("three of them full to start (%d)" % display.occupied(),
				display.occupied() == 3)
			_check("and the silo agrees (%d uses)" % vending.uses_left(),
				vending.uses_left() == 3)
			# One of each, not three of the same: the item type rotates as holes are filled.
			var kinds := {}
			for kind in display.contents():
				if kind >= 0:
					kinds[kind] = true
			_check("one cake, one can, one plant (%d distinct)" % kinds.size(),
				kinds.size() == 3)

			vending.use()
			await _frames(2)
			_check("buying something empties a hole (%d)" % display.occupied(),
				display.occupied() == 2)

			var restock := _make(game, "food_crate", &"food")
			vending.service(restock)
			await _frames(2)
			_check("a crate fills three more (%d)" % display.occupied(),
				display.occupied() == 5)
			_check("and the silo still agrees (%d)" % vending.uses_left(),
				vending.uses_left() == 5)

			# Empty it the whole way. The last item is where ninths-in-binary bites: without
			# the epsilon in Silo the machine reports empty with one still on the shelf.
			while vending.use():
				pass
			await _frames(2)
			_check("emptying it clears every hole (%d left)" % display.occupied(),
				display.occupied() == 0)
			_check("and the machine knows it is empty", vending.is_exhausted())

			# An empty machine is a WARNING, not a fault. Nothing is broken and there is
			# nothing to repair — the answer is a walk — so it must not wear the same red "!"
			# as a ruptured coolant line, or the player learns to distrust the colour.
			var readout: CanvasLayer = game.get_node("HUD")
			_check("an empty machine is amber, not fault red",
				readout._silo_color(vending) == readout.COLOR_WARN)
			_check("and marked as a warning, not a fault (%s)" % readout._silo_line(vending),
				readout._silo_line(vending).begins_with("~"))

			# The fuel tank is the one exception, and it earns it: running dry stops the ship.
			var fuel := run.silo_by_id(&"power")
			if fuel != null:
				fuel.advance(100.0)
				_check("but a dry fuel tank IS a fault — it stops the ship",
					fuel.is_exhausted() and readout._silo_color(fuel) == readout.COLOR_CRIT
						and readout._silo_line(fuel).begins_with("!"))
				fuel.service(_make(game, "power_cell", &"battery"))

			# --- the machine can also just break ------------------------------
			# Not a bespoke "out of order" flag: an ordinary Malfunction with an ordinary
			# repair hatch, so a jammed dispenser is a spare part or a hammer bodge, shows up
			# in the HUD fault list, and sounds like every other repair on the ship.
			var fault := vending.malfunction
			_check("the machine has a fault of its own", fault != null)
			if fault != null:
				_check("which is in the ship's fault list",
					run.malfunctions().has(fault))
				_check("and is a MINOR problem, not a drive one (%.2f)" % fault.speed_penalty,
					is_zero_approx(fault.speed_penalty)
						and fault.severity == Malfunction.Severity.DEGRADING)
				# It fires at a random point in the voyage, unlike every other fault, so all
				# that can be asserted is that it is scheduled to happen at all and within the
				# window the table declares.
				_check("scheduled to break somewhere mid-voyage (%.1f)" % fault.fire_at_distance,
					fault.fire_at_distance >= 30.0 and fault.fire_at_distance <= 62.0)

				var hatch: RepairPoint = null
				for child in fault.get_children():
					if child is RepairPoint:
						hatch = child
				_check("with a repair hatch bound to it",
					hatch != null and hatch.malfunction == fault)

				# Restock it FIRST, so "cannot be used" below is about the fault and not about
				# an empty machine.
				vending.service(_make(game, "food_crate", &"food"))
				await _frames(2)
				_check("there is food in it", not vending.is_exhausted())

				fault.break_now(false)
				await _frames(2)

				# It has to actually SHOW UP as a ship problem — that is what makes a jammed
				# machine feel like part of the same game as a coolant leak. And its row must
				# not claim a drive cost it does not have: "(-0% drive)" reads as a broken
				# readout rather than as a fault that simply does not slow the ship.
				var hud: CanvasLayer = game.get_node("HUD")
				var row: String = hud._fault_line(fault)
				_check("the fault gets a HUD row naming the machine (%s)" % row,
					row.contains(fault.system_name) and row.contains(fault.fault_text))
				_check("and does not claim a drive cost it has not got", not row.contains("drive"))

				_check("a broken machine will not serve you", not vending.use())
				_check("and says why (%s)" % vending.get_interaction_text(),
					vending.get_interaction_text().contains(fault.fault_text))
				_check("the reticle does not promise anything", not vending.can_act_on())
				# It will not take a crate either. It is out of order, not merely empty — the
				# mechanism that would hold the stock is the thing that has failed. The wasted
				# trip is the intended cost: it is what makes repairing it first, rather than
				# hopefully, the right move.
				_check("and it will not take a crate either",
					not vending.service(_make(game, "food_crate", &"food")))
				_check("which the prompt says before you spend the press (%s)"
					% vending.get_interaction_text(_make(game, "food_crate", &"food")),
					vending.get_interaction_text(
						_make(game, "food_crate", &"food")).contains(fault.fault_text))

				# The hammer route: fixed now, broken again soon. bodge_distance is 9 against
				# the ship's 25-33, which is the whole trade for a machine you keep needing.
				_check("a bodge holds for less than any other fault (%.0f)"
					% fault.bodge_distance, fault.bodge_distance < 25.0)

				fault.repair(true)
				await _frames(2)
				_check("repairing it puts the machine back in service", vending.use())

			# Back to a usable machine for the assertions below.
			vending.service(_make(game, "food_crate", &"food"))
			await _frames(2)

		var stock := vending.level
		_check("eating works", vending.use())
		await _frames(2)
		_check("and clears the hunger (%.2f -> %.2f)" % [starving, hunger.fraction()],
			hunger.fraction() > starving + 0.5)
		_check("at the cost of a portion (%.2f -> %.2f)" % [stock, vending.level],
			vending.level < stock)

		while vending.use():
			pass
		_check("the machine empties", vending.is_exhausted())
		var crate := _make(game, "food_crate", &"food")
		_check("a food crate restocks it", vending.service(crate))
		_check("and the crate is gone — it is not a canister", crate.is_spent)
		_check("there is something to eat again", not vending.is_exhausted())
		# Put hunger back to bed so it does not muddy the speed assertions below.
		hunger.stop()
		await _frames(2)

	# --- what an unmet need costs, and the septic ending -----------------------
	# Both parked with the chain: the walking-speed penalty was measured on the bladder and the
	# ending on the septic countdown, and neither starts now that thirst is gone. The mechanism
	# is intact — Need.movement_penalty and the lethal path are still there and still covered by
	# smoke_needs — so this comes back when thirst does.

	_finish()


func _make(game: Node, prop: String, kind: StringName) -> Consumable:
	var scene: PackedScene = load("res://scenes/props/%s.tscn" % prop)
	var node: Node = scene.instantiate()
	game.add_child(node)
	var view: Node3D = node
	var item := view as Consumable
	item.set_kind(kind)
	return item


func _finish() -> void:
	paused = false
	if _failures.is_empty():
		print("CHAIN TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("CHAIN TEST FAIL")
		quit(1)
