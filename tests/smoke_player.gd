extends SceneTree
# Headless test for the player controller (step 4) and game scene (step 3).
# Run: godot --headless --path . -s tests/smoke_player.gd

const GAME_SCENE := "res://scenes/game.tscn"
const PLAYER_SCENE := "res://scenes/player.tscn"

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	var player_script := load("res://scripts/player/player.gd")
	_check("player.gd loads", player_script != null)

	var dt := 1.0 / 60.0

	# --- Pure movement maths -------------------------------------------------
	var a1: Vector3 = player_script.accelerate(Vector3.ZERO, Vector3(1, 0, 0), 7.0, 10.0, dt)
	_check("accel one frame > 0", a1.length() > 0.0)
	_check("accel one frame < max", a1.length() < 7.0)

	var v := Vector3.ZERO
	for i in 60:
		v = player_script.accelerate(v, Vector3(1, 0, 0), 7.0, 10.0, dt)
	_check("accel converges near max speed", absf(v.length() - 7.0) < 0.5)

	var f1: Vector3 = player_script.apply_friction(Vector3(5, 0, 0), 6.0, 1.5, dt)
	_check("friction slows but does not stop in one frame", f1.length() < 5.0 and f1.length() > 0.0)

	var fv := Vector3(5, 0, 0)
	for i in 200:
		fv = player_script.apply_friction(fv, 6.0, 1.5, dt)
	_check("friction converges to ~0", fv.length() < 0.01)

	# Air-strafe: adds perpendicular speed without touching forward speed.
	var strafed: Vector3 = player_script.accelerate(Vector3(7, 0, 0), Vector3(0, 0, 1), 0.8, 40.0, dt)
	_check("air-strafe adds z velocity", strafed.z > 0.0)
	_check("air-strafe leaves x unchanged", absf(strafed.x - 7.0) < 0.001)

	# --- Project settings the camera silently depends on ---------------------
	_check(
		"physics_interpolation enabled (camera design requires it)",
		bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	)
	InputMap.load_from_project_settings()
	for action in ["forward", "back", "left", "right", "jump", "pause"]:
		_check("input action '%s' exists" % action, InputMap.has_action(action))

	# --- Player scene contract ----------------------------------------------
	var packed: PackedScene = load(PLAYER_SCENE)
	_check("player.tscn loads", packed != null)
	if packed != null:
		var p := packed.instantiate()
		_check("Player is a CharacterBody3D", p is CharacterBody3D)
		_check("CameraAnchor exists", p.has_node("CameraAnchor"))
		_check("CameraRig/Camera3D exists", p.has_node("CameraRig/Camera3D"))
		_check("HoldPoint exists (needed by step 8 carry)", p.has_node("CameraRig/Camera3D/HoldPoint"))
		var rig: Node3D = p.get_node("CameraRig")
		_check("CameraRig is top_level", rig.top_level)
		_check(
			"CameraRig has physics interpolation off",
			rig.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF
		)
		_check("player collision_layer is 1", p.collision_layer == 1)
		var shape: CollisionShape3D = p.get_node("CollisionShape3D")
		_check("collision shape is a capsule", shape.shape is CapsuleShape3D)
		p.free()

	# --- Live physics: player spawns, falls, lands, and walks ---------------
	var game: Node3D = load(GAME_SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame

	var player: CharacterBody3D = game.get_node("Player")
	var spawn: Marker3D = game.get_node("PlayerSpawn")
	# Horizontally exact; vertically loose, because gravity has already acted by now.
	var spawn_pos := spawn.global_position
	var player_pos := player.global_position
	_check(
		"player starts at the spawn marker in XZ (got %.2f,%.2f expected %.2f,%.2f)"
			% [player_pos.x, player_pos.z, spawn_pos.x, spawn_pos.z],
		Vector2(player_pos.x, player_pos.z).distance_to(Vector2(spawn_pos.x, spawn_pos.z)) < 0.01
	)
	_check("player starts near the spawn height", absf(player_pos.y - spawn_pos.y) < 0.3)

	# Settle onto the floor.
	for i in 60:
		await physics_frame
	var rest_y := player.global_position.y
	_check("player is resting on the floor (y ~ 0.9, got %.3f)" % rest_y, absf(rest_y - 0.9) < 0.25)
	_check("player is on the floor", player.is_on_floor())
	_check("player is not still falling", absf(player.velocity.y) < 1.0)

	# Walk forward for half a second and confirm it actually moves.
	var start_pos := player.global_position
	Input.action_press("forward")
	for i in 30:
		await physics_frame
	Input.action_release("forward")
	var travelled := player.global_position.distance_to(start_pos)
	_check("player moved while holding forward (travelled %.2fm)" % travelled, travelled > 1.0)
	_check("player did not fall through the floor", player.global_position.y > 0.5)

	# Friction brings it back to rest once input stops.
	for i in 60:
		await physics_frame
	var horiz_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check("player comes to rest after input stops (%.3f m/s)" % horiz_speed, horiz_speed < 0.1)

	# --- Camera rig tracks the player ---------------------------------------
	var rig_node: Node3D = player.get_node("CameraRig")
	var anchor: Marker3D = player.get_node("CameraAnchor")
	_check(
		"camera rig sits at the eye anchor",
		rig_node.global_position.distance_to(anchor.global_position) < 0.2
	)

	# --- Mouse look ----------------------------------------------------------
	# Needs a captured cursor; headless may refuse, so skip rather than false-fail.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var yaw_before := player.global_transform.basis.get_euler().y
		var pitch_before := rig_node.global_transform.basis.get_euler().x

		var look := InputEventMouseMotion.new()
		look.screen_relative = Vector2(100, 60)
		look.relative = Vector2(100, 60)
		root.push_input(look)
		await process_frame
		await process_frame

		var yaw_after := player.global_transform.basis.get_euler().y
		var pitch_after := rig_node.global_transform.basis.get_euler().x
		_check("mouse motion changes yaw", absf(yaw_after - yaw_before) > 0.001)
		_check("mouse motion changes pitch", absf(pitch_after - pitch_before) > 0.001)

		# Pitch must clamp well short of straight up/down (±89°).
		for i in 40:
			var big := InputEventMouseMotion.new()
			big.screen_relative = Vector2(0, 500)
			big.relative = Vector2(0, 500)
			root.push_input(big)
			await process_frame
		var clamped := rig_node.global_transform.basis.get_euler().x
		_check(
			"pitch clamps within ±90° (got %.1f°)" % rad_to_deg(clamped),
			absf(rad_to_deg(clamped)) <= 89.5
		)
	else:
		print("  (skipped mouse-look checks: cursor capture unavailable headless)")

	if _failures.is_empty():
		print("PLAYER TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("PLAYER TEST FAIL")
		quit(1)
