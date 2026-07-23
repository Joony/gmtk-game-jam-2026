extends SceneTree
# Step 11: space windows — wall openings, the starfield shader, and ship motion.
# Run: godot --headless --path . -s tests/smoke_space_windows.gd

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()
	_watchdog.call_deferred()


func _watchdog() -> void:
	await create_timer(90.0).timeout
	push_error("watchdog fired: the test never finished (look for a SCRIPT ERROR above)")
	print("SPACE WINDOWS TEST FAIL")
	quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_game()
	await _frames(5)

	var motion: ShipMotion = game.get_node("Motion")
	var ship: Node3D = game.get_node("Ship")
	# --- The starfield is a BACKDROP SHELL, not panes in the windows ---------
	# That is what makes each window a genuine hole, so real exterior geometry shows
	# through it, occluded by the walls and parallaxed because it is actually there.
	var shells := get_nodes_in_group(ShipMotion.GROUP_STARFIELD)
	_check("there is a starfield shell (%d)" % shells.size(), shells.size() == 1)
	if shells.is_empty():
		_report()
		return

	var shell: MeshInstance3D = shells[0]
	var material: ShaderMaterial = shell.get_surface_override_material(0) as ShaderMaterial
	_check("the shell carries a ShaderMaterial", material != null)
	_check("the starfield shader is loaded", material != null and material.shader != null)
	_check("the shell encloses the ship", (shell.mesh as SphereMesh).radius > 200.0)

	# Windows must build NO pane — a pane would hide anything outside the hull.
	var panes := 0
	for node in ship.get_node("Built").find_children("*", "MeshInstance3D", true, false):
		if node.mesh is QuadMesh:
			panes += 1
	_check("windows build no pane (%d found)" % panes, panes == 0)

	# --- The opening is really cut through the wall -------------------------
	# Find the window opening in the ship's data, then prove no wall piece covers
	# its vertical range at that location.
	var opening: Doorway = null
	for candidate in ship.doorways:
		if candidate.fit_window:
			opening = candidate
			break
	_check("ship recorded a window opening", opening != null)
	if opening != null:
		var top: float = opening.resolved_top(ship.doorway_height)
		var mid_height := (opening.sill + top) * 0.5
		var blocking := 0
		var sill_pieces := 0
		var lintel_pieces := 0
		for wall in get_nodes_in_group(RoomBuilder.GROUP_WALL):
			var body: StaticBody3D = wall
			# Only walls on the same line as this opening.
			var window_x: float = opening.position.x * ship.tile_size
			if absf(body.global_position.x - window_x) > 0.4:
				continue
			var size: Vector3 = ((body.get_node("Mesh") as MeshInstance3D).mesh as BoxMesh).size
			var z_lo := body.global_position.z - size.z * 0.5
			var z_hi := body.global_position.z + size.z * 0.5
			var window_z: float = opening.position.y * ship.tile_size
			if window_z < z_lo or window_z > z_hi:
				continue
			var y_lo := body.global_position.y - size.y * 0.5
			var y_hi := body.global_position.y + size.y * 0.5
			if mid_height > y_lo and mid_height < y_hi:
				blocking += 1
			if y_hi <= opening.sill + 0.01:
				sill_pieces += 1
			if y_lo >= top - 0.01:
				lintel_pieces += 1
		_check("no wall covers the window opening (%d blocking)" % blocking, blocking == 0)
		_check("wall remains BELOW the window (a sill, %d)" % sill_pieces, sill_pieces >= 1)
		_check("wall remains ABOVE the window (a lintel, %d)" % lintel_pieces, lintel_pieces >= 1)

		# Glass, or thrown items would fly out into space.
		var glazing := get_nodes_in_group(RoomBuilder.GROUP_WINDOW_GLASS)
		var window_count := 0
		for candidate2 in ship.doorways:
			if candidate2.fit_window:
				window_count += 1
		_check("every opening is glazed (%d windows, %d glass)" % [window_count, glazing.size()], glazing.size() == window_count)

	# --- Motion drives the starfield ----------------------------------------
	motion.speed = motion.cruise_speed
	await _frames(2)
	var travelled_a: float = material.get_shader_parameter("travelled")
	await _frames(20)
	var travelled_b: float = material.get_shader_parameter("travelled")
	_check(
		"stars advance while moving (%.2f -> %.2f)" % [travelled_a, travelled_b],
		travelled_b > travelled_a
	)

	var streak_cruise: float = material.get_shader_parameter("streak")
	_check("stars streak at cruise (%.2f)" % streak_cruise, streak_cruise > 0.01)

	# --- Stopping the ship stops the stars ----------------------------------
	motion.speed = 0.0
	await _frames(10)
	var stopped_a: float = material.get_shader_parameter("travelled")
	await _frames(20)
	var stopped_b: float = material.get_shader_parameter("travelled")
	_check(
		"stars stop dead when the ship stops (%.3f -> %.3f)" % [stopped_a, stopped_b],
		is_equal_approx(stopped_a, stopped_b)
	)
	_check(
		"streak collapses at rest (%.2f)" % float(material.get_shader_parameter("streak")),
		float(material.get_shader_parameter("streak")) < 0.01
	)

	# --- Speed changes are observable ---------------------------------------
	var speeds: Array = []
	motion.speed_changed.connect(func(s: float) -> void: speeds.append(s))
	motion.speed = motion.cruise_speed * 0.5
	await _frames(2)
	_check("speed_changed fired (%d)" % speeds.size(), speeds.size() == 1)
	_check("speed_fraction reports half (%.2f)" % motion.speed_fraction(), absf(motion.speed_fraction() - 0.5) < 0.02)

	# --- The destination hook is off until step 12 turns it on --------------
	_check(
		"destination hidden by default (%.2f)" % float(material.get_shader_parameter("destination_brightness")),
		float(material.get_shader_parameter("destination_brightness")) < 0.001
	)
	motion.destination_brightness = 1.0
	await _frames(3)
	_check(
		"destination can be turned on",
		float(material.get_shader_parameter("destination_brightness")) > 0.5
	)

	# --- Real geometry outside the hull -------------------------------------
	var station: Node3D = game.get_node_or_null("Station")
	_check("there is a station outside", station != null)
	if station != null:
		_check(
			"the station is outside the hull (%.0fm out)" % absf(station.global_position.x),
			absf(station.global_position.x) > 20.0
		)
		var hub: MeshInstance3D = station.get_node("Hub")
		# Layer 2 keeps the exterior sun off the interior.
		_check("station renders on the exterior layer (%d)" % hub.layers, hub.layers == 2)
		_check("the station is inside the shell", station.global_position.length() < (shell.mesh as SphereMesh).radius)

	var sun: DirectionalLight3D = game.get_node_or_null("ExteriorSun")
	_check("there is an exterior sun", sun != null)
	if sun != null:
		_check(
			"the exterior sun cannot light the interior (cull mask %d)" % sun.light_cull_mask,
			sun.light_cull_mask == 2
		)

	_report()


func _report() -> void:
	if _failures.is_empty():
		print("SPACE WINDOWS TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("SPACE WINDOWS TEST FAIL")
		quit(1)
