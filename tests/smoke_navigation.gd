extends SceneTree
# Can the player actually GET to everywhere the game asks them to go?
#
# Written after two separate incidents where the answer was no and nothing noticed: spare
# parts dropped straight across the walking line out of the pod bay (caught by accident,
# because the player smoke test walks forward for half a second), and a ring of cryo pods
# that left a 12cm gap against the wall. Both were invisible to every other test, because
# every other test either teleports things in front of the camera or never walks anywhere.
#
# It floods the ship with capsule casts at the player's own size and checks connectivity,
# then separately checks that each repair panel faces into open space rather than into the
# wall it is mounted on — the failure that put three of four panels backwards.
#
# Run: godot --headless --path . -s tests/smoke_navigation.gd

## Slightly under the real player capsule (0.4 x 1.8). A hair of slack keeps a cell that
## merely grazes a wall from reading as blocked, which would report false dead ends.
const RADIUS := 0.36
const HEIGHT := 1.7
const STEP := 0.5
const FLOOR_Y := 0.95

## The ship's footprint in grid/world XZ, plus a margin. Must cover the whole ship: the
## flood fill cannot leave this box, so a spawn or target outside it reads as unreachable.
## The 21x21 cryo bay runs x=-10..11, z=-4..17; the engine room reaches z=-24.
const MIN_X := -12.0
const MAX_X := 13.0
const MIN_Z := -24.0
const MAX_Z := 18.0

var _failures: Array[String] = []
var _space: PhysicsDirectSpaceState3D
var _query: PhysicsShapeQueryParameters3D
var _free: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok   %s" % label)
	else:
		_failures.append(label)
		print("  FAIL %s" % label)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(round(p.x / STEP)), int(round(p.z / STEP)))


func _world(c: Vector2i) -> Vector3:
	return Vector3(c.x * STEP, FLOOR_Y, c.y * STEP)


func _is_free(c: Vector2i) -> bool:
	if _free.has(c):
		return _free[c]
	_query.transform = Transform3D(Basis.IDENTITY, _world(c))
	var free := _space.intersect_shape(_query, 1).is_empty()
	_free[c] = free
	return free


## Flood fill from a start cell. Returns the set of reachable cells.
func _reachable_from(start: Vector3) -> Dictionary:
	var seen := {}
	var origin := _cell(start)
	if not _is_free(origin):
		# Nudge: a marker can legitimately sit a few cm inside a wall's tolerance.
		var found := false
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var c := origin + Vector2i(dx, dz)
				if _is_free(c):
					origin = c
					found = true
					break
			if found:
				break
		if not found:
			return seen

	var queue: Array[Vector2i] = [origin]
	seen[origin] = true
	var min_c := _cell(Vector3(MIN_X, 0, MIN_Z))
	var max_c := _cell(Vector3(MAX_X, 0, MAX_Z))
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			if n.x < min_c.x or n.x > max_c.x or n.y < min_c.y or n.y > max_c.y:
				continue
			if not _is_free(n):
				continue
			seen[n] = true
			queue.append(n)
	return seen


## Nearest reachable cell to a target, and how far away it is.
func _closest(reach: Dictionary, target: Vector3) -> float:
	var best := INF
	for c in reach:
		best = minf(best, _world(c).distance_to(Vector3(target.x, FLOOR_Y, target.z)))
	return best


func _run() -> void:
	print("== smoke_navigation ==")
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	await physics_frame

	var player: CharacterBody3D = game.get_node("Player")
	_space = player.get_world_3d().direct_space_state

	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = shape
	_query.collide_with_areas = false
	# The player and anything the player could shove aside are not walls.
	var exclude: Array[RID] = [player.get_rid()]
	for node in get_nodes_in_group(&"interactables"):
		if node is RigidBody3D:
			exclude.append((node as RigidBody3D).get_rid())
	_query.exclude = exclude

	# Doors are shut until you approach, and would wall off the whole ship from a static
	# sweep. Open every one first: the question is whether the LAYOUT is connected.
	var doors := 0
	for door in get_nodes_in_group(RoomBuilder.GROUP_DOOR):
		if door is SlidingDoor:
			(door as SlidingDoor).open()
			doors += 1
	# The panels slide on a tween over open_time; sampling before it finishes reports the
	# ship as walled off at every doorway.
	for i in 60:
		await physics_frame
	print("  (opened %d doors)" % doors)

	var spawn: Marker3D = game.get_node("PlayerSpawn")
	var reach := _reachable_from(spawn.global_position)
	_check("the spawn point itself is standable (%d cells reachable)" % reach.size(), reach.size() > 50)

	# Everywhere the game sends you.
	var targets: Array = []
	for node in get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var fault := node as Malfunction
		for child in fault.get_children():
			if child is RepairPoint:
				targets.append({"name": fault.system_name, "at": (child as Node3D).global_position})
	for node in get_nodes_in_group(&"spare_parts"):
		targets.append({"name": (node as Node).name, "at": (node as Node3D).global_position})
	var pod := game.get_node_or_null("StasisPod") as StasisPod
	if pod != null:
		targets.append({"name": "StasisPod", "at": pod.exit_transform().origin})

	for target in targets:
		# 1.4m: close enough to interact with (the ray reaches 2.5m) or to pick up.
		var distance: float = _closest(reach, target["at"])
		_check("%s is walkable to (nearest standable point %.2fm away)" % [target["name"], distance],
			distance <= 1.4)

	# Panels mounted backwards are invisible to every other test, because the interaction
	# test moves them in front of the camera before looking at them.
	print("[repair panels face into the room, not into the wall]")
	for node in get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var fault := node as Malfunction
		var panel: Node3D = null
		for child in fault.get_children():
			if child is RepairPoint:
				panel = child
		if panel == null:
			continue
		var normal := panel.global_transform.basis.z
		var from := panel.global_position
		var ahead := PhysicsRayQueryParameters3D.create(from, from + normal * 0.9)
		var behind := PhysicsRayQueryParameters3D.create(from, from - normal * 0.9)
		_check("%s panel has open space in front of it" % fault.system_name,
			_space.intersect_ray(ahead).is_empty())
		_check("%s panel is backed by geometry" % fault.system_name,
			not _space.intersect_ray(behind).is_empty())

	print("-- %d failures --" % _failures.size())
	for failure in _failures:
		print("   FAILED: %s" % failure)
	quit(1 if _failures.size() > 0 else 0)
