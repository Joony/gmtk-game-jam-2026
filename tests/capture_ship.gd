extends SceneTree
# Dev utility: an eye-level look around every room of the redrawn ship, plus the two views
# that the layout rewrite most easily gets wrong — the corridor bend, which is two rectangles
# pretending to be one L, and a doorway looked through into the room beyond, which is where
# per-room light culling would show up as a black hole.
#
# Run WITHOUT --headless:
#   godot --path . --resolution 1280x720 -s tests/capture_ship.gd -- <out_dir>

var _game: Node3D
var _player: CharacterBody3D
var _camera: CameraController
var _dir: String = "user://"

## name, position, yaw. Yaw 0 looks down -Z (toward the bow); POSITIVE yaw turns to port.
const VIEWS := [
	["bridge", Vector3(0.5, 0.95, -14.0), 0.0],
	["kitchen", Vector3(15.5, 0.95, -8.0), 0.0],
	["bathroom", Vector3(-4.5, 0.95, -6.0), 0.0],
	["janitor_closet", Vector3(3.0, 0.95, -6.5), -90.0],
	["life_support", Vector3(-22.5, 0.95, 4.0), 0.0],
	["pod_bay", Vector3(0.5, 0.95, 14.0), 0.0],
	["engine_room", Vector3(-28.5, 0.95, 24.0), 0.0],
	["cargo_bay", Vector3(29.5, 0.95, 28.0), 0.0],
	# The seam: standing in the spine looking into the fore arm. If the bend were left as a
	# door there would be a lintel across the corner here.
	["corridor_bend", Vector3(0.5, 0.95, -7.0), 0.0],
	# Through the pod bay's port door into the life-support corridor, and on into the room.
	["door_into_life_support", Vector3(-7.0, 0.95, 0.5), 90.0],
	# Down the long starboard crossing into the cargo bay.
	["door_into_cargo", Vector3(8.0, 0.95, 11.5), -90.0],
]


func _init() -> void:
	_go.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]

	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await _frames(2)
	if _game.has_method("start_game"):
		_game.start_game()
	await _frames(30)

	_player = _game.get_node("Player")
	_camera = _player.get_node("CameraController") if _player.has_node("CameraController") \
		else _player.find_children("*", "CameraController", true, false)[0]

	# Shoot in NORMAL light. The run opens on a broken drive, so everything is red at 1.15
	# energy otherwise, which hides exactly the detail these shots are for.
	var lighting: LightingController = _game.get_node("Lighting")
	lighting.transition_time = 0.0
	lighting.set_mode(LightingController.Mode.NORMAL)

	for view in VIEWS:
		_player.global_position = view[1]
		_player.reset_physics_interpolation()
		_camera.set_look(deg_to_rad(float(view[2])), 0.0)
		# Long enough for the doors to notice the player and slide, and for the light cull
		# set to settle on the new room.
		await _frames(40)
		await RenderingServer.frame_post_draw
		var path := "%s/ship_%s.png" % [_dir, view[0]]
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("save_png failed for %s" % path)
		else:
			print("saved %s" % path)

	quit(0)
