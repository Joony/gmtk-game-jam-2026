extends SceneTree
# Measurements for the oil-can puzzle: how big CD_Oil_v1 is, and where the cargo crawlers
# actually stand. Measured in a RUNNING scene rather than by instancing headlessly, because a
# freshly instanced node's global_transform reports nonsense (docs/debugging-gotchas.md).
#
# Run: godot --headless --path . -s tests/diag_oil_crawler.gd

const OIL := "res://3D-Models/CD_Oil_v1.blend"


func _init() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("oil/crawler diag timed out")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	for i in 30:
		await physics_frame

	# --- the oil can, at scale 1, in model units ---
	var can: Node3D = load(OIL).instantiate()
	game.add_child(can)
	can.global_position = Vector3(24.0, 2.0, 6.0)
	await process_frame
	var box := _aabb(can)
	print("CD_Oil_v1 at scale 1: size %v, origin offset from min %v"
		% [box.size, Vector3.ZERO - box.position])
	print("  -> to make it %.2fm tall, scale by %.4f" % [0.28, 0.28 / maxf(box.size.y, 0.0001)])
	print("  children: %s" % [_names(can)])
	# WHICH WAY THE SPOUT POINTS, in the can's own frame. Carried, Carry yaws the item so its
	# local -Z faces the way the player is looking, so a nozzle on +Z is a nozzle aimed back at
	# them. Measured off the Nozzle mesh rather than inferred from the whole-can AABB, which
	# only says the shape is lopsided and not which end is the business end.
	for entry in _meshes(can):
		var mesh := entry as MeshInstance3D
		var mbox: AABB = mesh.global_transform * mesh.get_aabb()
		var centre := mbox.position + mbox.size * 0.5 - can.global_position
		print("  %-8s centre relative to origin %v" % [mesh.name, centre])

	# The prop as actually built, which is what the player holds.
	var prop: Node3D = load("res://scenes/props/oil_can.tscn").instantiate()
	game.add_child(prop)
	prop.global_position = Vector3(24.0, 2.0, 9.0)
	await process_frame
	for entry in _meshes(prop):
		var mesh := entry as MeshInstance3D
		var mbox: AABB = mesh.global_transform * mesh.get_aabb()
		var centre := mbox.position + mbox.size * 0.5 - prop.global_position
		print("  oil_can.tscn %-8s centre relative to body %v" % [mesh.name, centre])

	# --- the crawlers, as dressed ---
	for name in ["CargoCrawlerA", "CargoCrawlerB"]:
		var crawler := game.find_child(name, true, false) as Node3D
		if crawler == null:
			print("%s: NOT FOUND" % name)
			continue
		var cbox := _aabb(crawler)
		print("%s at %v, scale %v, size %v, top y %+.2f"
			% [name, crawler.global_position, crawler.scale, cbox.size, cbox.end.y])
		print("  room: %s" % (game.get_node("Ship") as RoomBuilder).room_at(crawler.global_position))
		print("  has Indicator empty: %s" % str(crawler.find_child("Indicator", true, false) != null))
		print("  children: %s" % [_names(crawler)])
		print("  colliders: %d" % _colliders(crawler))

	quit(0)


func _aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for entry in _meshes(node):
		var mesh := entry as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _meshes(node: Node) -> Array:
	var out := []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _colliders(node: Node) -> int:
	var n := 0
	if node is CollisionShape3D:
		n += 1
	for child in node.get_children():
		n += _colliders(child)
	return n


func _names(node: Node) -> Array:
	var out := []
	for child in node.get_children():
		out.append("%s(%s)" % [child.name, child.get_class()])
	return out
