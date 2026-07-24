extends SceneTree
# Regression test for the chamfer on the sliding-door panels.
#
# Both panels used to be plain BoxMeshes meeting flush at the centre of the opening, so their
# touching faces were invisible and a closed door read as one slab. Each panel's INNER vertical
# edges are now chamfered, and the two chamfers together make a visible V-groove down the middle.
#
# This measures the built mesh rather than eyeballing a render: at the panel's inner end the
# depth (through the doorway) must be a full bevel narrower on each side than at its outer end,
# in whichever world axis the doorway actually runs. Getting the width/depth axes the wrong way
# round for one orientation would rotate the chamfer onto the wrong edge and not be visible in
# any single screenshot. See tests/capture_door.gd for the look-at-it counterpart. Run:
#   godot --headless --path . -s tests/smoke_door_bevel.gd

const EPSILON := 0.0005
# The groove between the two closed panels must be at least this wide in total (both chamfers),
# stated as an absolute so the test cannot be satisfied by shrinking SlidingDoor.BEVEL.
const MIN_GROOVE := 0.008

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


## Every vertex of the panel's mesh, in panel-local space.
func _vertices(panel: AnimatableBody3D) -> PackedVector3Array:
	var mesh: MeshInstance3D = panel.get_node("Mesh")
	return mesh.mesh.get_faces()


## The panel's extent along `axis`, measured only across the slice of vertices sitting at the
## `inner`/outer end of `along`. That difference IS the chamfer.
func _depth_at_end(
	verts: PackedVector3Array, along: Vector3, axis: Vector3, inner_sign: float
) -> float:
	var extreme := -INF
	for v in verts:
		extreme = maxf(extreme, v.dot(along) * inner_sign)
	var lo := INF
	var hi := -INF
	for v in verts:
		if absf(v.dot(along) * inner_sign - extreme) > EPSILON:
			continue
		var d := v.dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return hi - lo


func _check_door(door: SlidingDoor, label: String, width_axis: Vector3, depth_axis: Vector3,
		thickness: float) -> void:
	var bevel := SlidingDoor.BEVEL
	for i in 2:
		var panel: AnimatableBody3D = door.get_node("Panel_%d" % i)
		var verts := _vertices(panel)
		_check("%s panel %d has geometry" % [label, i], verts.size() > 0)
		if verts.is_empty():
			continue

		# Panel 0 is offset to +along, so the edge meeting the other panel is its -along end.
		var inner_sign := -1.0 if i == 0 else 1.0
		var inner_depth := _depth_at_end(verts, width_axis, depth_axis, inner_sign)
		var outer_depth := _depth_at_end(verts, width_axis, depth_axis, -inner_sign)

		_check(
			"%s panel %d outer end is full thickness (%.4f vs %.4f)"
				% [label, i, outer_depth, thickness],
			absf(outer_depth - thickness) < EPSILON
		)
		# A bevel taken off BOTH sides of the inner end: that is what forms the groove.
		#
		# Assert an ABSOLUTE minimum first. Checking only against SlidingDoor.BEVEL would be a
		# measurement that confounds itself — set the constant to zero and the expectation
		# follows it down, so the test passes on a door with no chamfer at all. (It did.)
		_check(
			"%s panel %d has a real groove: inner end %.4f narrower than outer %.4f"
				% [label, i, outer_depth - inner_depth, outer_depth],
			outer_depth - inner_depth > MIN_GROOVE
		)
		_check(
			"%s panel %d inner end is chamfered by %.3f on each side (%.4f vs %.4f)"
				% [label, i, bevel, inner_depth, thickness - bevel * 2.0],
			absf(inner_depth - (thickness - bevel * 2.0)) < EPSILON
		)
		# The chamfer must not eat the whole edge — that would leave a knife edge, not a bevel.
		_check("%s panel %d inner end still has width" % [label, i], inner_depth > 0.01)

		# The chamfer belongs on the INNER edge only. If the axes were swapped the mesh would
		# be narrowed through its width instead, so pin the overall bounds too.
		var mesh: MeshInstance3D = panel.get_node("Mesh")
		var aabb: AABB = mesh.mesh.get_aabb()
		_check(
			"%s panel %d is thickness %.3f through the doorway (got %.4f)"
				% [label, i, thickness, aabb.size.dot(depth_axis.abs())],
			absf(aabb.size.dot(depth_axis.abs()) - thickness) < EPSILON
		)


func _run() -> void:
	var builder := RoomBuilder.new()
	root.add_child(builder)
	current_scene = builder
	# Two rooms sharing a corner, so one doorway runs along X and the other along Z — the
	# panel mesh has to map width/depth onto the right world axes for both.
	builder.add_room(Rect2(-4, -4, 8, 8))
	builder.add_room(Rect2(4, -4, 6, 8))
	builder.add_doorway(Vector2(0, -4), Doorway.Axis.X, 1.6)
	builder.add_doorway(Vector2(4, 0), Doorway.Axis.Z, 1.6)
	builder.build()
	await process_frame

	var thickness := minf(builder.door_thickness, builder.wall_thickness * 0.7)
	var doors: Array[SlidingDoor] = []
	for node in builder.get_tree().get_nodes_in_group(RoomBuilder.GROUP_DOOR):
		var door := node as SlidingDoor
		if door != null:
			doors.append(door)
	_check("both doorways got a door (%d)" % doors.size(), doors.size() == 2)

	# The doorway's axis names the direction the opening SPANS, so panels slide along it and
	# the panel's depth runs perpendicular.
	for door in doors:
		if absf(door.position.z) > absf(door.position.x):
			_check_door(door, "X-axis door", Vector3.RIGHT, Vector3.BACK, thickness)
		else:
			_check_door(door, "Z-axis door", Vector3.BACK, Vector3.RIGHT, thickness)

	# The tint only reaches the screen if the material actually reads vertex colour.
	var material: StandardMaterial3D = doors[0].get_node("Panel_0/Mesh").material_override
	_check("door material uses vertex colour as albedo", material.vertex_color_use_as_albedo)
	_check("the chamfer tint is darker than plain white", SlidingDoor.BEVEL_TINT.v < 1.0)

	if _failures.is_empty():
		print("DOOR BEVEL TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("DOOR BEVEL TEST FAIL")
		quit(1)
