extends SceneTree
# Regression test for the "jump on a crate and get launched" bug.
#
# A light RigidBody3D crate springs when a CharacterBody3D lands on it. The player's
# move_and_slide() used to treat that crate as a moving platform and inherit its jitter
# velocity, flinging the player across the room. The fix puts pushable props on physics
# layer 2 and keeps the player's platform_floor_layers to layer 1 alone, so it still stands
# on and shoves the crate but never inherits its velocity. See scenes/player.tscn.
#
# This builds a minimal floor + real crate + real player, jumps with no movement input, and
# asserts the player never gains meaningful horizontal speed and stays put. Run:
#   godot --headless --path . -s tests/smoke_crate_jump.gd

const PLAYER_SCENE := "res://scenes/player.tscn"
const CRATE_SCENE := "res://scenes/props/pickup_crate.tscn"

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	InputMap.load_from_project_settings()
	_check("jump action exists", InputMap.has_action("jump"))

	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	# Static floor on layer 1, top face at y = 0.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)

	# Real crate, resting on the floor (0.8m box, origin at its centre -> y = 0.4).
	var crate: RigidBody3D = load(CRATE_SCENE).instantiate()
	world.add_child(crate)
	crate.global_position = Vector3(0, 0.4, 0)
	_check("crate is off layer 1 (not a player platform)", (crate.collision_layer & 1) == 0)
	_check("crate is on the props layer 2", (crate.collision_layer & 2) != 0)

	# Real player, standing on top of the crate (capsule half-height 0.9 over the 0.8 top).
	var player: CharacterBody3D = load(PLAYER_SCENE).instantiate()
	world.add_child(player)
	player.global_position = Vector3(0, 1.7, 0)

	# Settle so both bodies find rest contact before we jump.
	for _i in 45:
		await physics_frame

	var rest := player.global_position
	_check("player settled on the crate, not through it (y=%.2f)" % rest.y, rest.y > 0.8)

	# Three jumps in a row, tracking the worst horizontal speed and displacement. With no
	# movement input the player should go straight up and come back down over the same spot.
	var max_speed := 0.0
	var max_drift := 0.0
	for _jump in 3:
		Input.action_press("jump")
		await physics_frame
		Input.action_release("jump")
		for _i in 50:
			await physics_frame
			var horiz := Vector2(player.velocity.x, player.velocity.z).length()
			max_speed = maxf(max_speed, horiz)
			max_drift = maxf(max_drift, Vector2(player.global_position.x, player.global_position.z).length())

	# max_speed comfortably under the 7 m/s walk cap; a launched player blows well past it.
	_check("player never launches off the crate (peak %.2f m/s)" % max_speed, max_speed < 3.0)
	_check("player stays over the crate (drifted %.2f m)" % max_drift, max_drift < 2.0)
	_check("player did not fall through the world (y=%.2f)" % player.global_position.y, player.global_position.y > 0.5)

	if _failures.is_empty():
		print("CRATE JUMP TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("CRATE JUMP TEST FAIL")
		quit(1)
