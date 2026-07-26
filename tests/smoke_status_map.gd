extends SceneTree
# StatusMap / ShipPlan (TODO 19, Phase 1): the ship's damage control plan.
#
# Two things are under test and they are quite different:
#
#   THE DIAGRAM AGREES WITH THE SHIP. `ShipPlan` authors positions but DERIVES connections from
#   `RoomBuilder.doorways`, and the whole point of that split is that the map cannot silently
#   stop matching the ship. So: every room has a node, every node a room, and every door an
#   edge. The mutation at the end proves those checks can actually fail.
#
#   THE DIAGRAM IS LEGIBLE. Octilinear, no crossings, nothing overlapping. These are drawing
#   properties, and they are exactly the ones a render will not tell you about — two lines
#   crossing look deliberate in a PNG.
#
# Then the blobs, which are asserted against `StatusMap.blob_layout()` — the same list `_draw()`
# draws, so this is testing the drawing rather than a parallel calculation of it.
#
# Builds the REAL ship (ship_layout.gd), unlike smoke_room_voice which builds its own: the
# coverage check is meaningless against a made-up two-room ship, since agreeing with the actual
# layout is the only thing it asserts.
#
# Run: godot --headless --path . -s tests/smoke_status_map.gd

const SHIP_LAYOUT := preload("res://scripts/level/ship_layout.gd")

## Slack for comparing schematic coordinates, which are authored to one decimal place.
const EPSILON := 0.0001

## Assertions this suite must have run before it is allowed to call itself green. A section
## that dies mid-way leaves the remaining checks unrun, and without this the suite would
## cheerfully print PASS for the handful that did execute.
const MIN_CHECKS := 60

var _failures: Array[String] = []
var _checks: int = 0
var _ship: RoomBuilder = null
var _plan: ShipPlan = null
var _map: StatusMap = null


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("status map test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	# Doors and lights off: this suite reads `doorways`, which is populated by the layout
	# regardless, and building 12 sliding doors and a grid of omnis for it would be waste.
	_ship = SHIP_LAYOUT.new()
	_ship.build_doors = false
	_ship.build_lights = false
	world.add_child(_ship)
	await process_frame

	_plan = ShipPlan.from_builder(_ship)

	_test_coverage()
	_test_edges()
	_test_octilinear()
	_test_legibility()
	_test_orientation()
	_test_tree()
	await _test_blobs(world)
	_test_mutation()

	if _checks < MIN_CHECKS:
		_failures.append("only %d of the expected %d checks ran — a section died early"
			% [_checks, MIN_CHECKS])

	if _failures.is_empty():
		print("STATUS MAP TEST PASS (%d checks)" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("STATUS MAP TEST FAIL")
		quit(1)


# --- the diagram agrees with the ship ---------------------------------------

func _test_coverage() -> void:
	var missing := ShipPlan.missing_rooms(_ship)
	var orphans := ShipPlan.orphan_nodes(_ship)
	_check("every room on the ship has a node (missing: %s)" % str(missing), missing.is_empty())
	_check("every node names a real room (orphans: %s)" % str(orphans), orphans.is_empty())
	_check("the ship has the 13 rooms the plan draws (%d)" % _ship.rooms.size(),
		_ship.rooms.size() == ShipPlan.NODES.size())


func _test_edges() -> void:
	var doors := 0
	for opening in _ship.doorways:
		if opening.fit_door:
			doors += 1
	_check("the ship has 12 doors (%d)" % doors, doors == 12)
	_check("one edge per door (%d edges, %d doors)" % [_plan.edges.size(), doors],
		_plan.edges.size() == doors)

	for edge in _plan.edges:
		var a: String = edge["a"]
		var b: String = edge["b"]
		_check("edge %s-%s joins two different rooms" % [a, b], a != b)
		_check("edge %s-%s has nodes for both ends" % [a, b],
			ShipPlan.has_node(a) and ShipPlan.has_node(b))

	# Windows must NOT become edges. `Doorway` covers both openings, and the ship has 17
	# windows — if they were counted the diagram would sprout 17 lines into the hull.
	var windows := 0
	for opening in _ship.doorways:
		if opening.fit_window:
			windows += 1
	_check("the ship has windows to have ignored (%d)" % windows, windows > 0)

	# The spine specifically, because it is the edge that proves the axis probe is the right way
	# round: a door SPANNING X separates rooms in Z, and getting that backwards resolves both
	# probes into the same room and produces no edges at all.
	_check("the pod is joined to the spine corridor", _has_edge("corridor", "cryo_bay"))
	_check("the spine corridor is joined to the bridge", _has_edge("bridge", "corridor"))
	# ...and one that spans Z, separating rooms in X.
	_check("the mess is joined to the port arm", _has_edge("corridor_port", "kitchen"))


func _has_edge(a: String, b: String) -> bool:
	for edge in _plan.edges:
		if (edge["a"] == a and edge["b"] == b) or (edge["a"] == b and edge["b"] == a):
			return true
	return false


# --- the diagram is legible -------------------------------------------------

## Beck's rule, and the one thing that makes this read as a tube map rather than a floor plan.
func _test_octilinear() -> void:
	for edge in _plan.edges:
		var delta := ShipPlan.node_at(edge["b"]) - ShipPlan.node_at(edge["a"])
		var straight := absf(delta.x) < EPSILON or absf(delta.y) < EPSILON
		var diagonal := absf(absf(delta.x) - absf(delta.y)) < EPSILON
		_check("edge %s-%s runs at 0, 45 or 90 degrees (%v)" % [edge["a"], edge["b"], delta],
			straight or diagonal)


func _test_legibility() -> void:
	var ids := ShipPlan.NODES.keys()
	# Nodes far enough apart to carry a blob each. A blob is 0.19 units across, and two stations
	# closer than this would merge into one smear the moment both rooms had a problem.
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d := ShipPlan.node_at(ids[i]).distance_to(ShipPlan.node_at(ids[j]))
			_check("%s and %s are far enough apart (%.2f)" % [ids[i], ids[j], d], d >= 1.0)

	# No two lines cross. The ship's graph is a tree, so a crossing would be a drawing mistake
	# rather than a real junction — and it would read as one.
	for i in _plan.edges.size():
		for j in range(i + 1, _plan.edges.size()):
			var e1: Dictionary = _plan.edges[i]
			var e2: Dictionary = _plan.edges[j]
			# Edges sharing an endpoint meet there legitimately.
			if e1["a"] in [e2["a"], e2["b"]] or e1["b"] in [e2["a"], e2["b"]]:
				continue
			# Variant: the API returns the crossing point, or null when there isn't one.
			var hit: Variant = Geometry2D.segment_intersects_segment(
				ShipPlan.node_at(e1["a"]), ShipPlan.node_at(e1["b"]),
				ShipPlan.node_at(e2["a"]), ShipPlan.node_at(e2["b"]))
			_check("edges %s-%s and %s-%s do not cross" % [e1["a"], e1["b"], e2["a"], e2["b"]],
				hit == null)


## The diagram may straighten the ship, but it may not TURN it round.
##
## Coverage and edges between them still allow a mirror image — swap HEAD and CLOSET in the plan
## and every other check here passes, while the map sends the player to the wrong side of the
## bridge. So: for any two rooms genuinely apart on an axis, the schematic must not put them in
## the opposite order. Ties are fine and are the whole point of a tube map — LIFE SUPPORT and
## the MESS are 4m apart in Z on the real ship and sit on one horizontal line here.
func _test_orientation() -> void:
	# Metres. Below this two rooms are level enough that the drawing may order them freely.
	var apart := 2.0
	var centres := {}
	for room in _ship.rooms:
		centres[room.id] = room.center()

	var ids := ShipPlan.NODES.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: String = ids[i]
			var b: String = ids[j]
			if not centres.has(a) or not centres.has(b):
				continue
			var real_a: Vector2 = centres[a]
			var real_b: Vector2 = centres[b]
			var map_a := ShipPlan.node_at(a)
			var map_b := ShipPlan.node_at(b)
			if absf(real_a.x - real_b.x) > apart:
				var forward := real_a.x < real_b.x
				_check("%s is %s of %s on the map as it is on the ship" % [
					a, "port" if forward else "starboard", b],
					map_a.x <= map_b.x if forward else map_a.x >= map_b.x)
			if absf(real_a.y - real_b.y) > apart:
				var forward_z := real_a.y < real_b.y
				_check("%s is %s of %s on the map as it is on the ship" % [
					a, "forward" if forward_z else "aft", b],
					map_a.y <= map_b.y if forward_z else map_a.y >= map_b.y)


## The ship is a tree: one route to anywhere, which is what makes the walks long and the map
## simple. A cycle would mean a shortcut the balance does not know about.
func _test_tree() -> void:
	var reached := {"bridge": true}
	var frontier := ["bridge"]
	while not frontier.is_empty():
		var here: String = frontier.pop_back()
		for edge in _plan.edges:
			var other := ""
			if edge["a"] == here:
				other = edge["b"]
			elif edge["b"] == here:
				other = edge["a"]
			if other != "" and not reached.has(other):
				reached[other] = true
				frontier.append(other)
	_check("every room is reachable from the bridge (%d of %d)" % [
		reached.size(), ShipPlan.NODES.size()], reached.size() == ShipPlan.NODES.size())
	_check("the ship has no loops (%d edges for %d rooms)" % [
		_plan.edges.size(), ShipPlan.NODES.size()],
		_plan.edges.size() == ShipPlan.NODES.size() - 1)


# --- the blobs --------------------------------------------------------------

func _test_blobs(world: Node3D) -> void:
	_map = StatusMap.new()
	_map.size = Vector2(1024, 640)
	world.add_child(_map)
	_map.set_plan(_plan)
	await process_frame

	# The colours the ship already uses on every silo lamp. Asserted rather than imported: a UI
	# script should not have to depend on a game script for a colour, but the two must not be
	# allowed to drift, and this is the thing that stops them.
	_check("map red is the silo lamp red", StatusMap.FAULT_COLOR == Silo.LAMP_CRIT)
	_check("map orange is the silo lamp orange", StatusMap.WARN_COLOR == Silo.LAMP_WARN)

	# --- one problem sits ON its room ---------------------------------------
	_map.set_pulse(0.0)
	_map.set_problems([
		{"room": "engine_room", "kind": StatusMap.Kind.FAULT, "urgency": 0.5, "label": "MAIN DRIVE"},
	])
	var blobs := _map.blob_layout()
	_check("one problem makes one blob (%d)" % blobs.size(), blobs.size() == 1)
	if blobs.size() == 1:
		_check("a lone blob is centred on its room",
			blobs[0]["at"].distance_to(_node_px("engine_room")) < 0.001)
		_check("a fault blob is red", blobs[0]["color"] == StatusMap.FAULT_COLOR)
		_check("the blob is inside the page",
			Rect2(Vector2.ZERO, _map.size).has_point(blobs[0]["at"]))

	# --- problems land in the room they name --------------------------------
	_map.set_problems([
		{"room": "life_support", "kind": StatusMap.Kind.WARNING, "urgency": 0.9, "label": "CO2"},
	])
	blobs = _map.blob_layout()
	_check("a warning blob lands on its own room",
		blobs.size() == 1 and blobs[0]["at"].distance_to(_node_px("life_support")) < 0.001)
	_check("a warning blob is orange",
		blobs.size() == 1 and blobs[0]["color"] == StatusMap.WARN_COLOR)
	_check("a blob on life support is nowhere near the engine room",
		blobs.size() == 1
			and blobs[0]["at"].distance_to(_node_px("engine_room")) > _map.size.y * 0.3)

	# --- several in one room FAN OUT ----------------------------------------
	# The engine room really can hold three faults and the fuel tank at once.
	_map.set_problems([
		{"room": "engine_room", "kind": StatusMap.Kind.FAULT, "urgency": 0.2, "label": "MAIN DRIVE"},
		{"room": "engine_room", "kind": StatusMap.Kind.FAULT, "urgency": 0.4, "label": "COOLANT LOOP"},
		{"room": "engine_room", "kind": StatusMap.Kind.WARNING, "urgency": 0.6, "label": "DRIVE FUEL"},
	])
	blobs = _map.blob_layout()
	_check("three problems in one room make three blobs (%d)" % blobs.size(), blobs.size() == 3)
	var centre := _node_px("engine_room")
	var separated := true
	for i in blobs.size():
		if blobs[i]["at"].distance_to(centre) < 1.0:
			_check("fanned blob %d is off the node centre" % i, false)
		for j in range(i + 1, blobs.size()):
			if blobs[i]["at"].distance_to(blobs[j]["at"]) < blobs[i]["base_radius"]:
				separated = false
	_check("fanned blobs do not sit on top of each other", separated)

	# --- order in, order out -------------------------------------------------
	# Re-collecting the same problems in a different order must not make the blobs swap places:
	# a fan that reshuffled every time RunState emitted would read as movement.
	var positions_a := _positions(blobs)
	_map.set_problems([
		{"room": "engine_room", "kind": StatusMap.Kind.WARNING, "urgency": 0.6, "label": "DRIVE FUEL"},
		{"room": "engine_room", "kind": StatusMap.Kind.FAULT, "urgency": 0.4, "label": "COOLANT LOOP"},
		{"room": "engine_room", "kind": StatusMap.Kind.FAULT, "urgency": 0.2, "label": "MAIN DRIVE"},
	])
	_check("the same problems in a different order draw identically",
		_positions(_map.blob_layout()) == positions_a)

	# --- a problem with nowhere to go is dropped, not drawn at (0,0) ---------
	_map.set_problems([
		{"room": "", "kind": StatusMap.Kind.FAULT, "urgency": 0.5, "label": "NOWHERE"},
		{"room": "bridge", "kind": StatusMap.Kind.FAULT, "urgency": 0.5, "label": "NAV ARRAY"},
	])
	blobs = _map.blob_layout()
	_check("a problem in no room is dropped (%d blobs)" % blobs.size(), blobs.size() == 1)
	_check("and the real one is unaffected by it",
		blobs.size() == 1 and blobs[0]["room"] == "bridge"
			and blobs[0]["at"].distance_to(_node_px("bridge")) < 0.001)

	# --- rate encodes urgency ------------------------------------------------
	_map.set_problems([
		{"room": "bridge", "kind": StatusMap.Kind.FAULT, "urgency": 0.0, "label": "calm"},
		{"room": "cargo_bay", "kind": StatusMap.Kind.FAULT, "urgency": 1.0, "label": "urgent"},
		{"room": "cryo_bay", "kind": StatusMap.Kind.WARNING, "urgency": 1.0, "label": "urgent supply"},
	])
	var hz := {}
	for blob in _map.blob_layout():
		hz[blob["room"]] = blob["hz"]
	_check("an unurgent fault pulses at the floor (%.2f)" % hz.get("bridge", -1.0),
		absf(hz.get("bridge", -1.0) - StatusMap.PULSE_MIN_HZ) < EPSILON)
	_check("a desperate one pulses at the ceiling (%.2f)" % hz.get("cargo_bay", -1.0),
		absf(hz.get("cargo_bay", -1.0) - StatusMap.PULSE_MAX_HZ) < EPSILON)
	# The rate is about how bad it is, not about which kind it is: a tank about to run dry is as
	# urgent as a drive about to fail, and the colour is what says which errand it is.
	_check("a desperate supply pulses like a desperate fault (%.2f)" % hz.get("cryo_bay", -1.0),
		absf(hz.get("cryo_bay", -1.0) - StatusMap.PULSE_MAX_HZ) < EPSILON)

	# --- it actually pulses ---------------------------------------------------
	# Measured off the resolved draw list rather than a render: `blob_layout()` is what `_draw()`
	# consumes, so a radius that does not move here cannot move on screen either.
	_map.set_problems([
		{"room": "engine_room", "kind": StatusMap.Kind.FAULT, "urgency": 1.0, "label": "MAIN DRIVE"},
	])
	_map.set_pulse(0.0)
	var base: float = _map.blob_layout()[0]["base_radius"]
	var at_zero: float = _map.blob_layout()[0]["radius"]
	# A quarter cycle at the top rate is the peak of the breath.
	_map.set_pulse(0.25 / StatusMap.PULSE_MAX_HZ)
	var at_peak: float = _map.blob_layout()[0]["radius"]
	_map.set_pulse(0.75 / StatusMap.PULSE_MAX_HZ)
	var at_trough: float = _map.blob_layout()[0]["radius"]
	_check("the blob breathes out (%.2f -> %.2f)" % [at_zero, at_peak], at_peak > at_zero)
	_check("and back in (%.2f -> %.2f)" % [at_zero, at_trough], at_trough < at_zero)
	_check("the peak is the configured depth (%.3f)" % (at_peak / base),
		absf(at_peak / base - (1.0 + StatusMap.PULSE_DEPTH)) < 0.001)
	_check("the trough is too (%.3f)" % (at_trough / base),
		absf(at_trough / base - (1.0 - StatusMap.PULSE_DEPTH)) < 0.001)

	# --- YOU ARE HERE ---------------------------------------------------------
	_check("nobody is pointed at until somebody says where the player is",
		_map.here_layout().is_empty())

	_map.set_player_room("cryo_bay")
	var here := _map.here_layout()
	_check("the marker names the room it was given",
		not here.is_empty() and here["room"] == "cryo_bay")
	if not here.is_empty():
		var node: Vector2 = here["node"]
		_check("the marker sits on the pod", node.distance_to(_node_px("cryo_bay")) < 0.001)
		# The arrow POINTS AT the room: its tip is nearer the node than its tail is, and the tip
		# is close enough to touch the ring. An arrow that pointed the other way would still be
		# an arrow near the right room, which is exactly the bug this catches.
		var tail: Vector2 = here["tail"]
		var tip: Vector2 = here["tip"]
		_check("the arrow points inward at the node (%.1f -> %.1f)" % [
			tail.distance_to(node), tip.distance_to(node)],
			tip.distance_to(node) < tail.distance_to(node))
		_check("and its tip reaches the node's own ring",
			tip.distance_to(node) < _map.size.y * 0.06)
		# The caption has to stay on the page whichever room the player is in.
		var page := Rect2(Vector2.ZERO, _map.size)
		_check("the caption is on the page", page.has_point(here["caption"]))
		# Smaller than a blob, and by a clear margin: the player is not a problem and must not
		# be mistaken for one at a glance across the room. Measured against a real blob's real
		# radius rather than against the constants, so it is the DRAWN sizes being compared.
		_map.set_problems([
			{"room": "bridge", "kind": StatusMap.Kind.FAULT, "urgency": 0.5, "label": "size probe"},
		])
		var blob_radius: float = _map.blob_layout()[0]["base_radius"]
		var dot_radius: float = _map.here_layout()["base_radius"]
		_check("the dot is smaller than a problem blob (%.1f vs %.1f)" % [dot_radius, blob_radius],
			dot_radius < blob_radius * 0.6)
		# White, which is not a hue — so the two trouble colours keep the page to themselves.
		_check("the dot is white, not a trouble colour",
			StatusMap.HERE_COLOR.r > 0.85 and StatusMap.HERE_COLOR.g > 0.85
				and StatusMap.HERE_COLOR.b > 0.85)
		# ...and it must never be able to look like the most pressing thing on the page.
		_check("it pulses slower than the calmest blob (%.2f vs %.2f)" % [
			StatusMap.HERE_HZ, StatusMap.PULSE_MIN_HZ],
			StatusMap.HERE_HZ < StatusMap.PULSE_MIN_HZ)

		# And it really does pulse.
		_map.set_pulse(0.0)
		var flat: float = _map.here_layout()["radius"]
		_map.set_pulse(0.25 / StatusMap.HERE_HZ)
		var peak: float = _map.here_layout()["radius"]
		_map.set_pulse(0.75 / StatusMap.HERE_HZ)
		var trough: float = _map.here_layout()["radius"]
		_check("the dot breathes out (%.2f -> %.2f)" % [flat, peak], peak > flat)
		_check("and back in (%.2f -> %.2f)" % [flat, trough], trough < flat)
		_map.set_pulse(0.0)

	# Every room, because the caption is placed on a ray out of the diagram and the rooms at the
	# edges are the ones that can push it off the page.
	for id in ShipPlan.NODES:
		_map.set_player_room(id)
		var each := _map.here_layout()
		_check("%s gets a marker" % id, not each.is_empty())
		if each.is_empty():
			continue
		_check("%s keeps its caption on the page (%v)" % [id, each["caption"]],
			Rect2(Vector2.ZERO, _map.size).has_point(each["caption"]))
		_check("%s has its arrow pointing at itself" % id,
			(each["tip"] as Vector2).distance_to(each["node"]) <
			(each["tail"] as Vector2).distance_to(each["node"]))

	# Standing in a doorway is a real state — RoomBuilder.room_at() returns "" there — and it
	# must simply hide the marker rather than drawing it at the origin.
	_map.set_player_room("")
	_check("a player between rooms is not pointed at", _map.here_layout().is_empty())
	_map.set_player_room("nowhere_at_all")
	_check("nor is one in a room the map does not have", _map.here_layout().is_empty())
	_map.set_player_room("cryo_bay")

	# --- a clean ship costs nothing per frame --------------------------------
	# A static drawing must not redraw. This is the whole reason the map is not simply on
	# _process like an ordinary animated Control.
	_map.set_problems([])
	_map.set_player_room("")
	await process_frame
	_check("with nothing pulsing, the page stops processing", not _map.is_processing())
	# EITHER pulsing thing is enough to want a frame loop, and the player's dot is one of them.
	_map.set_player_room("cryo_bay")
	await process_frame
	_check("the player's dot alone is enough to start it", _map.is_processing())
	_map.set_player_room("")
	await process_frame
	_check("and it stops again when they are between rooms", not _map.is_processing())
	_map.set_problems([
		{"room": "bridge", "kind": StatusMap.Kind.FAULT, "urgency": 0.5, "label": "NAV ARRAY"},
	])
	await process_frame
	_check("a problem starts it too", _map.is_processing())


func _node_px(room_id: String) -> Vector2:
	# Whatever the map's own transform is; this suite asserts relationships, not pixel values,
	# so re-deriving the transform here would just be a second implementation to keep in sync.
	for blob in _reference_layout(room_id):
		return blob["at"]
	return Vector2.ZERO


## One blob in `room_id` and nothing else, purely to read back where that room lands.
func _reference_layout(room_id: String) -> Array[Dictionary]:
	var probe := StatusMap.new()
	probe.size = _map.size
	probe.set_plan(_plan)
	probe.set_problems([{"room": room_id, "kind": StatusMap.Kind.FAULT, "urgency": 0.0}])
	var out := probe.blob_layout()
	probe.free()
	return out


func _positions(blobs: Array[Dictionary]) -> Array:
	var out := []
	for blob in blobs:
		out.append(blob["at"])
	return out


# --- the mutation -----------------------------------------------------------

## The coverage checks are the reason `ShipPlan` derives its edges instead of listing them, so
## they have to be shown to fail. A guard nobody has watched fail is decoration.
func _test_mutation() -> void:
	var mutant := RoomBuilder.new()
	mutant.build_doors = false
	mutant.build_lights = false
	for room in _ship.rooms:
		mutant.add_room(room.rect, {"id": room.id})
	mutant.add_room(Rect2i(100, 100, 4, 4), {"id": "observation_deck"})

	var missing := ShipPlan.missing_rooms(mutant)
	_check("adding a room to the ship makes the coverage check fail (%s)" % str(missing),
		missing.size() == 1 and missing[0] == "observation_deck")
	_check("and the unchanged ship still passes it",
		ShipPlan.missing_rooms(_ship).is_empty())

	# The other direction: a room the plan draws that the ship no longer has.
	var shrunk := RoomBuilder.new()
	shrunk.build_doors = false
	shrunk.build_lights = false
	for room in _ship.rooms:
		if room.id != "janitor_closet":
			shrunk.add_room(room.rect, {"id": room.id})
	var orphans := ShipPlan.orphan_nodes(shrunk)
	_check("removing a room makes the orphan check fail (%s)" % str(orphans),
		orphans.size() == 1 and orphans[0] == "janitor_closet")

	mutant.free()
	shrunk.free()
