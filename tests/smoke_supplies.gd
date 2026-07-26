extends SceneTree
# TODO 17 Phase 2: the CO2 countdown, end to end in the real game scene.
#
# smoke_needs.gd owns the component logic in isolation. This owns the WIRING — that a run
# actually has a life-support silo standing where the player can see one, canisters in the
# cargo bay, everything carryable resting on the floor rather than in the air, and an engine
# core whose running dry stops the ship.
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


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


## Bottom of the lowest VISIBLE mesh under a node, in world space. Visible only, because the
## canister carries all four of its kinds and the three it is not currently showing are still
## in the tree.
func _lowest_visible_point(node: Node3D) -> float:
	var lowest := INF
	for entry in _meshes(node):
		var mesh := entry as MeshInstance3D
		if not mesh.visible:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	return lowest


func _meshes(node: Node) -> Array:
	var out := []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


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

	# The life-support tank is an OxygenSilo now, not a Silo (TODO 21e): it holds a CANISTER
	# you can see rather than a 0..1 level, and it refills the run's own air rather than
	# clearing a countdown. So it is not in the silo group and is not looked up by id.
	var tank := supplies.oxygen_silo()
	_check("the ship has an oxygen tank", tank != null)
	if tank == null:
		return _finish()
	_check("in life support, not floating in the hull (%s)"
		% ship.room_at(tank.global_position),
		ship.room_at(tank.global_position) == "life_support")
	# It starts with a SPENT canister in the cradle — the bottle whoever was awake last used —
	# so the object the player will be swapping is in front of them before it matters.
	_check("with a spent canister already in it (%s)"
		% ("none" if tank.fitted() == null else tank.fitted().kind),
		tank.fitted() != null and tank.fitted().kind == tank.spent_kind)
	# And it is IN the cradle, not on the floor beside it. A canister is a RigidBody3D, so a
	# local offset is ignored — the physics server owns the transform and puts it straight back.
	var cradle: Node3D = tank.find_child("Socket", true, false)
	if cradle != null:
		# Its BASE on the cradle, not its origin: a canister prop centres its mesh on its body
		# so it hangs right when carried, so dropping the origin onto the shelf buries half of
		# it. What matters is where the bottom of the thing you can see ends up.
		var base := _lowest_visible_point(tank.fitted())
		_check("standing ON the cradle, not sunk into it (base %+.3f vs %+.3f)"
			% [base, cradle.global_position.y],
			absf(base - cradle.global_position.y) < 0.08)

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
	_check("stocked with what the tank takes (%s)" % cans[0].kind,
		cans[0].matches(tank.accepts))

	# --- everything you can pick up is actually ON THE FLOOR ------------------
	# Two shipped bugs came out of this check and neither was visible in a screenshot. Model
	# origins are at the BASE, so a prop whose mesh is not dropped by half its height rests a
	# quarter of a metre in the air; and CD_Battery_v1 ships a StaticBody3D on its Socket mesh,
	# which inside a RigidBody is a second collider the engine drags around — it launched the
	# power cells TWENTY-ONE METRES through the hull on the first physics frame.
	#
	# Measured after letting physics settle, because both failures only exist once the body has
	# fallen: the spawn position is right in every case.
	await _physics_frames(150)
	for supply in supplies.canisters():
		var body := supply as Node3D
		var base := _lowest_visible_point(body)
		_check("a %s rests on the floor rather than in the air (mesh base %+.2f)"
			% [supply.kind, base], base < 0.05)
		_check("and is still inside the ship (%s at y %.1f)"
			% [supply.kind, body.global_position.y],
			ship.room_at(body.global_position) != "")

	# --- CO2 is PARKED --------------------------------------------------------
	# This suite used to walk the CO2 countdown end to end from here: the scrubber breaking,
	# the clock ticking awake and stopping in stasis, the HUD row, the silo clearing it, and
	# CO2 NARCOSIS. All of it is gone for now, not because it broke but because CO2 is waiting
	# on a silo of its own that has not been modelled (TODO 21f) — the life-support tank holds
	# OXYGEN now. Put this back when the tank exists; the mechanism it tested is untouched and
	# still covered by smoke_needs.
	_check("the CO2 need really is parked, not half-wired",
		run.need_by_id(&"co2") == null)

	# --- the drive's power ----------------------------------------------------
	# Fuel used to be a consumable slotted into a silo. It is a BATTERY ON A CABLE now
	# (TODO 21c): the engine core runs flat, and you charge a battery at the bay's wall socket
	# and run a cable into the engine. So there is no fuel tank to find — there is a fault.
	var core: Malfunction = null
	for node in game.get_tree().get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		if (node as Malfunction).system_name == "ENGINE CORE":
			core = node
	_check("the ship has an engine core fault", core != null)
	if core != null:
		_check("in the engine room (%s)" % ship.room_at(core.global_position),
			ship.room_at(core.global_position) == "engine_room")
		_check("with an inlet to feed it",
			core.get_parent().find_child("CoreInlet", true, false) != null)
		# It STOPS the ship rather than slowing it — the one fault that bypasses the speed
		# floor the rest of them share.
		core.break_now()
		await _frames(2)
		_check("a depleted core stops the ship dead (%.3f)" % run.speed_fraction(),
			is_zero_approx(run.speed_fraction()))
		_check("and it is a critical failure, so the klaxon goes", core.is_critical())
		core.repair(true, 50.0)
		await _frames(2)
		_check("feeding it gets the ship moving again (%.3f)" % run.speed_fraction(),
			run.speed_fraction() > 0.5)

	# --- a restarted run rebuilds cleanly --------------------------------------
	# Worth keeping even with CO2 parked: `finished` has to be cleared BEFORE the needs are
	# spawned, or a second run opens with its opening need switched off — only on the second
	# run, which is the worst kind of bug. This is the test that caught that ordering.
	run.running = false
	run.start()
	await _frames(2)
	_check("the restarted run is not still marked finished", not run.finished)
	_check("and it rebuilt its silos (%d)" % run.silos().size(), run.silos().size() >= 3)

	_finish()


## A fresh power cell, for testing the refuel without walking one across the ship.
func _make_cell(game: Node) -> Consumable:
	var scene: PackedScene = load("res://scenes/props/power_cell.tscn")
	var node: Node = scene.instantiate()
	game.add_child(node)
	var view: Node3D = node
	return view as Consumable


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
