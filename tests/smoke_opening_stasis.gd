extends SceneTree
# Regression test for how the run OPENS: the player is already asleep in the pod, and the ship
# wakes them a beat later.
#
# It used to start them stood in front of the pod facing it, which put the player one beat past
# their own story — looking at the thing the fiction says they just climbed out of. So the two
# halves below are both the point:
#
#   1. On frame zero the player is INSIDE the pod, sealed in, frozen, with no reticle — the
#      state _enter_pod() would have left behind.
#   2. Nothing else is needed to get them out: the ordinary wake runs on a timer and hands
#      control back. A start that seals the player in and never opens the door is the exact
#      failure this guards, and it is unrecoverable in a jam build.
#
# The door and the pod's occupancy are read off the pod itself rather than trusting Game's
# phase enum, so this fails if the two ever drift apart. Run:
#   godot --headless --path . -s tests/smoke_opening_stasis.gd

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


## Whether the "IN STASIS · [E] WAKE" box is actually on screen.
##
## Both terms are needed. The panel's own `visible` stays true through the cold open — the HUD
## sets it from RunState.stasis_changed and knows nothing about the opening — and it is the
## CanvasLayer above it being hidden that keeps it off screen. Reading either flag alone would
## report the wrong answer: the panel's says "showing" when nothing is drawn, and the layer's
## would miss the panel being left up after the overlay arrives.
func _stasis_box_showing(game) -> bool:
	return game._hud.visible and (game._hud.get_node("%StasisPanel") as Control).visible


func _run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame

	var player: CharacterBody3D = game.get_node("Player")
	var pod: StasisPod = game.get_node("StasisPod")
	var run = game.get_node("Run")

	# --- Frame zero: asleep in the pod ------------------------------------
	var view := pod.view_transform()
	_check(
		"player starts at the pod's view marker (%.2f,%.2f,%.2f vs %.2f,%.2f,%.2f)"
			% [
				player.global_position.x, player.global_position.y, player.global_position.z,
				view.origin.x, view.origin.y, view.origin.z
			],
		player.global_position.distance_to(view.origin) < 0.01
	)
	_check("the pod is occupied from the start", pod.occupied)
	_check("the game knows the player is in the pod", game._pod_phase == game.PodPhase.IN)
	# Sealed, and instantly — the door must not be caught mid-swing on the first frame, which
	# is what happens if the pose is done with an animated set_door_open().
	_check("the pod is sealed on frame zero", not pod._door_open)
	_check(
		"the door is posed shut, not swinging (%.3f rad)" % pod._door.rotation.y,
		absf(pod._door.rotation.y - pod._door_closed_y) < 0.001
	)
	# Frozen: a player who can walk is a player who can walk out through the shell.
	_check("the player cannot move in stasis", not player.is_physics_processing())
	_check("the camera is not the player's yet", not game._camera.input_enabled)
	_check("no reticle over a view you do not control", not game._reticle.visible)
	# The scenery pods must not have been swung open by the same pass that seals the player's.
	for node in game.get_tree().get_nodes_in_group(&"interactables"):
		var other := node as StasisPod
		if other != null and not other.is_player_pod:
			_check("scenery pod %s starts sealed" % other.name, not other._door_open)

	# The clock is running and the pod is buying time, both from frame zero — the opening is a
	# real stasis, not a cosmetic pause with the run held back.
	_check("the run is running", run.running)
	_check("the run is in stasis", run.in_stasis)

	# --- The cold open: bare, and silent but for the alarm ------------------
	# No HUD, and specifically no "IN STASIS · [E] WAKE" panel — the game explaining a mechanic
	# before it has shown the player anything. Both are asserted: hiding the panel alone would
	# still leave the air and distance gauges up over a pod interior.
	var audio = root.get_node("Audio")
	_check("no HUD during the cold open", not game._hud.visible)
	_check("no \"IN STASIS\" box during the cold open", not _stasis_box_showing(game))
	_check(
		"no music during the cold open (state %d)" % audio.music_state,
		audio.music_state == audio.Music.NONE
	)
	# music_state is the intent; this is whether anything is actually coming out. A fade-out
	# left running would still be audible with the state already reported as NONE.
	for _i in 90:
		await process_frame
		if not (audio._music_a.playing or audio._music_b.playing):
			break
	_check(
		"nothing is actually playing during the cold open",
		not (audio._music_a.playing or audio._music_b.playing)
	)
	# The klaxon is the ONE exception to the cold open, and the reason there is one at all: the
	# ship starts with a critical fault already broken (DriveRegulator.starts_broken), and the
	# alarm coming through the sealed shell is how the player learns they are being WOKEN
	# rather than arriving. Every other stasis seals the pod — see smoke_voice.
	_check("the klaxon sounds through the shell during the cold open", audio._alarm_player.playing)
	_check("and the pod is deliberately not sealed for it", not audio._sealed)
	var opening_faults := 0
	for node in game.get_tree().get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var fault := node as Malfunction
		if fault != null and fault.is_critical():
			opening_faults += 1
	_check("the run opens on a critical fault (%d)" % opening_faults, opening_faults >= 1)

	# --- The ship wakes you ------------------------------------------------
	# Generous: OPENING_STASIS_TIME, then the door, then the ride out. If this ever times out
	# the player is sealed in a pod they cannot leave.
	var woke := false
	# Sampled every frame of the ride out, not just at the end: the greeting is seconds long,
	# so checking only after the exit cannot tell whether it started here or three seconds ago
	# under the cork pop. That is exactly the regression this guards.
	var greeted_early := false
	for _i in 900:
		await process_frame
		if game._pod_phase == game.PodPhase.OUT:
			woke = true
			break
		if audio._voice_player.stream == audio._voices_by_name[&"intro"]:
			greeted_early = true
	_check("the ship wakes the player by itself", woke)
	if not woke:
		_report()
		return

	_check("the run is out of stasis", not run.in_stasis)
	_check("the pod is no longer occupied", not pod.occupied)
	_check("the pod door opened", pod._door_open)

	# --- ...and then the game turns on --------------------------------------
	# The cold open must be a delay, not a deletion: everything it held back comes in on waking.
	_check("the HUD comes up on waking", game._hud.visible)
	_check("no \"IN STASIS\" box once awake", not _stasis_box_showing(game))
	_check(
		"the music comes in on waking (state %d)" % audio.music_state,
		audio.music_state != audio.Music.NONE
	)
	for _i in 120:
		await process_frame
		if audio._music_a.playing or audio._music_b.playing:
			break
	_check(
		"a track is actually playing once awake",
		audio._music_a.playing or audio._music_b.playing
	)

	# Control is genuinely back, not just the phase flag.
	_check("the player can move again", player.is_physics_processing())
	_check("the camera is the player's again", game._camera.input_enabled)
	_check("the reticle is back", game._reticle.visible)
	_check(
		"the player is set down outside the pod (%.2fm from the exit marker)"
			% player.global_position.distance_to(pod.exit_transform().origin),
		player.global_position.distance_to(pod.exit_transform().origin) < 0.5
	)
	# Out of the shell, not still standing in it. The pod's radius is ~1.4m.
	_check(
		"the player is clear of the pod (%.2fm)"
			% player.global_position.distance_to(pod.global_position),
		player.global_position.distance_to(pod.global_position) > 1.5
	)
	# The pod stays usable — the opening must not have consumed the loop's anchor.
	_check("the pod can be entered again", pod.can_act_on())

	# --- The greeting lands once you are STOOD in the room ------------------
	# Played at the wake it would go under the cork pop and the door servo, which is the one
	# stretch of the opening guaranteed to be noisy. So it waits for _finish_exit().
	_check("the computer greets you once you are out",
		audio._voice_player.stream == audio._voices_by_name[&"intro"])
	_check("and not a moment earlier, under the pop and the door", not greeted_early)
	_check("and only once — the latch is spent", not game._intro_line_pending)

	# --- ...and from here the pod is soundproof -----------------------------
	# The klaxon through the shell is the OPENING's alone. Climb back in and the pod does what
	# a sealed pod does: the ship goes quiet until you are out of it again.
	game._on_pod_used(null)
	for _i in 900:
		await process_frame
		if game._run.in_stasis and game._pod_phase == game.PodPhase.IN:
			break
	_check("the player got back into the pod", game._run.in_stasis)
	_check("a later stasis seals the pod", audio._sealed)
	_check("and the klaxon does not sound through it", not audio._alarm_player.playing)

	_report()


func _report() -> void:
	if _failures.is_empty():
		print("OPENING STASIS TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("OPENING STASIS TEST FAIL")
		quit(1)
