extends SceneTree
# Dev utility: render a closed sliding door head-on to check the bevel between the two panels
# reads as a seam. Lit the same way the ship is (flat colour ambient + a shadowless omni), since
# that is what makes an angled face hard to see. Run WITHOUT --headless:
#   godot --path . --resolution 900x700 -s tests/capture_door.gd -- <out.png>

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://door.png"

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_energy = 0.45
	env.environment = e
	root.add_child(env)

	# The ship's ceiling fixtures: shadowless, cool white, above and in front.
	var lamp := OmniLight3D.new()
	lamp.shadow_enabled = false
	lamp.light_energy = 1.6
	lamp.omni_range = 9.0
	lamp.light_color = Color(0.95, 0.96, 1.0)
	lamp.position = Vector3(0.0, 2.6, 1.6)
	root.add_child(lamp)

	var builder := RoomBuilder.new()
	root.add_child(builder)
	builder.add_room(Rect2(-3, -3, 6, 6))
	builder.add_doorway(Vector2(0, -3), Doorway.Axis.X, 1.6)
	builder.build()
	await process_frame

	var door: SlidingDoor = null
	for node in root.get_tree().get_nodes_in_group(RoomBuilder.GROUP_DOOR):
		door = node as SlidingDoor
		break
	if door == null:
		push_error("no door was built")
		quit(1)
		return
	print("door built at %s, closed=%s" % [door.global_position, not door.is_open])

	var cam := Camera3D.new()
	root.add_child(cam)
	# Eye height, a couple of metres back, square on to the doorway so the seam is dead centre.
	# Optional second/third args: how far back, and how far to one side. The default is square
	# on and close; a bevel that only reads from there is no use across a room.
	var back: float = float(args[1]) if args.size() > 1 else 2.0
	var side: float = float(args[2]) if args.size() > 2 else 0.0
	cam.global_position = door.global_position + Vector3(side, 1.25, back)
	cam.look_at(door.global_position + Vector3(0.0, 1.1, 0.0), Vector3.UP)
	cam.make_current()

	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % out_path)
	quit(0)
