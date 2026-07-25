extends SceneTree
# Dev utility: look at the "01" stencilled inside the cryo pod door, from the player's own eyes.
#
# Uses the real game scene and the real player camera rather than posing a camera by hand — the
# whole question is whether the label lands where the player is actually looking during the
# opening stasis, and a camera placed to flatter it would answer a different question.
#
# Two shots: sealed in (the label dead ahead), and again once the door has swung, which is where
# a label parented to the wrong node shows up — it stays put while the panel leaves. Run WITHOUT
# --headless; RenderingServer.frame_post_draw never fires with no renderer:
#   godot --path . --resolution 1280x720 -s tests/capture_pod_label.gd -- <out-prefix>

func _init() -> void:
	_run.call_deferred()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved %s" % path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://pod_label"

	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for _i in 20:
		await process_frame

	var pod: StasisPod = game.get_node("StasisPod")
	var label: Label3D = pod.get_node_or_null("Model/Door/DoorLabel")
	if label == null:
		push_error("no DoorLabel was built")
		quit(1)
		return
	var eye: Camera3D = game.get_node("Player/CameraRig/Camera3D")
	print("label at %v, eye at %v, %.3fm ahead, %.1f deg off centre" % [
		label.global_position,
		eye.global_position,
		label.global_position.distance_to(eye.global_position),
		rad_to_deg(
			(-eye.global_transform.basis.z).angle_to(
				label.global_position - eye.global_position
			)
		),
	])
	await _shot("%s_sealed.png" % prefix)

	# Ride the wake: the label has to leave with the door.
	game._run.exit_stasis()
	for _i in 45:
		await process_frame
	await _shot("%s_opening.png" % prefix)
	for _i in 150:
		await process_frame
	await _shot("%s_open.png" % prefix)
	quit(0)
