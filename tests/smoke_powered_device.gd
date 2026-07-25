extends SceneTree
# Step 14d (Phase 6): the AUX POWER device — a fault fixable ONLY by a power feed.
#   * it breaks like any malfunction and stays broken while unpowered (no patch/part route),
#   * feeding its inlet (a live cable) repairs it PERMANENTLY,
#   * unplugging afterwards does NOT re-break it (the feed did its job).
# The device is fed here the real way: a loose cable from a source socket into its inlet.
# Run: godot --headless --path . -s tests/smoke_powered_device.gd

const DEVICE := "res://scenes/props/powered_device.tscn"
const LOOSE_CABLE := "res://scenes/props/loose_cable.tscn"

var _failures: Array[String] = []
var _world: Node3D


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("powered device test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)

	var device: Node3D = load(DEVICE).instantiate()
	_world.add_child(device)
	var fault := device as Malfunction
	var inlet_port := device.get_node("Inlet/Port") as CableSocket

	var source := CableSocket.new()
	source.is_power_source = true
	_world.add_child(source)
	source.global_position = Vector3(3, 1, 0)

	var loose: Node3D = load(LOOSE_CABLE).instantiate()
	_world.add_child(loose)
	loose.global_position = Vector3(1, 1, 1)
	var cable := loose.get_node("Cable") as Cable3D
	var plug_a := (loose.get_node("PlugA") as Node) as CablePlug
	var plug_b := (loose.get_node("PlugB") as Node) as CablePlug
	await _physics_frames(4)

	_check("the device registered as a malfunction", fault.is_in_group(Malfunction.GROUP_MALFUNCTION))
	_check("the device has no repair panel (power-only)", _repair_point(fault) == null)
	_check("it starts nominal", not fault.is_active)

	# --- Break it: stays broken while unpowered -------------------------------------------
	fault.break_now()
	await _physics_frames(2)
	_check("break_now activates the fault", fault.is_active)
	# Seat only the inlet end — the cable is dead (no source), so this must NOT fix it.
	plug_b.plug_into(inlet_port)
	await _physics_frames(3)
	_check("the inlet plug alone does not power the fault", not inlet_port.powered)
	_check("an unpowered inlet leaves the fault broken", fault.is_active)

	# --- Feed it from the source: permanent repair ---------------------------------------
	plug_a.plug_into(source)
	await _physics_frames(3)
	_check("the cable carries power from the source", cable.powered)
	_check("the inlet is now live", inlet_port.powered)
	_check("powering the inlet repairs the fault", not fault.is_active)
	_check("the power fix is PERMANENT, not a patch", not fault.is_patched)

	# --- Unplug: it stays fixed ----------------------------------------------------------
	plug_a.force_unseat(Vector3.ZERO)
	await _physics_frames(3)
	_check("unplugging the source kills the inlet power", not inlet_port.powered)
	_check("but the device stays repaired", not fault.is_active)

	if _failures.is_empty():
		print("POWERED DEVICE TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("POWERED DEVICE TEST FAIL")
		quit(1)


func _repair_point(fault: Malfunction) -> RepairPoint:
	for child in fault.get_children():
		if child is RepairPoint:
			return child
	return null
