extends SceneTree
# Step 8: interaction detection, carry physics and the reticle.
# Run: godot --headless --path . -s tests/smoke_interaction.gd

const GAME_SCENE := "res://scenes/game.tscn"

var _failures: Array[String] = []
var _game: Node3D
var _cam: Camera3D
var _carry: Carry
var _interactor: Interactor
var _reticle: CanvasLayer
var _player: CharacterBody3D


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)


# Park an item at eye level in front of the camera so the ray can hit it.
func _place_in_front(node: Node3D, distance: float) -> void:
	var forward := -_cam.global_transform.basis.z
	node.global_position = _cam.global_position + forward * distance


func _run() -> void:
	_game = load(GAME_SCENE).instantiate()
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_game.start_game()

	_player = _game.get_node("Player")
	_cam = _game.get_node("Player/CameraRig/Camera3D")
	_carry = _game.get_node("Player/Carry")
	_interactor = _game.get_node("Player/Interactor")
	_reticle = _game.get_node("Reticle")
	var holder: Node3D = _game.get_node("Player/CameraRig/Camera3D/HoldPoint")

	_check("player has an Interactor", _interactor != null)
	_check("player has a Carry", _carry != null)
	_check("Carry runs after the camera (priority 10)", _carry.process_priority == 10)

	await _physics_frames(45)  # settle on the floor

	# Move to the middle of the engine room before any of the physics work below. The carry
	# and throw sections walk the player 2m forward and park items 1.4m in front of that,
	# and the spawn point no longer has that much clear space — the cryo pod ring is right
	# there, so the "thrown" crate was being released inside a pod and going nowhere.
	_player.global_position = Vector3(0.0, 0.9, -17.0)
	_player.reset_physics_interpolation()
	(_game.get_node("Player/CameraRig") as CameraController).set_look(0.0, 0.0)
	await _physics_frames(20)

	var pickup: Node3D = _game.get_node("PickupA")
	# The Interactable script sits on the RigidBody3D itself — verify that actually works.
	_check("pickup is an Interactable", pickup is Interactable)
	_check("pickup is a RigidBody3D", pickup is RigidBody3D)
	_check("pickup registered in the interactables group", pickup.is_in_group(&"interactables"))
	_check("get_item_node returns the body", pickup.get_item_node() == pickup)

	# Float it so it doesn't fall out of the ray during the test.
	pickup.gravity_scale = 0.0
	pickup.linear_velocity = Vector3.ZERO
	_place_in_front(pickup, 1.2)
	await _physics_frames(3)

	# --- Detection ----------------------------------------------------------
	_check("ray finds the pickup", _interactor.current == pickup)
	_check("prompt offers the key", _interactor.get_prompt() == "[E] Pick up crate")
	_check("pickup is actionable with empty hands", _interactor.is_actionable())

	await _frames(12)  # let the reticle tween settle
	var dot: Panel = _reticle.get_node("%Dot")
	var prompt_label: Label = _reticle.get_node("%Prompt")
	_check("reticle dot is green on a target", dot.modulate.is_equal_approx(_reticle.COLOR_ACTIVE))
	_check("reticle prompt matches", prompt_label.text == "[E] Pick up crate")
	_check("reticle prompt is visible", prompt_label.modulate.a > 0.9)

	# --- Occlusion: a wall between camera and item breaks the target ---------
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	_game.add_child(wall)
	_place_in_front(wall, 0.6)
	await _physics_frames(3)
	_check("wall between camera and item clears the target", _interactor.current == null)
	await _frames(12)
	_check("reticle returns to grey with no target", dot.modulate.is_equal_approx(_reticle.COLOR_IDLE))

	wall.queue_free()
	await _physics_frames(3)
	_place_in_front(pickup, 1.2)
	await _physics_frames(3)
	_check("target returns once the wall is gone", _interactor.current == pickup)

	# --- Pickup via the real input path -------------------------------------
	_press("interact")
	await _frames(2)
	_check("interact picks the item up", _carry.is_holding())
	_check("held item is the pickup", _carry.held_item() == pickup)
	_check("held item is frozen kinematic", (pickup as RigidBody3D).freeze)
	_check(
		"held item stops interpolating (it is authored per frame)",
		pickup.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF
	)
	_check("carrying disables the item's own interactable", not (pickup as Interactable).is_enabled)

	# It should fly in and then track the hold point.
	await _frames(40)
	var offset := pickup.global_position.distance_to(holder.global_position)
	_check("held item tracks the hold point (%.3fm off)" % offset, offset < 0.15)

	# Held item must not block the ray, or you could never target anything while carrying.
	_check("held item does not block its own ray", _interactor.current != pickup)

	# --- Hands full: prompt shows, but the dot stays grey --------------------
	var pickup_b: Node3D = _game.get_node("PickupB")
	pickup_b.gravity_scale = 0.0
	pickup_b.linear_velocity = Vector3.ZERO
	_place_in_front(pickup_b, 2.0)
	await _physics_frames(3)
	_check("second pickup is targeted while carrying", _interactor.current == pickup_b)
	_check("prompt says hands are full", _interactor.get_prompt() == "Hands full")
	_check("hands-full target is NOT actionable", not _interactor.is_actionable())
	await _frames(12)
	_check("reticle stays grey when hands are full", dot.modulate.is_equal_approx(_reticle.COLOR_IDLE))
	pickup_b.global_position = Vector3(0, -50, 0)  # park it out of the way
	await _physics_frames(2)

	# --- Wall sweep: walking at a wall clamps the item to the near side ------
	# The sweep stops the item MOVING into geometry, so this has to be the real
	# scenario — advance the player until the hold point is past the wall.
	var forward := -_cam.global_transform.basis.z
	var sweep_wall := StaticBody3D.new()
	var sweep_shape := CollisionShape3D.new()
	var sweep_box := BoxShape3D.new()
	sweep_box.size = Vector3(6, 6, 0.2)
	sweep_shape.shape = sweep_box
	sweep_wall.add_child(sweep_shape)
	_game.add_child(sweep_wall)
	sweep_wall.global_position = _cam.global_position + forward * 3.0
	await _frames(10)

	var wall_along := (sweep_wall.global_position - _cam.global_position).dot(forward)
	# Step forward so the hold point (1.4m ahead) ends up beyond the wall plane.
	for i in 12:
		_player.global_position += forward * 0.18
		await process_frame
	await _frames(6)

	var item_along := (pickup.global_position - _cam.global_position).dot(forward)
	wall_along = (sweep_wall.global_position - _cam.global_position).dot(forward)
	_check(
		"held item is clamped to the near side of the wall (item %.2fm, wall %.2fm along view)"
			% [item_along, wall_along],
		item_along < wall_along
	)
	sweep_wall.queue_free()
	await _frames(20)

	# --- Drop ---------------------------------------------------------------
	if not _carry.is_holding():
		# Break-free may have dropped it against the wall; that is legitimate.
		_place_in_front(pickup, 1.2)
		await _physics_frames(3)
		_press("interact")
		await _frames(2)
	_check("holding again before the drop test", _carry.is_holding())
	_press("interact")
	await _frames(2)
	_check("interact drops the held item", not _carry.is_holding())
	_check("dropped item unfreezes", not (pickup as RigidBody3D).freeze)
	_check("dropped item re-enables its interactable", (pickup as Interactable).is_enabled)
	_check(
		"dropped item resumes interpolating",
		pickup.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	)
	_check(
		"collision with the player is restored",
		not (pickup as RigidBody3D).get_collision_exceptions().has(_player)
	)

	# --- Throw --------------------------------------------------------------
	pickup.linear_velocity = Vector3.ZERO
	_place_in_front(pickup, 1.2)
	await _physics_frames(3)
	_press("interact")
	await _frames(20)
	_check("holding before the throw test", _carry.is_holding())
	var throw_from := pickup.global_position
	_press("throw")
	await _frames(2)
	_check("throw releases the item", not _carry.is_holding())
	# The impulse lands on the next physics step, not the next render frame.
	await _physics_frames(6)
	var travelled := pickup.global_position.distance_to(throw_from)
	_check(
		"thrown item is launched (%.2f m/s, moved %.2fm)"
			% [pickup.linear_velocity.length(), travelled],
		pickup.linear_velocity.length() > 1.0 and travelled > 0.1
	)

	# --- USE_ITEM: carrying a spare part to a repair panel -------------------
	# Runs against the REAL panel from step 12 rather than a stand-in socket, so this
	# covers the actual repair route the game ships.
	var fault: Malfunction = _game.get_node("MainDrive")
	var panel: RepairPoint = fault.get_node("RepairPanel")
	var part: Node3D = _game.get_node("SparePart1")

	# A healthy system's panel is invisible to the ray — otherwise every panel on the
	# ship would offer a prompt for a problem the player does not have.
	pickup.global_position = Vector3(0, -50, 0)
	await _physics_frames(2)
	_place_in_front(panel, 1.2)
	await _physics_frames(3)
	_check("a working system's panel is not targeted", _interactor.current == null)

	fault.break_now()
	await _physics_frames(3)
	_check("a broken system's panel is targeted", _interactor.current == panel)
	# The patch route has to be offered empty-handed, or the player never discovers it.
	_check(
		"panel offers the patch when empty-handed (got '%s')" % _interactor.get_prompt(),
		"Clamp the coupling" in _interactor.get_prompt()
	)
	_check("panel is actionable empty-handed", _interactor.is_actionable())

	# Wrong item: refused by name, and the reticle must not promise anything.
	# The panel has to be moved aside first — it is a solid box, and leaving it in front
	# would mean the grab press hits the panel and patches the fault instead.
	panel.global_position = Vector3(0, -50, 0)
	await _physics_frames(2)
	pickup.linear_velocity = Vector3.ZERO
	_place_in_front(pickup, 1.2)
	await _physics_frames(3)
	_press("interact")
	await _frames(20)
	_check("carrying a generic crate", _carry.is_holding())
	_place_in_front(panel, 1.5)
	await _physics_frames(3)
	_check(
		"the wrong part is refused by name (got '%s')" % _interactor.get_prompt(),
		"Wrong part" in _interactor.get_prompt()
	)
	_press("interact")
	await _frames(4)
	_check("the wrong part does not repair anything", fault.is_active)

	# Right part: fits permanently and is consumed.
	_carry.drop(false)
	panel.global_position = Vector3(0, -50, 0)
	await _physics_frames(3)
	pickup.global_position = Vector3(0, -50, 0)
	part.linear_velocity = Vector3.ZERO
	_place_in_front(part, 1.2)
	await _physics_frames(3)
	_press("interact")
	await _frames(20)
	_check("carrying a spare part", _carry.is_holding())
	_place_in_front(panel, 1.5)
	await _physics_frames(3)
	_check(
		"panel offers the permanent fix while carrying the part (got '%s')" % _interactor.get_prompt(),
		"Fit a spare coupling" in _interactor.get_prompt()
	)
	_check("panel is actionable while carrying the part", _interactor.is_actionable())
	_press("interact")
	await _frames(4)
	_check("fitting the part repairs the system", not fault.is_active)
	_check("and permanently, not as a patch", not fault.is_patched)
	# One spare, one fix — the part must leave the world, or a single coupling could be
	# walked around the ship repairing everything.
	_check("the part is taken out of the player's hands", not _carry.is_holding())
	await _frames(4)
	_check("and is removed from the world", not is_instance_valid(part))

	if _failures.is_empty():
		print("INTERACTION TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("INTERACTION TEST FAIL")
		quit(1)
