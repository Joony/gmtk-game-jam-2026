extends SceneTree

# Step 12: the countdown loop. Every rule the design rests on, asserted.
#
# These are built from bare nodes rather than by loading game.tscn, so each rule is tested
# in isolation and a change to the ship layout cannot quietly turn a real regression into a
# passing test. The full-scene wiring is checked separately at the end.
#
# RunState._process is driven MANUALLY here. Waiting on real frames would make every
# assertion a function of frame timing, and the whole point is to pin down exact rates.

const WATCHDOG_SECONDS := 90.0

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	root.call_deferred("add_child", _Runner.new(self))


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		failures.append(label)
		print("  FAIL %s" % label)


func nearly(a: float, b: float, epsilon: float = 0.001) -> bool:
	return absf(a - b) <= epsilon


## A ShipMotion + RunState pair with no scene around them. `faults` are dictionaries of
## Malfunction property overrides.
func build_run(overrides: Dictionary = {}, faults: Array = []) -> Dictionary:
	var holder := Node.new()
	root.add_child(holder)

	var motion := ShipMotion.new()
	motion.name = "Motion"
	motion.cruise_speed = 20.0
	# The starfield push is irrelevant here and would just walk distance_travelled.
	motion.set_process(false)
	holder.add_child(motion)

	var made: Array[Malfunction] = []
	for spec in faults:
		var malfunction := Malfunction.new()
		for key in spec:
			malfunction.set(key, spec[key])
		holder.add_child(malfunction)
		made.append(malfunction)

	var run := RunState.new()
	run.name = "Run"
	run.motion_path = NodePath("../Motion")
	run.lighting_path = NodePath("../Lighting")
	run.total_distance = 10000.0
	run.oxygen_total = 100.0
	run.stasis_time_scale = 10.0
	for key in overrides:
		run.set(key, overrides[key])
	holder.add_child(run)
	run.start()
	# start() drives speed from the faults; _process is called by hand from here on.
	run.set_process(false)

	return {"holder": holder, "run": run, "motion": motion, "faults": made}


## Advance the run by `seconds`, in `steps` slices. Slicing matters for anything that
## depends on crossing a threshold partway through.
func tick(run: RunState, seconds: float, steps: int = 1) -> void:
	var slice := seconds / float(steps)
	for i in range(steps):
		run._process(slice)


class _Runner:
	extends Node

	var suite: SceneTree


	func _init(owner_suite: SceneTree) -> void:
		suite = owner_suite


	func _ready() -> void:
		_watchdog()
		_run()


	func _watchdog() -> void:
		# A script error inside an awaited coroutine kills it silently, so without this the
		# suite hangs forever instead of failing.
		await suite.create_timer(WATCHDOG_SECONDS).timeout
		if is_inside_tree():
			push_error("smoke_run_state: watchdog fired after %ds" % int(WATCHDOG_SECONDS))
			suite.quit(1)


	func _run() -> void:
		print("== smoke_run_state ==")
		_test_distance_rate()
		_test_speed_penalties()
		_test_oxygen_only_outside_pod()
		_test_pod_does_not_refill()
		_test_stasis_fast_forward()
		_test_schedule_fires_once()
		_test_patch_expires_and_refires()
		_test_permanent_repair_never_refires()
		_test_oxygen_cost_and_bonus()
		_test_scrubber_multiplier()
		_test_win_and_lose_fire_once()
		_test_repair_point_routes()
		await _test_scene_wiring()

		print("-- %d checks, %d failures --" % [suite.checks, suite.failures.size()])
		for failure in suite.failures:
			print("   FAILED: %s" % failure)
		suite.quit(1 if suite.failures.size() > 0 else 0)


	# --- 12a: distance ------------------------------------------------------------

	func _test_distance_rate() -> void:
		print("[distance falls at the ship's speed]")
		var ctx: Dictionary = suite.build_run()
		var run: RunState = ctx["run"]
		suite.tick(run, 10.0)
		# 10s at cruise 20 m/s = 200m.
		suite.check(suite.nearly(run.distance_remaining, 9800.0, 0.01),
			"10s at 20 m/s covers 200m (got %.2f remaining)" % run.distance_remaining)
		ctx["holder"].free()


	func _test_speed_penalties() -> void:
		print("[faults slow the ship, and the loss is additive]")
		var ctx: Dictionary = suite.build_run({}, [
			{"system_name": "A", "speed_penalty": 0.25},
			{"system_name": "B", "speed_penalty": 0.5},
		])
		var run: RunState = ctx["run"]
		var motion: ShipMotion = ctx["motion"]
		var faults: Array[Malfunction] = ctx["faults"]

		suite.check(suite.nearly(motion.speed, 20.0), "undamaged ship runs at cruise")

		faults[0].break_now()
		suite.check(suite.nearly(motion.speed, 15.0),
			"one 25%% fault gives 15 m/s (got %.2f)" % motion.speed)

		faults[1].break_now()
		suite.check(suite.nearly(motion.speed, 5.0),
			"25%% + 50%% gives 5 m/s (got %.2f)" % motion.speed)

		# Penalties can total over 100%; the floor keeps the run finishable.
		faults[0].speed_penalty = 0.7
		faults[1].speed_penalty = 0.7
		run._update_speed()
		suite.check(motion.speed > 0.0 and suite.nearly(motion.speed, 20.0 * run.min_speed_fraction),
			"over-100%% penalty clamps to the floor, not to zero (got %.2f)" % motion.speed)

		faults[0].repair(true)
		faults[1].repair(true)
		suite.check(suite.nearly(motion.speed, 20.0), "repairing everything restores cruise")
		ctx["holder"].free()


	# --- 12b: oxygen --------------------------------------------------------------

	func _test_oxygen_only_outside_pod() -> void:
		print("[oxygen is time spent outside the pod]")
		var ctx: Dictionary = suite.build_run()
		var run: RunState = ctx["run"]

		suite.tick(run, 12.0)
		suite.check(suite.nearly(run.oxygen_remaining, 88.0, 0.01),
			"12s outside costs 12s of air (got %.2f left)" % run.oxygen_remaining)

		# The pod slows breathing rather than stopping it. Balance forced this: with a
		# free pod, sleeping through every fault won the run with the air budget untouched.
		run.enter_stasis()
		suite.tick(run, 30.0)
		suite.check(suite.nearly(run.oxygen_remaining, 77.5, 0.01),
			"30s in the pod costs 30 x 0.35 = 10.5s (got %.2f left)" % run.oxygen_remaining)

		run.exit_stasis()
		suite.tick(run, 5.0)
		suite.check(suite.nearly(run.oxygen_remaining, 72.5, 0.01),
			"the full drain resumes on waking (got %.2f left)" % run.oxygen_remaining)
		ctx["holder"].free()


	func _test_pod_does_not_refill() -> void:
		print("[the pod slows the bleed, it NEVER refuels]")
		# A long journey on purpose: at the default 10km the ship ARRIVES partway through
		# the sleep, _process stops early, and the measured cost comes out short.
		var ctx: Dictionary = suite.build_run({"total_distance": 1000000.0})
		var run: RunState = ctx["run"]
		suite.tick(run, 40.0)
		var before := run.oxygen_remaining
		run.enter_stasis()
		suite.tick(run, 120.0, 60)
		run.exit_stasis()
		# The single most load-bearing rule in the design: air is one pool for the whole
		# run and nothing gives it back except a proper scrubber repair. If sleeping ever
		# tops you up, the budget stops being a budget and the game has no spine.
		suite.check(run.oxygen_remaining < before,
			"a long sleep still costs air (%.2f -> %.2f)" % [before, run.oxygen_remaining])
		suite.check(suite.nearly(run.oxygen_remaining, before - 120.0 * 0.35, 0.01),
			"and costs exactly the stasis rate (got %.2f)" % run.oxygen_remaining)
		ctx["holder"].free()


	# --- 12c: stasis --------------------------------------------------------------

	func _test_stasis_fast_forward() -> void:
		print("[stasis scales SHIP time, not real time]")
		var ctx: Dictionary = suite.build_run()
		var run: RunState = ctx["run"]
		var motion: ShipMotion = ctx["motion"]

		suite.tick(run, 10.0)
		var awake_covered := 10000.0 - run.distance_remaining

		run.enter_stasis()
		suite.check(suite.nearly(motion.time_scale, 10.0),
			"the starfield is told to stream at the scaled rate")
		var before := run.distance_remaining
		suite.tick(run, 10.0)
		var asleep_covered := before - run.distance_remaining

		suite.check(suite.nearly(asleep_covered, awake_covered * 10.0, 0.01),
			"10s asleep covers 10x what 10s awake covers (%.1f vs %.1f)" % [asleep_covered, awake_covered])

		run.exit_stasis()
		suite.check(suite.nearly(motion.time_scale, 1.0), "waking restores the starfield rate")
		ctx["holder"].free()


	# --- 12d: malfunctions --------------------------------------------------------

	func _test_schedule_fires_once() -> void:
		print("[faults fire on schedule, once, and wake you]")
		var ctx: Dictionary = suite.build_run({}, [
			{"system_name": "A", "speed_penalty": 0.2, "fire_at_distance": 9000.0},
		])
		var run: RunState = ctx["run"]
		var fault: Malfunction = ctx["faults"][0]
		var alarms := [0]
		run.alarm.connect(func(_m: Malfunction, _p: bool) -> void: alarms[0] += 1)

		run.enter_stasis()
		suite.tick(run, 1.0, 10)
		suite.check(not fault.is_active, "nothing fires before its distance")

		suite.tick(run, 10.0, 100)
		suite.check(fault.is_active, "the fault fires once distance passes its threshold")
		suite.check(alarms[0] == 1, "exactly one alarm (got %d)" % alarms[0])
		suite.check(not run.in_stasis, "the alarm wakes the player out of the pod")

		suite.tick(run, 20.0, 40)
		suite.check(alarms[0] == 1, "an active fault does not keep re-firing (got %d)" % alarms[0])
		ctx["holder"].free()


	func _test_patch_expires_and_refires() -> void:
		print("[a patch buys distance, then gives out at the same panel]")
		var ctx: Dictionary = suite.build_run({}, [
			{"system_name": "A", "speed_penalty": 0.2, "bodge_distance": 1000.0},
		])
		var run: RunState = ctx["run"]
		var fault: Malfunction = ctx["faults"][0]
		fault.break_now()
		suite.check(fault.is_active, "fault starts broken")

		fault.repair(false, run.distance_remaining)
		suite.check(not fault.is_active and fault.is_patched, "patching clears it and flags the patch")
		suite.check(suite.nearly(run.speed_fraction(), 1.0),
			"a patch restores FULL speed — its cost is that it expires")

		# 900m of travel: not far enough.
		suite.tick(run, 45.0, 45)
		suite.check(not fault.is_active,
			"the patch holds for its distance (%.0fm covered)" % (10000.0 - run.distance_remaining))

		suite.tick(run, 20.0, 40)
		suite.check(fault.is_active, "the patch gives out after bodge_distance")
		suite.check(fault.break_count == 2, "it is the SAME fault breaking again (count %d)" % fault.break_count)
		suite.check(run.patch_failures == 1, "the failure is recorded for the summary")
		suite.check(run.choices.size() > 0 and "gave out" in run.choices[-1],
			"and it is attributable to the player's own choice: '%s'" % run.choices[-1])
		ctx["holder"].free()


	func _test_permanent_repair_never_refires() -> void:
		print("[a fitted part is permanent]")
		var ctx: Dictionary = suite.build_run({}, [
			{"system_name": "A", "speed_penalty": 0.2, "bodge_distance": 500.0},
		])
		var run: RunState = ctx["run"]
		var fault: Malfunction = ctx["faults"][0]
		fault.break_now()
		fault.repair(true, run.distance_remaining)
		suite.check(not fault.is_patched, "a proper fix is not a patch")
		suite.tick(run, 200.0, 200)
		suite.check(not fault.is_active,
			"still fixed after %.0fm" % (10000.0 - run.distance_remaining))
		suite.check(run.repairs_permanent == 1, "counted as a permanent repair")
		ctx["holder"].free()


	func _test_oxygen_cost_and_bonus() -> void:
		print("[air spent as a currency, and the one way it comes back]")
		var ctx: Dictionary = suite.build_run({}, [
			{"system_name": "VENT", "speed_penalty": 0.2, "bodge_oxygen_cost": 25.0},
			{"system_name": "SCRUB", "speed_penalty": 0.1, "repair_oxygen_bonus": 30.0},
		])
		var run: RunState = ctx["run"]
		var faults: Array[Malfunction] = ctx["faults"]

		suite.tick(run, 10.0)  # 90 left
		faults[0].break_now()
		faults[0].repair(false, run.distance_remaining)
		suite.check(suite.nearly(run.oxygen_remaining, 65.0, 0.01),
			"venting to patch costs 25s immediately (got %.2f)" % run.oxygen_remaining)

		faults[1].break_now()
		faults[1].repair(true, run.distance_remaining)
		suite.check(suite.nearly(run.oxygen_remaining, 95.0, 0.01),
			"a proper scrubber fix recovers 30s (got %.2f)" % run.oxygen_remaining)

		# The bonus must never manufacture air above the run's budget.
		faults[1].break_now()
		faults[1].repair(true, run.distance_remaining)
		suite.check(run.oxygen_remaining <= run.oxygen_total + 0.001,
			"recovered air is capped at the run total (got %.2f of %.2f)" % [run.oxygen_remaining, run.oxygen_total])
		ctx["holder"].free()


	func _test_scrubber_multiplier() -> void:
		print("[a scrubber fault makes you breathe harder]")
		var ctx: Dictionary = suite.build_run({}, [
			{"system_name": "SCRUB", "speed_penalty": 0.0, "oxygen_drain_multiplier": 2.0},
		])
		var run: RunState = ctx["run"]
		var fault: Malfunction = ctx["faults"][0]

		suite.tick(run, 10.0)
		suite.check(suite.nearly(run.oxygen_remaining, 90.0, 0.01), "baseline drain is 1x")
		fault.break_now()
		suite.tick(run, 10.0)
		suite.check(suite.nearly(run.oxygen_remaining, 70.0, 0.01),
			"a 2x fault doubles the drain (got %.2f)" % run.oxygen_remaining)
		fault.repair(true, run.distance_remaining)
		suite.tick(run, 10.0)
		suite.check(suite.nearly(run.oxygen_remaining, 60.0, 0.01),
			"fixing it returns the drain to 1x (got %.2f)" % run.oxygen_remaining)
		ctx["holder"].free()


	# --- 12e: end states ----------------------------------------------------------

	func _test_win_and_lose_fire_once() -> void:
		print("[win at distance zero, lose at air zero, each exactly once]")

		var won: Dictionary = suite.build_run({"total_distance": 100.0, "oxygen_total": 1000.0})
		var win_run: RunState = won["run"]
		var win_events := []
		win_run.run_ended.connect(func(w: bool, s: Dictionary) -> void: win_events.append({"won": w, "summary": s}))
		suite.tick(win_run, 30.0, 30)
		suite.check(win_events.size() == 1, "arrival fires once (got %d)" % win_events.size())
		suite.check(win_events.size() == 1 and win_events[0]["won"], "and it is a win")
		suite.check(win_run.distance_remaining >= 0.0, "distance never goes negative")
		suite.tick(win_run, 30.0, 30)
		suite.check(win_events.size() == 1, "and does not fire again after the run ends")
		won["holder"].free()

		var lost: Dictionary = suite.build_run({"total_distance": 1000000.0, "oxygen_total": 5.0})
		var lose_run: RunState = lost["run"]
		var lose_events := []
		lose_run.run_ended.connect(func(w: bool, s: Dictionary) -> void: lose_events.append({"won": w, "summary": s}))
		suite.tick(lose_run, 20.0, 20)
		suite.check(lose_events.size() == 1, "suffocation fires once (got %d)" % lose_events.size())
		suite.check(lose_events.size() == 1 and not lose_events[0]["won"], "and it is a loss")
		suite.check(lose_run.oxygen_remaining == 0.0, "air never goes negative")
		lost["holder"].free()

		# Venting air you do not have has to end the run too, not leave it at zero.
		var vented: Dictionary = suite.build_run({"oxygen_total": 10.0}, [
			{"system_name": "VENT", "speed_penalty": 0.2, "bodge_oxygen_cost": 25.0},
		])
		var vent_run: RunState = vented["run"]
		var vent_events := []
		vent_run.run_ended.connect(func(w: bool, _s: Dictionary) -> void: vent_events.append(w))
		vented["faults"][0].break_now()
		vented["faults"][0].repair(false, vent_run.distance_remaining)
		suite.check(vent_events.size() == 1 and not vent_events[0],
			"venting more air than you have ends the run immediately")
		vented["holder"].free()


	func _test_repair_point_routes() -> void:
		print("[one panel, two routes: empty hands patch, held part fits]")
		var holder := Node.new()
		suite.root.add_child(holder)

		var fault := Malfunction.new()
		fault.system_name = "DRIVE"
		fault.speed_penalty = 0.3
		holder.add_child(fault)

		var panel := RepairPoint.new()
		panel.required_part = "DriveCoupling"
		panel.patch_text = "Clamp it"
		panel.fit_text = "Fit coupling"
		fault.add_child(panel)

		var part := RigidBody3D.new()
		part.name = "DriveCoupling"
		part.add_to_group(&"spare_parts")
		holder.add_child(part)
		var wrong := RigidBody3D.new()
		wrong.name = "PickupCrate"
		holder.add_child(wrong)

		suite.check(panel.malfunction == fault, "the panel binds to its parent fault")
		suite.check(not panel.is_enabled, "a working system's panel is not a ray target")

		fault.break_now()
		suite.check(panel.is_enabled, "breaking the system arms its panel")
		# Without the override the base class would grey this out with empty hands and
		# hide the patch route exactly when it matters.
		suite.check(panel.can_act_on(null), "a broken panel is actionable with empty hands")
		suite.check("Clamp it" in panel.get_interaction_text(null), "empty hands offers the patch")
		suite.check("Fit coupling" in panel.get_interaction_text(part), "the right part offers the proper fix")
		suite.check("Wrong part" in panel.get_interaction_text(wrong), "the wrong part is refused by name")

		# Group membership, not the item's name, is what makes something a spare — a crate
		# you happened to be carrying must never count as one. Checked on a panel with NO
		# `required_part`, which is how every panel in the shipping scene is configured;
		# the panel above deliberately pins an exact name, and that still takes priority.
		var generic := RepairPoint.new()
		fault.add_child(generic)
		var loose_spare := RigidBody3D.new()
		loose_spare.name = "SomeOtherSpare"
		loose_spare.add_to_group(&"spare_parts")
		holder.add_child(loose_spare)
		suite.check(generic.can_use_with_item(loose_spare), "any item in the spare_parts group fits")
		suite.check(not generic.can_use_with_item(wrong), "an item outside the group never fits")
		suite.check(not panel.can_use_with_item(loose_spare),
			"a panel pinning an exact part still refuses a different spare")

		panel.use_with_item(wrong)
		suite.check(fault.is_active, "the wrong part does not repair anything")
		suite.check(not panel.consumed_last_item(), "and is not consumed")

		panel.use_with_item(part)
		suite.check(not fault.is_active and not fault.is_patched, "the right part fixes it permanently")
		suite.check(panel.consumed_last_item(), "and the part is consumed — one spare, one fix")
		suite.check(not panel.is_enabled, "the repaired panel stops being a target again")

		fault.break_now()
		panel.interact()
		suite.check(not fault.is_active and fault.is_patched, "empty-handed interact patches it")

		holder.free()


	func _test_scene_wiring() -> void:
		print("[game.tscn is wired up]")
		var packed := load("res://scenes/game.tscn") as PackedScene
		suite.check(packed != null, "game.tscn loads")
		if packed == null:
			return
		var game := packed.instantiate()
		suite.root.add_child(game)
		await suite.process_frame

		var run := game.get_node_or_null("Run") as RunState
		suite.check(run != null, "Run node exists and is a RunState")

		var faults := suite.root.get_tree().get_nodes_in_group(Malfunction.GROUP_MALFUNCTION)
		suite.check(faults.size() >= 3, "at least 3 malfunctions are placed (got %d)" % faults.size())

		var missing_panel := 0
		var missing_part := 0
		for node in faults:
			var fault := node as Malfunction
			var panel: RepairPoint = null
			for child in fault.get_children():
				if child is RepairPoint:
					panel = child
			if panel == null:
				missing_panel += 1
				continue
			if panel.required_part != "" and game.get_node_or_null(NodePath(panel.required_part)) == null:
				missing_part += 1
				push_error("no spare part named '%s' for %s" % [panel.required_part, fault.system_name])
		suite.check(missing_panel == 0, "every malfunction has a repair panel")
		suite.check(missing_part == 0, "every named spare part exists in the scene")

		# Spares must be SCARCER than the faults, or fitting one is free and the patch
		# route is strictly worse — which is what the balance simulation showed.
		var spares := suite.root.get_tree().get_nodes_in_group(&"spare_parts")
		suite.check(spares.size() > 0, "spare parts are placed (got %d)" % spares.size())
		suite.check(spares.size() < faults.size(),
			"there are fewer spares (%d) than faults (%d), so which to fix properly is a choice"
				% [spares.size(), faults.size()])

		suite.check(game.get_node_or_null("StasisPod") != null, "the stasis pod is placed")
		suite.check(game.get_node_or_null("StasisPod/PodView") != null, "the pod has a view marker")
		suite.check(game.get_node_or_null("HUD") != null, "the HUD is present")
		suite.check(game.get_node_or_null("RunEnd") != null, "the end screen is present")
		# The countdowns must not start behind the start prompt.
		suite.check(not run.running, "the run does not start until START is clicked")

		game.free()
