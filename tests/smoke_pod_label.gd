extends SceneTree
# Regression test for the "01" stencilled inside the cryo pod door.
#
# Two things make it what it is, and both are easy to lose without anything looking broken:
#
#   1. It is dead ahead of the player's EYE while they are sealed in — which is 0.65m above
#      PodView, not PodView itself. Aim it at the body origin instead and it sits below the
#      frame, out of shot, for the whole of every stasis.
#   2. It is parented to the DOOR, so it swings away on the door's own tween. Parent it to the
#      pod (the obvious-looking version, and the one with sane local coordinates) and it hangs
#      in mid-air over an open doorway. So the test opens the door and requires the label to
#      have MOVED, rather than only checking where it starts.
#
# See tests/capture_pod_label.gd for the look-at-it counterpart. Run:
#   godot --headless --path . -s tests/smoke_pod_label.gd

const Opening := preload("res://tests/opening.gd")
const FONT_PATH := "res://assets/AbolitionTest-Regular.otf"

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame

	var pod: StasisPod = game.get_node("StasisPod")
	# The path is the assertion: a child of the door is what makes it ride the swing.
	var label: Label3D = pod.get_node_or_null("Model/Door/DoorLabel")
	_check("the door has a label under it", label != null)
	if label == null:
		_report()
		return

	_check("it reads the pod's number (%s)" % label.text, label.text == pod.door_label)
	_check("it is set in Abolition (%s)" % label.font.resource_path, label.font.resource_path == FONT_PATH)
	# "Slightly transparent" is the whole look — an opaque one reads as a sticker.
	_check(
		"it is transparent (alpha %.2f)" % label.modulate.a,
		label.modulate.a > 0.05 and label.modulate.a < 1.0
	)
	# Flat-lit interior: a shaded label is a slightly different flat grey and nothing more.
	_check("it is unshaded", not label.shaded)
	# Only ever read from inside; culling the back stops it ghosting through the open panel.
	_check("it is single-sided", not label.double_sided)

	# --- Dead ahead of the eye, while sealed in ----------------------------
	var eye: Camera3D = game.get_node("Player/CameraRig/Camera3D")
	_check("the player is sealed in to start with", game._pod_phase == game.PodPhase.IN)
	var to_label := label.global_position - eye.global_position
	var off_axis := rad_to_deg((-eye.global_transform.basis.z).angle_to(to_label))
	_check(
		"the label is in front of the player, not below or behind them (%.1f deg off centre)"
			% off_axis,
		off_axis < 8.0
	)
	# Close enough to read, far enough not to be a blur across the whole screen. The door's
	# inner face is 0.78m from the pod axis, so this is also "inside the pod, not through it".
	var range_m := to_label.length()
	_check(
		"the label is within arm's reach ahead (%.2fm)" % range_m,
		range_m > 0.4 and range_m < 0.78
	)

	# --- It leaves with the door -------------------------------------------
	var sealed_at := label.global_position
	_check("the opening stasis lets go", await Opening.wake(self, game))
	var moved := sealed_at.distance_to(label.global_position)
	# The door swings 105 degrees around a 0.78m radius, so anything parented to it travels
	# the better part of a metre. A label pinned to the pod would move exactly 0.
	_check(
		"the label swings away with the door (moved %.2fm)" % moved,
		moved > 0.5
	)

	# The scenery pods are sealed for the whole run; a label none of them will ever show is
	# four more transparent draws for nothing.
	for node in game.get_tree().get_nodes_in_group(&"interactables"):
		var other := node as StasisPod
		if other != null and not other.is_player_pod:
			_check(
				"scenery pod %s has no label" % other.name,
				other.get_node_or_null("Model/Door/DoorLabel") == null
			)

	_report()


func _report() -> void:
	if _failures.is_empty():
		print("POD LABEL TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("POD LABEL TEST FAIL")
		quit(1)
