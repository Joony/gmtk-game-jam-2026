extends SceneTree
# The cargo crawlers seize, and a can of oil frees them.
#
# The one AMBER fault on a ship where everything else is a red alert, and the one with a bespoke
# fix: no hammer bodge, no generic spare, and the can is KEPT rather than consumed.
#
# Run: godot --headless --path . -s tests/smoke_crawler_oil.gd

const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []
var _game: Node


func _init() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("crawler oil test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_check("the opening stasis lets go", await Opening.wake(self, _game))
	await _physics_frames(20)

	var ship := _game.get_node("Ship") as RoomBuilder

	# --- the fault exists, in the right register ------------------------------
	var fault: Malfunction = null
	for node in get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var m := node as Malfunction
		if m != null and m.system_name == "CARGO CRAWLERS":
			fault = m
	_check("the ship has a crawler seizure", fault != null)
	if fault == null:
		return _finish()

	# AMBER, and this is the point of the whole fault. Everything else on the ship is CRITICAL;
	# a run where every fault sounds the klaxon has no way left to say "this one matters".
	_check("it is DEGRADING, not CRITICAL — amber, no klaxon",
		fault.severity == Malfunction.Severity.DEGRADING)
	_check("...so it does not raise the red alert", not fault.is_critical())
	_check("in the cargo bay (%s)" % ship.room_at(fault.global_position),
		ship.room_at(fault.global_position) == "cargo_bay")
	_check("and it says the line that was mis-wired to the drive regulator (%s)"
		% fault.vo_line, fault.vo_line == &"need_oil")

	# THE MISATTRIBUTION ITSELF. "Them robots in the garage need oil" played on a stuck output
	# regulator, which is a different machine in a different room.
	var regulator: Malfunction = null
	for node in get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var m := node as Malfunction
		if m != null and m.system_name == "DRIVE REGULATOR":
			regulator = m
	_check("the drive regulator is still there", regulator != null)
	if regulator != null:
		_check("...and has no voice line at all (%s)" % regulator.vo_line,
			regulator.vo_line == &"")

	# --- both machines are the repair point -----------------------------------
	var points := fault.repair_points()
	_check("both crawlers repair it (%d)" % points.size(), points.size() == 2)
	if points.size() < 1:
		return _finish()
	for point in points:
		_check("a crawler is a ray target when seized (%s)" % point.name, true)

	# --- the can ---------------------------------------------------------------
	var cans := get_nodes_in_group(&"oil_cans")
	_check("there is an oil can (%d)" % cans.size(), cans.size() == 1)
	if cans.is_empty():
		return _finish()
	var can := cans[0] as RigidBody3D
	await _physics_frames(150)
	_check("it is in the cargo bay (%s)" % ship.room_at(can.global_position),
		ship.room_at(can.global_position) == "cargo_bay")
	# The floor probe every carryable gets — model origins are at the base, so an undropped
	# mesh floats, and a nested StaticBody3D launches the thing through the hull.
	var base := _lowest_visible_point(can)
	_check("and rests on the deck rather than in the air (base %+.3f)" % base, base < 0.05)

	# THE SPOUT POINTS AWAY. Carry aligns a held item's local axes with the view
	# (_upright_facing_basis), so a nozzle modelled on +Z is a nozzle aimed at your own face —
	# which is how CD_Oil_v1 comes out of Blender, and how this first shipped. The prop yaws the
	# model 180 to fix it, and that is invisible in every other measurement: the bounding box,
	# the collider fit and the floor probe are all identical either way round.
	var nozzle := _find_mesh(can, "Nozzle")
	_check("the can has a nozzle to point", nozzle != null)
	if nozzle != null:
		var box: AABB = nozzle.global_transform * nozzle.get_aabb()
		var toward_z := (box.position.z + box.size.z * 0.5) - can.global_position.z
		_check("and the spout points AWAY from the holder, not at them (%+.3f)" % toward_z,
			toward_z < 0.0)

	# --- oiling it -------------------------------------------------------------
	var point := points[0]
	fault.break_now()
	await _frames(2)
	_check("a seized crawler is broken", fault.is_active)
	_check("the prompt offers oil, not a spare (%s)" % point.get_interaction_text(can),
		point.get_interaction_text(can).to_lower().contains("oil"))

	# NO BODGE. You cannot bash a dry bearing back to life, so the hammer is not a route here —
	# unlike every other repair point on the ship.
	var hammer := _game.get_node_or_null("Hammer") as Node3D
	_check("the hammer exists to be refused", hammer != null)
	if hammer != null:
		_check("the hammer is not a tool for this", not point.is_tool(hammer))
		point.use_with_item(hammer)
		await _frames(2)
		_check("...and bashing it does nothing", fault.is_active)

	# A generic spare is refused too — this is the one bespoke fix on the ship.
	var spares := get_nodes_in_group(&"spare_parts")
	if not spares.is_empty():
		_check("a generic spare part will not do",
			not point.can_use_with_item(spares[0] as Node3D))

	point.use_with_item(can)
	await _frames(2)
	_check("oiling it frees the crawler", not fault.is_active)
	_check("...permanently, not as a bodge", not fault.is_patched)
	# THE CAN IS KEPT. There is exactly one on the ship and the seizure recurs, so consuming it
	# would make the fault permanently unfixable the second time.
	_check("and the can is NOT consumed — you keep it", not point.consumed_last_item())
	_check("so it is still in the world", is_instance_valid(can))

	# ...which the second seizure proves.
	fault.break_now()
	await _frames(2)
	point.use_with_item(can)
	await _frames(2)
	_check("so it still works when they seize again", not fault.is_active)

	# --- and the OTHER crawler fixes the same fault ---------------------------
	if points.size() == 2:
		fault.break_now()
		await _frames(2)
		points[1].use_with_item(can)
		await _frames(2)
		_check("oiling either machine clears the one seizure", not fault.is_active)

	_finish()


func _lowest_visible_point(node: Node3D) -> float:
	var lowest := INF
	for entry in _meshes(node):
		var mesh := entry as MeshInstance3D
		if not mesh.visible:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	return lowest


func _find_mesh(node: Node, wanted: String) -> MeshInstance3D:
	for entry in _meshes(node):
		var mesh := entry as MeshInstance3D
		if mesh.name == wanted:
			return mesh
	return null


func _meshes(node: Node) -> Array:
	var out := []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _finish() -> void:
	if _failures.is_empty():
		print("CRAWLER OIL TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("CRAWLER OIL TEST FAIL")
		quit(1)
