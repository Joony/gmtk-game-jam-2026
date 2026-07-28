extends SceneTree
# Does a CARRIED item clear the door, or does it hit it?
#
# The trigger that opens a door is sized for the player's body, but the thing in their hands is
# 1.4m further forward (player.tscn, HoldPoint z -1.4). So the item crosses the doorway plane
# `1.4 / speed` seconds before the player would, against a door that started opening when the
# PLAYER tripped the trigger.
#
# This walks the player at full speed straight at a real door with a real prop held, and reports
# the gap between the panels at the moment the item's leading face reaches the door plane. Run it
# across a range of `door_approach` values so the number can be chosen rather than guessed.
#
# Run: godot --headless --path . -s tests/diag_door_clearance.gd

## The doorway between the spine corridor and the cryo bay: dead ahead of the pod, so it is the
## one every single trip goes through, in both directions.
const DOOR_AT := Vector3(0.5, 0.0, -4.0)
const APPROACHES := [1.6, 2.0, 2.2, 2.4, 2.8]
const CARRIED := "res://scenes/props/canister.tscn"

## The bulkiest things the player carries, and how far off the doorway's centre line they walk.
## Both matter and neither is the average case: the gap opens symmetrically about the centre, so
## walking 0.3m off-centre spends 0.3m of the clearance before the item's own width is counted.
const BULKY := [
	"res://scenes/props/pickup_crate.tscn",
	"res://scenes/props/food_crate.tscn",
	"res://scenes/props/canister.tscn",
	"res://scenes/props/battery.tscn",
]
const OFFSETS := [0.0, 0.3]

const Opening := preload("res://tests/opening.gd")


func _init() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		push_error("door clearance diag timed out")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	print("walking at max_speed into the corridor/cryo-bay door, carrying a canister")
	print("gap = clear width between the panels when the item's leading face reaches the door\n")
	print("  approach   item width   gap at arrival   verdict")
	for approach in APPROACHES:
		var result := await _walk(approach, CARRIED, 0.0)
		print("  %-10.2f %-12.3f %-16.3f %s" % [
			approach, result["item_width"], result["gap"],
			"CLIPS" if result["gap"] < result["item_width"] else "clears by %.2fm"
				% (result["gap"] - result["item_width"])])

	# The bulky props, CENTRED. Deliberately not swept off the centre line: an off-centre carry
	# has the item scraping the door frame on the way in, so Carry's own collide-and-slide shoves
	# it and the numbers stop being a measurement of the door. Centred is the clean signal.
	#
	# A wide prop is not simply a harder version of a narrow one. It is also DEEPER, so its nose
	# reaches the doorway plane earlier — the crate gives back in arrival time most of what a
	# bigger approach buys it, which is why it needs its own sweep rather than an inference.
	print("\nbulky props, centred")
	print("  approach  prop                   width   gap     clearance each side")
	for prop in BULKY:
		for approach in [1.6, 2.4, 3.0, 3.6]:
			var r := await _walk(approach, prop, 0.0)
			var clearance: float = (r["gap"] - r["item_width"]) * 0.5
			print("  %-9.2f %-22s %-7.3f %-7.3f %s" % [
				approach, String(prop).get_file(), r["item_width"], r["gap"],
				"CLIPS by %.3f" % -clearance if clearance < 0.0
					else "clears by %.3f" % clearance])
	quit(0)


func _walk(approach: float, prop: String, offset: float) -> Dictionary:
	var game = load("res://scenes/game.tscn").instantiate()
	var ship := game.get_node("Ship") as RoomBuilder
	ship.door_approach = approach
	root.add_child(game)
	current_scene = game
	await process_frame
	# Out of the pod first, or Game._pose_in_pod() holds the player at the pod every frame and
	# every teleport below is silently undone — which is exactly what the first run of this
	# measured, and reported as "the item never reached the door".
	if not await Opening.wake(self, game):
		push_error("the pod never let go")
	await _physics_frames(10)

	var door: SlidingDoor = _door_near(game, DOOR_AT)
	var player: CharacterBody3D = game.get_node("Player")
	var rig := game.get_node("Player/CameraRig") as CameraController
	var carry: Carry = game.get_node("Player/Carry")

	# Hand the player a canister, and face them up the corridor at the door (travel is -Z, so
	# walking from the cryo bay toward the bridge is -Z).
	var node: Node = load(prop).instantiate()
	game.add_child(node)
	var item := node as RigidBody3D
	item.global_position = Vector3(DOOR_AT.x + offset, 1.0, DOOR_AT.z + 3.5)
	await _physics_frames(5)
	rig.set_look(0.0, 0.0)
	player.global_position = Vector3(DOOR_AT.x + offset, 0.0, DOOR_AT.z + 4.0)
	await _frames(2)
	var grabbed := carry.grab(item as Node3D as Interactable)
	# Let the pickup fly-in finish, or the item is still easing in from the floor.
	await _frames(30)
	if not grabbed:
		push_error("could not pick the canister up — the walk below would measure nothing")

	var item_width := _width_z(item)
	var gap := -1.0
	# Teleport-walk at max_speed. 7 m/s at 60Hz is 0.117m a step, so the Area3D cannot be
	# stepped over, and Carry re-authors the item from the hold point every render frame.
	var speed := 7.0
	var step := speed / 60.0
	for _i in 300:
		player.global_position += Vector3(0.0, 0.0, -step)
		await _frames(1)
		await physics_frame
		var lead := item.global_position.z - _width_z(item) * 0.5
		if lead <= DOOR_AT.z:
			gap = _panel_gap(door)
			break
	if gap < 0.0:
		push_error("the item never reached the door: item z %.2f, player z %.2f, held %s"
			% [item.global_position.z, player.global_position.z, str(carry.is_holding())])

	var out := {"gap": gap, "item_width": _x_width(item)}
	game.free()
	await process_frame
	return out


## Clear width between the two panels' inner faces, along the doorway.
func _panel_gap(door: SlidingDoor) -> float:
	var inner := []
	for child in door.get_children():
		var panel := child as AnimatableBody3D
		if panel == null:
			continue
		var shape := panel.get_node("Shape") as CollisionShape3D
		var size: Vector3 = (shape.shape as BoxShape3D).size
		# The doorway here runs along X.
		inner.append(panel.position.x - signf(panel.position.x) * size.x * 0.5)
	if inner.size() < 2:
		return 0.0
	return absf(float(inner[0]) - float(inner[1]))


## The item's extent ACROSS the doorway (X here) — what has to fit through the gap.
func _x_width(item: Node3D) -> float:
	var box := _visible_aabb(item)
	return box.size.x


## ...and its extent along the direction of travel, for working out when its nose arrives.
func _width_z(item: Node3D) -> float:
	return _visible_aabb(item).size.z


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


func _door_near(game: Node, at: Vector3) -> SlidingDoor:
	var best: SlidingDoor = null
	var best_d := INF
	for node in game.get_tree().get_nodes_in_group(RoomBuilder.GROUP_DOOR):
		var door := node as SlidingDoor
		if door == null:
			continue
		var d := door.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = door
	return best


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame
