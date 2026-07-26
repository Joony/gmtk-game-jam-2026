extends SceneTree
# Diagnostic: does CARRYING a prop stay sane when the render rate collapses?
#
# diag_physics_fps.gd showed idle props are stable at 6 fps, so plain frame pacing is not the
# story. Carry is the one system that is framerate-coupled BY DESIGN: it authors a frozen
# KINEMATIC RigidBody3D's transform in `_process`, i.e. once per RENDER frame, while physics
# steps at 60 Hz. At 60 fps that is one teleport per physics step. At 10 fps it is one
# teleport per SIX physics steps — the body sits still for five and then jumps, and Jolt
# derives a velocity from the jump.
#
# This shakes a carried crate around (the player looking about while holding it) and reports
# what velocity the held body and everything near it end up with.
#
# Run WITHOUT --headless:
#   godot --path . --resolution 640x360 -s tests/diag_carry_fps.gd -- <fps> <seconds>

const SHAKE_HZ := 1.5
const SHAKE_YAW := 1.2   # radians either side


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var fps := int(args[0]) if args.size() > 0 else 60
	var seconds := float(args[1]) if args.size() > 1 else 6.0
	Engine.max_fps = fps

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for i in 10:
		await process_frame

	var player := game.find_child("Player", true, false)
	var carry: Carry = player.find_child("Carry", true, false)
	var rig: Node3D = player.find_child("CameraRig", true, false)

	# Grab the nearest pickup-able prop.
	var target: Interactable = null
	var best := INF
	for node in _all(game):
		if node is Interactable and node is RigidBody3D:
			var d: float = (node as Node3D).global_position.distance_to(player.global_position)
			if d < best:
				best = d
				target = node
	if target == null:
		print("[diag] no carryable prop found")
		quit(1)
		return

	var held: RigidBody3D = target.get_item_node() as RigidBody3D
	print("[diag] max_fps=%d  grabbing %s (%.2fm away)" % [fps, held.name, best])
	if not carry.grab(target):
		print("[diag] grab refused")
		quit(1)
		return

	var others: Array[RigidBody3D] = []
	for node in _all(game):
		if node is RigidBody3D and node != held:
			others.append(node)

	var elapsed := 0.0
	var frames := 0
	var worst_held := 0.0
	var worst_other := 0.0
	var worst_other_name := ""
	var base_yaw: float = rig.rotation.y
	while elapsed < seconds:
		await process_frame
		var dt := root.get_process_delta_time()
		elapsed += dt
		frames += 1
		# Look around: the hold point swings with the camera, so the held body is dragged.
		rig.rotation.y = base_yaw + sin(elapsed * TAU * SHAKE_HZ) * SHAKE_YAW
		worst_held = maxf(worst_held, held.linear_velocity.length())
		for body in others:
			if not is_instance_valid(body):
				continue
			var speed: float = body.linear_velocity.length()
			if speed > worst_other:
				worst_other = speed
				worst_other_name = body.name

	print("[diag] %.1f fps average over %d frames" % [frames / elapsed, frames])
	print("[diag] held body peak speed        : %7.2f m/s" % worst_held)
	print("[diag] fastest OTHER body while held: %7.2f m/s  (%s)" % [worst_other, worst_other_name])

	# And what happens on release — the moment Carry hands its estimate to the solver.
	carry.drop(false)
	var peak_after := 0.0
	for i in 60:
		await process_frame
		peak_after = maxf(peak_after, held.linear_velocity.length())
	print("[diag] peak speed in the second after release: %.2f m/s" % peak_after)
	print("[diag] final height y=%.2f  distance from origin %.2f" % [
		held.global_position.y, held.global_position.length()])
	quit(0)


func _all(node: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(node)
	for child in node.get_children():
		_all(child, out)
	return out
