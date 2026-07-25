@tool
class_name SlidingDoor
extends Node3D

# Two panels that slide apart when the player approaches, ported from GMTK 2025's
# V1/DoorManager.gd (307 lines, of which the panel geometry, the proximity Area3D and
# the slide tween are the parts worth keeping).
#
# Left behind: the control panel (already commented out in 2025), is_player_near_door()'s
# manual distance check (the Area3D supersedes it), the player_node reference, and its
# grid_boundary_to_world helper (our coordinate convention differs — see RoomBuilder).
#
# UPGRADE ON PORT: panels are AnimatableBody3D, not 2025's StaticBody3D. Moving a static
# body does not sweep against other bodies — a closing panel would clip through the player
# or trap them. AnimatableBody3D with sync_to_physics pushes properly, which also means the
# tween must run on the PHYSICS clock, not the render clock.

signal opened
signal closed

# Panels overlap the lintel above and the floor below by this much. Sitting flush would
# put the panel's top face exactly on the lintel's underside and its base exactly on the
# floor — coplanar overlapping faces, the same z-fighting that thickness fixes sideways.
# Interpenetrating slightly is invisible and cannot shimmer.
const SEAM_OVERLAP := 0.02

# The opening's half-depth (perpendicular to the door) used for obstruction tests. Bigger than a
# panel is thick so a cable crossing the thin doorway plane always lands a rope point inside the
# region (points are spaced ~segment_length ≈ 0.12 m), without being so deep that a cable merely
# lying NEAR the door in the same room trips it.
const OPENING_MIN_DEPTH := 0.25
# How often (seconds) an open, empty door rechecks whether a cable still blocks it before closing.
const RECHECK_INTERVAL := 0.1
# The cable group Cable3D registers in (see cable_3d.gd) — the rope isn't a body, so it's found here.
const CABLE_GROUP := &"cables"

# How deep the chamfer on each panel's inner vertical edge is. Two closed panels put their
# chamfers together, so the groove down the middle of a shut door is twice this wide. Clamped
# against the panel's own half-depth in _build_panel_mesh — at door_thickness 0.08 the panel is
# only 0.04 deep either side of centre, and a chamfer that ate all of it would meet in a knife edge.
const BEVEL := 0.012
# Albedo multiplier on the chamfer faces only, applied as vertex colour. See _build_panel_mesh:
# the flat shadowless interior gives an angled face almost no shading contrast, so the geometry
# needs help to read.
const BEVEL_TINT := Color(0.5, 0.52, 0.56)

@export var open_time: float = 0.4
## How much of each panel stays visible in the opening when fully open. A door that
## retracts completely into the wall reads as a hole; leaving a sliver showing keeps
## it legible as a door.
@export var open_reveal: float = 0.06
## A jammed door refuses to open. Cheap hook for step 12d: "the door won't open" is a
## repair with no new mechanics behind it.
@export var jammed: bool = false

var is_open: bool = false

var _panels: Array[AnimatableBody3D] = []
var _closed_positions: Array[Vector3] = []
var _open_positions: Array[Vector3] = []
var _tween: Tween
var _occupants: int = 0
# The doorway opening in door-local space, as a centre + half-extents box (where the closed panels
# sit, widened in depth — see OPENING_MIN_DEPTH). A cable whose polyline enters this box holds the
# door open so it can't guillotine the line running between rooms.
var _opening_center := Vector3.ZERO
var _opening_half := Vector3.ZERO
var _recheck_accum := 0.0


## Build the panels and the proximity trigger for `doorway`. Called by RoomBuilder.
## `thickness` must be LESS than the wall thickness: an open panel slides inside the
## wall, and equal thickness makes the two coplanar, which z-fights badly.
func build(
	doorway: Doorway,
	height: float,
	thickness: float,
	tile: float,
	material: StandardMaterial3D,
	approach: float = 1.6
) -> void:
	name = "Door_%s" % doorway.id
	position = Vector3(doorway.position.x * tile, 0.0, doorway.position.y * tile)

	var along := Vector3.RIGHT if doorway.axis == Doorway.Axis.X else Vector3.BACK
	var half_width := doorway.width * 0.5 * tile
	# Each panel covers half the opening. When open, a panel's inner edge lands at
	# `half_width - open_reveal`, so it clears the opening except for a visible sliver.
	# (The panel's inner edge when open sits exactly at `slide` from the centre.)
	var slide := maxf(half_width - open_reveal, 0.0)

	for i in 2:
		var direction := 1.0 if i == 0 else -1.0
		var panel := AnimatableBody3D.new()
		panel.name = "Panel_%d" % i
		panel.sync_to_physics = true

		var panel_height := height + SEAM_OVERLAP * 2.0
		var size := Vector3(half_width, panel_height, thickness)
		if doorway.axis == Doorway.Axis.Z:
			size = Vector3(thickness, panel_height, half_width)

		# Width along the doorway, depth through it. Which world axis each is depends on the
		# doorway's orientation; the mesh builder works in those two directions rather than
		# in X/Z so one routine covers both.
		var width_axis := Vector3.RIGHT if doorway.axis == Doorway.Axis.X else Vector3.BACK
		var depth_axis := Vector3.BACK if doorway.axis == Doorway.Axis.X else Vector3.RIGHT
		# The panel sits centred at `direction * half_width * 0.5`, i.e. offset outward from the
		# doorway's middle, so the edge that meets the other panel is the one at -direction.
		var inner_sign := -direction

		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		mesh.mesh = _build_panel_mesh(
			width_axis, depth_axis,
			half_width * 0.5, panel_height * 0.5, thickness * 0.5,
			BEVEL, inner_sign
		)
		mesh.material_override = material
		panel.add_child(mesh)

		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		panel.add_child(shape)

		var closed_at := along * (direction * half_width * 0.5) + Vector3(0.0, height * 0.5, 0.0)
		panel.position = closed_at
		add_child(panel)

		_panels.append(panel)
		_closed_positions.append(closed_at)
		_open_positions.append(closed_at + along * (direction * slide))

	# The obstruction box: the full opening (both closed panels span [-half_width, +half_width] about
	# centre), at mid-height, widened in depth so a rope crossing the thin door plane is caught.
	var depth := maxf(thickness * 0.5, OPENING_MIN_DEPTH)
	_opening_center = Vector3(0.0, height * 0.5, 0.0)
	if doorway.axis == Doorway.Axis.X:
		_opening_half = Vector3(half_width, height * 0.5 + SEAM_OVERLAP, depth)
	else:
		_opening_half = Vector3(depth, height * 0.5 + SEAM_OVERLAP, half_width)

	_build_trigger(doorway, height, tile, approach)


## A box with its two INNER vertical edges chamfered. Two closed panels put those chamfers
## together and the shut door shows a shallow V-groove down the middle, so it reads as two
## doors instead of one slab — which is all it read as while both panels were plain BoxMeshes
## meeting flush at the centre, their touching faces invisible.
##
## Hand-built because BoxMesh has no bevel. The chamfer faces carry a darker VERTEX COLOUR
## rather than a second material: the interior is lit flat and shadowless (see
## docs/features/flat-lighting.md), which gives a chamfer almost no shading contrast against
## the face it cuts, so geometry alone would be invisible from across the room. Vertex colour
## keeps it to one surface and one draw call — the door material just enables
## vertex_color_use_as_albedo. Collision stays a plain box; a 12 mm chamfer is cosmetic.
##
## `width_axis`/`depth_axis` are the panel's local along-the-doorway and through-the-doorway
## directions, so this covers both doorway orientations without a rotated mesh node.
## `inner_sign` (+1/-1) picks which end along `width_axis` faces the join.
func _build_panel_mesh(
	width_axis: Vector3,
	depth_axis: Vector3,
	half_width: float,
	half_height: float,
	half_depth: float,
	bevel: float,
	inner_sign: float
) -> ArrayMesh:
	var b := clampf(bevel, 0.0, minf(half_depth, half_width) * 0.8)
	var s := inner_sign

	# The prism's cross-section, as (along width_axis, along depth_axis) pairs, walked in order
	# around the outline: the outer face (buried in the wall when open), one side face, the
	# chamfer, the inner face, the second chamfer, the other side face. Convex and centred on
	# the panel's origin, which is what lets the outward normals be found by inspection below.
	var section: Array[Vector2] = [
		Vector2(-s * half_width, -half_depth),
		Vector2(s * (half_width - b), -half_depth),
		Vector2(s * half_width, -half_depth + b),
		Vector2(s * half_width, half_depth - b),
		Vector2(s * (half_width - b), half_depth),
		Vector2(-s * half_width, half_depth),
	]
	# Indices of the two edges that ARE the chamfer, i.e. section[i] -> section[i + 1].
	var chamfer_edges := [1, 3]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in section.size():
		var from := section[i]
		var to := section[(i + 1) % section.size()]
		var a := width_axis * from.x + depth_axis * from.y
		var c := width_axis * to.x + depth_axis * to.y
		# The section is convex about the origin, so the outward normal of an edge is the one
		# pointing the same way as that edge's midpoint.
		var normal := (c - a).cross(Vector3.UP).normalized()
		if normal.dot((a + c) * 0.5) < 0.0:
			normal = -normal
		var color := BEVEL_TINT if chamfer_edges.has(i) else Color.WHITE
		_add_quad(
			st,
			a + Vector3.DOWN * half_height, c + Vector3.DOWN * half_height,
			c + Vector3.UP * half_height, a + Vector3.UP * half_height,
			normal, color
		)

	# Caps. Both are buried — the top in the lintel, the bottom in the floor (SEAM_OVERLAP) —
	# but a mesh left open would still show as missing geometry if the overlap ever changed.
	for top in [true, false]:
		var y := Vector3.UP * half_height if top else Vector3.DOWN * half_height
		var normal := Vector3.UP if top else Vector3.DOWN
		var fan: Array[Vector3] = []
		for point in section:
			fan.append(width_axis * point.x + depth_axis * point.y + y)
		for i in range(1, fan.size() - 1):
			if top:
				_add_tri(st, fan[0], fan[i], fan[i + 1], normal, Color.WHITE)
			else:
				_add_tri(st, fan[0], fan[i + 1], fan[i], normal, Color.WHITE)

	st.generate_tangents()
	return st.commit()


## Emit one triangle, wound to face `normal`. The winding cannot be fixed at the call sites:
## the section is mirrored for the panel on the other side of the doorway (`inner_sign`), which
## reverses the outline's direction and turned that whole panel inside out — backface-culled to
## a dark hole. Godot treats CLOCKWISE as front-facing, so a correctly wound triangle's
## geometric normal points AWAY from the face normal; when it doesn't, swap two vertices.
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


func _build_trigger(doorway: Doorway, height: float, tile: float, approach: float) -> void:
	var area := Area3D.new()
	area.name = "Trigger"
	# Only the player opens doors — otherwise a thrown crate would trip it.
	area.collision_mask = 1
	area.position = Vector3(0.0, height * 0.5, 0.0)

	var span := doorway.width * tile + 1.0
	var size := Vector3(span, height, approach * 2.0)
	if doorway.axis == Doorway.Axis.Z:
		size = Vector3(approach * 2.0, height, span)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	add_child(area)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return
	_occupants += 1
	open()


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return
	_occupants = maxi(0, _occupants - 1)
	# Don't guillotine a cable running through the doorway: only close once the opening is clear. If a
	# cable still blocks it, stay open — _physics_process rechecks and closes when the line clears.
	if _occupants == 0 and not _is_obstructed():
		close()


# While OPEN and empty, a cable spanning the doorway holds the door open; poll (cheaply, throttled)
# so it closes the moment the player unplugs or drags the line clear. Opening stays player-only (the
# trigger) — a cable lying near a CLOSED door must never make it yawn open by itself.
func _physics_process(delta: float) -> void:
	# In the editor the door is set dressing: it is BUILT so the opening reads correctly in the
	# viewport, but nothing drives it. Proximity polling there would chase a player that does
	# not exist, and create_tween() outside a running scene is a needless liability.
	if Engine.is_editor_hint():
		return
	if not is_open or _occupants > 0:
		return
	_recheck_accum += delta
	if _recheck_accum < RECHECK_INTERVAL:
		return
	_recheck_accum = 0.0
	if not _is_obstructed():
		close()


# True while any cable's polyline enters the doorway opening (see _opening_half). The rope is not a
# physics body, so it is found via the CABLE_GROUP and tested point-by-point in door-local space.
func _is_obstructed() -> bool:
	for node in get_tree().get_nodes_in_group(CABLE_GROUP):
		var cable := node as Cable3D
		if cable == null:
			continue
		for p in cable.points:
			var local := to_local(p) - _opening_center
			if absf(local.x) <= _opening_half.x \
					and absf(local.y) <= _opening_half.y \
					and absf(local.z) <= _opening_half.z:
				return true
	return false


func open() -> void:
	if is_open or jammed:
		return
	is_open = true
	_slide_to(_open_positions)
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_slide_to(_closed_positions)
	closed.emit()


func _slide_to(targets: Array[Vector3]) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# AnimatableBody3D only sweeps correctly when moved during the physics step.
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_parallel(true)
	for i in _panels.size():
		_tween.tween_property(_panels[i], "position", targets[i], open_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
