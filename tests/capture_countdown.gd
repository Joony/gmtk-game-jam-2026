extends SceneTree
# Dev utility: renders the step 12 states to PNGs so the HUD and panels can be eyeballed.
# The generic capture_scene.gd cannot reach these — they only exist after START is clicked
# and after a fault has fired.
#
# Run WITHOUT --headless (needs a real renderer):
#   godot --path . --resolution 1280x720 -s tests/capture_countdown.gd -- <out_dir>

var _game: Node3D
var _player: CharacterBody3D
var _camera: CameraController
var _run: RunState
var _dir: String = "user://"


func _init() -> void:
	_go.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Yaw 0 looks down -Z (toward the bow). POSITIVE yaw turns toward -X (port), because a
## +Y rotation swings the forward vector that way — easy to get backwards, and I did.
func _look_from(position: Vector3, yaw_degrees: float, pitch_degrees: float = 0.0) -> void:
	_player.global_position = position
	_player.reset_physics_interpolation()
	_camera.set_look(deg_to_rad(yaw_degrees), deg_to_rad(pitch_degrees))
	await _frames(14)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [_dir, name]
	if image.save_png(path) != OK:
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
	_game.start_game()
	await _frames(10)

	_player = _game.get_node("Player")
	_camera = _game.get_node("Player/CameraRig")
	_run = _game.get_node("Run")

	# 1. The pod bay: the pentagon of cryo pods, seen from the player's own pod.
	await _look_from(Vector3(0.0, 0.9, 8.8), 0.0)
	await _shot("01_from_spawn")
	await _look_from(Vector3(-5.6, 0.9, 8.4), -35.0)
	await _shot("01b_pentagon_oblique")
	await _look_from(Vector3(0.0, 3.9, 9.5), 0.0, -32.0)
	await _shot("01d_bay_overview")
	await _look_from(Vector3(0.0, 0.9, -3.4), 180.0)
	await _shot("01c_from_corridor")

	# The nav console, and the camera walking up to read it.
	await _look_from(Vector3(4.9, 0.9, 5.0), -90.0)
	await _shot("07_console")
	_game._open_nav_screen()
	# Long enough for the glide (NAV_MOVE_TIME) to finish.
	await _frames(70)
	await _shot("08_nav_reading")
	_game._nav_screen.close()
	await _frames(60)

	# The vent pipe in its three states.
	var coolant: Malfunction = _game.get_node("CoolantLoop")
	coolant.break_now()
	await _frames(30)
	await _look_from(Vector3(4.05, 0.9, -17.0), -90.0)
	var interactor: Interactor = _game.get_node("Player/Interactor")
	print("  DIAG player=%v cam=%v target=%s prompt='%s'" % [
		_player.global_position,
		(_game.get_node("Player/CameraRig/Camera3D") as Camera3D).global_position,
		str(interactor.current), interactor.get_prompt()])
	await _shot("09_pipe_broken")
	coolant.repair(false, _run.distance_remaining)
	await _frames(20)
	await _shot("10_pipe_patched")
	coolant.break_now()
	coolant.repair(true, _run.distance_remaining)
	await _frames(20)
	await _shot("11_pipe_fixed")

	# 2. A critical fault: HUD fault list, red alert lighting, red panel light.
	var drive: Malfunction = _game.get_node("MainDrive")
	drive.break_now()
	await _frames(40)
	await _look_from(Vector3(-3.5, 0.9, -20.2), 0.0)
	await _shot("02_broken_panel")

	# 3. The same panel after a patch — the light must read amber, not green.
	drive.repair(false, _run.distance_remaining)
	await _frames(30)
	await _shot("03_patched_panel")

	# 4. Air running out: the vignette and the red gauge.
	_run.oxygen_remaining = 14.0
	_run.oxygen_changed.emit(_run.oxygen_remaining, _run.oxygen_total)
	await _frames(30)
	await _shot("04_low_air")

	# 5. In the pod, fast-forwarding.
	_run.enter_stasis()
	await _frames(20)
	await _shot("05_stasis")
	_run.exit_stasis()
	await _frames(5)

	# 6. The end screen, with a couple of choices recorded.
	_run.distance_remaining = 0.0
	await _frames(20)
	await _shot("06_run_end")

	quit(0)
