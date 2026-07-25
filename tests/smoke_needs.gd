extends SceneTree
# TODO 17 Phase 1: the three components the six needs are all built out of — Need, Silo,
# Consumable.
#
# ONE suite for the component pair, not six near-identical ones, which is the whole claim of
# 17a: hunger, thirst, bladder, CO2, power and the crap tank are the same mechanic configured
# six ways. If that claim is true this file can prove all of it; if it needs a seventh section
# per system, the claim was false and the design should be revisited rather than the test
# extended.
#
# Builds every fixture in code — the `_make_plug()` technique from smoke_cable_drag.gd. Two
# reasons, and both matter: `scenes/game.tscn` is locked for editing elsewhere so there is
# nothing placed to test against, and a suite about component logic must not be decided by
# whatever furniture happens to be in the ship this week (which is exactly how the cable suite
# broke when the bridge was furnished).
#
# Run: godot --headless --path . -s tests/smoke_needs.gd

var _failures: Array[String] = []
var _world: Node3D


func _init() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("needs test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


# --- fixtures ---------------------------------------------------------------

# Consumable and Silo are Interactable scripts, so they extend Node3D — a SIBLING branch of
# RigidBody3D/StaticBody3D as far as the parser is concerned, and `body as Consumable` is a
# compile-time "invalid cast" even though it is exactly what the prop scenes do. Re-viewing
# the body through a Node3D-typed variable first is how smoke_cable_drag's _make_plug() gets
# round the same wall.
func _make_consumable(kind: StringName, amount: float = 0.5,
		becomes: Dictionary = {}) -> Consumable:
	var body := RigidBody3D.new()
	body.set_script(load("res://scripts/game/consumable.gd"))
	var view: Node3D = body
	var item := view as Consumable
	item.kind = kind
	item.amount = amount
	item.becomes = becomes
	_world.add_child(body)
	return item


func _make_silo(id: StringName, mode: Silo.Mode, accepts: StringName,
		level: float, use_amount: float = 0.25) -> Silo:
	var body := StaticBody3D.new()
	body.set_script(load("res://scripts/game/silo.gd"))
	var view: Node3D = body
	var silo := view as Silo
	silo.silo_id = id
	silo.mode = mode
	silo.accepts = accepts
	silo.level = level
	silo.use_amount = use_amount
	_world.add_child(body)
	return silo


func _make_need(id: StringName, seconds: float, warn_at: float = 0.4) -> Need:
	var node := Node.new()
	node.set_script(load("res://scripts/game/need.gd"))
	var need := node as Need
	need.id = id
	need.seconds = seconds
	need.warn_at = warn_at
	_world.add_child(node)
	return need


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	await process_frame

	_test_consumable()
	_test_supply_silo()
	_test_waste_silo()
	_test_need()
	_test_the_chain()

	if _failures.is_empty():
		print("NEEDS TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("NEEDS TEST FAIL")
		quit(1)


# --- Consumable -------------------------------------------------------------

func _test_consumable() -> void:
	# The canister cycle, which is the reason `becomes` exists: an air canister you have
	# emptied into life support is an EMPTY canister, and an empty canister is what the crap
	# tank needs pumping into. Solving one problem hands you the next one, as an object.
	var can := _make_consumable(&"o2", 0.5, {&"o2": &"empty", &"empty": &"shit"})

	_check("a canister matches its own kind", can.matches(&"o2"))
	_check("and nothing else", not can.matches(&"beer") and not can.matches(&""))

	var log: Array = []
	can.spent.connect(func(was: StringName, became: StringName) -> void:
		log.append([was, became]))

	_check("spending an air canister leaves an empty one in your hands", can.spend())
	_check("which is now an empty (%s)" % can.kind, can.kind == &"empty")
	_check("and no longer services life support", not can.matches(&"o2"))
	_check("but does service the crap tank", can.matches(&"empty"))

	_check("spending the empty leaves a full one", can.spend())
	_check("of the thing you were dreading (%s)" % can.kind, can.kind == &"shit")

	# End of the line: nothing maps `shit` on to anything, so it is used up.
	_check("spending that one uses it up", not can.spend())
	_check("and it is marked spent", can.is_spent)
	_check("a spent canister services nothing", not can.matches(&"shit"))
	_check("spending it again is a no-op", not can.spend())
	_check("three spends were reported (%s)" % str(log), log.size() == 3
		and log[0] == [&"o2", &"empty"] and log[2] == [&"shit", &""])

	# A one-shot with no cycle — food, a spare part.
	var cake := _make_consumable(&"food", 1.0)
	_check("a consumable with no cycle is used up in one go", not cake.spend())
	_check("and is spent", cake.is_spent)


# --- Silo, the SUPPLY half --------------------------------------------------

func _test_supply_silo() -> void:
	var silo := _make_silo(&"life_support", Silo.Mode.SUPPLY, &"o2", 1.0, 0.25)
	# Counters live in ARRAYS because a GDScript lambda captures by VALUE: `var n := 0`
	# incremented inside a `func()` increments the lambda's own copy and the outer variable
	# never moves, so every count below silently read zero and four real assertions passed
	# vacuously. An Array is a reference, so mutating it is visible out here.
	var exhausted: Array[int] = [0]
	silo.exhausted.connect(func(_s: Silo) -> void: exhausted[0] += 1)

	_check("a full supply silo has full headroom (%.2f)" % silo.headroom(),
		is_equal_approx(silo.headroom(), 1.0))
	_check("with four uses in it (%d)" % silo.uses_left(), silo.uses_left() == 4)

	_check("using it works", silo.use())
	_check("and takes a quarter out (%.2f)" % silo.level, is_equal_approx(silo.level, 0.75))
	_check("three uses left (%d)" % silo.uses_left(), silo.uses_left() == 3)

	for i in 3:
		silo.use()
	_check("draining it empties it (%.2f)" % silo.level, silo.level <= 0.0)
	_check("it reports exhausted", silo.is_exhausted())
	_check("and said so exactly once (%d)" % exhausted[0], exhausted[0] == 1)
	_check("an empty supply cannot be used", not silo.use())

	# --- servicing it ---------------------------------------------------------
	var wrong := _make_consumable(&"beer", 0.5)
	_check("the wrong canister is refused", not silo.service(wrong))
	_check("and is NOT spent by the refusal", not wrong.is_spent and wrong.kind == &"beer")

	var can := _make_consumable(&"o2", 0.5, {&"o2": &"empty"})
	_check("the right canister is accepted", silo.service(can))
	_check("and puts half a tank in (%.2f)" % silo.level, is_equal_approx(silo.level, 0.5))
	_check("the silo is usable again", not silo.is_exhausted() and silo.use())
	_check("the canister is now an empty, still in your hands (%s)" % can.kind,
		can.kind == &"empty" and not can.is_spent)
	_check("so the game does not take it off you", not silo.consumed_last_item())

	# A canister with nowhere to go IS taken off you — the spare-part precedent, and the hook
	# Interactor already checks.
	var one_shot := _make_consumable(&"o2", 0.5)
	silo.service(one_shot)
	_check("a canister with no next life is consumed", silo.consumed_last_item()
		and one_shot.is_spent)

	# --- a full silo must reject the can, not swallow it ----------------------
	var full := _make_silo(&"beer", Silo.Mode.SUPPLY, &"beer", 1.0)
	var spare := _make_consumable(&"beer", 0.5)
	_check("a full silo refuses a canister", not full.service(spare))
	_check("and the trip is not wasted — the can is untouched",
		not spare.is_spent and spare.kind == &"beer")


# --- Silo, the WASTE half ---------------------------------------------------
#
# The same script with one sign flipped. If this section needed anything Silo does not already
# do for the supply case, the "it is one mechanic" claim of 17a would be wrong.

func _test_waste_silo() -> void:
	var toilet := _make_silo(&"crap", Silo.Mode.WASTE, &"empty", 0.0, 0.25)
	# A toilet that politely declines is a worse outcome than one that overflows: the overflow
	# is the consequence the explosion countdown hangs off.
	toilet.block_when_exhausted = false
	var exhausted: Array[int] = [0]
	toilet.exhausted.connect(func(_s: Silo) -> void: exhausted[0] += 1)

	_check("an empty waste tank has full headroom (%.2f)" % toilet.headroom(),
		is_equal_approx(toilet.headroom(), 1.0))
	_check("using it FILLS it rather than emptying it", toilet.use()
		and is_equal_approx(toilet.level, 0.25))
	_check("and headroom falls as it fills (%.2f)" % toilet.headroom(),
		is_equal_approx(toilet.headroom(), 0.75))
	_check("three flushes left (%d)" % toilet.uses_left(), toilet.uses_left() == 3)

	for i in 3:
		toilet.use()
	_check("filling it reports exhausted", toilet.is_exhausted())
	_check("exactly once (%d)" % exhausted[0], exhausted[0] == 1)
	_check("and it does NOT refuse you — it overflows", toilet.use())
	_check("clamped at full (%.2f)" % toilet.level, is_equal_approx(toilet.level, 1.0))

	# Pumping it out is `service`, with an EMPTY can — which is why `accepts` cannot be
	# derived from the mode.
	var empty_can := _make_consumable(&"empty", 0.5, {&"empty": &"shit"})
	_check("an empty canister services the tank", toilet.service(empty_can))
	_check("and takes half of it away (%.2f)" % toilet.level,
		is_equal_approx(toilet.level, 0.5))
	_check("leaving you holding the consequence (%s)" % empty_can.kind,
		empty_can.kind == &"shit" and not empty_can.is_spent)
	_check("the toilet works again", not toilet.is_exhausted())

	var full_can := _make_consumable(&"o2", 0.5)
	_check("a FULL canister is no use on a waste tank", not toilet.service(full_can))


# --- Need -------------------------------------------------------------------

func _test_need() -> void:
	var need := _make_need(&"co2", 10.0, 0.4)
	var warns: Array[int] = [0]
	var expiries: Array[int] = [0]
	need.warned.connect(func(_n: Need) -> void: warns[0] += 1)
	need.expired.connect(func(_n: Need) -> void: expiries[0] += 1)

	# Staggering (17d) depends entirely on this: a need not chosen for the run must be inert,
	# not merely hidden. Six live countdowns do not fit in 240 seconds of air.
	_check("a need starts out of play", not need.active)
	need.advance(5.0)
	_check("and an inactive need does not tick (%.1f)" % need.remaining,
		is_equal_approx(need.remaining, 10.0))

	need.start()
	_check("starting it puts it in play, full", need.active and need.fraction() == 1.0)
	_check("and it is not pressing yet", not need.is_pressing())

	need.advance(5.0)
	_check("it ticks while awake (%.1f)" % need.remaining, is_equal_approx(need.remaining, 5.0))
	_check("still above the warning line, so no row yet (%.2f)" % need.fraction(),
		warns[0] == 0 and not need.is_pressing())

	need.advance(2.0)
	_check("crossing the threshold warns (%.2f)" % need.fraction(),
		need.fraction() <= 0.4 and warns[0] == 1)
	_check("which is what puts it on the HUD", need.is_pressing())
	need.advance(1.0)
	_check("and it only warns once (%d)" % warns[0], warns[0] == 1)

	need.advance(10.0)
	_check("it bottoms out at zero (%.1f)" % need.remaining, need.remaining == 0.0)
	_check("and expires", expiries[0] == 1 and need.has_expired)
	need.advance(1.0)
	_check("an expired need stops ticking, so it cannot expire twice (%d)" % expiries[0],
		expiries[0] == 1)

	# `start()` is idempotent BECAUSE of the chain: drinking a second beer must not silently
	# reset a bladder that is already running, or the second beer would be free.
	var bladder := _make_need(&"bladder", 20.0)
	bladder.start()
	bladder.advance(8.0)
	bladder.start()
	_check("starting an already-running need does not refill it (%.1f)" % bladder.remaining,
		is_equal_approx(bladder.remaining, 12.0))

	bladder.satisfy()
	_check("satisfying it does (%.1f)" % bladder.remaining,
		is_equal_approx(bladder.remaining, 20.0))


# --- The chain (17c) --------------------------------------------------------
#
# Drink the beer -> you need the toilet -> the tank fills -> it needs pumping out. The part of
# section 17 worth protecting, because it is the only place in the game where SOLVING a problem
# is what CREATES the next one. Assembled here from the three components with no extra script,
# which is the evidence that Phase 1 is actually enough to build it out of.

func _test_the_chain() -> void:
	var beer := _make_silo(&"beer", Silo.Mode.SUPPLY, &"beer", 1.0, 0.25)
	var toilet := _make_silo(&"crap", Silo.Mode.WASTE, &"empty", 0.0, 0.25)
	var thirst := _make_need(&"thirst", 60.0)
	var bladder := _make_need(&"bladder", 30.0)
	thirst.triggers = &"bladder"
	thirst.silo_id = &"beer"
	bladder.silo_id = &"crap"

	# The link Need deliberately does NOT make itself: it carries `triggers` as data and the
	# owner does the lookup, because a need has no business knowing about the others.
	var needs := {&"thirst": thirst, &"bladder": bladder}
	thirst.satisfied.connect(func(_n: Need, triggers: StringName) -> void:
		if needs.has(triggers):
			(needs[triggers] as Need).start())

	thirst.start()
	thirst.advance(50.0)
	_check("thirst is getting on", thirst.fraction() < 0.4)
	_check("and the bladder is not in play yet", not bladder.active)

	# Drink: use the silo, satisfy the need.
	_check("there is beer in the silo", beer.use())
	thirst.satisfy()
	_check("drinking clears the thirst", thirst.fraction() == 1.0)
	_check("and starts the bladder — the chain", bladder.active and bladder.fraction() == 1.0)
	_check("at the cost of a quarter of the beer (%.2f)" % beer.level,
		is_equal_approx(beer.level, 0.75))

	# Use the toilet: satisfies the bladder, fills the tank.
	bladder.advance(25.0)
	_check("using the toilet works", toilet.use())
	bladder.satisfy()
	_check("which clears the bladder", bladder.fraction() == 1.0)
	_check("and fills the crap tank (%.2f)" % toilet.level,
		is_equal_approx(toilet.level, 0.25))

	# Four flushes and the tank has nowhere left to go.
	for i in 3:
		toilet.use()
	_check("four flushes fills it", toilet.is_exhausted())

	# The only way out is a trip to the cargo bay for empties.
	var empties: Array[Consumable] = []
	for i in 2:
		empties.append(_make_consumable(&"empty", 0.5, {&"empty": &"shit"}))
	for can in empties:
		toilet.service(can)
	_check("two empties clear it (%.2f)" % toilet.level, toilet.level <= 0.0)
	_check("and you are now holding two cans of it",
		empties[0].kind == &"shit" and empties[1].kind == &"shit")
