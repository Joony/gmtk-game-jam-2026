extends SceneTree
# Does the held item get pushed out of the way by the FLOOR the same as by a WALL?
#
# _clamp_to_walls sweeps the item every frame and is supposed to treat any surface alike. This
# measures that claim directly: press the held item into a wall and record how far its mesh gets
# past the wall face, then look straight down and record how far its mesh gets below the deck.
# Same item, same carry, two surfaces.
#
# Run: godot --headless --path . -s tests/diag_wall_vs_floor.gd

const PLAYER := "res://scenes/player.tscn"
const PROPS := [
	"res://scenes/props/food_crate.tscn",
	"res://scenes/props/hammer.tscn",
	"res://scenes/props/canister.tscn",
]

## The room spans x -5..5; its west wall's inner face is at x = -5.
const WALL_X := -5.0

var _world: Node3D
var _player: CharacterBody3D
var _carry: Carry
var _rig: CameraController


func _init() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		push_error("wall vs floor diag timed out")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	_build()
	await _physics_frames(30)
	print("how far the HELD item's mesh gets past each surface")
	print("(negative = it is inside the wall / under the deck)\n")
	print("  prop                 past wall face   below deck")
	for path in PROPS:
		var wall := await _press_into_wall(path)
		var floor_dip := await _look_down(path)
		print("  %-20s %+9.4f        %+9.4f" % [String(path).get_file(), wall, floor_dip])
	quit(0)


func _build() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var ship := RoomBuilder.new()
	ship.build_lights = false
	_world.add_child(ship)
	ship.add_room(Rect2i(-5, -5, 10, 10), {"id": "test_room", "height": 3.0})
	ship.build()
	_player = load(PLAYER).instantiate()
	_world.add_child(_player)
	_carry = _player.get_node("Carry")
	_rig = _player.get_node("CameraRig")


## Walk the player at the west wall, looking at it, so the held item is driven into it.
## Returns how far past the wall's inner face the item's mesh reached (negative = inside).
func _press_into_wall(path: String) -> float:
	var item := await _hold(path, Vector3(0.0, 0.5, 0.0))
	if item == null:
		return 999.0
	# Face -X and walk into the wall.
	_rig.set_look(PI * 0.5, 0.0)
	await _frames(20)
	for i in 60:
		_player.global_position = _player.global_position.lerp(
			Vector3(WALL_X + 0.4, 0.5, 0.0), 0.15)
		await process_frame
		await physics_frame
	var lowest_x := INF
	for entry in _meshes(item):
		var mesh := entry as MeshInstance3D
		if not mesh.visible:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		lowest_x = minf(lowest_x, box.position.x)
	var past := lowest_x - WALL_X
	_carry.drop(false)
	item.queue_free()
	await _physics_frames(5)
	return past


## Look straight down. Returns the item's lowest mesh point (negative = under the deck).
func _look_down(path: String) -> float:
	var item := await _hold(path, Vector3(0.0, 0.5, 0.0))
	if item == null:
		return 999.0
	for i in range(1, 13):
		_rig.set_look(0.0, deg_to_rad(-90.0) * (float(i) / 12.0))
		await process_frame
	await _frames(20)
	var lowest := INF
	for entry in _meshes(item):
		var mesh := entry as MeshInstance3D
		if not mesh.visible:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	_carry.drop(false)
	item.queue_free()
	await _physics_frames(5)
	return lowest


func _hold(path: String, at: Vector3) -> RigidBody3D:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_rig.set_look(0.0, 0.0)
	await _physics_frames(15)
	var node: Node = load(path).instantiate()
	_world.add_child(node)
	var item := _first_body(node)
	item.global_position = at + Vector3(0.0, 0.0, -1.2)
	await _physics_frames(15)
	if not _carry.grab(item as Node3D as Interactable):
		push_error("could not pick up %s" % path)
		return null
	await _frames(45)
	return item


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
