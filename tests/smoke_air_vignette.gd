extends SceneTree
# The red creep at the edges of the screen as the air runs out.
#
# Two properties, and the second is the one that was actually broken:
#   1. it pulses SLOWLY — a breath, not a strobe
#   2. it pulses SMOOTHLY, with the frequency ramping rather than the phase jumping
#
# (2) failed silently for as long as the vignette existed. The phase was `TAU * hz * elapsed`,
# and `hz` rises as the air drains, so every change to it moved the whole phase term by
# TAU * delta_hz * elapsed. Minutes into a run `elapsed` is in the hundreds, so a hz change of
# 0.001 between two frames threw the phase a third of a cycle. Nothing measured it, and from the
# outside it just looked like the flashing was too fast.
#
# Run: godot --headless --path . -s tests/smoke_air_vignette.gd

const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []
var _game: Node


func _init() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("air vignette test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_check("the opening stasis lets go", await Opening.wake(self, _game))
	await _frames(4)

	var run: RunState = _game.get_node("Run")
	var hud = _game.get_node("HUD")
	var vignette: Control = hud._vignette

	# --- above the threshold it is not there at all ---------------------------
	run.oxygen_remaining = run.oxygen_warning * 2.0
	await _frames(3)
	_check("plenty of air means no vignette (%.3f)" % vignette.modulate.a,
		is_zero_approx(vignette.modulate.a))

	# --- inside the warning band ----------------------------------------------
	# Deliberately at a HIGH elapsed time. The old phase-from-elapsed-time arithmetic was fine
	# in the first seconds of a run and fell apart later, which is exactly why nothing caught it.
	hud._pulse = 600.0
	run.oxygen_remaining = run.oxygen_warning * 0.5
	await _frames(3)
	_check("low air brings it up (%.3f)" % vignette.modulate.a, vignette.modulate.a > 0.0)

	# SMOOTHNESS. Sampled every frame while the oxygen keeps draining, which is the condition
	# that broke it: a moving `hz`. At a plausible frame time the alpha cannot lurch.
	var samples: Array[float] = []
	for i in 90:
		# Keep it draining, so `hz` is genuinely in motion between samples.
		run.oxygen_remaining = maxf(run.oxygen_remaining - run.oxygen_warning * 0.004, 0.01)
		await process_frame
		samples.append(vignette.modulate.a)

	var biggest_jump := 0.0
	for i in range(1, samples.size()):
		biggest_jump = maxf(biggest_jump, absf(samples[i] - samples[i - 1]))
	# One frame of a 1 Hz wave at 60fps moves the sine by about 10% of its range at the steepest
	# point, and the alpha range here is ~0.55 — so a real pulse steps by a few hundredths. A
	# phase that is jumping lands anywhere, repeatedly.
	_check("the vignette moves smoothly, not in lurches (biggest frame step %.3f)"
		% biggest_jump, biggest_jump < 0.12)

	# ...and it is genuinely oscillating, not just creeping in one direction: a smooth-but-dead
	# vignette would pass the check above trivially.
	var turns := 0
	for i in range(2, samples.size()):
		var before := samples[i - 1] - samples[i - 2]
		var after := samples[i] - samples[i - 1]
		if before > 0.0 and after < 0.0:
			turns += 1
	_check("and it is actually pulsing (%d peaks in 90 frames)" % turns, turns >= 1)

	# --- and the RATE, measured -----------------------------------------------
	# Against ACCUMULATED TIME, not a frame count: headless runs the loop as fast as it can, so
	# "90 frames" is not 1.5 seconds and a peak count on its own says nothing. `hud._pulse` sums
	# the same deltas the vignette does, which makes it the honest clock here.
	#
	# Held at near-empty so `hz` is pinned at AIR_HZ_FAST — the fastest the vignette ever goes,
	# and the number the complaint was about.
	# Pinned just short of empty and RE-PINNED every frame below: the run drains air on its own,
	# and letting it reach zero ends the run — which stops HUD._process, stops the clock this
	# measures against, and spins the loop until the watchdog. (It did exactly that first time.)
	run.oxygen_remaining = run.oxygen_warning * 0.05
	await _frames(3)
	var started_at: float = hud._pulse
	var last := vignette.modulate.a
	var rising := false
	var peaks := 0
	for i in 60000:
		run.oxygen_remaining = run.oxygen_warning * 0.05
		await process_frame
		var now := vignette.modulate.a
		if now > last and not rising:
			rising = true
		elif now < last and rising:
			rising = false
			peaks += 1
		last = now
		if hud._pulse - started_at >= 4.0:
			break
	var elapsed: float = hud._pulse - started_at
	var measured := peaks / maxf(elapsed, 0.001)
	_check("it pulses at about AIR_HZ_FAST when the air is nearly gone (%.2f Hz over %.1fs, want %.2f)"
		% [measured, elapsed, hud.AIR_HZ_FAST],
		absf(measured - hud.AIR_HZ_FAST) < hud.AIR_HZ_FAST * 0.3)
	# ...which is a breath, not a strobe. Stated as its own assertion because the one above
	# would happily follow AIR_HZ_FAST back up to a strobe if someone raised it.
	_check("...and that is slow enough to read as breathing (%.2f Hz)" % measured,
		measured < 1.4)

	_finish()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("AIR VIGNETTE TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("AIR VIGNETTE TEST FAIL")
		quit(1)
