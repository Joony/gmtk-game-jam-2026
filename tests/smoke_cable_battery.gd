extends SceneTree
# Step 14d (Phase 5): the battery cube.
# Wires real cables into the cube's port and checks the charge model end to end:
#   * plugged into a live wall SOURCE, the cube charges and its port becomes a source,
#   * plugged into a SINK, a charged cube powers it and drains,
#   * at empty the port stops sourcing and the sink loses power,
#   * with nothing plugged, charge holds.
# Run: godot --headless --path . -s tests/smoke_cable_battery.gd

const BATTERY_SCENE := "res://scenes/props/battery_cube.tscn"
const PLUG_SCRIPT := "res://scripts/game/cable_plug.gd"

var _failures: Array[String] = []
var _world: Node3D


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("battery test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _make_plug() -> Node3D:
	var p := RigidBody3D.new()
	p.set_script(load(PLUG_SCRIPT))
	p.freeze = true  # keep it still; we only care about the power wiring here
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.1, 0.1, 0.1)
	cs.shape = b
	p.add_child(cs)
	_world.add_child(p)
	return p


func _make_cable(a: Node3D, b: Node3D, rest: float) -> Cable3D:
	var c := Cable3D.new()
	c.rest_length = rest
	c.plug_a_path = a.get_path()
	c.plug_b_path = b.get_path()
	_world.add_child(c)
	return c


# Seat a plug into a socket by hand (the full carry-driven seat is covered by smoke_cable_plug;
# here we only need the power bookkeeping the battery reads).
func _seat(plug: Node3D, socket: CableSocket, cable: Cable3D) -> void:
	socket.seat(plug)
	cable.set_endpoint_socket(plug, socket)


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)

	var battery: Node3D = load(BATTERY_SCENE).instantiate()
	_world.add_child(battery)
	battery.global_position = Vector3(2, 1, 0)
	var bat := battery as BatteryCube
	var bport := battery.get_node("Port") as CableSocket
	await _physics_frames(3)

	_check("battery starts empty", bat.charge == 0.0)
	_check("an empty battery port is not a source", not bport.is_power_source)

	# --- Charge from a live wall source ---------------------------------------------------
	var wall := CableSocket.new()
	wall.is_power_source = true
	_world.add_child(wall)
	wall.global_position = Vector3(0, 1, 0)
	var plug_w := _make_plug()
	var plug_b := _make_plug()
	var cable1 := _make_cable(plug_w, plug_b, 3.0)
	await _physics_frames(3)  # cable resolves its anchors + back-refs the plugs

	_seat(plug_w, wall, cable1)
	_seat(plug_b, bport, cable1)
	await _physics_frames(2)
	_check("the wall cable is powered", cable1.powered)

	var c0 := bat.charge
	await _physics_frames(30)
	_check("battery charges from a live source (%.2f -> %.2f)" % [c0, bat.charge], bat.charge > c0)
	_check("a charging battery's port becomes a source", bport.is_power_source)

	# --- Idle: holds charge when nothing is plugged ---------------------------------------
	bport.unseat()
	cable1.set_endpoint_socket(plug_b, null)
	await _physics_frames(2)
	var held := bat.charge
	await _physics_frames(20)
	_check("an unplugged battery holds its charge", is_equal_approx(bat.charge, held))

	# --- Drain into a sink -----------------------------------------------------------------
	bat.charge = 2.0
	await _physics_frames(2)  # _refresh_source makes the port a source again
	_check("a charged battery's port is a source", bport.is_power_source)

	var sink := CableSocket.new()  # NOT a source — a device inlet
	_world.add_child(sink)
	sink.global_position = Vector3(4, 1, 0)
	var plug_c := _make_plug()
	var plug_d := _make_plug()
	var cable2 := _make_cable(plug_c, plug_d, 3.0)
	await _physics_frames(3)

	_seat(plug_c, bport, cable2)
	_seat(plug_d, sink, cable2)
	await _physics_frames(3)
	_check("a charged battery powers the sink", sink.powered)

	var d0 := bat.charge
	await _physics_frames(6)
	_check("powering a sink drains the battery (%.2f -> %.2f)" % [d0, bat.charge], bat.charge < d0)

	await _physics_frames(40)  # run it flat (2.0 charge / 4.0 per sec ~= 0.5 s)
	_check("battery drains to empty under load", bat.charge == 0.0)
	_check("an empty battery stops sourcing", not bport.is_power_source)
	_check("an empty battery cuts power to the sink", not sink.powered)

	# --- Charge bars track the fraction ---------------------------------------------------
	_check("charge_fraction reads empty at zero", bat.charge_fraction() == 0.0)
	# charge_fraction is a pure read; set and check without a tick so the still-plugged sink
	# doesn't drain it between the two lines.
	bat.charge = bat.capacity
	_check("charge_fraction reads full at capacity", is_equal_approx(bat.charge_fraction(), 1.0))

	if _failures.is_empty():
		print("BATTERY TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("BATTERY TEST FAIL")
		quit(1)
