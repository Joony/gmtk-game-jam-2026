extends SceneTree
# Dev utility: render the engine-room power cable to a PNG to eyeball its placement.
# Run WITHOUT --headless (needs a real renderer):
#   godot --path . --resolution 1280x720 -s tests/capture_cable.gd -- <out_png>

const GAME_SCENE := "res://scenes/game.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://cable.png"

	var game: Node3D = load(GAME_SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_game()

	# Let the rope drape and the free plug fall.
	for i in 120:
		await physics_frame

	# A dedicated camera framing the cable at (-6, 1.3, -20).
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.global_position = Vector3(-1.6, 1.5, -12.3)
	cam.look_at(Vector3(-3.0, 0.6, -13.9), Vector3.UP)
	cam.make_current()

	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	var err := image.save_png(out_path)
	if err != OK:
		push_error("save_png failed: %d" % err)
		quit(1)
		return
	print("saved %s" % out_path)
	quit(0)
