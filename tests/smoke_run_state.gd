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
	# Round numbers on purpose: 1 million miles per real second awake, 10 asleep, 1s of air
	# per second. The default journey is deliberately far too long to finish, so a test that
	# is not about arrival can never accidentally end the run mid-measurement.
	run.total_distance = 100000.0
	run.cruise_speed_per_day = 1.0
	run.days_per_real_second = 1.0
	# No spin-up by default: every other test here measures an exact rate, and a ramp would
	# turn each of those into an approximation. The ramp gets its own test.
	run.stasis_ramp_time = 0.0
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
		_test_state_visuals()
		_test_digit_readout()
		await _test_computer()
		await _test_scene_wiring()

		print("-- %d checks, %d failures --" % [suite.checks, suite.failures.size()])
		for failure in suite.failures:
			print("   FAILED: %s" % failure)
		suite.quit(1 if suite.failures.size() > 0 else 0)


	# --- 12a: distance ------------------------------------------------------------

	func _test_distance_rate() -> void:
		print("[distance falls at the ship's speed]")
		var ctx: Dictionary = suite.build_run({"total_distance": 100.0})
		var run: RunState = ctx["run"]
		suite.tick(run, 10.0)
		suite.check(suite.nearly(run.distance_remaining, 90.0, 0.01),
			"10s covers 10 million miles (got %.2f remaining)" % run.distance_remaining)
		suite.check(suite.nearly(run.days_elapsed, 10.0, 0.01),
			"and 10 days pass (got %.2f)" % run.days_elapsed)
		suite.check(suite.nearly(run.eta_days(), 90.0, 0.01),
			"ETA is the remaining distance at the current rate (got %.2f days)" % run.eta_days())
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
		var ctx: Dictionary = suite.build_run({"stasis_ramp_time": 2.0})
		var run: RunState = ctx["run"]
		var motion: ShipMotion = ctx["motion"]

		var start_distance := run.distance_remaining
		suite.tick(run, 10.0)
		var awake_covered := start_distance - run.distance_remaining

		run.enter_stasis()
		# The drive winds up rather than snapping. Checked at three points, because a ramp
		# that jumped on the first frame would still pass a "settles at 10x" check alone.
		suite.check(suite.nearly(run.time_scale, 1.0, 0.01),
			"the clock is still at 1x the instant the lid shuts (got %.3f)" % run.time_scale)
		suite.tick(run, 1.0, 10)
		suite.check(run.time_scale > 1.2 and run.time_scale < 9.5,
			"halfway through the ramp it is part-way there (got %.2f)" % run.time_scale)
		suite.tick(run, 1.2, 12)
		suite.check(suite.nearly(run.time_scale, 10.0, 0.01),
			"and it reaches the full rate (got %.3f)" % run.time_scale)
		suite.check(suite.nearly(motion.time_scale, run.time_scale, 0.001),
			"the starfield is told the same rate, so the stars stretch as it climbs")

		# Now that it has settled, the rate itself is exact.
		var before := run.distance_remaining
		suite.tick(run, 10.0)
		var asleep_covered := before - run.distance_remaining
		suite.check(suite.nearly(asleep_covered, awake_covered * 10.0, 0.01),
			"10s at full rate covers 10x what 10s awake covers (%.1f vs %.1f)" % [asleep_covered, awake_covered])

		run.exit_stasis()
		suite.check(run.time_scale > 9.0,
			"waking does not snap the clock back either (got %.2f)" % run.time_scale)
		suite.tick(run, 2.2, 22)
		suite.check(suite.nearly(run.time_scale, 1.0, 0.01),
			"it winds back down to real time (got %.3f)" % run.time_scale)
		suite.check(suite.nearly(motion.time_scale, 1.0, 0.01), "and the starfield relaxes with it")

		# Diving back in mid-spin-down must pick up from where the ramp actually is.
		run.enter_stasis()
		suite.tick(run, 0.6, 6)
		var partway := run.time_scale
		run.exit_stasis()
		suite.tick(run, 0.1, 1)
		suite.check(run.time_scale < partway + 0.01 and run.time_scale > 1.0,
			"reversing mid-ramp continues from the current rate (%.2f -> %.2f)" % [partway, run.time_scale])
		ctx["holder"].free()


	# --- 12d: malfunctions --------------------------------------------------------

	func _test_schedule_fires_once() -> void:
		print("[faults fire on schedule, once, and wake you]")
		var ctx: Dictionary = suite.build_run({"total_distance": 100.0}, [
			{"system_name": "A", "speed_penalty": 0.2, "fire_at_distance": 50.0},
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
		var ctx: Dictionary = suite.build_run({"total_distance": 100.0}, [
			{"system_name": "A", "speed_penalty": 0.2, "bodge_distance": 10.0},
		])
		var run: RunState = ctx["run"]
		var fault: Malfunction = ctx["faults"][0]
		fault.break_now()
		suite.check(fault.is_active, "fault starts broken")

		fault.repair(false, run.distance_remaining)
		suite.check(not fault.is_active and fault.is_patched, "patching clears it and flags the patch")
		suite.check(suite.nearly(run.speed_fraction(), 1.0),
			"a patch restores FULL speed — its cost is that it expires")

		# 5 million miles of travel: not far enough to use up a 10-million-mile patch.
		suite.tick(run, 5.0, 5)
		suite.check(not fault.is_active,
			"the patch holds for its distance (%.1f Mm covered)" % (100.0 - run.distance_remaining))

		suite.tick(run, 10.0, 20)
		suite.check(fault.is_active, "the patch gives out after bodge_distance")
		suite.check(fault.break_count == 2, "it is the SAME fault breaking again (count %d)" % fault.break_count)
		suite.check(run.patch_failures == 1, "the failure is recorded for the summary")
		suite.check(run.choices.size() > 0 and "gave out" in run.choices[-1],
			"and it is attributable to the player's own choice: '%s'" % run.choices[-1])
		ctx["holder"].free()


	func _test_permanent_repair_never_refires() -> void:
		print("[a fitted part is permanent]")
		var ctx: Dictionary = suite.build_run({"total_distance": 100.0}, [
			{"system_name": "A", "speed_penalty": 0.2, "bodge_distance": 5.0},
		])
		var run: RunState = ctx["run"]
		var fault: Malfunction = ctx["faults"][0]
		fault.break_now()
		fault.repair(true, run.distance_remaining)
		suite.check(not fault.is_patched, "a proper fix is not a patch")
		suite.tick(run, 50.0, 50)
		suite.check(not fault.is_active,
			"still fixed after %.1f Mm" % (100.0 - run.distance_remaining))
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

		var won: Dictionary = suite.build_run({"total_distance": 10.0, "oxygen_total": 1000.0})
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


	func _test_state_visuals() -> void:
		print("[a panel shows its state in the world, not just on a light]")
		var holder := Node.new()
		suite.root.add_child(holder)
		var fault := Malfunction.new()
		holder.add_child(fault)
		var panel := RepairPoint.new()
		var crack := Node3D.new()
		crack.name = "Crack"
		var tape := Node3D.new()
		tape.name = "Tape"
		var sleeve := Node3D.new()
		sleeve.name = "Sleeve"
		panel.add_child(crack)
		panel.add_child(tape)
		panel.add_child(sleeve)
		# `damaged` stands in for the vent pipe's ruptured model: it must stay visible under
		# the tape (broken OR patched), which is why it cannot just live in broken_nodes.
		var damaged := Node3D.new()
		damaged.name = "Damaged"
		panel.add_child(damaged)
		panel.broken_nodes = [NodePath("Crack")]
		panel.patched_nodes = [NodePath("Tape")]
		panel.fixed_nodes = [NodePath("Sleeve")]
		panel.damaged_nodes = [NodePath("Damaged")]
		fault.add_child(panel)

		suite.check(not crack.visible and not tape.visible and sleeve.visible and not damaged.visible,
			"a healthy system shows only the intact fix")
		fault.break_now()
		suite.check(crack.visible and not tape.visible and not sleeve.visible and damaged.visible,
			"breaking it shows the damage")
		fault.repair(false, 100.0)
		suite.check(tape.visible and not crack.visible and not sleeve.visible,
			"a patch shows the patch — visible evidence of the choice made")
		suite.check(damaged.visible,
			"and the damage stays visible UNDER the patch — the split is still there")
		fault.break_now()
		fault.repair(true, 100.0)
		suite.check(sleeve.visible and not tape.visible and not crack.visible and not damaged.visible,
			"a permanent fix replaces everything with the intact part")
		holder.free()


	func _test_digit_readout() -> void:
		print("[the clocks do not twitch as their digits change]")
		var readout := DigitReadout.new()
		readout.digit_width = 40.0
		readout.separator_width = 18.0
		suite.root.add_child(readout)

		readout.set_value("0:00")
		var widths: Array[float] = []
		for child in readout.get_children():
			widths.append((child as Label).custom_minimum_size.x)
		suite.check(widths.size() == 4, "one slot per character (got %d)" % widths.size())
		suite.check(widths[0] == 40.0 and widths[1] == 18.0 and widths[2] == 40.0,
			"digits get the wide slot and the colon the narrow one")

		# The point of the whole class: swapping 1 for 8 must not move anything.
		readout.set_value("1:11")
		var after: Array[float] = []
		for child in readout.get_children():
			after.append((child as Label).custom_minimum_size.x)
		suite.check(after == widths, "slot widths are identical for different digits")

		var before_count := readout.get_child_count()
		readout.set_value("8:88")
		suite.check(readout.get_child_count() == before_count,
			"labels are reused, not rebuilt every update")
		readout.free()


	func _test_computer() -> void:
		print("[the nav console reads the run]")
		var ctx: Dictionary = suite.build_run({"total_distance": 100.0})
		var run: RunState = ctx["run"]
		suite.tick(run, 25.0)

		var computer := (load("res://scenes/props/computer.tscn") as PackedScene).instantiate() as ComputerTerminal
		suite.root.add_child(computer)
		await suite.process_frame
		computer.bind(run)

		var chart := NavChart.new()
		suite.root.add_child(chart)
		computer.push_to(chart)
		suite.check(suite.nearly(chart._progress, 0.25, 0.01),
			"progress is the fraction of the journey covered (got %.3f)" % chart._progress)
		suite.check(suite.nearly(chart._distance_left, 75.0, 0.01),
			"and it reports the remaining distance (got %.2f)" % chart._distance_left)
		suite.check(suite.nearly(chart._days_left, 75.0, 0.01),
			"and the ETA in days (got %.2f)" % chart._days_left)

		# A limping drive has to show on the chart too, or the console lies to the player.
		# A separate run, because start() is idempotent — adding a fault to a run that is
		# already going never registers it, which is exactly the bug this check first hit.
		var damaged: Dictionary = suite.build_run({"total_distance": 100.0}, [
			{"system_name": "DRIVE", "speed_penalty": 0.5},
		])
		(damaged["faults"][0] as Malfunction).break_now()
		computer.bind(damaged["run"])
		computer.push_to(chart)
		suite.check(suite.nearly(chart._drive, 0.5, 0.01),
			"a broken system shows as reduced drive (got %.2f)" % chart._drive)

		chart.free()
		computer.free()
		damaged["holder"].free()
		ctx["holder"].free()


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

		# Four pods in a plus, but only one of them is yours.
		var pods: Array = []
		for node in suite.root.get_tree().get_nodes_in_group(&"interactables"):
			if node is StasisPod:
				pods.append(node)
		suite.check(pods.size() == 4, "four cryo pods are placed (got %d)" % pods.size())
		var player_pods := 0
		for pod in pods:
			if (pod as StasisPod).is_player_pod:
				player_pods += 1
			else:
				suite.check(not (pod as StasisPod).is_enabled,
					"scenery pod %s offers no prompt" % (pod as Node).name)
		suite.check(player_pods == 1, "exactly one pod is the player's (got %d)" % player_pods)

		var pod := game.get_node_or_null("StasisPod") as StasisPod
		suite.check(pod != null, "the player's pod is placed")
		suite.check(game.get_node_or_null("StasisPod/PodView") != null, "the pod has a view marker")
		if pod != null:
			# The ride out has to actually leave the shell, or control is handed back with
			# the player standing inside the pod they just got out of.
			var travel := pod.view_transform().origin.distance_to(pod.exit_transform().origin)
			suite.check(travel > 1.5, "the exit marker is clear of the pod (%.2fm out)" % travel)
			# Facing aft: the player's pod looks back down the wake, which is the whole
			# reason the aft windows are where they are.
			var facing := -pod.view_transform().basis.z
			suite.check(facing.z > 0.7, "the player's pod faces the rear of the ship (z=%.2f)" % facing.z)
			# Getting out must NOT spin the camera round. You walk out forwards and keep
			# looking where you were looking.
			var out_facing := -pod.exit_transform().basis.z
			suite.check(facing.dot(out_facing) > 0.99,
				"leaving the pod keeps the player's facing (dot %.3f)" % facing.dot(out_facing))
			pod.set_door_open(true, true)
			var opened := (pod.get_node("Model/Door") as Node3D).rotation.y
			pod.set_door_open(false, true)
			var closed := (pod.get_node("Model/Door") as Node3D).rotation.y
			suite.check(not is_equal_approx(opened, closed), "the pod door actually moves")

		var computer := game.get_node_or_null("Computer") as ComputerTerminal
		suite.check(computer != null, "the nav console is placed")
		if computer != null:
			# The camera is flown to this marker, so it has to be in front of the glass and
			# pointed at it — a marker behind the console would park the view inside the case.
			var screen := computer.get_node("Screen") as Node3D
			var view := computer.view_transform()
			# The marker is a BODY position; the camera anchor sits 0.65m above it, and it
			# is the eye that has to line up with the glass.
			var eye := view.origin + Vector3(0.0, 0.65, 0.0)
			var to_screen := screen.global_position - eye
			suite.check(to_screen.length() > 0.4 and to_screen.length() < 1.5,
				"the reading position is a sensible distance from the screen (%.2fm)" % to_screen.length())
			suite.check((-view.basis.z).dot(to_screen.normalized()) > 0.95,
				"and it faces the screen (dot %.3f)" % (-view.basis.z).dot(to_screen.normalized()))
			suite.check(absf(view.origin.y + 0.65 - screen.global_position.y) < 0.1,
				"with the eyes level with the middle of the screen")
		suite.check(game.get_node_or_null("HUD") != null, "the HUD is present")
		suite.check(game.get_node_or_null("RunEnd") != null, "the end screen is present")
		# The game auto-starts on load (the intro video is the only gate now), so the run is
		# already ticking by the time the scene is in the tree.
		suite.check(run.running, "the run starts itself when the scene loads")

		game.free()
