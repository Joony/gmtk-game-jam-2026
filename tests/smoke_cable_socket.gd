extends SceneTree
# Step 14d (Phase 2): CableSocket in isolation.
# The socket came over from Doortal unchanged — it is pure bookkeeping plus a runtime-built
# receptacle visual, and duck-types its plug as a bare Node3D so the addon stays
# game-independent. This proves that whole surface without a real CablePlug yet:
#   * a source socket is powered synchronously at ready AND announces power_changed(true) deferred,
#   * an external feed (set_fed) drives power + the signal; a source ignores an unfeed,
#   * seat/unseat bookkeeping + the plugged/unplugged signals + can_accept occupancy,
#   * the snap preview highlight toggles,
#   * mount_body finds the socket's owning physics body (the moving-mount case) or null,
#   * snap_transform is the socket's own global transform.
# Run: godot --headless --path . -s tests/smoke_cable_socket.gd

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	# --- Source: powered now, announced deferred ------------------------------
	var source := CableSocket.new()
	source.is_power_source = true
	root.add_child(source)  # _ready runs synchronously, queues the deferred announce
	# powered is set synchronously in _ready...
	_check("a source socket is powered synchronously at ready", source.powered)
	# ...and the initial announce is DEFERRED so listeners that connect in their own _ready
	# (possibly later in tree order) still receive it. Connect now, then let it flush.
	var announces := {"count": 0, "last": false}
	source.power_changed.connect(func(p: bool) -> void:
		announces["count"] += 1
		announces["last"] = p)
	await process_frame
	_check("a source announces power_changed(true) deferred at ready",
		announces["count"] == 1 and announces["last"] == true)
	# A source ignores an external unfeed — it is always powered.
	source.set_fed(false)
	_check("a source ignores set_fed(false)", source.powered)
	_check("ignored unfeed emits no signal", announces["count"] == 1)

	# --- Sink: external feed drives power + signal ----------------------------
	var sink := CableSocket.new()
	root.add_child(sink)
	await process_frame
	_check("a bare sink starts unpowered", not sink.powered)
	_check("default snap_radius is 0.35", is_equal_approx(sink.snap_radius, 0.35))

	var feeds := {"count": 0, "last": false}
	sink.power_changed.connect(func(p: bool) -> void:
		feeds["count"] += 1
		feeds["last"] = p)
	sink.set_fed(true)
	_check("set_fed(true) powers the sink", sink.powered)
	_check("set_fed(true) emits power_changed(true)", feeds["count"] == 1 and feeds["last"] == true)
	sink.set_fed(true)  # idempotent
	_check("a redundant feed emits nothing", feeds["count"] == 1)
	sink.set_fed(false)
	_check("set_fed(false) unpowers the sink", not sink.powered)
	_check("set_fed(false) emits power_changed(false)", feeds["count"] == 2 and feeds["last"] == false)

	# --- Seat / unseat bookkeeping + occupancy --------------------------------
	# The socket duck-types its plug: a bare Node3D is enough (seat/unseat touch nothing on it).
	var plug := Node3D.new()
	root.add_child(plug)
	var seated := {"count": 0}
	var released := {"count": 0}
	sink.plugged.connect(func(_p: Node3D) -> void: seated["count"] += 1)
	sink.unplugged.connect(func(_p: Node3D) -> void: released["count"] += 1)

	_check("a free socket can accept a plug", sink.can_accept(plug))
	_check("a free socket has no occupant", sink.occupied_by == null)
	var other_plug := Node3D.new()
	root.add_child(other_plug)
	sink.seat(plug)
	_check("seat records the occupant", sink.occupied_by == plug)
	_check("seat emits plugged", seated["count"] == 1)
	_check("an occupied socket refuses another plug", not sink.can_accept(other_plug))
	sink.unseat()
	_check("unseat clears the occupant", sink.occupied_by == null)
	_check("unseat emits unplugged", released["count"] == 1)
	sink.unseat()  # idempotent when already free
	_check("unseat on a free socket does nothing", released["count"] == 1)

	# --- Snap preview highlight ----------------------------------------------
	var preview := sink.get_node_or_null("SnapPreview") as MeshInstance3D
	_check("the runtime receptacle built a SnapPreview", preview != null)
	if preview != null:
		_check("the preview starts hidden", not preview.visible)
		sink.set_preview(true)
		_check("set_preview(true) shows the highlight", preview.visible)
		sink.set_preview(false)
		_check("set_preview(false) hides it", not preview.visible)

	# --- mount_body: static vs moving mount -----------------------------------
	# A socket parented straight under the viewport has no physics body above it.
	_check("a free-standing socket has no mount body", sink.mount_body() == null)
	# A socket on a RigidBody3D (a battery cube face, later) reports that body — a taut cable
	# then drags the mount around by its socket.
	var cube := RigidBody3D.new()
	root.add_child(cube)
	var mounted := CableSocket.new()
	cube.add_child(mounted)
	await process_frame
	_check("a mounted socket reports its owning body", mounted.mount_body() == cube)

	# --- snap_transform is the socket's own global transform ------------------
	sink.global_position = Vector3(1, 2, 3)
	_check("snap_transform is the socket's global transform",
		sink.snap_transform().origin.is_equal_approx(Vector3(1, 2, 3)))

	if _failures.is_empty():
		print("CABLE SOCKET TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("CABLE SOCKET TEST FAIL")
		quit(1)
