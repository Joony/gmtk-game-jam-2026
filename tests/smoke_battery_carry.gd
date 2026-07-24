extends SceneTree
# Step 14d (playtest fix): a plug seated in a CARRIED battery must not lag behind it.
# Carry authors the battery every render frame; the seated plug now follows its port every render
# frame too (interpolation off, priority after Carry). To make any lag visible headlessly the
# physics rate is dropped low, so many render frames pass between physics ticks — a plug that only
# followed in _physics_process would fall metres behind while the battery moves; the render-rate
# follow keeps it glued.
# Run: godot --headless --path . -s tests/smoke_battery_carry.gd

const GAME_SCENE := "res://scenes/game.tscn"
const BATTERY_SCENE := "res://scenes/props/battery_cube.tscn"
const PLUG_SCRIPT := "res://scripts/game/cable_plug.gd"

var _failures: Array[String] = []
var _game: Node3D
var _cam: Camera3D
var _carry: Carry
var _player: CharacterBody3D


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("battery carry test timed out")
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


func _run() -> void:
	_game = load(GAME_SCENE).instantiate()
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_game.start_game()

	_cam = _game.get_node("Player/CameraRig/Camera3D")
	_carry = _game.get_node("Player/Carry")
	_player = _game.get_node("Player")

	await _physics_frames(30)
	_player.global_position = Vector3(0.0, 0.9, -17.0)
	_player.reset_physics_interpolation()
	(_game.get_node("Player/CameraRig") as CameraController).set_look(0.0, 0.0)
	await _physics_frames(10)

	# Carry the battery.
	var battery: Node3D = load(BATTERY_SCENE).instantiate()
	_game.add_child(battery)
	var bport := battery.get_node("Port") as CableSocket
	_place_in_front(battery, 1.2)
	await _physics_frames(3)
	_press("interact")
	await _frames(2)
	_check("carrying the battery", _carry.is_holding())
	await _frames(20)  # let it reach the hold point

	# Seat a standalone plug into the carried battery's port.
	var plug := RigidBody3D.new()
	plug.set_script(load(PLUG_SCRIPT))
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.3, 0.3, 0.3)
	cs.shape = b
	plug.add_child(cs)
	_game.add_child(plug)
	await _physics_frames(2)
	var cplug := (plug as Node) as CablePlug
	_check("the plug seated into the carried battery's port", cplug.plug_into(bport))
	await _frames(4)

	# Now drop the physics rate right down and swing the battery around by moving/looking. A plug
	# that only followed in _physics_process would drift far behind between ticks.
	Engine.physics_ticks_per_second = 5
	var rig := _game.get_node("Player/CameraRig") as CameraController
	var worst := 0.0
	for i in 40:
		_player.global_position += Vector3(0.06, 0.0, 0.0)
		rig.set_look(float(i) * 0.05, 0.0)  # look around as we go
		await process_frame
		worst = maxf(worst, (plug as Node3D).global_position.distance_to(bport.global_position))
	Engine.physics_ticks_per_second = 60

	_check("a plug in a carried battery stays glued to its port (worst %.3f m)" % worst, worst < 0.05)

	if _failures.is_empty():
		print("BATTERY CARRY TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("BATTERY CARRY TEST FAIL")
		quit(1)
