extends SceneTree

# The ship's own geometry, checked against the drawing it was transcribed from
# (docs/features/ship-layout.md). smoke_room_builder.gd covers the BUILDER — this covers the
# LAYOUT, which that suite only asserts `rooms.size() >= 3` about. A wrong ship passes there.
#
# Every expectation below is derived from room_layout_3.png, not from ship_layout.gd, so this
# fails if the code drifts from the drawing.
#
# Run: godot --headless --path . -s tests/smoke_ship_layout.gd

var _failures: Array[String] = []

# id -> Rect2i, straight off the decoded image.
const EXPECTED_ROOMS := {
	"bridge": Rect2i(-9, -22, 19, 10),
	"kitchen": Rect2i(10, -17, 11, 11),
	"bathroom": Rect2i(-8, -12, 7, 8),
	"janitor_closet": Rect2i(2, -9, 6, 5),
	"life_support": Rect2i(-29, -6, 13, 13),
	"pod_bay": Rect2i(-10, -4, 21, 21),
	"engine_room": Rect2i(-39, 7, 21, 21),
	"cargo_bay": Rect2i(19, -1, 21, 33),
	"corridor": Rect2i(-1, -12, 3, 8),
	"corridor_fore": Rect2i(2, -12, 8, 3),
	"corridor_life": Rect2i(-16, -1, 6, 3),
	"corridor_engine": Rect2i(-18, 10, 8, 3),
	"corridor_cargo": Rect2i(11, 10, 8, 3),
}

const EXPECTED_DOORS := 12   # 11 drawn doors + the unsealed corridor bend
const EXPECTED_WINDOWS := 16


func _init() -> void:
	_run.call_deferred()
	_watchdog.call_deferred()


func _watchdog() -> void:
	await create_timer(60.0).timeout
	push_error("watchdog fired: the test never finished (look for a SCRIPT ERROR above)")
	print("SHIP LAYOUT TEST FAIL")
	quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	var ship := load("res://scripts/level/ship_layout.gd").new() as RoomBuilder
	root.add_child(ship)
	await process_frame

	var by_id := {}
	for room in ship.rooms:
		by_id[room.id] = room

	# --- rooms match the drawing --------------------------------------------
	_check("room count is %d (got %d)" % [EXPECTED_ROOMS.size(), ship.rooms.size()],
		ship.rooms.size() == EXPECTED_ROOMS.size())
	for id: String in EXPECTED_ROOMS:
		if not by_id.has(id):
			_check("room '%s' exists" % id, false)
			continue
		var got: Rect2i = by_id[id].rect
		_check("room '%s' rect is %s (got %s)" % [id, EXPECTED_ROOMS[id], got],
			got == EXPECTED_ROOMS[id])

	# --- no two rooms overlap ------------------------------------------------
	# The builder gives every room a closed wall skin, so an overlap raises a wall through a
	# neighbour's floor. This is why the drawn L-shaped corridor is built as two rectangles.
	for i in ship.rooms.size():
		for j in range(i + 1, ship.rooms.size()):
			var a: Room = ship.rooms[i]
			var b: Room = ship.rooms[j]
			var hit := a.rect.intersection(b.rect)
			_check("rooms '%s' and '%s' do not overlap (%s)" % [a.id, b.id, hit],
				hit.size.x == 0 or hit.size.y == 0)

	# --- opening tallies -----------------------------------------------------
	var doors := 0
	var windows := 0
	for opening: Doorway in ship.doorways:
		if opening.fit_window:
			windows += 1
		else:
			doors += 1
	_check("door count is %d (got %d)" % [EXPECTED_DOORS, doors], doors == EXPECTED_DOORS)
	_check("window count is %d (got %d)" % [EXPECTED_WINDOWS, windows], windows == EXPECTED_WINDOWS)

	# --- every door joins exactly two spaces ---------------------------------
	# A door onto hull is a hole in the hull; a door on no wall at all is a door to nowhere.
	for opening: Doorway in ship.doorways:
		if opening.fit_window:
			continue
		var joined := _spaces_on_wall(ship, opening)
		_check("door at %s joins 2 spaces (joins %d: %s)" % [opening.position, joined.size(), joined],
			joined.size() == 2)

	# --- every window faces open hull ----------------------------------------
	# The failure this catches: a window onto another room shows stars THROUGH the ship.
	for opening: Doorway in ship.doorways:
		if not opening.fit_window:
			continue
		var joined := _spaces_on_wall(ship, opening)
		_check("window at %s faces hull (opens into %s)" % [opening.position, joined],
			joined.size() == 1)

	# --- the corridor bend is genuinely open ---------------------------------
	# The seam between the spine and the fore arm must leave NO wall geometry: no sill below,
	# no lintel above. Assert on the built boxes, not on the Doorway's fields, because it is
	# the geometry that the player walks into.
	var bend_walls := 0
	for node in ship.find_children("*", "StaticBody3D", true, false):
		if not node.is_in_group(RoomBuilder.GROUP_WALL):
			continue
		# The bend spans x=2, z=-12..-9. A wall box straddling that line inside that span
		# is the seam failing to open.
		if absf(node.position.x - 2.0) < 0.2 and node.position.z > -12.0 and node.position.z < -9.0:
			bend_walls += 1
	_check("corridor bend has no wall across it (found %d boxes)" % bend_walls, bend_walls == 0)

	# --- no light can reach another room's shell -----------------------------
	# The fixtures are shadowless (GL Compatibility cannot afford shadows), so a light with an
	# unmasked cull mask shines straight through walls — the corridor lit the pod bay's floor
	# from outside it. Confinement is by visual layer, which means it is checkable here rather
	# than only by looking: a light's cull mask must intersect its OWN room's layer and no
	# other room's.
	var layers := {}
	for id: String in EXPECTED_ROOMS:
		layers[id] = ship.room_layer(id)
	var distinct := {}
	for id: String in layers:
		distinct[layers[id]] = true
	_check("every room has its own visual layer (%d rooms, %d layers)" % [layers.size(), distinct.size()],
		distinct.size() == layers.size())

	# No room may sit on the EXTERIOR layer. ExteriorSun is a DirectionalLight3D masked to
	# layer 2 so it lights the station outside and nothing within; a room sharing that layer
	# gets white directional light across whichever surfaces happen to face the sun, which
	# reads as "the floor and two walls ignore the alert lighting".
	for id: String in layers:
		_check("room '%s' is off the exterior layer (mask %d)" % [id, layers[id]],
			(layers[id] & RoomBuilder.EXTERIOR_LAYER) == 0)

	for light in ship.find_children("*", "OmniLight3D", true, false):
		var owner_id: String = light.get_meta("room_id", "")
		var mask: int = (light as OmniLight3D).light_cull_mask
		_check("light in '%s' lights its own room" % owner_id,
			owner_id != "" and (mask & layers.get(owner_id, 0)) != 0)
		var leaks: Array = []
		for id: String in layers:
			if id != owner_id and (mask & layers[id]) != 0:
				leaks.append(id)
		_check("light in '%s' cannot reach %s" % [owner_id, leaks], leaks.is_empty())

	# --- the ship is one connected space -------------------------------------
	# Reachability through doors only. Catches a room drawn correctly but sealed off.
	var reached := _flood(ship)
	for id: String in EXPECTED_ROOMS:
		_check("'%s' is reachable from the pod bay" % id, reached.has(id))

	_report()


## Which rooms have a wall on the line this opening sits on, overlapping its span.
func _spaces_on_wall(ship: RoomBuilder, opening: Doorway) -> Array:
	var out: Array = []
	var half: float = opening.width * 0.5
	for room: Room in ship.rooms:
		var x0 := float(room.rect.position.x)
		var z0 := float(room.rect.position.y)
		var x1 := x0 + float(room.rect.size.x)
		var z1 := z0 + float(room.rect.size.y)
		if opening.axis == Doorway.Axis.X:
			# Opening spans X, so it cuts a wall running along X: the room's z0 or z1 line.
			var on_line := absf(opening.position.y - z0) < 0.05 or absf(opening.position.y - z1) < 0.05
			if on_line and opening.position.x + half > x0 + 0.05 and opening.position.x - half < x1 - 0.05:
				out.append(room.id)
		else:
			var on_line2 := absf(opening.position.x - x0) < 0.05 or absf(opening.position.x - x1) < 0.05
			if on_line2 and opening.position.y + half > z0 + 0.05 and opening.position.y - half < z1 - 0.05:
				out.append(room.id)
	return out


## Room ids reachable from the pod bay by walking through doorways.
func _flood(ship: RoomBuilder) -> Dictionary:
	var edges := {}
	for opening: Doorway in ship.doorways:
		if opening.fit_window:
			continue
		var joined := _spaces_on_wall(ship, opening)
		if joined.size() != 2:
			continue
		edges.get_or_add(joined[0], []).append(joined[1])
		edges.get_or_add(joined[1], []).append(joined[0])
	var seen := {"pod_bay": true}
	var queue: Array = ["pod_bay"]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		for next: String in edges.get(at, []):
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen


func _report() -> void:
	if _failures.is_empty():
		print("SHIP LAYOUT TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("SHIP LAYOUT TEST FAIL")
		quit(1)
