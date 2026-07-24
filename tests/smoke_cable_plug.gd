extends SceneTree
# Step 14d (Phase 3): CablePlug rebased onto Interactable + Carry.
# Drives the REAL input path (Interactor -> Carry) against the shipping game scene, so this
# covers the actual pick-up / seat / re-grab / breakaway loop the game will use:
#   * the plug is a RigidBody3D Interactable — the ray finds it and Carry picks it up,
#   * a held plug near a socket lights the socket's snap preview,
#   * releasing in snap range SEATS the plug (not a floor drop); a source socket then powers the
#     cable, and the seated body is frozen and tracks the socket,
#   * re-grabbing a seated plug unseats it and kills the power,
#   * a seated plug follows a moving socket (the moving-mount path),
#   * sustained overstretch pops the seated plug loose (the cable's breakaway -> force_unseat).
# Run: godot --headless --path . -s tests/smoke_cable_plug.gd

const GAME_SCENE := "res://scenes/game.tscn"
const PLUG_SCRIPT := "res://scripts/game/cable_plug.gd"

var _failures: Array[String] = []
var _game: Node3D
var _cam: Camera3D
var _carry: Carry
var _interactor: Interactor
var _player: CharacterBody3D
var _holder: Node3D


func _init() -> void:
	# Failsafe: a silent runtime error inside an await chain stops the coroutine without ever
	# reaching quit(), leaving the tree running forever. Cap the whole run.
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("cable plug test timed out")
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


# Returns the plug typed as Node3D — the node is a RigidBody3D wearing the CablePlug script, and
# those two types sit on different branches from Node3D, so no single static type sees both. The
# caller re-views it as `RigidBody3D` (body ops) and `CablePlug` (plug API) via Node3D casts, the
# same shape smoke_interaction.gd uses for the crate.
func _make_plug() -> Node3D:
	var plug := RigidBody3D.new()
	plug.set_script(load(PLUG_SCRIPT))
	plug.continuous_cd = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 0.2, 0.2)
	shape.shape = box
	plug.add_child(shape)
	_game.add_child(plug)
	return plug


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
	# Open floor, level view (see smoke_interaction.gd's note about the cryo ring).
	_player.global_position = Vector3(0.0, 0.9, -17.0)
	_player.reset_physics_interpolation()
	(_game.get_node("Player/CameraRig") as CameraController).set_look(0.0, 0.0)
	# The cable must never collide with / shove the player. Doortal put the player in the
	# cable's exclude group; do the same here BEFORE the cable resolves its exclusions.
	_player.add_to_group(&"cable_ignore")
	await _physics_frames(20)

	# --- Build a cable: plug (free end) <-> static anchor, plus a source socket -------------
	var plug := _make_plug()
	var anchor := Node3D.new()
	_game.add_child(anchor)
	var forward := -_cam.global_transform.basis.z
	anchor.global_position = _cam.global_position + forward * 1.5 + Vector3(0, -0.5, 0)

	var cable := Cable3D.new()
	cable.rest_length = 2.5
	cable.plug_a_path = plug.get_path()
	cable.anchor_b_path = anchor.get_path()
	_game.add_child(cable)

	var socket := CableSocket.new()
	socket.is_power_source = true
	_game.add_child(socket)
	socket.global_position = Vector3(0, -50, 0)  # parked out of the way until needed
	await _physics_frames(5)

	var body := plug as RigidBody3D
	var cplug := plug as CablePlug
	_check("plug is an Interactable", plug is Interactable)
	_check("plug is a PICKUP", cplug.interaction_type == Interactable.InteractionType.PICKUP)
	_check("cable back-referenced itself into the plug", cplug.cable == cable)
	_check("a fresh plug is neither held nor seated", not cplug.is_held() and not cplug.is_seated())

	# --- Pick the plug up through the real input path --------------------------------------
	body.gravity_scale = 0.0
	body.linear_velocity = Vector3.ZERO
	_place_in_front(plug, 1.2)
	await _physics_frames(3)
	_check("ray finds the plug", _interactor.current == plug)
	_press("interact")
	await _frames(2)
	_check("interact picks the plug up", _carry.is_holding() and _carry.held_item() == plug)
	_check("plug reports held", cplug.is_held())
	await _frames(40)  # fly to the hold point

	# --- Held near a socket: the preview lights --------------------------------------------
	var preview := socket.get_node_or_null("SnapPreview") as MeshInstance3D
	_check("socket built a SnapPreview", preview != null)
	socket.global_position = _holder.global_position  # the held plug sits here
	await _frames(4)  # the snap scan runs on render frames
	_check("held plug in snap range lights the socket preview", preview != null and preview.visible)

	# --- Release in snap range: SEAT, not drop ---------------------------------------------
	_press("interact")
	await _frames(2)
	_check("releasing in range seats the plug", cplug.is_seated())
	_check("the socket is occupied by the plug", socket.occupied_by == plug)
	_check("Carry let go", not _carry.is_holding())
	_check("the cable records the seated socket", cable.socket_a == socket)
	_check("seating cleared the snap preview", preview != null and not preview.visible)
	_check("the seated body is frozen", body.freeze)
	await _physics_frames(2)
	_check("seating into a source powers the cable", cable.powered)

	# --- Seated plug follows a moving socket -----------------------------------------------
	socket.global_position = _cam.global_position + forward * 1.0
	await _physics_frames(6)
	_check("the seated plug follows the moved socket",
		plug.global_position.distance_to(socket.global_position) < 0.3)

	# --- Re-grab a seated plug: it unseats and power dies ----------------------------------
	_check("the seated plug is targetable again", _interactor.current == plug)
	_press("interact")
	await _frames(2)
	_check("re-grab picks the plug back up", _carry.is_holding())
	_check("re-grab unseats it", not cplug.is_seated())
	_check("the socket is freed", socket.occupied_by == null)
	_check("the cable end is cleared", cable.socket_a == null)
	await _physics_frames(2)
	_check("unplugging the source kills cable power", not cable.powered)

	# --- Breakaway: sustained overstretch pops the seated end ------------------------------
	await _frames(30)  # let the re-grabbed plug reach the hold point
	socket.global_position = _holder.global_position
	await _frames(5)
	_press("interact")  # release -> seat again
	await _frames(2)
	_check("re-seated for the breakaway test", cplug.is_seated())
	# Yank the far anchor well past the breakaway ratio (rest 2.5 x 1.6 = 4 m) and hold it.
	anchor.global_position = socket.global_position + forward * 8.0
	await _physics_frames(50)  # warm-up (10) + breakaway hold (~15) + margin
	_check("sustained overstretch pops the seated plug loose", not cplug.is_seated())
	_check("breakaway freed the socket", socket.occupied_by == null)
	_check("breakaway cleared the cable end", cable.socket_a == null)

	if _failures.is_empty():
		print("CABLE PLUG TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("CABLE PLUG TEST FAIL")
		quit(1)
