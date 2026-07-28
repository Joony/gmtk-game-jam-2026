extends SceneTree
# THE REPORTED BUG, in a world with nothing else in it.
#
# Every previous attempt loaded game.tscn — the pod, the cryo station, the supplies, the whole
# ship — and never reproduced the loss in ~200 throws. This builds the smallest thing that can
# show it: one room, the real player scene, one prop. No LostAndFound at all, so a lost item
# stays lost and is visible as such.
#
#   pick it up -> look straight down -> throw -> does it go through the floor?
#
# Run: godot --headless --path . -s tests/diag_void_repro.gd

const PLAYER := "res://scenes/player.tscn"
const PROPS := [
	"res://scenes/props/food_crate.tscn",
	"res://scenes/props/hammer.tscn",
	"res://scenes/props/pickup_crate.tscn",
	"res://scenes/props/battery_cube.tscn",
]

var _world: Node3D
var _ship: RoomBuilder
var _player: CharacterBody3D
var _carry: Carry
var _rig: CameraController


func _init() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		push_error("void repro timed out")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	_build_world()
	await _physics_frames(30)

	print("one room, one player, one prop. no lost-and-found.\n")
	print("  prop                 pitch  throw?  base@drop  vel@drop            final y    result")
	for path in PROPS:
		for threw in [true, false]:
			var r := await _try(path, threw, -90.0)
			print("  %-20s %-6.0f %-7s %-10.3f %-19s %-10.2f %s" % [
				String(path).get_file(), -90.0, str(threw), r["base"], "%v" % r["velocity"],
				r["final_y"], "LOST INTO THE VOID" if r["final_y"] < -1.0 else "kept"])

	# CONTROL: a normal forward throw must still fling. If removing the collision exception
	# before the clip made every throw limp, that is a worse bug than the one being fixed.
	print("\ncontrol — looking level, thrown forward (must still fly)")
	for path in PROPS:
		var r := await _try(path, true, 0.0)
		print("  %-20s %-6.0f %-7s %-10.3f %-19s %-10.2f %s" % [
			String(path).get_file(), 0.0, "true", r["base"], "%v" % r["velocity"],
			r["final_y"], "speed %.2f" % r["velocity"].length()])
	quit(0)


## A single room with a real RoomBuilder floor — same 0.2m slab the ship uses.
func _build_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world

	_ship = RoomBuilder.new()
	_ship.name = "Ship"
	_ship.build_lights = false
	_world.add_child(_ship)
	_ship.add_room(Rect2i(-5, -5, 10, 10), {"id": "test_room", "height": 3.0})
	_ship.build()

	var player_scene: PackedScene = load(PLAYER)
	_player = player_scene.instantiate()
	_world.add_child(_player)
	_player.global_position = Vector3(0.0, 0.5, 0.0)
	_carry = _player.get_node("Carry")
	_rig = _player.get_node("CameraRig")


func _try(path: String, threw: bool, pitch: float) -> Dictionary:
	_player.global_position = Vector3(0.0, 0.5, 0.0)
	_player.velocity = Vector3.ZERO
	_rig.set_look(0.0, 0.0)
	await _physics_frames(20)

	var node: Node = load(path).instantiate()
	_world.add_child(node)
	var item := _first_body(node)
	item.global_position = Vector3(0.0, 0.5, -1.2)
	await _physics_frames(20)

	if not _carry.grab(item as Node3D as Interactable):
		push_error("could not pick up %s" % path)
		return {"base": 0.0, "velocity": Vector3.ZERO, "final_y": 999.0}
	# Let the pickup fly-in finish and the hold settle.
	await _frames(45)

	# Look straight down, swept the way a mouse would.
	for i in range(1, 13):
		_rig.set_look(0.0, deg_to_rad(pitch) * (float(i) / 12.0))
		await process_frame

	var base := _lowest_visible_point(item)
	_carry.drop(threw)
	await physics_frame
	var velocity := item.linear_velocity
	await _physics_frames(240)

	var out := {"base": base, "velocity": velocity, "final_y": item.global_position.y}
	item.queue_free()
	await _physics_frames(2)
	return out


func _lowest_visible_point(node: Node3D) -> float:
	var lowest := INF
	for entry in _meshes(node):
		var mesh := entry as MeshInstance3D
		if not mesh.visible:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	return lowest


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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame
