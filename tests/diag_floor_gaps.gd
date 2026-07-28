extends SceneTree
# Where can a dropped item leave the ship? Two questions, measured rather than guessed:
#
#   1. GEOMETRY. Floors are one box per room (RoomBuilder note 2), and adjacent rooms abut
#      EXACTLY — bridge ends at z -12, bathroom starts at z -12 — so every doorway between two
#      rooms sits directly on a seam between two static boxes. This reports the seams and any
#      genuine hole.
#   2. BEHAVIOUR. Small rigid bodies are rained onto the walkable floor, doorways included, and
#      anything that ends up below the floor is named with where it started.
#
# Run: godot --headless --path . -s tests/diag_floor_gaps.gd

const PROBE_RADIUS := 0.06
const SETTLE_FRAMES := 240


func _init() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		push_error("floor diag timed out")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var ship: RoomBuilder = game.get_node("Ship")
	await _frames(20)

	# --- 1. the floor boxes themselves ---------------------------------------
	var boxes: Array = []
	for node in get_nodes_in_group(RoomBuilder.GROUP_FLOOR):
		var body := node as StaticBody3D
		if body == null:
			continue
		for child in body.get_children():
			var shape := child as CollisionShape3D
			if shape == null or not (shape.shape is BoxShape3D):
				continue
			var size: Vector3 = (shape.shape as BoxShape3D).size
			var centre: Vector3 = shape.global_position
			boxes.append({
				"name": String(body.name),
				"aabb": AABB(centre - size * 0.5, size),
			})
	print("floor boxes: %d" % boxes.size())
	for entry in boxes:
		var box: AABB = entry["aabb"]
		print("  %-28s x %+7.2f..%+7.2f  z %+7.2f..%+7.2f  top y %+.3f  thick %.3f" % [
			entry["name"], box.position.x, box.end.x, box.position.z, box.end.z,
			box.end.y, box.size.y])

	# Seams: pairs whose spans touch on one axis and overlap on the other. Zero overlap is a
	# seam a body can be squeezed into; a NEGATIVE overlap is an outright hole.
	print("\nseams between adjacent floors (overlap 0.000 = exact abut):")
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var a: AABB = boxes[i]["aabb"]
			var b: AABB = boxes[j]["aabb"]
			var gap_x: float = maxf(a.position.x, b.position.x) - minf(a.end.x, b.end.x)
			var gap_z: float = maxf(a.position.z, b.position.z) - minf(a.end.z, b.end.z)
			# Touching on x and genuinely overlapping on z, or vice versa.
			if absf(gap_x) < 0.001 and gap_z < -0.001:
				print("  %s | %s  abut on X at %+.2f, share %.2fm of Z"
					% [boxes[i]["name"], boxes[j]["name"],
					maxf(a.position.x, b.position.x), -gap_z])
			elif absf(gap_z) < 0.001 and gap_x < -0.001:
				print("  %s | %s  abut on Z at %+.2f, share %.2fm of X"
					% [boxes[i]["name"], boxes[j]["name"],
					maxf(a.position.z, b.position.z), -gap_x])

	# --- 2. rain probes on every walkable square metre -----------------------
	# Deliberately small (6cm) and dropped from just above the floor: the question is whether
	# the STATIC geometry has a hole, not whether a fast body can tunnel.
	var probes: Array = []
	for entry in boxes:
		var box: AABB = entry["aabb"]
		var x := box.position.x + 0.5
		while x < box.end.x:
			var z := box.position.z + 0.5
			while z < box.end.z:
				probes.append(_probe(game, Vector3(x, 0.35, z)))
				z += 1.0
			x += 1.0
	print("\nprobes dropped: %d" % probes.size())

	await _physics_frames(SETTLE_FRAMES)
	var lost := 0
	for probe in probes:
		var body := probe as RigidBody3D
		if not is_instance_valid(body):
			continue
		if body.global_position.y < -0.5:
			lost += 1
			print("  LOST from %v -> now y %+.2f (room %s)" % [
				body.get_meta("from"), body.global_position.y,
				ship.room_at(body.get_meta("from"))])
	print("probes that left the ship: %d" % lost)

	quit(0)


func _probe(game: Node, at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.continuous_cd = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PROBE_RADIUS
	shape.shape = sphere
	body.add_child(shape)
	game.add_child(body)
	body.global_position = at
	body.set_meta("from", at)
	return body


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame
