extends SceneTree
# Dev utility: render the battery cube (charged, so the bars are lit) to a PNG.
# Run WITHOUT --headless: godot --path . --resolution 900x700 -s tests/capture_battery.gd -- <out>

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://battery.png"

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.64, 0.7)
	e.ambient_light_energy = 0.7
	env.environment = e
	root.add_child(env)

	var battery: Node3D = load("res://scenes/props/battery_cube.tscn").instantiate()
	root.add_child(battery)
	await process_frame
	var bat := battery as BatteryCube
	bat.charge = bat.capacity * 0.6  # 3 of 5 bars, so lit and unlit both show
	await process_frame

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0.45, 0.55, 0.6)
	cam.look_at(Vector3(0, 0.1, 0), Vector3.UP)
	cam.make_current()

	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("saved %s" % out_path)
	quit(0)
