extends SceneTree
# Step 14d (playtest fix): a carried plug must NOT push through a wall.
# The reported bug was the small plug tunnelling a wall while carried (its collision box was much
# smaller than its visual). With the box sized to the model, Carry's collide-and-slide sweep
# clamps it to the near side. Isolated here with a standalone plug (no cable, so no breakaway) so
# only the Carry+plug collision is under test. Box matches power_cable.tscn's plug (0.42^3-ish).
# Run: godot --headless --path . -s tests/smoke_plug_wall.gd

const GAME_SCENE := "res://scenes/game.tscn"
const PLUG_SCRIPT := "res://scripts/game/cable_plug.gd"
const PLUG_BOX := Vector3(0.42, 0.18, 0.42)  # keep in sync with scenes/props/power_cable.tscn

var _failures: Array[String] = []
var _game: Node3D
var _cam: Camera3D
var _carry: Carry
var _player: CharacterBody3D


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("plug wall test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	root.push_input(e)


func _run() -> void:
	_game = load(GAME_SCENE).instantiate()
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_game.start_game()

	_cam = _game.get_node("Player/CameraRig/Camera3D")
	_carry = _game.get_node("Player/Carry")
	_player = _game.get_node("Player")

	await _physics_frames(45)
	_player.global_position = Vector3(0.0, 0.9, -17.0)
	_player.reset_physics_interpolation()
	(_game.get_node("Player/CameraRig") as CameraController).set_look(0.0, 0.0)
	await _physics_frames(20)

	# A standalone plug (no cable) with the shipping box size.
	var plug := RigidBody3D.new()
	plug.set_script(load(PLUG_SCRIPT))
	plug.continuous_cd = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = PLUG_BOX
	cs.shape = box
	plug.add_child(cs)
	_game.add_child(plug)
	plug.gravity_scale = 0.0
	plug.linear_velocity = Vector3.ZERO
	var forward := -_cam.global_transform.basis.z
	(plug as Node3D).global_position = _cam.global_position + forward * 1.0
	await _physics_frames(3)

	_press("interact")
	await _frames(2)
	_check("picked the plug up", _carry.is_holding())
	await _frames(30)  # reach the hold point

	# A wall 2 m ahead; then walk the player straight into it.
	var wall := StaticBody3D.new()
	var wsh := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(6, 6, 0.2)
	wsh.shape = wbox
	wall.add_child(wsh)
	_game.add_child(wall)
	wall.global_position = _cam.global_position + forward * 2.0
	await _frames(6)
	var wall_along := (wall.global_position - _cam.global_position).dot(forward)

	# Advance the player well past the wall plane (2.5 m of steps into a wall 2 m away).
	for i in 14:
		_player.global_position += forward * 0.18
		await process_frame
	await _frames(6)

	# The plug (whether still clamped in-hand or broken free against the wall) must be on the
	# near side of the wall plane — never punched through it.
	var plug_along := ((plug as Node3D).global_position - _cam.global_position).dot(forward)
	_check(
		"a carried plug does not push through a wall (plug %.2f < wall %.2f along view)"
			% [plug_along, wall_along],
		plug_along < wall_along
	)

	if _failures.is_empty():
		print("PLUG WALL TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("PLUG WALL TEST FAIL")
		quit(1)
