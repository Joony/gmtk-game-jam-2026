extends SceneTree
# Step 14d: the seated-plug FLOOR GUARD.
# A plug seated in a socket is a frozen KINEMATIC body — it ghosts through the static floor. When a
# pulled cable tips a plugged BATTERY onto its plug face, the plug would rotate under the floor into
# the void. The fix: while seated in a DYNAMIC mount, the plug clones its own collider onto the
# mount where it protrudes, so the mount's real dynamic collision props the cube off the floor there
# before the plug can go under. This test proves that mechanism without needing the tip to occur:
#   * seating into a dynamic mount adds a "PlugGuard" collider on the mount, at the plug's spot,
#     with the plug's own shape,
#   * unseating removes it,
#   * seating into a STATIC mount adds NO guard (a wall can't tip and must not sprout a shape that
#     would block the player).
# Run: godot --headless --path . -s tests/smoke_plug_guard.gd

const PLUG_SCRIPT := "res://scripts/game/cable_plug.gd"
const SOCKET_SCRIPT := "res://addons/cables/scripts/cable_socket.gd"

var _failures: Array[String] = []


func _init() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("plug guard test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


# A plug: a RigidBody3D wearing the CablePlug script, with a box collider matching the real plug
# (0.42 x 0.18 x 0.42). Returned as Node3D — the RigidBody3D node and the CablePlug (Interactable)
# script sit on sibling branches, so the caller re-views it via Node3D casts.
func _make_plug() -> Node3D:
	var plug := RigidBody3D.new()
	plug.set_script(load(PLUG_SCRIPT))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.42, 0.18, 0.42)
	shape.shape = box
	plug.add_child(shape)
	return plug


# A socket on a fresh mount body of the given type, placed on the mount's +Z face at local z=0.2
# (like the battery port). The mount sits at the origin.
func _make_mount_with_socket(mount: PhysicsBody3D) -> CableSocket:
	root.add_child(mount)
	mount.global_position = Vector3.ZERO
	var socket := CableSocket.new()
	socket.set_script(load(SOCKET_SCRIPT))
	mount.add_child(socket)
	socket.position = Vector3(0.0, 0.0, 0.2)
	return socket


func _guard_of(mount: Node) -> CollisionShape3D:
	return mount.get_node_or_null("PlugGuard") as CollisionShape3D


func _run() -> void:
	# --- Dynamic mount: seating installs a guard where the plug protrudes -------------------
	var cube := RigidBody3D.new()
	cube.freeze = true  # keep it put; the guard install path doesn't care that it's frozen
	var port := _make_mount_with_socket(cube)
	var plug := _make_plug()
	root.add_child(plug)
	await _frames(2)  # let _ready run on both

	var cplug := plug as CablePlug
	_check("plug seated into the dynamic mount", cplug.plug_into(port))

	var guard := _guard_of(cube)
	_check("seating a dynamic mount installs a PlugGuard collider", guard != null)
	if guard != null:
		var gbox := guard.shape as BoxShape3D
		_check("the guard wears the plug's own box shape",
			gbox != null and gbox.size.is_equal_approx(Vector3(0.42, 0.18, 0.42)))
		# The seated plug sits out along the socket's +Z by SEAT_STANDOFF (0.18) and down by
		# SEAT_MODEL_Y (0.08): socket at z=0.2 -> guard at ~(0, -0.08, 0.38) in the mount frame.
		_check("the guard sits where the plug protrudes (pos=%s)" % str(guard.position),
			guard.position.is_equal_approx(Vector3(0.0, -0.08, 0.38)))

	# --- Unseating removes the guard --------------------------------------------------------
	cplug.force_unseat(Vector3.ZERO)
	await _frames(2)  # queue_free settles
	_check("unseating removes the PlugGuard", _guard_of(cube) == null)

	# --- Static mount: NO guard (a wall can't tip and must not sprout a room-blocking shape) -
	var wall := StaticBody3D.new()
	var wall_port := _make_mount_with_socket(wall)
	var plug2 := _make_plug()
	root.add_child(plug2)
	await _frames(2)

	var cplug2 := plug2 as CablePlug
	_check("plug seated into the static mount", cplug2.plug_into(wall_port))
	_check("seating a static mount installs NO guard", _guard_of(wall) == null)

	if _failures.is_empty():
		print("PLUG GUARD TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("PLUG GUARD TEST FAIL")
		quit(1)
