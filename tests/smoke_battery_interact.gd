extends SceneTree
# Step 14d (playtest fix): plug a held cable into the battery with the standard look-and-press
# interaction (no more "Hands full"). The whole cube is the target.
#   * empty-handed, the battery reads as a PICKUP ("Pick up battery"),
#   * holding a plug, it reads as USE_ITEM ("Plug in cable") and pressing E seats the plug into the
#     port (and the cube charges, since the plug's cable runs to a wall source).
# Run: godot --headless --path . -s tests/smoke_battery_interact.gd

const GAME_SCENE := "res://scenes/game.tscn"
const BATTERY_SCENE := "res://scenes/props/battery_cube.tscn"
const PLUG_SCRIPT := "res://scripts/game/cable_plug.gd"

var _failures: Array[String] = []
var _game: Node3D
var _cam: Camera3D
var _carry: Carry
var _interactor: Interactor
var _player: CharacterBody3D


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("battery interact test timed out")
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
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	root.push_input(e)


func _place_in_front(node: Node3D, distance: float) -> void:
	var forward := -_cam.global_transform.basis.z
	node.global_position = _cam.global_position + forward * distance


func _make_plug() -> Node3D:
	var p := RigidBody3D.new()
	p.set_script(load(PLUG_SCRIPT))
	p.continuous_cd = true
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.3, 0.3, 0.3)
	cs.shape = b
	p.add_child(cs)
	_game.add_child(p)
	return p


func _run() -> void:
	_game = load(GAME_SCENE).instantiate()
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_game.start_game()

	_cam = _game.get_node("Player/CameraRig/Camera3D")
	_carry = _game.get_node("Player/Carry")
	_interactor = _game.get_node("Player/Interactor")
	_player = _game.get_node("Player")

	await _physics_frames(45)
	_player.global_position = Vector3(0.0, 0.9, -17.0)
	_player.reset_physics_interpolation()
	(_game.get_node("Player/CameraRig") as CameraController).set_look(0.0, 0.0)
	_player.add_to_group(&"cable_ignore")
	await _physics_frames(20)

	# A battery in front of the player.
	var battery: Node3D = load(BATTERY_SCENE).instantiate()
	_game.add_child(battery)
	var bport := battery.get_node("Port") as CableSocket
	var bat := battery as BatteryCube
	_place_in_front(battery, 1.6)
	battery.freeze = true  # hold it still for the test
	await _physics_frames(3)

	# --- Empty-handed: the cube is a pickup -----------------------------------------------
	_check("empty-handed, the battery is targeted", _interactor.current == battery)
	_check("empty-handed prompt offers pickup (got '%s')" % _interactor.get_prompt(),
		"Pick up battery" in _interactor.get_prompt())
	_check("empty-handed the battery is actionable", _interactor.is_actionable())

	# --- Build a wall-source cable and carry its free plug --------------------------------
	var source := CableSocket.new()
	source.is_power_source = true
	_game.add_child(source)
	source.global_position = Vector3(-4, 1, -17)
	var plug_src := _make_plug()
	var plug_free := _make_plug()
	var cable := Cable3D.new()
	cable.rest_length = 6.0
	cable.plug_a_path = plug_src.get_path()
	cable.plug_b_path = plug_free.get_path()
	_game.add_child(cable)
	await _physics_frames(3)
	# Seat the source end by hand; the player will carry the free end.
	source.seat(plug_src)
	cable.set_endpoint_socket(plug_src, source)
	await _physics_frames(2)

	# Grab the free plug.
	(plug_free as RigidBody3D).gravity_scale = 0.0
	(plug_free as RigidBody3D).linear_velocity = Vector3.ZERO
	_place_in_front(plug_free, 1.0)
	await _physics_frames(3)
	_press("interact")
	await _frames(2)
	_check("carrying the free plug", _carry.is_holding())
	await _frames(20)

	# --- Holding a plug: the cube reads as a plug target ----------------------------------
	_place_in_front(battery, 1.6)
	await _physics_frames(3)
	_check("holding a plug, the battery is still targeted", _interactor.current == battery)
	_check("holding a plug the prompt offers plugging in (got '%s')" % _interactor.get_prompt(),
		"Plug in cable" in _interactor.get_prompt())
	_check("holding a plug the battery is actionable (NOT 'Hands full')", _interactor.is_actionable())

	# --- Press E: the plug seats into the port --------------------------------------------
	_press("interact")
	await _frames(2)
	_check("pressing E plugs the cable into the battery", bport.occupied_by == plug_free)
	_check("plugging in released the plug from the hand", not _carry.is_holding())
	await _physics_frames(20)
	_check("the plugged-in cable charges the battery (charge=%.2f)" % bat.charge, bat.charge > 0.0)

	if _failures.is_empty():
		print("BATTERY INTERACT TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("BATTERY INTERACT TEST FAIL")
		quit(1)
