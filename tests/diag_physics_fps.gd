extends SceneTree
# Diagnostic: does the physics in game.tscn stay sane when the render rate collapses?
#
# The web build is the only place crates and cables go wild, and the thing that is
# categorically different about it is frame pacing: 25 MB of wasm on one thread renders far
# slower than the desktop build. Physics still ticks at 60 Hz, so Godot runs MORE physics
# steps per rendered frame — and anything that authors a body's transform in `_process`
# (Carry does exactly that, on a frozen KINEMATIC body) teleports it once per render frame
# instead of once per physics step. Jolt derives a velocity from that teleport.
#
# So: load the real scene, pin Engine.max_fps low, let it run, and report every rigid body
# that ends up moving fast or leaving the ship.
#
# Run WITHOUT --headless (needs a renderer for the scene to behave normally):
#   godot --path . --resolution 640x360 -s tests/diag_physics_fps.gd -- <fps> <seconds>

const ESCAPE_RADIUS := 60.0
const FAST := 8.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var fps := int(args[0]) if args.size() > 0 else 60
	var seconds := float(args[1]) if args.size() > 1 else 8.0

	Engine.max_fps = fps
	print("[diag] max_fps=%d  physics_ticks=%d  max_steps_per_frame=%d  jitter_fix=%.2f" % [
		fps,
		Engine.physics_ticks_per_second,
		Engine.max_physics_steps_per_frame,
		Engine.physics_jitter_fix,
	])

	var packed: PackedScene = load("res://scenes/game.tscn")
	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game

	for i in 10:
		await process_frame

	var bodies := _rigid_bodies(game)
	var start := {}
	for body in bodies:
		start[body] = body.global_position
	print("[diag] tracking %d rigid bodies for %.1fs" % [bodies.size(), seconds])

	var elapsed := 0.0
	var frames := 0
	var worst_speed := 0.0
	var worst_name := ""
	while elapsed < seconds:
		await process_frame
		elapsed += root.get_process_delta_time()
		frames += 1
		for body in bodies:
			if not is_instance_valid(body):
				continue
			var speed: float = body.linear_velocity.length()
			if speed > worst_speed:
				worst_speed = speed
				worst_name = body.name

	print("[diag] %d frames in %.1fs (%.1f fps average)" % [frames, elapsed, frames / elapsed])
	print("[diag] fastest body seen: %s at %.1f m/s" % [worst_name, worst_speed])

	var escaped := 0
	var moved := 0
	for body in bodies:
		if not is_instance_valid(body):
			continue
		var travelled: float = body.global_position.distance_to(start[body])
		var speed: float = body.linear_velocity.length()
		var flag := ""
		if body.global_position.length() > ESCAPE_RADIUS:
			flag = "  <== LEFT THE MAP"
			escaped += 1
		elif speed > FAST:
			flag = "  <== MOVING FAST"
		if travelled > 0.05 or flag != "":
			moved += 1
			print("   %-22s moved %6.2fm  speed %6.2f  y %7.2f%s" % [
				body.name, travelled, speed, body.global_position.y, flag])

	print("[diag] %d/%d bodies moved, %d left the map" % [moved, bodies.size(), escaped])
	quit(0)


func _rigid_bodies(node: Node, out: Array[RigidBody3D] = []) -> Array[RigidBody3D]:
	if node is RigidBody3D:
		out.append(node)
	for child in node.get_children():
		_rigid_bodies(child, out)
	return out
