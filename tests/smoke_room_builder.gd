extends SceneTree
# Step 9: procedural room builder.
# Run: godot --headless --path . -s tests/smoke_room_builder.gd

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()
	_watchdog.call_deferred()


# A script error inside an awaited coroutine kills it silently — quit() is never
# reached and the test hangs forever instead of failing. This turns that into a
# visible failure.
func _watchdog() -> void:
	await create_timer(90.0).timeout
	push_error("watchdog fired: the test never finished (look for a SCRIPT ERROR above)")
	print("ROOM BUILDER TEST FAIL")
	quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _count_in_group(node_root: Node, group: StringName) -> int:
	var n := 0
	for child in node_root.find_children("*", "Node", true, false):
		if child.is_in_group(group):
			n += 1
	return n


func _new_builder(parent: Node) -> RoomBuilder:
	var builder := RoomBuilder.new()
	parent.add_child(builder)
	return builder


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	# --- Pure span maths (no scene needed) ----------------------------------
	var whole := RoomBuilder.subtract_spans(Vector2(0, 10), [])
	_check("subtract nothing leaves the whole span", whole.size() == 1 and whole[0] == Vector2(0, 10))
	var holed := RoomBuilder.subtract_spans(Vector2(0, 10), [Vector2(4, 6)])
	_check("subtracting a middle span leaves two pieces", holed.size() == 2)
	var covered := RoomBuilder.subtract_spans(Vector2(2, 5), [Vector2(0, 10)])
	_check("a fully covered span leaves nothing", covered.is_empty())
	var partial := RoomBuilder.subtract_spans(Vector2(0, 10), [Vector2(-5, 3)])
	_check("partial overlap trims the front", partial.size() == 1 and is_equal_approx(partial[0].x, 3.0))

	# --- One plain room ------------------------------------------------------
	var b1 := _new_builder(world)
	b1.build_lights = false
	var room := b1.add_room(Rect2i(0, 0, 6, 4), {"id": "a", "height": 3.0})
	var built := b1.build()
	await process_frame

	_check("one floor", _count_in_group(built, RoomBuilder.GROUP_FLOOR) == 1)
	_check("one ceiling", _count_in_group(built, RoomBuilder.GROUP_CEILING) == 1)
	_check(
		"four walls with no doorways (got %d)" % _count_in_group(built, RoomBuilder.GROUP_WALL),
		_count_in_group(built, RoomBuilder.GROUP_WALL) == 4
	)

	# Geometry lands where the grid says it should — no level-size centring.
	var floor_body: Node3D = built.get_node("Floor_a")
	_check(
		"floor is centred on the room (%s)" % floor_body.position,
		is_equal_approx(floor_body.position.x, 3.0) and is_equal_approx(floor_body.position.z, 2.0)
	)
	_check("floor top sits at y=0", is_equal_approx(floor_body.position.y + b1.floor_thickness * 0.5, 0.0))
	var ceiling_body: Node3D = built.get_node("Ceiling_a")
	_check(
		"ceiling sits at the room height",
		is_equal_approx(ceiling_body.position.y - b1.ceiling_thickness * 0.5, room.height)
	)

	b1.free()
	await physics_frame

	# --- A doorway splits its wall ------------------------------------------
	var b2 := _new_builder(world)
	b2.build_lights = false
	b2.add_room(Rect2i(0, 0, 6, 4), {"id": "a", "height": 3.0})
	b2.add_doorway(Vector2(3, 0), Doorway.Axis.X, 2.0)
	var built2 := b2.build()
	await process_frame

	# North wall becomes: left segment, lintel, right segment. Plus 3 untouched walls.
	_check(
		"doorway splits its wall into three (total %d walls)" % _count_in_group(built2, RoomBuilder.GROUP_WALL),
		_count_in_group(built2, RoomBuilder.GROUP_WALL) == 6
	)
	var lintels := 0
	for child in built2.find_children("*", "StaticBody3D", true, false):
		if child.has_meta("lintel"):
			lintels += 1
	_check("exactly one lintel above the opening (got %d)" % lintels, lintels == 1)

	b2.free()
	await physics_frame

	# --- Adjacent rooms share one wall, not two -----------------------------
	var b3 := _new_builder(world)
	b3.build_lights = false
	b3.add_room(Rect2i(0, 0, 6, 4), {"id": "a"})
	b3.add_room(Rect2i(0, 4, 6, 4), {"id": "b"})  # shares the y=4 line
	var built3 := b3.build()
	await process_frame
	# 4 + 4 = 8 if naive; the shared wall must be built once, so 7.
	_check(
		"shared wall built once (got %d walls, want 7)" % _count_in_group(built3, RoomBuilder.GROUP_WALL),
		_count_in_group(built3, RoomBuilder.GROUP_WALL) == 7
	)

	b3.free()
	await physics_frame

	# Differently-sized neighbours: partial overlap must not double up either.
	var b4 := _new_builder(world)
	b4.build_lights = false
	b4.add_room(Rect2i(0, 0, 8, 4), {"id": "wide"})
	b4.add_room(Rect2i(2, 4, 3, 4), {"id": "narrow"})
	var built4 := b4.build()
	await process_frame
	var overlapping := 0
	for child in built4.find_children("*", "StaticBody3D", true, false):
		if child.is_in_group(RoomBuilder.GROUP_WALL) and is_equal_approx(child.position.z, 4.0):
			overlapping += 1
	# The wide room's south wall plus the narrow room's leftovers — but the shared
	# 3m stretch must appear exactly once, so total length on that line is 8m.
	var total_len := 0.0
	for child in built4.find_children("*", "StaticBody3D", true, false):
		if child.is_in_group(RoomBuilder.GROUP_WALL) and is_equal_approx(child.position.z, 4.0):
			var mesh: MeshInstance3D = child.get_node("Mesh")
			total_len += (mesh.mesh as BoxMesh).size.x
	_check(
		"partial overlap builds each stretch once (%d pieces, %.2fm total, want 8m)"
			% [overlapping, total_len],
		is_equal_approx(snappedf(total_len, 0.01), 8.0)
	)

	b4.free()
	await physics_frame

	# --- The built geometry is physically real ------------------------------
	var b5 := _new_builder(world)
	b5.build_lights = false
	b5.add_room(Rect2i(0, 0, 8, 8), {"id": "phys", "height": 3.0})
	b5.add_doorway(Vector2(4, 0), Doorway.Axis.X, 2.0)
	b5.build()
	await process_frame
	await physics_frame
	await physics_frame

	var space := world.get_world_3d().direct_space_state
	# A ray straight down inside the room hits the floor.
	var down := PhysicsRayQueryParameters3D.create(Vector3(4, 2, 4), Vector3(4, -1, 4))
	_check("floor is solid underfoot", not space.intersect_ray(down).is_empty())

	# A ray through the doorway at head height passes; the wall beside it blocks.
	var through := PhysicsRayQueryParameters3D.create(Vector3(4, 1.2, 2), Vector3(4, 1.2, -2))
	_check("doorway opening is passable", space.intersect_ray(through).is_empty())
	var into_wall := PhysicsRayQueryParameters3D.create(Vector3(1, 1.2, 2), Vector3(1, 1.2, -2))
	_check("wall beside the doorway is solid", not space.intersect_ray(into_wall).is_empty())
	# Above the opening there is a lintel, so that must block.
	var into_lintel := PhysicsRayQueryParameters3D.create(Vector3(4, 2.6, 2), Vector3(4, 2.6, -2))
	_check("lintel above the opening is solid", not space.intersect_ray(into_lintel).is_empty())

	# --- Rebuild is idempotent ----------------------------------------------
	var before := _count_in_group(b5.get_node("Built"), RoomBuilder.GROUP_WALL)
	b5.build()
	await process_frame
	var after := _count_in_group(b5.get_node("Built"), RoomBuilder.GROUP_WALL)
	_check("rebuilding produces the same geometry (%d -> %d)" % [before, after], before == after)

	# --- The actual ship layout builds and is walkable ----------------------
	world.free()  # same reason: the test rooms must not sit inside the ship
	await physics_frame

	var ship_scene: Node3D = load("res://scenes/game.tscn").instantiate()
	root.add_child(ship_scene)
	current_scene = ship_scene
	await process_frame
	ship_scene.start_game()
	var ship: Node3D = ship_scene.get_node("Ship")
	_check("ship built rooms", ship.rooms.size() >= 3)
	_check("ship built doorways", ship.doorways.size() >= 2)
	_check("ship has lights", _count_in_group(ship, RoomBuilder.GROUP_LIGHT) >= 3)

	for i in 60:
		await physics_frame
	var player: CharacterBody3D = ship_scene.get_node("Player")
	_check(
		"player stands on the ship floor (y=%.2f)" % player.global_position.y,
		player.is_on_floor() and absf(player.global_position.y - 0.9) < 0.3
	)

	if _failures.is_empty():
		print("ROOM BUILDER TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("ROOM BUILDER TEST FAIL")
		quit(1)
