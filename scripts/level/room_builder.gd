class_name RoomBuilder
extends Node3D

# Runtime geometry kit ported from GMTK 2025's V1/RoomBuilder.gd: rectangular rooms
# with auto-generated perimeter walls that split correctly around doorways. That
# splitting is the genuinely non-trivial part and it came over nearly intact.
#
# Three deliberate departures from the 2025 version:
#
# 1. ONE COORDINATE CONVENTION. 2025 had two — grid_to_world (tile centres, +0.5) for
#    floors and grid_boundary_to_world (tile edges) for walls — and BOTH subtracted
#    level_width/2, so world position depended on the level's declared size. Adding a
#    room moved everything already placed, which is why its level data is full of
#    hand-tuned floats like Vector3(11.4, 1.285, 6.07). Here grid coordinates are
#    boundary coordinates and map straight to world: grid (x, y) -> world
#    (x * tile_size, y * tile_size), with grid y running along world Z. Tile centres
#    are at +0.5. No centring, no level dimensions.
#
# 2. ONE BOX PER SURFACE, not one per tile. 2025 emitted a StaticBody3D per floor tile
#    and per ceiling tile — a 20x20 room cost 800 nodes. Rooms are rectangles, so a
#    single box each does the same job.
#
# 3. SHARED WALLS ARE BUILT ONCE. Adjacent rooms each generate the wall between them.
#    Rather than 2025's per-side nudge offsets to hide the resulting z-fighting, wall
#    spans are tracked per line and each new segment has the already-built spans
#    subtracted from it. Handles partial overlaps between differently-sized rooms too.
#
# Lights: one omni per room, in the `room_lights` group so step 10's lighting modes can
# retint them. Deliberately NOT 2025's one-OmniLight3D-per-floor-tile, which was a
# GL-compatibility-era hack costing hundreds of lights on a large level.

const GROUP_FLOOR := &"room_floor"
const GROUP_CEILING := &"room_ceiling"
const GROUP_WALL := &"room_wall"
const GROUP_LIGHT := &"room_lights"

@export var tile_size: float = 1.0
@export var wall_thickness: float = 0.15
@export var floor_thickness: float = 0.2
@export var ceiling_thickness: float = 0.2
## Height of doorway openings. The wall above one becomes a lintel.
@export var doorway_height: float = 2.2
@export var build_lights: bool = true
## Fallback light colour. Step 10's LightingController drives these once it exists.
@export var light_color: Color = Color(1.0, 0.97, 0.92)
@export var light_energy: float = 1.4

var rooms: Array[Room] = []
var doorways: Array[Doorway] = []

var _materials: Dictionary = {}
# line key -> Array[Vector2] of [min, max] spans already built on that line.
var _spans: Dictionary = {}
var _built_root: Node3D = null


## Add a room. `opts` may set: height, floor_color, wall_color, ceiling_color, id.
func add_room(rect: Rect2i, opts: Dictionary = {}) -> Room:
	var room := Room.new(
		opts.get("id", "room_%d" % rooms.size()),
		rect,
		opts.get("height", 3.0)
	)
	if opts.has("floor_color"):
		room.floor_color = opts["floor_color"]
	if opts.has("wall_color"):
		room.wall_color = opts["wall_color"]
	if opts.has("ceiling_color"):
		room.ceiling_color = opts["ceiling_color"]
	rooms.append(room)
	return room


func add_doorway(position: Vector2, axis: Doorway.Axis, width: float = 1.6) -> Doorway:
	var doorway := Doorway.new(position, axis, width)
	doorways.append(doorway)
	return doorway


## Grid (boundary) coordinates to world XZ. The single conversion in the system.
func grid_to_world(grid_x: float, grid_y: float) -> Vector2:
	return Vector2(grid_x, grid_y) * tile_size


func clear() -> void:
	if _built_root != null and is_instance_valid(_built_root):
		_built_root.free()
	_built_root = null
	_spans.clear()
	_materials.clear()


## Build every room and doorway added so far. Safe to call again — it rebuilds.
func build() -> Node3D:
	clear()
	_built_root = Node3D.new()
	_built_root.name = "Built"
	add_child(_built_root)

	for room in rooms:
		_build_floor(room)
		_build_ceiling(room)
		if build_lights:
			_build_light(room)
	# Walls last, so span subtraction sees every room's openings consistently.
	for room in rooms:
		_build_walls(room)
	return _built_root


# --- surfaces ---------------------------------------------------------------

func _build_floor(room: Room) -> void:
	var size := Vector3(room.rect.size.x * tile_size, floor_thickness, room.rect.size.y * tile_size)
	var centre := grid_to_world(room.center().x, room.center().y)
	var body := _make_box(
		"Floor_%s" % room.id,
		size,
		Vector3(centre.x, -floor_thickness * 0.5, centre.y),
		_material("floor_" + room.id, room.floor_color),
		true
	)
	body.add_to_group(GROUP_FLOOR)


func _build_ceiling(room: Room) -> void:
	var size := Vector3(room.rect.size.x * tile_size, ceiling_thickness, room.rect.size.y * tile_size)
	var centre := grid_to_world(room.center().x, room.center().y)
	var body := _make_box(
		"Ceiling_%s" % room.id,
		size,
		Vector3(centre.x, room.height + ceiling_thickness * 0.5, centre.y),
		_material("ceiling_" + room.id, room.ceiling_color),
		true
	)
	body.add_to_group(GROUP_CEILING)


func _build_light(room: Room) -> void:
	var light := OmniLight3D.new()
	light.name = "Light_%s" % room.id
	var centre := grid_to_world(room.center().x, room.center().y)
	light.position = Vector3(centre.x, room.height - 0.4, centre.y)
	var span: float = maxf(room.rect.size.x, room.rect.size.y) * tile_size
	light.omni_range = span * 1.1
	light.light_color = light_color
	light.light_energy = light_energy
	light.shadow_enabled = false
	light.add_to_group(GROUP_LIGHT)
	_built_root.add_child(light)


# --- walls ------------------------------------------------------------------

func _build_walls(room: Room) -> void:
	var material := _material("wall_" + room.id, room.wall_color)
	for wall in room.perimeter_walls():
		for segment in wall_segments(wall["start"], wall["end"], doorways):
			_emit_wall_span(segment, room, material)


func _emit_wall_span(segment: Dictionary, room: Room, material: StandardMaterial3D) -> void:
	var start: Vector2 = segment["start"]
	var end: Vector2 = segment["end"]
	var has_door: bool = segment["has_door"]
	var runs_along_x := absf(end.x - start.x) > absf(end.y - start.y)

	var key := ("H:%.3f" % start.y) if runs_along_x else ("V:%.3f" % start.x)
	# A lintel and a full wall can share a line without being the same thing.
	key += "|door" if has_door else "|solid"
	var lo := minf(start.x, end.x) if runs_along_x else minf(start.y, end.y)
	var hi := maxf(start.x, end.x) if runs_along_x else maxf(start.y, end.y)

	var existing: Array = _spans.get(key, [])
	for piece in subtract_spans(Vector2(lo, hi), existing):
		if piece.y - piece.x < 0.01:
			continue
		var piece_start := Vector2(piece.x, start.y) if runs_along_x else Vector2(start.x, piece.x)
		var piece_end := Vector2(piece.y, start.y) if runs_along_x else Vector2(start.x, piece.y)
		_create_wall(piece_start, piece_end, room, material, has_door)
		existing.append(piece)
	_spans[key] = existing


func _create_wall(start: Vector2, end: Vector2, room: Room, material: StandardMaterial3D, has_door: bool) -> void:
	var length := start.distance_to(end) * tile_size
	if length < 0.01:
		return
	var runs_along_x := absf(end.x - start.x) > absf(end.y - start.y)

	# Above a doorway only a lintel remains.
	var wall_height := room.height - doorway_height if has_door else room.height
	if wall_height <= 0.01:
		return
	var y_offset := doorway_height if has_door else 0.0

	var size := Vector3(length, wall_height, wall_thickness)
	if not runs_along_x:
		size = Vector3(wall_thickness, wall_height, length)

	var centre := grid_to_world((start.x + end.x) * 0.5, (start.y + end.y) * 0.5)
	var body := _make_box(
		"Wall_%s_%.1f_%.1f" % [room.id, start.x, start.y],
		size,
		Vector3(centre.x, y_offset + wall_height * 0.5, centre.y),
		material,
		true
	)
	body.add_to_group(GROUP_WALL)
	if has_door:
		body.set_meta("lintel", true)


## Split a wall into segments around any doorways crossing it. Ported from 2025's
## get_wall_segments_with_doors(). Segments flagged `has_door` become lintels.
static func wall_segments(wall_start: Vector2, wall_end: Vector2, all_doorways: Array[Doorway]) -> Array[Dictionary]:
	var crossing: Array[Doorway] = []
	for doorway in all_doorways:
		if doorway.intersects_wall(wall_start, wall_end):
			crossing.append(doorway)

	if crossing.is_empty():
		return [{"start": wall_start, "end": wall_end, "has_door": false}]

	var runs_along_x := absf(wall_end.x - wall_start.x) > absf(wall_end.y - wall_start.y)
	if runs_along_x:
		crossing.sort_custom(func(a: Doorway, b: Doorway) -> bool: return a.position.x < b.position.x)
	else:
		crossing.sort_custom(func(a: Doorway, b: Doorway) -> bool: return a.position.y < b.position.y)

	var segments: Array[Dictionary] = []
	var cursor := wall_start
	for doorway in crossing:
		var opening: Dictionary = doorway.bounds()
		var opening_start: Vector2 = opening["start"]
		var opening_end: Vector2 = opening["end"]
		# Pull the opening onto the wall line.
		if runs_along_x:
			opening_start.y = wall_start.y
			opening_end.y = wall_start.y
		else:
			opening_start.x = wall_start.x
			opening_end.x = wall_start.x

		if cursor.distance_to(opening_start) > 0.01:
			segments.append({"start": cursor, "end": opening_start, "has_door": false})
		segments.append({"start": opening_start, "end": opening_end, "has_door": true})
		cursor = opening_end

	if cursor.distance_to(wall_end) > 0.01:
		segments.append({"start": cursor, "end": wall_end, "has_door": false})
	return segments


## Subtract already-built spans from [span.x, span.y], returning what's left.
static func subtract_spans(span: Vector2, existing: Array) -> Array[Vector2]:
	var pieces: Array[Vector2] = [span]
	for taken in existing:
		var next: Array[Vector2] = []
		for piece in pieces:
			if taken.y <= piece.x or taken.x >= piece.y:
				next.append(piece)  # no overlap
				continue
			if taken.x > piece.x:
				next.append(Vector2(piece.x, taken.x))
			if taken.y < piece.y:
				next.append(Vector2(taken.y, piece.y))
		pieces = next
	return pieces


# --- helpers ----------------------------------------------------------------

func _make_box(node_name: String, size: Vector3, position: Vector3, material: StandardMaterial3D, collide: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position

	# Named explicitly: auto-names are not guaranteed stable, and tests and later
	# systems (step 10's lighting) need to find these.
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	body.add_child(mesh)

	if collide:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)

	_built_root.add_child(body)
	return body


func _material(key: String, color: Color) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.metallic = 0.0
	_materials[key] = material
	return material
