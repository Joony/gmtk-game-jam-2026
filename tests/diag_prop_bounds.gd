extends SceneTree
# Diagnostic: does each carryable prop's COLLIDER match the size of the MESH you can see?
#
# The props are built as a RigidBody3D whose CollisionShape3D is authored in metres, with the
# .blend model instanced underneath at a scale that is supposed to bring it to the same size
# (a 2 m crate model at 0.4 -> 0.8 m, matching a 0.8 m box). Nothing enforces that pairing.
# If a model is re-authored at a different size in Blender, the scale in the .tscn still says
# 0.4 and the collider still says 0.8 — and the two silently drift apart.
#
# A collider LARGER than the mesh is the interesting case: props rest interpenetrating walls
# and each other, and the solver pushes them apart hard — objects rotating and flying off.
#
# Run headless:  godot --headless -s tests/diag_prop_bounds.gd

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
	"res://scenes/props/oil_can.tscn",
	"res://scenes/props/battery_cube.tscn",
	"res://scenes/props/loose_cable.tscn",
	"res://scenes/props/power_cable.tscn",
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("%-18s %-22s %-22s %s" % ["prop", "collider (m)", "mesh (m)", "verdict"])
	for path in SCENES:
		var packed: PackedScene = load(path)
		if packed == null:
			print("%-18s could not load" % path.get_file())
			continue
		var node := packed.instantiate()
		root.add_child(node)
		await process_frame

		var body := _first_rigid(node)
		if body == null:
			print("%-18s no RigidBody3D" % path.get_file().get_basename())
			node.free()
			continue

		var col := _collider_extent(body)
		var mesh := _mesh_extent(body)
		var verdict := "-"
		if col == Vector3.ZERO or mesh == Vector3.ZERO:
			verdict = "could not measure"
		else:
			var ratio := Vector3(col.x / mesh.x, col.y / mesh.y, col.z / mesh.z)
			var worst: float = maxf(maxf(ratio.x, ratio.y), ratio.z)
			var least: float = minf(minf(ratio.x, ratio.y), ratio.z)
			if worst > 1.25:
				verdict = "*** COLLIDER %.0f%% TOO BIG ***" % ((worst - 1.0) * 100.0)
			elif least < 0.8:
				verdict = "collider %.0f%% too small" % ((1.0 - least) * 100.0)
			else:
				verdict = "ok (%.2f-%.2f)" % [least, worst]
		print("%-18s %-22s %-22s %s" % [
			path.get_file().get_basename(), _fmt(col), _fmt(mesh), verdict])
		node.free()
	quit()


func _fmt(v: Vector3) -> String:
	return "%.2f x %.2f x %.2f" % [v.x, v.y, v.z]


func _first_rigid(node: Node) -> RigidBody3D:
	if node is RigidBody3D:
		return node
	for child in node.get_children():
		var found := _first_rigid(child)
		if found != null:
			return found
	return null


## Size of the body's OWN collision shapes (direct CollisionShape3D children only — the
## disabled `-col` bodies inside the model are not the body's collider).
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
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	return Vector3.ZERO if first else box.size


## Size of everything actually drawn under the body.
func _mesh_extent(body: RigidBody3D) -> Vector3:
	var box := AABB()
	var first := true
	for node in _all(body):
		if not (node is VisualInstance3D):
			continue
		var vis := node as VisualInstance3D
		var world := vis.global_transform * vis.get_aabb()
		if first:
			box = world
			first = false
		else:
			box = box.merge(world)
	return Vector3.ZERO if first else box.size


func _all(node: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(node)
	for child in node.get_children():
		_all(child, out)
	return out
