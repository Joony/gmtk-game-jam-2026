extends SceneTree
# Regression test for what a CRITICAL fault costs, and for the hammer that bodges it shut.
#
# A critical fault used to take its whole `speed_penalty` the instant it broke, and either
# repair route gave all of it back. That made the two routes trivial to compare — both cleared
# it, so the patch was free and the spare part was only ever for the second failure. There was
# no reason to walk anywhere.
#
# Now the penalty RAMPS while the fault stands, and the two routes differ in what they do to
# the number that has accrued:
#
#   patch (hammer)     stops the ramp, KEEPS the loss. Cheap, permanent, and it expires later.
#   proper (spare)     clears it to zero. Costs the walk — during which the ramp keeps running.
#
# So the four things below are the mechanic, and each of them is a way it has been wrong:
# ramping at all, ramping on the SHIP's clock (so stasis is not a free ride), a patch that
# freezes rather than heals, and a proper fix that actually heals.
#
# Run: godot --headless --path . -s tests/smoke_drive_decay.gd

const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []
## The hand-driven faults below. They add themselves to the `malfunctions` group like any
## other, so RunState.start() would sweep them into the real run and charge the ship for
## faults that exist nowhere in the world. They have to be gone before the scene loads.
var _lone: Array[Malfunction] = []


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


## A fault on its own, with no scene around it, so the maths can be driven by hand.
func _lone_fault(critical: bool, decay: float) -> Malfunction:
	var fault := Malfunction.new()
	fault.severity = Malfunction.Severity.CRITICAL if critical else Malfunction.Severity.DEGRADING
	fault.speed_penalty = 0.4
	fault.speed_decay_per_day = decay
	root.add_child(fault)
	_lone.append(fault)
	return fault


func _run() -> void:
	# --- The ramp, in isolation --------------------------------------------
	var fault := _lone_fault(true, 0.1)
	fault.break_now()
	_check("a fresh critical fault costs nothing yet", is_equal_approx(fault.active_speed_penalty(), 0.0))
	fault.advance(50.0, 1.0)
	_check(
		"one day of it costs 10%% (%.3f)" % fault.active_speed_penalty(),
		absf(fault.active_speed_penalty() - 0.1) < 0.001
	)
	fault.advance(50.0, 2.0)
	_check(
		"it keeps falling the longer it stands (%.3f)" % fault.active_speed_penalty(),
		absf(fault.active_speed_penalty() - 0.3) < 0.001
	)
	# `speed_penalty` is the CEILING now, not an instant charge. Without the clamp a fault
	# left alone would eventually take more than 100% of the drive on its own.
	fault.advance(50.0, 99.0)
	_check(
		"it stops at speed_penalty, it does not run away (%.3f)" % fault.active_speed_penalty(),
		absf(fault.active_speed_penalty() - fault.speed_penalty) < 0.001
	)

	# --- A patch freezes it. It does NOT heal it. --------------------------
	var patched := _lone_fault(true, 0.1)
	patched.break_now()
	patched.advance(50.0, 1.5)
	var at_patch := patched.active_speed_penalty()
	patched.repair(false, 50.0)
	_check("patching leaves the fault not-active", not patched.is_active and patched.is_patched)
	_check(
		"the patch KEEPS the speed already lost (%.3f)" % patched.active_speed_penalty(),
		absf(patched.active_speed_penalty() - at_patch) < 0.001
	)
	patched.advance(50.0, 5.0)
	_check(
		"and the ramp stops — five more days cost nothing (%.3f)"
			% patched.active_speed_penalty(),
		absf(patched.active_speed_penalty() - at_patch) < 0.001
	)
	# A patch that gives out picks the ramp back up from where it stood, rather than
	# restarting at zero. The debt is cumulative across the whole run.
	patched.break_now(true)
	patched.advance(50.0, 1.0)
	_check(
		"a failed patch resumes the ramp from where it left off (%.3f)"
			% patched.active_speed_penalty(),
		absf(patched.active_speed_penalty() - (at_patch + 0.1)) < 0.001
	)

	# --- A proper fix clears it --------------------------------------------
	var fixed := _lone_fault(true, 0.1)
	fixed.break_now()
	fixed.advance(50.0, 2.0)
	_check("it had lost speed before the fix", fixed.active_speed_penalty() > 0.1)
	fixed.repair(true, 50.0)
	_check(
		"fitting a spare gives the drive back in full (%.3f)" % fixed.active_speed_penalty(),
		is_equal_approx(fixed.active_speed_penalty(), 0.0)
	)

	# --- Ramping is about the FAULT, not about its severity -----------------
	# This used to read "the ramp is the critical faults' character", and severity was what
	# decided whether a fault bled or charged one flat toll. Two unrelated ideas tied together:
	# severity is whether the ship-wide red alert trips, and the nav computer (TODO 21b) ramps
	# from -5% to -10% without being critical at all. That combination was unrepresentable.
	#
	# What decides it now is whether the fault HAS a ramp — somewhere to start from, or
	# somewhere to climb to. A degrading fault with a decay rate bleeds like any other.
	var minor := _lone_fault(false, 0.1)
	minor.break_now()
	_check("a degrading fault with a decay rate ramps too (%.3f)"
			% minor.active_speed_penalty(),
		minor.ramps() and is_equal_approx(minor.active_speed_penalty(), 0.0))
	minor.advance(50.0, 2.0)
	_check("bleeding as time passes (%.3f)" % minor.active_speed_penalty(),
		minor.active_speed_penalty() > 0.1)

	# ...and one with NO ramp at all still charges its whole penalty the moment it fires, which
	# is what every fault did before there was a ramp to have.
	var flat := _lone_fault(false, 0.0)
	flat.break_now()
	_check("a fault with no ramp charges everything at once (%.3f)"
			% flat.active_speed_penalty(),
		not flat.ramps()
			and absf(flat.active_speed_penalty() - flat.speed_penalty) < 0.001)
	flat.repair(false, 50.0)
	_check("and a patch clears it completely (%.3f)" % flat.active_speed_penalty(),
		is_equal_approx(flat.active_speed_penalty(), 0.0))

	# --- An initial effect: a fault costs something the instant it fires -----
	# Without one a ramping fault is free on the frame it breaks — klaxon, HUD row, drive still
	# at 100% — which reads as nothing having happened.
	var opener := _lone_fault(false, 0.05)
	opener.initial_speed_penalty = 0.05
	opener.speed_penalty = 0.10
	opener.break_now()
	_check("it costs its initial figure straight away (%.3f)"
			% opener.active_speed_penalty(),
		is_equal_approx(opener.active_speed_penalty(), 0.05))
	opener.advance(50.0, 0.6)
	var before_bodge := opener.active_speed_penalty()
	_check("and climbs from there (%.3f)" % before_bodge, before_bodge > 0.05)

	# THE BODGE RULE. A hammer freezes the loss where it stands and never hands it back: break
	# at -5%, let it climb to -7%, bodge it, and the drive stays down 7% until a real part goes
	# in. Buying time, not power.
	opener.repair(false, 50.0)
	_check("a bodge freezes the loss where it stands (%.3f vs %.3f)"
			% [opener.active_speed_penalty(), before_bodge],
		is_equal_approx(opener.active_speed_penalty(), before_bodge))
	opener.repair(true, 50.0)
	_check("only a fitted part gives it back (%.3f)" % opener.active_speed_penalty(),
		is_equal_approx(opener.active_speed_penalty(), 0.0))

	# --- A bodge brings the fault back sooner --------------------------------
	# `bodge_recurrence` is a RATE, not a second distance, so the two numbers cannot drift
	# apart and leave a bodge outlasting a proper repair.
	var recurring := _lone_fault(false, 0.0)
	recurring.bodge_distance = 21.0
	recurring.bodge_recurrence = 3.5
	recurring.break_now()
	recurring.repair(false, 50.0)
	_check("a patch is still holding most of the way through (%.2f)"
			% recurring.patch_margin(45.0), recurring.patch_margin(45.0) > 0.0)
	recurring.advance(43.0, 0.0)
	_check("but gives out at a THIRD of the full interval, not the whole of it",
		recurring.is_active and not recurring.is_patched)

	# --- In the real run: stasis is not a free ride ------------------------
	# The ramp runs on the SHIP's clock, so the pod's time scale carries into it. Measured
	# against a REAL stasis rather than by calling advance() by hand, because the wiring from
	# RunState._process through to Malfunction.advance is the half that silently rots.
	for orphan in _lone:
		orphan.free()
	_lone.clear()

	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	_check("the opening stasis lets go", await Opening.wake(self, game))

	var run: RunState = game.get_node("Run")
	var drive: Malfunction = game.get_node("MainDrive")
	_check("the shipped main drive is critical", drive.severity == Malfunction.Severity.CRITICAL)
	_check("and it is configured to bleed", drive.speed_decay_per_day > 0.0)

	drive.break_now()
	await process_frame
	var full := run.speed_fraction()
	# Measured against the FAULT'S OWN numbers, not against a literal ship speed. This used to
	# assert `speed_fraction() > 0.9`, which quietly meant "and nothing else is broken" — and
	# the run now opens on the nav computer (TODO 21b), so two initial penalties together
	# landed on exactly 0.900 and the test failed for a reason that had nothing to do with it.
	_check(
		"breaking it costs its INITIAL figure, not its maximum (%.3f of %.3f, ship at %.3f)"
			% [drive.speed_decay, drive.speed_penalty, full],
		is_equal_approx(drive.speed_decay, drive.initial_speed_penalty)
			and drive.speed_decay < drive.speed_penalty
	)

	# Awake: the ramp is slow enough that the walk to a panel is not a death sentence...
	var awake_start := drive.speed_decay
	for _i in 60:
		await process_frame
	var awake_gain := drive.speed_decay - awake_start
	_check("the drive bleeds while you are awake (%.4f)" % awake_gain, awake_gain > 0.0)
	_check("the drive slows as it bleeds", run.speed_fraction() < full)

	# ...but stasis runs the ship's clock at stasis_time_scale, and the bleed goes with it.
	# That is the whole reason the rate is per-DAY: sleeping through a failing drive has to
	# be the worst thing you can do, not the cheapest.
	var before_stasis := drive.speed_decay
	run.enter_stasis()
	# Past the ramp-up, so this measures stasis proper rather than the spin-up.
	await create_timer(run.stasis_ramp_time + 0.2).timeout
	var stasis_start := drive.speed_decay
	for _i in 60:
		await process_frame
	var stasis_gain := drive.speed_decay - stasis_start
	run.exit_stasis()
	_check("the drive kept bleeding in the pod", drive.speed_decay > before_stasis)
	_check(
		"and far faster there — the pod is no refuge (awake %.4f vs stasis %.4f)"
			% [awake_gain, stasis_gain],
		stasis_gain > awake_gain * 4.0
	)

	# --- The hammer is where it should be ----------------------------------
	var hammer: Node3D = game.get_node_or_null("Hammer")
	_check("the ship has a hammer", hammer != null)
	if hammer != null:
		_check("the hammer is a repair tool", hammer.is_in_group(&"repair_tools"))
		# THE BRIDGE, not the janitor's closet it used to live in. The opening tutorial (TODO
		# 18) wants the hammer beside the fault the run starts on, so picking it up is how you
		# learn the tool exists — and the bridge is the hub every trip passes through.
		#
		# Asserted against the ROOM rather than a hand-written world box: a box copied out of
		# ship_layout is a second copy of the room's coordinates, and the two drifted apart the
		# moment the hammer moved. room_at() reads the rects the geometry was built from.
		var ship := game.get_node("Ship") as RoomBuilder
		var at := hammer.global_position
		_check(
			"the hammer is in the bridge (%.1f, %.1f -> %s)"
				% [at.x, at.z, ship.room_at(at)],
			ship.room_at(at) == "bridge"
		)

	if _failures.is_empty():
		print("DRIVE DECAY TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("DRIVE DECAY TEST FAIL")
		quit(1)
