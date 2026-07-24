extends SceneTree
# Render a plug plugged into the battery to check it sits OUTSIDE the cube.
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var out_path: String = OS.get_cmdline_user_args()[0]
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.1,0.11,0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.6,0.64,0.7); e.ambient_light_energy = 0.9
	env.environment = e; root.add_child(env)
	var dl := DirectionalLight3D.new(); dl.rotation = Vector3(-0.9, -0.6, 0.0); root.add_child(dl)
	var battery: Node3D = load("res://scenes/props/battery_cube.tscn").instantiate()
	root.add_child(battery); battery.freeze = true
	var bport := battery.get_node("Port") as CableSocket
	var plug := RigidBody3D.new(); plug.set_script(load("res://scripts/game/cable_plug.gd"))
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(0.3,0.3,0.3); cs.shape = bx; plug.add_child(cs)
	root.add_child(plug)
	await process_frame
	var cplug := (plug as Node) as CablePlug
	cplug.plug_into(bport)
	await process_frame
	await process_frame
	var cam := Camera3D.new(); root.add_child(cam)
	cam.global_position = Vector3(0.55, 0.35, 0.75); cam.look_at(Vector3(0, 0, 0.15), Vector3.UP); cam.make_current()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % out_path); quit(0)
