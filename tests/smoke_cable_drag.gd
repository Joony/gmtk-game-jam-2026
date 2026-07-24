extends SceneTree
# Step 14d playtest fix: dragging a cable whose FAR end is loose.
# When you carry one plug and the other end is plugged into nothing, walking the cable to where you
# need it must TOW the loose end along without rubber-banding — but if the cable genuinely can't
# follow (the far end snagged on geometry, or out-walked past what the tow reels), it must RELEASE
# instead of stretching forever. Two guarantees, driven through the real Interactor -> Carry pickup
# path against the game scene:
#   * TAUT DRAG: steadily walking a followable light loose cable keeps it within the breakaway
#     distance (the free-end tow keeps up) and never drops it.
#   * SNAG RELEASE: when the far end can't follow (here, too heavy to reel in time — standing in for
#     a plug wedged against a door frame), sustained overstretch pops the held plug from your hand
#     (the breakaway release valve) rather than stretching without bound.
# Run: godot --headless --path . -s tests/smoke_cable_drag.gd

const GAME_SCENE := "res://scenes/game.tscn"
const PLUG_SCRIPT := "res://scripts/game/cable_plug.gd"
const REST := 2.5

var _failures: Array[String] = []
var _game: Node3D
var _cam: Camera3D
var _carry: Carry
var _interactor: Interactor
var _player: CharacterBody3D
var _holder: Node3D


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("cable drag test timed out")
		quit(1))
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


func _place_in_front(node: Node3D, distance: float) -> void:
	var forward := -_cam.global_transform.basis.z
	node.global_position = _cam.global_position + forward * distance


# A cable plug (RigidBody3D + CablePlug script + box collider), returned as Node3D — the body and the
# Interactable script sit on sibling branches, so the caller re-views it via Node3D casts.
func _make_plug(mass: float) -> Node3D:
	var plug := RigidBody3D.new()
	plug.set_script(load(PLUG_SCRIPT))
	plug.mass = mass
	plug.gravity_scale = 0.0  # hold height for a deterministic drag geometry
	plug.continuous_cd = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 0.2, 0.2)
	shape.shape = box
	plug.add_child(shape)
	_game.add_child(plug)
	return plug


# Pick up `plug` through the real ray + interact path and wait for it to reach the hold point.
func _grab(plug: Node3D) -> void:
	_place_in_front(plug, 1.2)
	await _physics_frames(3)
	_press("interact")
	await _frames(2)
	await _frames(40)


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
	_holder = _game.get_node("Player/CameraRig/Camera3D/HoldPoint")

	await _physics_frames(45)  # settle on the floor
	_player.global_position = Vector3(0.0, 0.9, -17.0)
	_player.reset_physics_interpolation()
	(_game.get_node("Player/CameraRig") as CameraController).set_look(0.0, 0.0)
	_player.add_to_group(&"cable_ignore")  # the cable must never shove the player
	await _physics_frames(20)

	# ================= SNAG RELEASE: a far end that can't follow pops the held plug =========
	# Near plug A (carried) <-> far plug B (heavy, loose). The heavy B stands in for a plug wedged
	# against a door frame: the tow can't reel it in fast enough, so the straight-line cable holds
	# past breakaway (REST * 1.2 = 3.0 m) — and the breakaway must then release the held plug rather
	# than let the cable stretch forever.
	var plug_a := _make_plug(1.0)
	var plug_b := _make_plug(50.0)
	var cable := Cable3D.new()
	cable.rest_length = REST
	cable.plug_a_path = plug_a.get_path()
	cable.plug_b_path = plug_b.get_path()
	_game.add_child(cable)
	await _physics_frames(5)

	var ca := plug_a as CablePlug
	_check("cable back-referenced both ends", ca.cable == cable and (plug_b as CablePlug).cable == cable)

	await _grab(plug_a)
	_check("carrying the near plug", _carry.is_holding() and _carry.held_item() == plug_a)

	# Park the free far end just ahead of the held one, then walk the player steadily BACKWARD away
	# from it (small per-tick steps — a teleport makes Carry auto-drop). Move on RENDER frames, where
	# Carry builds its carry velocity.
	var forward := -_cam.global_transform.basis.z
	plug_b.global_position = _cam.global_position + forward * 0.5
	(plug_b as RigidBody3D).linear_velocity = Vector3.ZERO
	await _physics_frames(2)
	var dropped_a := false
	for i in 150:
		_player.global_position -= forward * 0.08
		await process_frame
		if not _carry.is_holding():
			dropped_a = true
			break
	await _physics_frames(5)
	# The cable can't follow the far end, so walking on must release the held plug (the breakaway
	# valve) instead of stretching without bound. (Mutation-tests the removed gate — re-add it and
	# the held plug never drops, so this fails.)
	_check("a cable that can't follow releases the held plug rather than stretching forever",
		dropped_a and not _carry.is_holding())

	# Put the held plug down and clear the scene for the next phase.
	_press("interact")
	await _frames(2)
	cable.queue_free()
	plug_a.queue_free()
	plug_b.queue_free()
	await _physics_frames(5)

	# ================= TAUT DRAG: a light loose cable stays taut while walked =================
	_player.global_position = Vector3(0.0, 0.9, -17.0)
	_player.reset_physics_interpolation()
	(_game.get_node("Player/CameraRig") as CameraController).set_look(0.0, 0.0)
	await _physics_frames(10)

	var near := _make_plug(1.0)
	var far := _make_plug(1.0)  # a light loose end: the stiff tow should keep it up
	var cable2 := Cable3D.new()
	cable2.rest_length = REST
	cable2.plug_a_path = near.get_path()
	cable2.plug_b_path = far.get_path()
	_game.add_child(cable2)
	await _physics_frames(5)

	await _grab(near)
	_check("carrying the near plug (phase 2)", _carry.is_holding())
	forward = -_cam.global_transform.basis.z
	far.global_position = _cam.global_position + forward * 0.5
	await _physics_frames(10)

	# Walk the player steadily BACKWARD away from the far plug on PHYSICS frames — a deterministic
	# 60 Hz * 0.06 m = 3.6 m/s drag, independent of the (variable) headless render rate. That sits
	# ABOVE the default endpoint spring's terminal pursuit (~1.9 m/s, so a spring-only cable balloons
	# past the breakaway distance) and BELOW the reel cap (8 m/s), so ONLY the inextensible tow keeps
	# the far plug taut. Measured over the steady window (past the startup accelerate-from-rest
	# transient); a rubber-band cable would stretch well past the breakaway distance here.
	var steady_gap := 0.0
	var dropped := false
	for i in 120:
		_player.global_position -= forward * 0.06
		await physics_frame
		if not _carry.is_holding():
			dropped = true
			break
		if i >= 70:
			var gap := (near as Node3D).global_position.distance_to(far.global_position)
			steady_gap = maxf(steady_gap, gap)
	_check("walking a light loose cable never drops it", not dropped)
	_check("the towed far end keeps up while walking (steady gap %.2f m < %.2f)"
			% [steady_gap, REST * 1.3], steady_gap > 0.0 and steady_gap < REST * 1.3)

	if _failures.is_empty():
		print("CABLE DRAG TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("CABLE DRAG TEST FAIL")
		quit(1)
