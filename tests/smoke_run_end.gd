extends SceneTree
# The end of a run: the view goes over sideways like the player passed out, the screen wipes to
# black, and the numbers arrive on it.
#
# The whole thing is an animation that has to play while the game is still RUNNING, and that is
# where it goes wrong. Both of the shutdowns it used to do on frame one kill it silently:
# pausing the tree freezes the fall, and disabling the player node stops CameraController — a
# child of it — which is the thing performing the fall. Either way the player sees an instant
# cut and no test that only looked at the final screen would notice.
#
# So this measures the CAMERA'S WORLD BASIS rather than the tween's own variables. A roll that
# is written but never read looks identical from the outside otherwise, and that is exactly the
# failure mode of animating a camera whose controller rewrites its transform every frame.
#
# Run: godot --headless --path . -s tests/smoke_run_end.gd

const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []


func _init() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("run end test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


## How far the view has tipped, 0 upright to 1 flat on its side. The right vector of an
## upright camera is horizontal; rolling about the view axis is what lifts it.
func _tilt(camera: Camera3D) -> float:
	return absf(camera.global_transform.basis.x.y)


func _run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	_check("the opening stasis lets go", await Opening.wake(self, game))

	var camera: Camera3D = game.get_node("Player/CameraRig/Camera3D")
	var rig: CameraController = game.get_node("Player/CameraRig")
	var run_end: CanvasLayer = game.get_node("RunEnd")
	var dim: ColorRect = run_end.get_node("Dim")
	var run: RunState = game.get_node("Run")

	_check("the view starts upright (%.3f)" % _tilt(camera), _tilt(camera) < 0.05)
	var eye_before := camera.global_position.y
	_check("the end screen is not up yet", not run_end.visible)

	# DIE HOLDING SOMETHING. Carry authors a held item's transform from the hold point every
	# render frame and the hold point rides the camera — so an item still held when the player
	# goes over rides the collapse down with them, and then hangs in mid-air the moment the
	# player node stops processing. It is the one object on screen that does not fall.
	var carry: Carry = game.get_node("Player/Carry")
	var node: Node = load("res://scenes/props/hammer.tscn").instantiate()
	game.add_child(node)
	var held := node as RigidBody3D
	held.global_position = game._player.global_position + Vector3(0.0, 0.6, -1.0)
	for i in 10:
		await physics_frame
	_check("the player can pick something up to die holding",
		carry.grab(held as Node3D as Interactable))
	for i in 30:
		await process_frame
	_check("...and is holding it when the run ends", carry.is_holding())
	var held_at := held.global_position

	# --- Out of air --------------------------------------------------------
	run._end(false)
	await process_frame

	_check("dying drops what you were holding", not carry.is_holding())

	# The two shutdowns that must NOT have happened yet. Either one on this frame and there is
	# no collapse at all — the player simply cuts to a black screen.
	_check("the tree is still running, so the fall can play", not paused)
	_check("the player node is still processing", game._player.process_mode != Node.PROCESS_MODE_DISABLED)
	# ...but the player is not steering any of it.
	_check("the player cannot move", not game._player.is_physics_processing())
	_check("and the mouse no longer turns the view", not rig.input_enabled)

	# --- The fall ----------------------------------------------------------
	# Sampled to a PEAK rather than read at the end: the screen is black by the time this
	# finishes, so a collapse that happened only after the wipe would be a collapse nobody saw.
	var tilt_peak := 0.0
	var lowest_eye := eye_before
	var frames := 0
	while frames < 6000 and not run_end.visible:
		await process_frame
		frames += 1
		tilt_peak = maxf(tilt_peak, _tilt(camera))
		lowest_eye = minf(lowest_eye, camera.global_position.y)
	_check("the end screen comes up", run_end.visible)

	# ...and it FELL, rather than riding the camera down or hanging where it was. Measured on
	# the way through, because the tree is paused once the summary lands and nothing moves after.
	_check("the dropped item fell instead of floating (%.2f -> %.2f)"
		% [held_at.y, held.global_position.y],
		is_instance_valid(held) and held.global_position.y < held_at.y - 0.1)

	# `visible` goes true when the WIPE STARTS, not when the summary lands — fade_to_black()
	# turns the layer on to show the black over the collapse, and show_result() only runs once
	# that finishes. Asserting straight off the loop above therefore read the screen mid-wipe:
	# a=0.00, no stats, and the title still on its default. Wait for the numbers themselves.
	var summary: CenterContainer = run_end.get_node("Center")
	frames = 0
	while frames < 6000 and not summary.visible:
		await process_frame
		frames += 1
	_check("the summary arrives after the wipe (%d frames)" % frames, summary.visible)

	# Roughly sin(END_FALL_ROLL_DEG); loose, because the point is "went over", not a number.
	_check(
		"the view goes over on its side (tilt %.2f, want > 0.7)" % tilt_peak,
		tilt_peak > 0.7
	)
	_check(
		"and drops toward the floor (%.2fm from %.2fm)" % [lowest_eye, eye_before],
		eye_before - lowest_eye > 0.6
	)

	# --- Black first, THEN the numbers -------------------------------------
	# The wipe has to be finished before the summary arrives, or the stats read over a room
	# the player is no longer standing in.
	_check("the screen is fully black behind the numbers (%.2f)" % dim.modulate.a,
		dim.modulate.a > 0.99)
	_check("the black is opaque, not a dim over the world (%.2f)" % dim.color.a,
		dim.color.a > 0.99)
	_check("the stats are showing", summary.visible)
	var title: Label = run_end.get_node("%Title")
	_check("the result is named (%s)" % title.text, title.text == "OUT OF AIR")
	var stats: GridContainer = run_end.get_node("%Stats")
	_check("the final stats are filled in (%d rows)" % stats.get_child_count(),
		stats.get_child_count() >= 8)

	# --- Only now is everything shut down ----------------------------------
	_check("the tree is paused once the screen is up", paused)
	_check("the player node is disabled", game._player.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("the HUD is gone", not game._hud.visible)
	_check("the reticle is gone", not game._reticle.visible)

	# Unpause, or every suite that runs after this one inherits a frozen tree.
	paused = false

	if _failures.is_empty():
		print("RUN END TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("RUN END TEST FAIL")
		quit(1)
