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

	var thirst := run.need_by_id(&"thirst")
	var bladder := run.need_by_id(&"bladder")
	var septic := run.need_by_id(&"overflow")
	_check("the run has thirst, bladder and a septic countdown",
		thirst != null and bladder != null and septic != null)
	if thirst == null or bladder == null or septic == null:
		return _finish()

	# --- link 0: thirst arrives on a schedule, not at minute zero -------------
	# The staggering (17d). Six live needs do not fit in 240 seconds of air; needs that turn up
	# on different days do.
	_check("thirst is not waiting for you when you wake up", not thirst.active)
	_check("nor is the bladder", not bladder.active)
	_check("nor the septic tank", not septic.active)

	run.days_elapsed = thirst.starts_after_days + 0.1
	await _frames(2)
	_check("it arrives once the voyage has gone on long enough", thirst.active)
	_check("but the bladder still has no reason to exist", not bladder.active)

	# --- link 1: drinking clears the thirst and starts the bladder ------------
	var beer_before := beer.level
	_check("there is beer in the silo", beer.use())
	await _frames(2)
	_check("drinking clears the thirst (%.2f)" % thirst.fraction(), thirst.fraction() > 0.9)
	_check("and costs a measure (%.2f -> %.2f)" % [beer_before, beer.level],
		beer.level < beer_before)
	_check("AND STARTS THE BLADDER — this is the chain", bladder.active)

	# A second beer must not silently re-arm a bladder that is already running, or the second
	# beer would be free.
	bladder.advance(30.0)
	var pressing := bladder.remaining
	beer.use()
	await _frames(2)
	_check("a second drink does not reset the bladder (%.1f -> %.1f)"
		% [pressing, bladder.remaining], bladder.remaining <= pressing)

	# --- link 2: using the toilet clears the bladder and fills the tank -------
	var tank_before := toilet.level
	_check("the toilet can be used", toilet.use())
	await _frames(2)
	_check("which clears the bladder (%.2f)" % bladder.fraction(), bladder.fraction() > 0.9)
	_check("and fills the tank (%.2f -> %.2f)" % [tank_before, toilet.level],
		toilet.level > tank_before)

	# --- link 3: a full tank is a countdown to a bad end ----------------------
	_check("no septic countdown while there is room", not septic.active)
	while not toilet.is_exhausted():
		toilet.use()
	await _frames(2)
	_check("filling it starts the septic countdown", septic.active)
	_check("which is on the HUD immediately — there is no gentle phase",
		run.pressing_needs().has(septic))
	_check("and it is the lethal one", septic.lethal)
	# The toilet does NOT refuse you once full. The overflow is the consequence.
	_check("a full toilet still accepts you", toilet.use())

	# --- link 4: the way out is a walk to the cargo bay -----------------------
	var empty_can := _make(game, "canister", &"empty")
	_check("an empty canister pumps it out", toilet.service(empty_can))
	await _frames(2)
	_check("which stops the septic countdown", not septic.active)
	_check("and takes it off the HUD", not run.pressing_needs().has(septic))
	_check("leaving you holding the consequence (%s)" % empty_can.kind,
		empty_can.kind == &"shit")

	# ...and an air canister you have already spent becomes one of those empties, which is the
	# loop closing on itself.
	var air := _make(game, "canister", &"o2")
	var life := run.silo_by_id(&"life_support")
	if life != null:
		while life.use():
			pass
		life.service(air)
		_check("a spent air canister becomes an empty for the toilet (%s)" % air.kind,
			air.kind == &"empty" and air.matches(toilet.accepts))

	# --- an unmet need costs you walking speed --------------------------------
	# 17e: only CO2 and the tank kill you; everything else makes the rest of the run harder.
	# The currency here is seconds outside the pod, so a fifth off your speed is a fifth more
	# air on every future trip.
	var player: CharacterBody3D = game.get_node("Player")
	var full_speed: float = player.max_speed
	_check("you start at full speed (%.2f)" % full_speed, full_speed > 0.0)
	bladder.advance(bladder.seconds + 1.0)
	await _frames(2)
	_check("an expired bladder slows you down (%.2f -> %.2f)" % [full_speed, player.max_speed],
		player.max_speed < full_speed)
	toilet.use()
	await _frames(2)
	_check("and dealing with it gives the speed back (%.2f)" % player.max_speed,
		is_equal_approx(player.max_speed, full_speed))

	# --- and if you leave it, it goes off -------------------------------------
	while not toilet.is_exhausted():
		toilet.use()
	await _frames(2)
	_check("the run is still going", not run.finished)
	septic.remaining = 0.05
	await _frames(30)
	_check("letting the tank go ends the run", run.finished)
	var summary := run.summary()
	_check("with the least dignified death in the game (%s)" % summary.get("end_title", ""),
		summary.get("end_title", "") == "SEPTIC")

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
