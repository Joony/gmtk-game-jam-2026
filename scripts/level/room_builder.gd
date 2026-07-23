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
# 3. EACH ROOM BUILDS ITS OWN WALL SKIN. Adjacent rooms both generate the wall between
#    them, so 2025 nudged them apart per side to hide z-fighting. Instead each room
#    builds half the wall thickness on its own side. No overlap, no z-fighting, each
#    side shows its own room's colour, and every room is a closed box — so a taller
#    room can never leave a gap above a shorter neighbour.
#
# Lights: one omni per room, in the `room_lights` group so step 10's lighting modes can
# retint them. Deliberately NOT 2025's one-OmniLight3D-per-floor-tile, which was a
# GL-compatibility-era hack costing hundreds of lights on a large level.

const GROUP_FLOOR := &"room_floor"
const GROUP_CEILING := &"room_ceiling"
const GROUP_WALL := &"room_wall"
const GROUP_LIGHT := &"room_lights"
const GROUP_DOOR := &"room_door"
const GROUP_LIGHT_PANEL := &"room_light_panels"
const GROUP_WINDOW_GLASS := &"space_window_glass"

@export var tile_size: float = 1.0
@export var wall_thickness: float = 0.15
@export var floor_thickness: float = 0.2
@export var ceiling_thickness: float = 0.2
## Height of doorway openings. The wall above one becomes a lintel.
@export var doorway_height: float = 2.2
## Door panels are deliberately THINNER than the walls and centred in their depth.
## An open panel slides inside the wall, so equal thickness put the two exactly
## coplanar and produced z-fighting. Clamped below wall_thickness so it stays true
## if the walls are ever made thinner.
@export var door_thickness: float = 0.08
## Sliver of each door panel left showing when fully open — see SlidingDoor.open_reveal.
@export var door_open_reveal: float = 0.06
## Doors read as distinct by being LIGHTER than the walls, not by being shiny. Under GL
## Compatibility there is no reflection probe or sky for a metallic surface to reflect,
## so metallic/low-roughness materials fall back to hard specular off the omni lights —
## which showed up as odd bright streaks sliding across the panels.
@export var door_color: Color = Color(0.66, 0.69, 0.74)
@export var door_roughness: float = 0.85
@export var build_lights: bool = true
## Sliding door panels in each opening. Turn off to test the raw wall gap.
@export var build_doors: bool = true
## How far from an opening the player has to be for its door to slide apart.
@export var door_approach: float = 1.6
## Fallback light colour. Step 10's LightingController drives these once it exists.
@export var light_color: Color = Color(0.95, 0.96, 1.0)
@export var light_energy: float = 1.6
## Roughly how far apart ceiling fixtures sit. A GRID of shadowless omnis is what
## gives the flat, evenly-lit interior look — one lamp per room leaves a hotspot in
## the middle and dark corners.
@export var light_spacing: float = 5.0
@export var light_range: float = 9.0
## Emissive housings under each fixture, so the lights are visibly the source.
@export var build_light_panels: bool = true

var rooms: Array[Room] = []
var doorways: Array[Doorway] = []

var _materials: Dictionary = {}
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


## A window is an opening that does not reach the floor: wall below (the sill) and above
## (the lintel), with a starfield pane fitted instead of a door.
func add_window(position: Vector2, axis: Doorway.Axis, width: float = 2.4, sill: float = 1.0, height: float = 1.3) -> Doorway:
	var opening := Doorway.new(position, axis, width)
	opening.sill = sill
	opening.top = sill + height
	opening.fit_door = false
	opening.fit_window = true
	doorways.append(opening)
	return opening


## Grid (boundary) coordinates to world XZ. The single conversion in the system.
func grid_to_world(grid_x: float, grid_y: float) -> Vector2:
	return Vector2(grid_x, grid_y) * tile_size


func clear() -> void:
	if _built_root != null and is_instance_valid(_built_root):
		_built_root.free()
	_built_root = null
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
	if build_doors:
		for doorway in doorways:
			if doorway.fit_door:
				_build_door(doorway)
	for opening in doorways:
		if opening.fit_window:
			_build_window(opening)
	return _built_root


func _build_window(opening: Doorway) -> void:
	var height: float = opening.resolved_top(doorway_height) - opening.sill
	if height <= 0.01:
		return

	# No pane: the starfield is a backdrop shell around the whole ship (see
	# ShipMotion), so a window is a genuine hole and anything outside the hull —
	# a station, a planet, debris — is simply visible through it.
	var at := grid_to_world(opening.position.x, opening.position.y)

	# Glass. The opening is a real hole now: the player can't fit through (the sill
	# blocks them) but a thrown crate would otherwise sail out into space.
	var glass := StaticBody3D.new()
	glass.name = "WindowGlass_%s" % opening.id
	glass.position = Vector3(at.x, opening.sill + height * 0.5, at.y)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	var span := opening.width * tile_size
	box.size = Vector3(span, height, wall_thickness * 0.5)
	if opening.axis == Doorway.Axis.Z:
		box.size = Vector3(wall_thickness * 0.5, height, span)
	shape.shape = box
	glass.add_child(shape)
	# Grouped rather than found by name: node names are sanitised (dots stripped), so
	# "WindowGlass_door_-5.0_2.0" is not the name it ends up with.
	glass.add_to_group(GROUP_WINDOW_GLASS)
	_built_root.add_child(glass)



func _build_door(doorway: Doorway) -> void:
	var door := SlidingDoor.new()
	door.open_reveal = door_open_reveal
	_built_root.add_child(door)
	door.build(
		doorway,
		doorway_height,
		minf(door_thickness, wall_thickness * 0.7),
		tile_size,
		_door_material(),
		door_approach
	)
	door.add_to_group(GROUP_DOOR)


func _door_material() -> StandardMaterial3D:
	if _materials.has("door"):
		return _materials["door"]
	var material := StandardMaterial3D.new()
	material.albedo_color = door_color
	material.metallic = 0.0
	material.roughness = door_roughness
	_materials["door"] = material
	return material


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
	# Grid of shadowless omnis across the ceiling. Both reference projects landed here:
	# Doortal ADR 0010 ("all lights are shadowless for an even, flat test-chamber look",
	# a 2x2 grid in a 12x12 room) and GMTK 2025 (shadowless omnis + emissive panels).
	var width := room.rect.size.x * tile_size
	var depth := room.rect.size.y * tile_size
	var cols := maxi(1, int(round(width / light_spacing)))
	var rows := maxi(1, int(round(depth / light_spacing)))

	for i in cols:
		for j in rows:
			var u := (i + 0.5) / float(cols)
			var v := (j + 0.5) / float(rows)
			var grid_x: float = room.rect.position.x + u * room.rect.size.x
			var grid_y: float = room.rect.position.y + v * room.rect.size.y
			var at := grid_to_world(grid_x, grid_y)

			var light := OmniLight3D.new()
			light.name = "Light_%s_%d_%d" % [room.id, i, j]
			light.position = Vector3(at.x, room.height - 0.25, at.y)
			light.omni_range = light_range
			light.light_color = light_color
			light.light_energy = light_energy
			# Shadowless on purpose: shadows are what make interior lighting read as
			# dramatic rather than flat, and they are expensive under GL Compatibility.
			light.shadow_enabled = false
			light.add_to_group(GROUP_LIGHT)
			_built_root.add_child(light)

			if build_light_panels:
				_build_light_panel(room, at)


func _build_light_panel(room: Room, at: Vector2) -> void:
	var panel := MeshInstance3D.new()
	panel.name = "LightPanel_%s_%.1f_%.1f" % [room.id, at.x, at.y]
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.06, 0.9)
	panel.mesh = box
	panel.position = Vector3(at.x, room.height - 0.05, at.y)
	panel.material_override = _panel_material()
	panel.add_to_group(GROUP_LIGHT_PANEL)
	_built_root.add_child(panel)


func _panel_material() -> StandardMaterial3D:
	if _materials.has("light_panel"):
		return _materials["light_panel"]
	var material := StandardMaterial3D.new()
	material.albedo_color = light_color
	material.emission_enabled = true
	material.emission = light_color
	material.emission_energy_multiplier = 1.6
	material.roughness = 1.0
	_materials["light_panel"] = material
	return material


# --- walls ------------------------------------------------------------------

func _build_walls(room: Room) -> void:
	var material := _material("wall_" + room.id, room.wall_color)
	for wall in room.perimeter_walls():
		for segment in wall_segments(wall["start"], wall["end"], doorways):
			_create_wall(segment, room, material, wall["inward"])


# Each room builds its OWN skin on its OWN side of the wall line: half the full wall
# thickness, offset inward. Two adjacent rooms therefore produce the two halves of the
# wall between them, each in its own colour.
#
# This replaces an earlier model that built each shared wall once and deduplicated by
# span. That was wrong twice over: the first room to build claimed the span AND supplied
# the material, so a shared wall wore the neighbour's colour; and coverage had to be
# tracked in height as well, or a taller room left a gap above a shorter neighbour.
# Per-room skins make both problems structurally impossible — every room is a closed box.
func _create_wall(segment: Dictionary, room: Room, material: StandardMaterial3D, inward: Vector2) -> void:
	var start: Vector2 = segment["start"]
	var end: Vector2 = segment["end"]
	var has_door: bool = segment["has_door"]

	if start.distance_to(end) * tile_size < 0.01:
		return

	if not has_door:
		_create_wall_piece(start, end, 0.0, room.height, room, material, inward)
		return

	# An opening splits its segment into up to two pieces: wall below (a window's sill)
	# and wall above (the lintel). A doorway has sill 0, so only the lintel is built.
	var opening: Doorway = segment["opening"]
	var bottom: float = opening.sill
	var top: float = opening.resolved_top(doorway_height)
	if bottom > 0.01:
		_create_wall_piece(start, end, 0.0, bottom, room, material, inward)
	if top < room.height - 0.01:
		_create_wall_piece(start, end, top, room.height, room, material, inward)


func _create_wall_piece(
	start: Vector2,
	end: Vector2,
	y_bottom: float,
	y_top: float,
	room: Room,
	material: StandardMaterial3D,
	inward: Vector2
) -> void:
	var length := start.distance_to(end) * tile_size
	var wall_height := y_top - y_bottom
	if length < 0.01 or wall_height <= 0.01:
		return

	var skin := wall_thickness * 0.5
	var runs_along_x := absf(end.x - start.x) > absf(end.y - start.y)
	var size := Vector3(length, wall_height, skin)
	if not runs_along_x:
		size = Vector3(skin, wall_height, length)

	var centre := grid_to_world((start.x + end.x) * 0.5, (start.y + end.y) * 0.5)
	var offset := Vector3(inward.x, 0.0, inward.y) * (skin * 0.5)

	var body := _make_box(
		"Wall_%s_%.1f_%.1f" % [room.id, start.x, y_bottom],
		size,
		Vector3(centre.x, y_bottom + wall_height * 0.5, centre.y) + offset,
		material,
		true
	)
	body.add_to_group(GROUP_WALL)
	if y_bottom > 0.01:
		body.set_meta("lintel", true)


## Split a wall into segments around any doorways crossing it. Ported from 2025's
## get_wall_segments_with_doors(). A segment flagged `has_door` carries the `opening`
## that split it, so the caller knows its vertical extent (doorway vs window).
static func wall_segments(wall_start: Vector2, wall_end: Vector2, all_doorways: Array[Doorway]) -> Array[Dictionary]:
	var crossing: Array[Doorway] = []
	for doorway in all_doorways:
		if doorway.intersects_wall(wall_start, wall_end):
			crossing.append(doorway)

	if crossing.is_empty():
		return [{"start": wall_start, "end": wall_end, "has_door": false, "opening": null}]

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
			segments.append({"start": cursor, "end": opening_start, "has_door": false, "opening": null})
		segments.append({"start": opening_start, "end": opening_end, "has_door": true, "opening": doorway})
		cursor = opening_end

	if cursor.distance_to(wall_end) > 0.01:
		segments.append({"start": cursor, "end": wall_end, "has_door": false, "opening": null})
	return segments


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
