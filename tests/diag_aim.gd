extends SceneTree
# How hard is each prop to put the reticle on, and does it depend which way it landed?
#
# Interactor._cast() is a single infinitely-thin `intersect_ray` from the camera centre, first
# hit wins. So the question is what fraction of the prop's VISIBLE silhouette actually returns
# the interactable — and whether that fraction collapses at some orientations.
#
# Method: stand at eye height a fixed distance away and sweep the AIM DIRECTION over a cone
# centred on the prop, counting which directions come back with it. The answer is in DEGREES OF
# AIM SLOP — how far off centre you can be and still be pointing at the thing — which is what
# "difficult to interact with" actually means for a reticle that is one pixel of ray.
#
# An earlier version of this measured "what fraction of the silhouette hits" and reported a
# flat 100% for everything, because it used the same ray to decide whether an aim point was
# over the prop as it used to test the hit. It could not have found anything.
#
# Run: godot --headless --path . -s tests/diag_aim.gd

const PROPS := [
	"res://scenes/props/hammer.tscn",
	"res://scenes/props/oil_can.tscn",
	"res://scenes/props/spare_gear.tscn",
	"res://scenes/props/spare_screw.tscn",
	"res://scenes/props/canister.tscn",
	"res://scenes/props/pickup_crate.tscn",
]

## Where the prop is dropped, on open cargo-bay floor.
const AT := Vector3(24.0, 0.0, 6.0)
## Eye height and how far back the player stands — a normal "I am looking at that" pose.
const EYE := 1.55
const BACK := 1.1
const GRID := 41
## Half-angle of the aim sweep, in degrees either side of dead centre.
const SWEEP_DEG := 6.0

var _game: Node
var _interactor: Interactor


func _init() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		push_error("aim diag timed out")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_interactor = _game.get_node("Player/Interactor")
	# Parked far away so the player's own body is never what the sweep runs into.
	_game.get_node("Player").global_position = Vector3(24.0, 0.0, 14.0)
	for i in 30:
		await physics_frame

	print("aim slop: how far off centre the reticle can be and still find the prop")
	print("(dropped on the floor, looked at from %.1fm away at %.2fm eye height)\n" % [BACK, EYE])
	print("  prop                 yaw   tip    slop across   slop up/down   solid")
	for path in PROPS:
		for yaw in [0.0, 45.0, 90.0]:
			for tip in [0.0, 90.0]:
				var r := await _measure(path, yaw, tip)
				print("  %-20s %-5.0f %-6.0f %-13s %-14s %s" % [
					String(path).get_file(), yaw, tip,
					"%.2f deg" % r["half_x"], "%.2f deg" % r["half_y"],
					"%d/%d" % [r["hit"], r["total"]]])
	quit(0)


func _measure(path: String, yaw_deg: float, tip_deg: float) -> Dictionary:
	var node: Node = load(path).instantiate()
	_game.add_child(node)
	var body := _first_body(node)
	body.global_transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(tip_deg), deg_to_rad(yaw_deg), 0.0)),
		AT + Vector3(0.0, 0.5, 0.0))
	# Let it fall and settle the way a dropped prop does.
	for i in 120:
		await physics_frame

	var box := _visible_aabb(body)
	var centre := box.position + box.size * 0.5
	var eye := Vector3(AT.x, EYE, AT.z + BACK)
	var space: PhysicsDirectSpaceState3D = _game.get_world_3d().direct_space_state

	# A basis around the line of sight, so the sweep is in "aim left/right" and "aim up/down"
	# rather than in world axes.
	var forward := (centre - eye).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()

	var hit := 0
	var total := 0
	var half_x := 0.0
	var half_y := 0.0
	for ix in GRID:
		for iy in GRID:
			var ax := lerpf(-SWEEP_DEG, SWEEP_DEG, float(ix) / float(GRID - 1))
			var ay := lerpf(-SWEEP_DEG, SWEEP_DEG, float(iy) / float(GRID - 1))
			var dir := (forward
				+ right * tan(deg_to_rad(ax))
				+ up * tan(deg_to_rad(ay))).normalized()
			total += 1
			if _aim_finds(dir) == body:
				hit += 1
				half_x = maxf(half_x, absf(ax))
				half_y = maxf(half_y, absf(ay))

	body.queue_free()
	for i in 3:
		await physics_frame
	return {"hit": hit, "total": total, "half_x": half_x, "half_y": half_y}


## Does a ray at this aim point strike the prop's own collider at all — i.e. is the reticle over
## the thing, as far as physics is concerned?
func _ray_reaches_mesh(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		body: RigidBody3D) -> bool:
	var direction := (to - from).normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 4.0)
	query.collide_with_areas = true
	var result := space.intersect_ray(query)
	return not result.is_empty() and result.get("collider") == body


## What the REAL Interactor comes back with — its own cast_from(), not a copy of it. A replica
## here would measure the replica, and the whole point of this diagnostic is the aim code that
## actually ships.
func _aim_finds(direction: Vector3) -> Object:
	var eye := Vector3(AT.x, EYE, AT.z + BACK)
	return _interactor.cast_from(eye, direction)


func _visible_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for entry in _meshes(node):
		var mesh := entry as MeshInstance3D
		if not mesh.visible:
			continue
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


func _first_body(node: Node) -> RigidBody3D:
	if node is RigidBody3D:
		return node
	for child in node.get_children():
		var found := _first_body(child)
		if found != null:
			return found
	return null
