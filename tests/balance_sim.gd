extends SceneTree
# Balance tool, not a pass/fail test. Plays the real game.tscn numbers against three
# strategies and reports what happens, so the exported values can be tuned against
# evidence instead of vibes.
#
#   godot --headless --path . -s tests/balance_sim.gd
#
# Walking times are estimates measured off the ship layout at the player's ~7 m/s, plus a
# couple of seconds of fumbling per repair. They are the weakest input here — treat the
# output as "which strategies are viable", not as exact seconds.

const WALK_SECONDS := {
	"MAIN DRIVE": 7.0,    # engine room, forward wall — the longest trip on the ship
	"COOLANT LOOP": 6.5,  # engine room, starboard
	"O2 SCRUBBER": 3.5,   # corridor, roughly halfway
	"NAV ARRAY": 2.0,     # pod bay, a few steps from the pod
}
## Fiddling with the panel once you are standing at it.
const REPAIR_SECONDS := 2.0
const DT := 0.1


func _init() -> void:
	_run.call_deferred()


func _await_awake(run: RunState, seconds: float, clock: Array) -> void:
	var elapsed := 0.0
	while elapsed < seconds and not run.finished:
		run._process(DT)
		elapsed += DT
		clock[0] += DT


func simulate(policy: String) -> Dictionary:
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame

	var run: RunState = game.get_node("Run")
	run.start()
	# Driven by hand so the result does not depend on the frame rate of the machine.
	run.set_process(false)

	var pending: Array = []
	run.alarm.connect(func(m: Malfunction, _p: bool) -> void: pending.append(m))

	# Spares are finite and generic, so "fix it properly" is only available while any
	# remain. This is the constraint that makes patching a real choice rather than a
	# strictly worse one.
	var spares: int = root.get_tree().get_nodes_in_group(&"spare_parts").size()

	var clock := [0.0]
	run.enter_stasis()

	while not run.finished and clock[0] < 7200.0:
		run._process(DT)
		clock[0] += DT
		if run.finished or run.in_stasis or pending.is_empty():
			continue

		if policy == "ignore":
			pending.clear()
			run.enter_stasis()
			continue

		# One fault per excursion: you have one pair of hands, so a permanent fix means
		# one part per trip, and two faults at once means two trips.
		var queue: Array = pending.duplicate()
		pending.clear()
		for entry in queue:
			var fault: Malfunction = entry
			if run.finished:
				break
			if not fault.is_active:
				continue
			var walk: float = WALK_SECONDS.get(fault.system_name, 5.0)
			_await_awake(run, walk * 2.0 + REPAIR_SECONDS, clock)
			if run.finished:
				break
			var permanent := policy == "proper" and spares > 0
			if permanent:
				spares -= 1
			fault.repair(permanent, run.distance_remaining)
		if not run.finished:
			run.enter_stasis()

	var result := {
		"policy": policy,
		"won": run.distance_remaining <= 0.0,
		"real_seconds": clock[0],
		"air_left": run.oxygen_remaining,
		"summary": run.summary(),
	}
	game.free()
	return result


func _run() -> void:
	print("== balance simulation ==")
	print("(policy 'proper' fits a spare while any remain, then falls back to patching)")
	for policy in ["ignore", "patch", "proper"]:
		var result: Dictionary = await simulate(policy)
		var summary: Dictionary = result["summary"]
		print("%-8s %-9s  run %5.1fs   air left %5.1fs   repairs %d perm / %d patch (%d gave out)   %.1f million miles covered" % [
			result["policy"],
			"ARRIVED" if result["won"] else "SUFFOCATED",
			result["real_seconds"],
			result["air_left"],
			summary["repairs_permanent"],
			summary["repairs_patched"],
			summary["patch_failures"],
			summary["distance_covered"],
		])
	quit(0)
