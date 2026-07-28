extends SceneTree
# HOW an item actually leaves the ship. diag_floor_gaps proved the static floor has no hole and
# loses nothing at rest, so the loss has to come from a force event. Three candidates, each run
# against the REAL props:
#
#   A. DEPENETRATION. Carry._clamp_to_walls gives up after 4 slide iterations, so an item wedged
#      in a corner can be authored partly inside geometry; drop() then unfreezes it there and
#      Jolt shoves it out. Which side does it come out?
#   B. THROWN AT A SEAM. Every doorway stands on an exact butt joint between two floor boxes.
#   C. THROWN AT THE FLOOR at the speed the game actually allows (max_release_speed 12 m/s plus
#      throw_impulse 6).
#
# Run: godot --headless --path . -s tests/diag_floor_escape.gd

const PROPS := [
	"res://scenes/props/canister.tscn",
	"res://scenes/props/spare_gear.tscn",
	"res://scenes/props/spare_screw.tscn",
	"res://scenes/props/hammer.tscn",
	"res://scenes/props/power_cell.tscn",
]

# Doorway seams, straight out of diag_floor_gaps.
const SEAMS := [
	Vector3(0.5, 0.0, -4.0),    # cryo bay | corridor
	Vector3(0.5, 0.0, -12.0),   # corridor | bridge
	Vector3(-7.0, 0.0, -14.5),  # corridor_port | bridge
	Vector3(-3.5, 0.0, -12.0),  # bridge | bathroom
	Vector3(20.5, 0.0, -2.0),   # corridor_cargo | cargo bay
]

var _game: Node
var _lost: Array[String] = []


func _init() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		push_error("floor escape diag timed out")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await process_frame
	await _physics_frames(20)

	await _test_depenetration()
	await _test_seam_throws()
	await _test_floor_slams()

	print("\n=== %d escapes ===" % _lost.size())
	for entry in _lost:
		print("  " + entry)
	quit(0)


## A. Spawned already INSIDE the floor slab, at increasing depth. The floor spans y -0.2..0.
func _test_depenetration() -> void:
	print("A. depenetration — dropped already embedded in the 0.2m slab")
	for path in PROPS:
		for depth in [0.02, 0.06, 0.10, 0.15, 0.19, 0.25]:
			var body := _spawn(path, Vector3(0.5, -depth, 8.0))
			await _physics_frames(120)
			var y := body.global_position.y if is_instance_valid(body) else -999.0
			var escaped := y < -0.5
			print("   %-22s depth %.2f -> y %+.3f %s"
				% [path.get_file(), depth, y, "LOST" if escaped else ""])
			if escaped:
				_lost.append("A depenetration: %s embedded %.2fm fell to y %+.2f"
					% [path.get_file(), depth, y])
			if is_instance_valid(body):
				body.queue_free()
			await _physics_frames(2)


## B. Thrown hard straight down onto a doorway seam.
func _test_seam_throws() -> void:
	print("\nB. thrown down onto doorway seams at 18 m/s")
	for seam in SEAMS:
		for path in PROPS:
			var body := _spawn(path, seam + Vector3(0.0, 0.6, 0.0))
			body.linear_velocity = Vector3(0.0, -18.0, 0.0)
			await _physics_frames(90)
			var y := body.global_position.y if is_instance_valid(body) else -999.0
			if y < -0.5:
				print("   LOST %-22s at seam %v -> y %+.2f" % [path.get_file(), seam, y])
				_lost.append("B seam %v: %s fell to y %+.2f" % [seam, path.get_file(), y])
			if is_instance_valid(body):
				body.queue_free()
			await _physics_frames(2)
	print("   (only losses printed)")


## C. Slammed into open floor at the speeds Carry actually permits, and well beyond.
func _test_floor_slams() -> void:
	print("\nC. slammed into open floor")
	for speed in [12.0, 18.0, 30.0, 60.0, 120.0]:
		for path in PROPS:
			var body := _spawn(path, Vector3(2.5, 0.5, 8.0))
			body.linear_velocity = Vector3(0.0, -speed, 0.0)
			await _physics_frames(90)
			var y := body.global_position.y if is_instance_valid(body) else -999.0
			if y < -0.5:
				print("   LOST %-22s at %.0f m/s -> y %+.2f" % [path.get_file(), speed, y])
				_lost.append("C slam: %s at %.0f m/s fell to y %+.2f"
					% [path.get_file(), speed, y])
			if is_instance_valid(body):
				body.queue_free()
			await _physics_frames(2)
	print("   (only losses printed)")


func _spawn(path: String, at: Vector3) -> RigidBody3D:
	var node: Node = load(path).instantiate()
	_game.add_child(node)
	var body := _first_body(node)
	body.global_position = at
	return body


func _first_body(node: Node) -> RigidBody3D:
	if node is RigidBody3D:
		return node
	for child in node.get_children():
		var found := _first_body(child)
		if found != null:
			return found
	return null


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame
