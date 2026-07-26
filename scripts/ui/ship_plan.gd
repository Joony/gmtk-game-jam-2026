class_name ShipPlan
extends RefCounted

# The ship as a London Underground diagram: where each room sits on the page, and which rooms
# are joined to which.
#
# HALF OF THIS IS AUTHORED AND HALF IS DERIVED, and the split is the whole point.
#
#   AUTHORED   the schematic POSITIONS below. Beck's transformation is a drawing decision and
#              there is no algorithm for it — you cannot compute "this reads well at a glance".
#   DERIVED    the CONNECTIONS, from `RoomBuilder.doorways` at runtime. A hand-authored edge
#              list would quietly stop matching the ship the first time a door moved, and
#              nothing would say so.
#
# `ship_layout.gd` is emphatic that the room rectangles come from a drawing and must not be
# hand-edited, so the same rule applies here: this file may only ever disagree with the ship
# about LAYOUT, never about TOPOLOGY. `smoke_status_map` holds the other half of the bargain —
# every room must have a node and every node a room, or the suite fails.
#
# COORDINATES are schematic units, not metres: +x is starboard, +y is aft, and the bow is at
# the top of the page because travel is -Z. Scale and centring are the drawing's business
# (see StatusMap), so nothing here depends on the size of the screen.

enum Glyph {
	## An unnamed stop — a corridor. On the line, but there is nothing to do there.
	TICK,
	## A named room.
	STATION,
	## More than two ways out. Only the bridge.
	JUNCTION,
	## The end of the line, and the place you always come back to.
	TERMINUS,
}

## How far either side of an opening to probe for the rooms it joins, in grid units. Every
## corridor on the ship is 3m wide and the smallest room is 3x3, so 0.6 lands well inside both
## and never on a boundary — where `RoomBuilder.room_at()` is ambiguous by construction, since
## its bounds are inclusive at both ends.
const PROBE := 0.6

## Where each room sits on the page. Thirteen rooms, and the ship's real shape is already
## almost octilinear — corridors run along X and Z — so this is close to a straightened version
## of the truth rather than a reinvention of it.
##
## `label_dir` is stated rather than inferred. A heuristic ("label goes on the side away from
## the line") gets the bridge and the two stubs wrong, and there are only thirteen of them.
const NODES := {
	# The bow. Five doors, so it is the only junction on the ship.
	"bridge": {"at": Vector2(0.0, 0.0), "label": "BRIDGE", "glyph": Glyph.JUNCTION, "label_dir": "above"},

	# Port arm: out to the mess, then aft to the engine room.
	"corridor_port": {"at": Vector2(-1.6, 0.0), "label": "", "glyph": Glyph.TICK, "label_dir": "above"},
	"kitchen": {"at": Vector2(-3.0, 0.0), "label": "MESS", "glyph": Glyph.STATION, "label_dir": "above"},
	"corridor_engine": {"at": Vector2(-3.0, 1.6), "label": "", "glyph": Glyph.TICK, "label_dir": "left"},
	"engine_room": {"at": Vector2(-3.0, 3.0), "label": "ENGINE", "glyph": Glyph.STATION, "label_dir": "below"},

	# Starboard arm, mirroring it: life support, then aft to the cargo bay.
	"corridor_stbd": {"at": Vector2(1.6, 0.0), "label": "", "glyph": Glyph.TICK, "label_dir": "above"},
	"life_support": {"at": Vector2(3.0, 0.0), "label": "LIFE SUPPORT", "glyph": Glyph.STATION, "label_dir": "above"},
	"corridor_cargo": {"at": Vector2(3.0, 1.6), "label": "", "glyph": Glyph.TICK, "label_dir": "right"},
	"cargo_bay": {"at": Vector2(3.0, 3.0), "label": "CARGO", "glyph": Glyph.STATION, "label_dir": "below"},

	# Two stubs off the bridge's aft wall, at 45° either side of the spine — which is where
	# they really are, so the schematic costs nothing here.
	"bathroom": {"at": Vector2(-1.3, 1.3), "label": "HEAD", "glyph": Glyph.STATION, "label_dir": "left"},
	"janitor_closet": {"at": Vector2(1.3, 1.3), "label": "CLOSET", "glyph": Glyph.STATION, "label_dir": "right"},

	# The spine, and the pod at the end of it. The player's anchor: every trip starts and ends
	# here, so it gets the terminus glyph.
	"corridor": {"at": Vector2(0.0, 1.7), "label": "", "glyph": Glyph.TICK, "label_dir": "right"},
	"cryo_bay": {"at": Vector2(0.0, 3.0), "label": "POD", "glyph": Glyph.TERMINUS, "label_dir": "below"},
}

## Which line each run of rooms belongs to, in order. Used only to pick a stroke weight — see
## the note on WEIGHTS in StatusMap. An edge whose endpoints are not consecutive in any line is
## a stub, and gets the stub weight.
const LINES := {
	"SPINE": ["bridge", "corridor", "cryo_bay"],
	"PORT": ["engine_room", "corridor_engine", "kitchen", "corridor_port", "bridge"],
	"STARBOARD": ["bridge", "corridor_stbd", "life_support", "corridor_cargo", "cargo_bay"],
}

## {"a": room id, "b": room id, "line": name or ""}. Filled by from_builder().
var edges: Array[Dictionary] = []


## Read the ship's doorways and build the diagram's edges from them.
static func from_builder(builder: RoomBuilder) -> ShipPlan:
	var plan := ShipPlan.new()
	plan.edges = derive_edges(builder)
	return plan


## One edge per DOOR. Windows are skipped: `Doorway` covers both (see its own note on the
## name), and a window joins a room to space, which is not a walk anyone survives.
static func derive_edges(builder: RoomBuilder) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for opening in builder.doorways:
		if not opening.fit_door:
			continue
		var pair := rooms_joined_by(builder, opening)
		if pair.size() != 2:
			# A door with nothing on one side of it is a hole in the hull, not an edge. Loud,
			# because it means the ship is wrong rather than the map.
			push_warning("ShipPlan: door at %v joins %d rooms, not 2" % [opening.position, pair.size()])
			continue
		var key := "%s|%s" % [pair[0], pair[1]]
		if seen.has(key):
			continue
		seen[key] = true
		out.append({"a": pair[0], "b": pair[1], "line": line_for(pair[0], pair[1])})
	return out


## The two rooms an opening separates, sorted, so the same pair always produces the same key.
##
## `Axis.X` means the opening SPANS X, so the wall it is cut through runs along X and the rooms
## are either side of it in Z. Getting that backwards resolves every door to one room twice and
## produces an empty diagram, which is why the smoke test counts edges.
static func rooms_joined_by(builder: RoomBuilder, opening: Doorway) -> PackedStringArray:
	var step := Vector2(0.0, PROBE) if opening.axis == Doorway.Axis.X else Vector2(PROBE, 0.0)
	var rooms := PackedStringArray()
	for side in [-1.0, 1.0]:
		var grid: Vector2 = opening.position + step * side
		var world := builder.grid_to_world(grid.x, grid.y)
		var id := builder.room_at(Vector3(world.x, 0.0, world.y))
		if id != "" and not rooms.has(id):
			rooms.append(id)
	rooms.sort()
	return rooms


## The line two adjacent rooms sit on, or "" for a stub.
static func line_for(a: String, b: String) -> String:
	for line_name in LINES:
		var run: Array = LINES[line_name]
		for i in run.size() - 1:
			if (run[i] == a and run[i + 1] == b) or (run[i] == b and run[i + 1] == a):
				return line_name
	return ""


static func has_node(room_id: String) -> bool:
	return NODES.has(room_id)


static func node_at(room_id: String) -> Vector2:
	return NODES[room_id]["at"] if NODES.has(room_id) else Vector2.ZERO


# --- drift guards -----------------------------------------------------------
#
# The two halves of the bargain this file makes with `ship_layout.gd`. Both are asserted by
# `smoke_status_map`; neither is called by the drawing code, because a map that silently
# dropped a room would still render.

## Rooms on the ship with nowhere to be drawn.
static func missing_rooms(builder: RoomBuilder) -> PackedStringArray:
	var out := PackedStringArray()
	for room in builder.rooms:
		if not NODES.has(room.id):
			out.append(room.id)
	return out


## Nodes on the diagram that name a room the ship does not have.
static func orphan_nodes(builder: RoomBuilder) -> PackedStringArray:
	var ids := {}
	for room in builder.rooms:
		ids[room.id] = true
	var out := PackedStringArray()
	for id in NODES:
		if not ids.has(id):
			out.append(id)
	return out
