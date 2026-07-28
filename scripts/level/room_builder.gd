@tool
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
const GROUP_CHAMFER := &"opening_chamfer"

## Albedo multiplier on a chamfer's 45° face, applied as vertex colour. The interior is lit by
## SHADOWLESS omnis (see _build_light), and under that an angled face picks up almost no shading
## contrast against the wall it was cut from — a geometrically correct chamfer renders as a flat
## continuation of the wall and the whole feature is invisible. SlidingDoor.BEVEL_TINT exists for
## exactly the same reason. Only the hypotenuse is tinted; the end caps stay wall-coloured,
## because they ARE wall.
const CHAMFER_TINT := Color(0.78, 0.79, 0.82)
## How far each chamfer is pushed into the surrounding sill/lintel/jamb, so the faces that meet
## them are not decided by exact float equality between two independently-computed positions.
## Same trick as SlidingDoor.SEAM_OVERLAP.
const CHAMFER_OVERLAP := 0.001
## Gap left between a doorway's chamfers and the slab its sliding panels move through, so the two
## cannot graze even if the panel thickness is retuned. See _build_chamfers.
const PANEL_CLEARANCE := 0.005

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
## Seconds for a door to slide fully apart. Unchanged in feel — this is SlidingDoor's own
## long-standing default — but it was never plumbed through here, so it could not be tuned from
## the ship at all. Exposed now because it is one of the two numbers that decide whether a
## carried item meets a closed door; the other, and the one that was actually wrong, is
## `door_approach`.
##
## The panels ease SINE-OUT, so most of the gap arrives early: a usable width is there at about
## 0.23 of this, not at the end of it.
@export var door_open_time: float = 0.4
## Doors read as distinct by being LIGHTER than the walls, not by being shiny. Under GL
## Compatibility there is no reflection probe or sky for a metallic surface to reflect,
## so metallic/low-roughness materials fall back to hard specular off the omni lights —
## which showed up as odd bright streaks sliding across the panels.
@export var door_color: Color = Color(0.66, 0.69, 0.74)
@export var door_roughness: float = 0.85
@export var build_lights: bool = true
## Sliding door panels in each opening. Turn off to test the raw wall gap.
@export var build_doors: bool = true
## How far from an opening the player has to be for its door to slide apart, in metres,
## measured from the door plane.
##
## THIS IS A CARRY DISTANCE, NOT A WALKING ONE, and that is what 1.6 got wrong. The hold point
## is 1.4m in front of the camera (`player.tscn`, HoldPoint z -1.4), so at the moment the player
## crossed the old trigger the thing in their hands was already 0.2m from the panels — at
## `max_speed` 7 m/s it arrived 0.03s later, against a door that needs about 0.09s to be worth
## walking through. It clipped, every time, which is exactly what it looked like.
##
## MEASURED, not guessed — tests/diag_door_clearance.gd walks the player at `max_speed` into the
## corridor/cryo-bay door carrying each bulky prop and reports the gap when the item's nose
## arrives. Clearance each side, centred:
##
##   prop            1.6      2.4      2.8
##   canister        0.017    0.311    0.466
##   battery         0.072    0.211    0.406
##   food crate      0.071    0.261    0.436
##   pickup crate    0.067    0.067    0.194
##
## At 1.6 every prop cleared by under 7cm, which is why it only went wrong SOMETIMES. The pickup
## crate is the case that picks the number: it is 0.8m DEEP as well as wide, so its nose arrives
## earlier and it gains nothing at all between 1.6 and 2.4 — a wide prop is not just a harder
## version of a narrow one.
@export var door_approach: float = 2.8
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
## Leg length of the 45° cut at each corner of an opening, so a window reads as a chamfered
## porthole and a doorway as a chamfered frame rather than a plain rectangular hole. One knob for
## both, because the point of it is that the ship's openings look like a set. 0 disables it.
@export var opening_chamfer: float = 0.12

## Confine each room's lights to that room's own surfaces, using one visual layer per room.
##
## WHY. The lights are shadowless on purpose (see _build_light), and a shadowless omni passes
## straight THROUGH a wall: with `light_range` at 9m and rooms sharing walls, the corridor lit
## the pod bay's floor from outside it. Turning shadows on is the textbook fix and is exactly
## what GL Compatibility cannot afford, so instead every room's geometry goes on its own
## visual layer and every fixture is masked to that layer. A light physically cannot reach
## another room's floor, at no per-frame cost.
##
## Layer 1 stays the general layer — props, the player, anything not built by this class — and
## every light includes it, so a carried crate is still lit wherever it is taken. Only the
## room SHELL is masked, which is what the bleed was actually visible on.
@export var confine_lights_to_rooms: bool = true

## Layer 1 is the shared/prop layer and layer 2 is the EXTERIOR layer, so rooms start at 3.
## Godot has 20 layers, which leaves 18 rooms.
##
## Layer 2 is not free. `ExteriorSun` in game.tscn is a DirectionalLight3D with
## `light_cull_mask = 2`, and `space_station.tscn` puts its meshes on layer 2 to match — that
## pairing is what lets the sun light the station outside without leaking into the interior.
## Handing layer 2 to a room puts that room's shell under a white directional light: the pod
## bay's floor and the two walls facing the sun stopped turning red in ALERT mode, while the
## two facing away still did.
const EXTERIOR_LAYER := 2
const FIRST_ROOM_LAYER := 3
const MAX_ROOM_LAYERS := 18

var rooms: Array[Room] = []
var doorways: Array[Doorway] = []

## room id -> visual layer mask. Empty when confine_lights_to_rooms is off.
var _room_layers: Dictionary = {}

## opening id -> {"room": Room, "inward": Vector2}. Recorded while building walls, because that is
## the only place that knows which room's skin an opening was cut through — and hence which
## colour, which visual layer, and which SIDE of the wall line the chamfers belong on. `room_at()`
## cannot answer it: an opening sits exactly on the room boundary, where the test is ambiguous.
var _opening_walls: Dictionary = {}

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
	_opening_walls.clear()


## Build every room and doorway added so far. Safe to call again — it rebuilds.
func build() -> Node3D:
	clear()
	_built_root = Node3D.new()
	_built_root.name = "Built"
	# DELIBERATELY UNOWNED. This class is @tool, so build() also runs while the scene is merely
	# open in the editor — that is what makes the ship visible in the viewport instead of an
	# empty Node3D. Godot serialises only nodes that have an `owner`, so leaving it null is the
	# single thing keeping several hundred generated boxes out of game.tscn on every save. Do
	# not set owner here, and do not add these nodes through an EditorUndoRedo.
	add_child(_built_root)

	_assign_room_layers()


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
		# Doorways get chamfered too, so every opening on the ship reads the same way.
		_build_chamfers(opening)
	return _built_root


## One visual layer per room. Falls back to no masking (everything on layer 1, every light
## unmasked) if the ship outgrows the 19 available — a ship that lights wrong is better than
## one where the twentieth room is invisible to every light it contains.
func _assign_room_layers() -> void:
	_room_layers.clear()
	if not confine_lights_to_rooms:
		return
	if rooms.size() > MAX_ROOM_LAYERS:
		push_warning(
			"RoomBuilder: %d rooms exceeds the %d available visual layers — per-room light "
			% [rooms.size(), MAX_ROOM_LAYERS]
			+ "confinement is off, so lights will bleed through walls."
		)
		return
	for i in rooms.size():
		_room_layers[rooms[i].id] = 1 << (FIRST_ROOM_LAYER - 1 + i)


## The layer mask a room's own shell is drawn on. Layer 1 when confinement is off.
func room_layer(room_id: String) -> int:
	return _room_layers.get(room_id, 1)


## Which room a WORLD position is standing in, or "" for none (a doorway gap, or outside the
## hull). Rooms never overlap — smoke_ship_layout asserts it — so at most one can match.
##
## The Y axis is ignored on purpose: this answers "which room am I in", and a player is in the
## engine room whether they are on its floor or halfway up a crate in it.
func room_at(position: Vector3) -> String:
	for room in rooms:
		var x0 := float(room.rect.position.x) * tile_size
		var z0 := float(room.rect.position.y) * tile_size
		var x1 := x0 + float(room.rect.size.x) * tile_size
		var z1 := z0 + float(room.rect.size.y) * tile_size
		if position.x >= x0 and position.x <= x1 and position.z >= z0 and position.z <= z1:
			return room.id
	return ""


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


## How many wall skins an opening was cut through: 1 for a window (exterior wall, one room) and 2
## for a doorway between two rooms, each of which builds its own half-thickness side. This is also
## the answer to "is this opening on an exterior wall", which nothing checked before.
func opening_skins(opening_id: String) -> int:
	var entries: Array = _opening_walls.get(opening_id, [])
	return entries.size()


## Cut the square corners off an opening: a small right-triangular prism dropped into each corner
## of the void, its hypotenuse facing the room, so a window reads as a chamfered porthole and a
## doorway as a chamfered frame.
##
## ADDITIVE, not subtractive. The wall-splitting maths that produces the sill, lintel and jambs is
## untouched — the hole simply gets a few small solids in its corners. Carving the corners out of
## the wall pieces instead would mean teaching _create_wall_piece about non-box geometry.
##
## No collision. A window's glass box already spans the whole opening, and a doorway's chamfers
## are at head height in the corners, where nothing needs stopping.
##
## THREE THINGS A DOORWAY DOES DIFFERENTLY, all handled here rather than in a second routine:
##
## 1. It reaches the floor, so it has two corners, not four. A chamfer at floor level would read
##    as a moulding nobody asked for.
## 2. It is cut through BOTH neighbouring rooms' skins, so it gets a set of chamfers per side,
##    each in that room's own colour and on that room's own visual layer.
## 3. A sliding panel occupies the MIDDLE of the wall depth. See `near` below.
func _build_chamfers(opening: Doorway) -> void:
	if opening_chamfer < 0.01:
		return
	var entries: Array = _opening_walls.get(opening.id, [])
	if entries.is_empty():
		return

	var top: float = opening.resolved_top(doorway_height)
	var height := top - opening.sill
	var span := opening.width * tile_size
	if height <= 0.01 or span <= 0.01:
		return
	# Clamp so a small opening cannot close up into a diamond. The binding case is the bathroom's
	# 1.0 x 1.0m portholes; at 0.3 the cuts still leave 40% of every edge as a flat run.
	var leg := minf(opening_chamfer, 0.3 * minf(span, height))
	if leg < 0.01:
		return

	# The depth slab the prisms occupy, measured inward from the wall line. A window gets the whole
	# skin. A DOORWAY cannot: its two panels sit centred on the wall line and slide sideways
	# through exactly this region, so a full-depth chamfer would have the panel grinding through
	# the corner solid every time the door opened. The chamfer is confined to the part of the skin
	# the panel can never reach, which is why doors were scoped out of the first pass.
	var skin := wall_thickness * 0.5
	var near := 0.0
	if opening.fit_door and build_doors:
		near = minf(door_thickness, wall_thickness * 0.7) * 0.5 + PANEL_CLEARANCE
	if skin - near < 0.005:
		push_warning(
			"RoomBuilder: opening '%s' has no room for a chamfer — the door panel fills the wall."
			% opening.id
		)
		return
	var half_depth := (skin - near) * 0.5

	# A doorway's corners are the two at the top; a window's are all four.
	var corners: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1)]
	if opening.sill > 0.01:
		corners.append_array([Vector2(1, -1), Vector2(-1, -1)])

	var at := grid_to_world(opening.position.x, opening.position.y)
	var along := Vector3.RIGHT if opening.axis == Doorway.Axis.X else Vector3.BACK

	for entry in entries:
		var room: Room = entry["room"]
		var inward: Vector2 = entry["inward"]
		var through := Vector3(inward.x, 0.0, inward.y)
		# Centred in the slab, exactly as _create_wall_piece offsets its skin. Get this wrong and
		# the chamfer does not error — it just floats proud of the wall face, or hides behind it.
		var origin := Vector3(at.x, 0.0, at.y) + through * ((near + skin) * 0.5)
		var material := _chamfer_material(room)

		for corner in corners:
			var mesh := MeshInstance3D.new()
			mesh.name = "Chamfer_%s_%s_%d_%d" % [opening.id, room.id, int(corner.x), int(corner.y)]
			mesh.position = origin
			mesh.mesh = _chamfer_mesh(
				along, through, span * 0.5, top if corner.y > 0.0 else opening.sill,
				leg, half_depth, corner
			)
			mesh.material_override = material
			# Without this the chamfer lands on layer 1 and is lit by EVERY room's fixtures — a
			# subtly wrong-coloured corner that also refuses to turn red with the wall in ALERT.
			mesh.layers = room_layer(room.id)
			mesh.add_to_group(GROUP_CHAMFER)
			_built_root.add_child(mesh)


## One corner prism. `u` runs along the opening (signed by corner.x), `v` is world height (the
## corner sits at `y_corner`, and corner.y says whether that is the lintel or the sill/floor).
##
## Built in the opening's own axes rather than in X/Z, so one routine covers both orientations —
## the same approach as SlidingDoor._build_panel_mesh, whose section-walking idiom this follows.
func _chamfer_mesh(
	along: Vector3,
	through: Vector3,
	half_span: float,
	y_corner: float,
	leg: float,
	half_depth: float,
	corner: Vector2
) -> ArrayMesh:
	var su := corner.x
	var sv := corner.y
	var o := CHAMFER_OVERLAP

	# The right triangle, walked in order: along the sill/lintel face, along the jamb face, then
	# back down the hypotenuse. The two leg faces are pushed `o` into the surrounding wall.
	var section: Array[Vector2] = [
		Vector2(su * (half_span - leg), y_corner + sv * o),
		Vector2(su * (half_span + o), y_corner + sv * o),
		Vector2(su * (half_span + o), y_corner - sv * leg),
	]
	# Index of the edge section[i] -> section[i + 1] that IS the 45° face — the only one the
	# player can see, and the only one tinted. Pushing both legs out by the same `o` shifts this
	# edge outward very slightly but leaves it at exactly 45°.
	const CHAMFER_EDGE := 2

	var centroid := (section[0] + section[1] + section[2]) / 3.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in section.size():
		var from := section[i]
		var to := section[(i + 1) % section.size()]
		var a := along * from.x + Vector3.UP * from.y
		var b := along * to.x + Vector3.UP * to.y
		# Outward normal: perpendicular to the edge in the opening's plane, pointing away from the
		# section's centroid. The centroid test is needed because the section is NOT centred on the
		# mesh origin, so SlidingDoor's "same way as the midpoint" shortcut does not apply here.
		var mid := (from + to) * 0.5 - centroid
		var normal := (b - a).cross(through).normalized()
		if normal.dot(along * mid.x + Vector3.UP * mid.y) < 0.0:
			normal = -normal
		var color := CHAMFER_TINT if i == CHAMFER_EDGE else Color.WHITE
		_add_quad(
			st,
			a - through * half_depth, b - through * half_depth,
			b + through * half_depth, a + through * half_depth,
			normal, color
		)

	# End caps: small triangles flush with the wall's two faces. Untinted, so they read as wall.
	for front in [true, false]:
		var offset := through * (half_depth if front else -half_depth)
		var normal := through if front else -through
		var fan: Array[Vector3] = []
		for point in section:
			fan.append(along * point.x + Vector3.UP * point.y + offset)
		_add_tri(st, fan[0], fan[1], fan[2], normal, Color.WHITE)

	st.generate_tangents()
	return st.commit()


## Emit one triangle, wound to face `normal`. The winding cannot be fixed at the call sites:
## three of the four corners are MIRRORED in u, v or both, which reverses the section's outline
## and turns those prisms inside out — backface-culled to a dark hole. Godot treats CLOCKWISE as
## front-facing, so a correctly wound triangle's geometric normal points AWAY from the face
## normal; when it doesn't, swap two vertices. (Copied from SlidingDoor, which hit this first.
## Lifting the pair into a shared helper would mean touching a working, tested door mid-jam.)
func _add_tri(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color
) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var swap := b
		b = c
		c = swap
	for v in [a, b, c]:
		st.set_normal(normal)
		st.set_color(color)
		# The material is untextured, so UVs only need to exist for tangent generation.
		st.set_uv(Vector2(v.x + v.z, -v.y))
		st.add_vertex(v)


func _add_quad(
	st: SurfaceTool,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	normal: Vector3, color: Color
) -> void:
	_add_tri(st, a, b, c, normal, color)
	_add_tri(st, a, c, d, normal, color)


## The room's wall material, but reading vertex colour — which is what lets the 45° face be tinted
## while the end caps stay wall-coloured. A separate material because turning vertex colour on for
## the walls themselves would affect every box they build.
func _chamfer_material(room: Room) -> StandardMaterial3D:
	var key := "chamfer_" + room.id
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = room.wall_color
	material.roughness = 0.95
	material.metallic = 0.0
	material.vertex_color_use_as_albedo = true
	_materials[key] = material
	return material



func _build_door(doorway: Doorway) -> void:
	var door := SlidingDoor.new()
	door.open_reveal = door_open_reveal
	door.open_time = door_open_time
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
	# The panels tint their chamfered inner edges by vertex colour so the seam between the two
	# doors reads under flat lighting — see SlidingDoor._build_panel_mesh. Everything else on
	# the panel is white, so this is a no-op for the rest of the surface.
	material.vertex_color_use_as_albedo = true
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
		true,
		room_layer(room.id)
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
		true,
		room_layer(room.id)
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
			# The range must reach the FLOOR, or a tall room goes black below the lights.
			# Ceiling lights in the 9.3m cryo bay were 9.05m up against a 9.0m range and the
			# floor got nothing but ambient. Short rooms keep the default; only genuinely
			# tall ones widen it.
			light.omni_range = maxf(light_range, room.height + 2.0)
			light.light_color = light_color
			light.light_energy = light_energy
			# Shadowless on purpose: shadows are what make interior lighting read as
			# dramatic rather than flat, and they are expensive under GL Compatibility.
			light.shadow_enabled = false
			# Which room this fixture belongs to, so LightingController can switch a whole
			# room's lights off when nobody is in it. Metadata rather than parsing it back
			# out of the node name — names with dots in them get sanitised on load.
			light.set_meta("room_id", room.id)
			# Own room's shell, plus layer 1 so props and the player stay lit anywhere.
			light.light_cull_mask = room_layer(room.id) | 1
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
	panel.layers = room_layer(room.id)
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
	# The chamfer builder runs later and needs this room's colour, layer and inward direction. An
	# ENTRY PER SIDE, not one per opening: a doorway is cut through both neighbours' skins and
	# needs a set of chamfers in each, in that room's own colour. A window is on an exterior wall,
	# so it collects exactly one.
	if not _opening_walls.has(opening.id):
		_opening_walls[opening.id] = []
	_opening_walls[opening.id].append({"room": room, "inward": inward})
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
		true,
		room_layer(room.id)
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

func _make_box(node_name: String, size: Vector3, position: Vector3, material: StandardMaterial3D, collide: bool, layers: int = 1) -> StaticBody3D:
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
	# Per-room visual layer, so only this room's fixtures can light it.
	mesh.layers = layers
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
