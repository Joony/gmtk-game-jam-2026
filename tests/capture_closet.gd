extends SceneTree
# Dev utility: look at the janitor's closet and the hammer in it, plus the corridor view a
# player actually approaches it from.
#
# A 3x4m room hung off the side of a corridor is the easiest thing on the ship to get wrong
# in a way no numeric test catches: the doorway can land in the wrong wall, the room can be
# lit like a void, and the hammer can end up scaled like a sledge or sunk through the floor.
# smoke_drive_decay checks it is in the right box and smoke_navigation checks you can walk to
# it; this is the one that checks it looks like a cupboard.
#
# Run WITHOUT --headless:
#   godot --path . --resolution 1280x720 -s tests/capture_closet.gd -- <out_dir>

var _game: Node3D
var _player: CharacterBody3D
var _camera: CameraController
var _dir: String = "user://"


func _init() -> void:
	_go.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Yaw 0 looks down -Z (toward the bow); POSITIVE yaw turns toward -X (port).
func _look_from(position: Vector3, yaw_degrees: float, pitch_degrees: float = 0.0) -> void:
	_player.global_position = position
	_player.reset_physics_interpolation()
	_camera.set_look(deg_to_rad(yaw_degrees), deg_to_rad(pitch_degrees))
	await _frames(14)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_dir, name]
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("save_png failed for %s" % path)
	else:
		print("saved %s" % path)


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]

	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await _frames(3)
	_player = _game.get_node("Player")
	_camera = _game.get_node("Player/CameraRig")
	# The run opens asleep in the pod; take the controls off it before posing the camera.
	_game._pod_phase = _game.PodPhase.OUT
	_camera.input_enabled = false
	await _frames(3)

	var hammer: Node3D = _game.get_node("Hammer")
	print("hammer at %v" % hammer.global_position)

	# 1. Approaching down the corridor: is there visibly a door in the starboard wall?
	await _look_from(Vector3(0.5, 0.9, -6.0), 25.0, 0.0)
	await _shot("01_corridor_approach")

	# 2. In the doorway, looking in.
	await _look_from(Vector3(1.4, 0.9, -9.0), -90.0, -10.0)
	await _shot("02_closet_doorway")

	# 3. Stood over the hammer, looking down at it — scale and whether it sits ON the floor.
	await _look_from(hammer.global_position + Vector3(0.0, 0.7, 1.1), 0.0, -38.0)
	await _shot("03_hammer")
	quit(0)
