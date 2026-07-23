extends SceneTree
func _init() -> void: _go.call_deferred()
func _go() -> void:
	var args := OS.get_cmdline_user_args(); var dir: String = args[0] if args.size()>0 else "user://"
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	for i in 4: await process_frame
	game.start_game()
	for i in 10: await process_frame
	var player: CharacterBody3D = game.get_node("Player")
	var cam: CameraController = game.get_node("Player/CameraRig")
	player.global_position = Vector3(0.5, 5.5, 15.0); player.reset_physics_interpolation()
	cam.set_look(0.0, deg_to_rad(-42.0))
	for i in 14: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/flush2.png" % dir); print("saved")
	quit(0)
