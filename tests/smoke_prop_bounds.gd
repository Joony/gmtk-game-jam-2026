extends SceneTree
# Every carryable prop's collider must match the mesh you can see.
#
# WHY THIS IS A TEST AND NOT A NOTE. The pairing is hand-maintained across two files: a
# CollisionShape3D authored in metres, and a `.blend` instanced under it at a scale chosen to
# bring the model to the same size. Nothing enforces it, and it has now broken twice — once
# when models were re-authored at new unit sizes (the power cell ended up 3.3x smaller than
# its collider, the canister and both cable plugs half as wide as theirs), and once when the
# editor reset a Model's scale to 1 on save, giving a 2 m crate a 0.8 m collider.
#
# Both faults present the same way and neither shows in a screenshot: props rest
# interpenetrating the world and each other, and the solver flings them apart — rotating,
# jittering, and leaving through the hull.
#
# Tolerances are deliberately loose. This is not asserting a design; it is catching the case
# where a collider and its model are describing different objects.

## A collider may not exceed the mesh by more than this...
const MAX_OVERSIZE := 1.25
## ...nor fall below it by more than this. Under-size is the milder fault (the mesh clips into
## the floor rather than the prop fighting the world), so it gets more rope.
const MIN_UNDERSIZE := 0.80

const SCENES := [
	"res://scenes/props/pickup_crate.tscn",
	"res://scenes/props/food_crate.tscn",
	"res://scenes/props/power_cell.tscn",
	"res://scenes/props/canister.tscn",
	"res://scenes/props/spare_part.tscn",
	"res://scenes/props/spare_spring.tscn",
	"res://scenes/props/spare_screw.tscn",
	"res://scenes/props/spare_gear.tscn",
	"res://scenes/props/hammer.tscn",
	"res://scenes/props/battery_cube.tscn",
	"res://scenes/props/loose_cable.tscn",
	"res://scenes/props/power_cable.tscn",
]

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		failures.append(label)
		print("  FAIL %s" % label)


func _run() -> void:
	print("[every prop's collider matches its mesh]")
	for path in SCENES:
		var name: String = path.get_file().get_basename()
		var packed: PackedScene = load(path)
		if packed == null:
			check(false, "%s loads" % name)
			continue
		var node := packed.instantiate()
		root.add_child(node)
		await process_frame

		var body := _first_rigid(node)
		if body == null:
			check(false, "%s has a RigidBody3D" % name)
			node.free()
			continue

		var col := _collider_extent(body)
		var mesh := _mesh_extent(body)
		if col == Vector3.ZERO or mesh == Vector3.ZERO:
			check(false, "%s: could not measure collider or mesh" % name)
			node.free()
			continue

		var ratio := Vector3(col.x / mesh.x, col.y / mesh.y, col.z / mesh.z)
		var worst: float = maxf(maxf(ratio.x, ratio.y), ratio.z)
		var least: float = minf(minf(ratio.x, ratio.y), ratio.z)
		check(worst <= MAX_OVERSIZE,
			"%s collider is not oversized (%.2fx mesh; %s vs %s)" % [name, worst, _fmt(col), _fmt(mesh)])
		check(least >= MIN_UNDERSIZE,
			"%s collider is not undersized (%.2fx mesh)" % [name, least])

		# The half-height drop that centres a base-origin model on the body: if it is computed
		# from a height the model no longer has, the mesh hangs below its own collider.
		#
		# Tolerance is half the MESH height, not half the collider's: the fault this catches is
		# a drop computed from a stale, larger height, and the stale collider is the very thing
		# that would excuse it. The power cell was 0.245m off a 0.21m mesh and would have passed
		# against its own 0.70m collider. Props whose model is deliberately offset within its
		# collider (the cable plugs sit 0.12m up a 0.33m mesh) stay inside this.
		var mesh_centre := _mesh_centre(body)
		var drift: float = mesh_centre.y - body.global_position.y
		check(absf(drift) <= mesh.y * 0.5,
			"%s mesh sits within its own height of the body origin (off by %.3fm)" % [name, drift])

		# The `-col` StaticBody3D hazard: a second, world-layer collider inside the rigid body.
		for child in body.find_children("*", "StaticBody3D", true, false):
			var static_body := child as StaticBody3D
			check(static_body.collision_layer == 0 and static_body.collision_mask == 0,
				"%s: nested %s is silenced" % [name, static_body.name])

		node.free()

	print("-- %d checks, %d failures --" % [checks, failures.size()])
	for failure in failures:
		print("   FAILED: %s" % failure)
	quit(1 if failures.size() > 0 else 0)


func _fmt(v: Vector3) -> String:
	return "%.2fx%.2fx%.2f" % [v.x, v.y, v.z]


func _first_rigid(node: Node) -> RigidBody3D:
	if node is RigidBody3D:
		return node
	for child in node.get_children():
		var found := _first_rigid(child)
		if found != null:
			return found
	return null


func _collider_extent(body: RigidBody3D) -> Vector3:
	var box := AABB()
	var first := true
	for child in body.get_children():
		if not (child is CollisionShape3D):
			continue
		var shape: Shape3D = (child as CollisionShape3D).shape
		if shape == null:
			continue
		var debug := shape.get_debug_mesh()
		if debug == null:
			continue
		var local := debug.get_aabb()
		local.position += (child as Node3D).position
		box = local if first else box.merge(local)
		first = false
	return Vector3.ZERO if first else box.size


func _mesh_aabb(body: RigidBody3D) -> AABB:
	var box := AABB()
	var first := true
	for node in _all(body):
		if not (node is VisualInstance3D):
			continue
		var vis := node as VisualInstance3D
		var world := vis.global_transform * vis.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return box


func _mesh_extent(body: RigidBody3D) -> Vector3:
	return _mesh_aabb(body).size


func _mesh_centre(body: RigidBody3D) -> Vector3:
	var box := _mesh_aabb(body)
	return box.position + box.size * 0.5


func _all(node: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(node)
	for child in node.get_children():
		_all(child, out)
	return out
