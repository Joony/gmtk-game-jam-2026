extends SceneTree
# Dev utility: render the socket receptacle (empty) to check orientation/scale. It should read as a
# faceplate facing +Z (toward the camera below). Run WITHOUT --headless.
#   godot --path . --resolution 900x700 -s tests/capture_socket.gd -- <out>

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://socket.png"

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.68, 0.74)
	e.ambient_light_energy = 0.8
	env.environment = e
	root.add_child(env)

	var socket: Node3D = load("res://scenes/props/socket_receptacle.tscn").instantiate()
	root.add_child(socket)
	await process_frame

	# +Z faces the room; sit the camera on +Z looking back at the faceplate, slightly above.
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0.25, 0.22, 0.5)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	cam.make_current()

	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % out_path)
	quit(0)
