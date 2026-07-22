extends SceneTree
# Dev utility: render a scene to a PNG so it can be eyeballed without opening the editor.
# Run WITHOUT --headless (needs a real renderer):
#   godot --path . --resolution 1280x720 -s tests/capture_scene.gd -- <scene_path> <out_png>

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://scenes/main_menu.tscn"
	var out_path: String = args[1] if args.size() > 1 else "user://capture.png"
	# Optional 3rd arg: an input action to fire before capturing (e.g. "pause"),
	# so states that only exist after input can be eyeballed too.
	var action: String = args[2] if args.size() > 2 else ""

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("could not load %s" % scene_path)
		quit(1)
		return

	var instance := packed.instantiate()
	root.add_child(instance)
	current_scene = instance

	# Let layout settle and the frame actually draw.
	for i in 5:
		await process_frame

	if action != "":
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		root.push_input(event)
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
