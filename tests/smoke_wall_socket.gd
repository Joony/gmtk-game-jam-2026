extends SceneTree
# Step 14d (pre-Phase 6): wall sockets + a loose cable.
#   * a WallSocket presents USE_ITEM ("Plug in cable") only while you hold a plug, and DISABLED
#     empty-handed,
#   * using a plug on it seats the plug into its port,
#   * a source wall socket is live; running a loose cable from it to a sink socket powers the cable
#     and feeds the sink.
# Run: godot --headless --path . -s tests/smoke_wall_socket.gd

const WALL_SOCKET := "res://scenes/props/wall_socket.tscn"
const LOOSE_CABLE := "res://scenes/props/loose_cable.tscn"

var _failures: Array[String] = []
var _world: Node3D


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("wall socket test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _make_wall_socket(pos: Vector3, source: bool) -> Node3D:
	var ws: Node3D = load(WALL_SOCKET).instantiate()
	ws.set("is_power_source", source)  # before _ready
	_world.add_child(ws)
	ws.global_position = pos
	return ws


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)

	var source_ws := _make_wall_socket(Vector3(0, 1, 0), true)
	var sink_ws := _make_wall_socket(Vector3(2, 1, 0), false)
	var loose: Node3D = load(LOOSE_CABLE).instantiate()
	_world.add_child(loose)
	loose.global_position = Vector3(1, 1, 1)
	await _physics_frames(4)

	var source_port := source_ws.get_node("Port") as CableSocket
	var sink_port := sink_ws.get_node("Port") as CableSocket
	var plug_a := loose.get_node("PlugA") as Node3D
	var plug_b := loose.get_node("PlugB") as Node3D
	var cable := loose.get_node("Cable") as Cable3D

	_check("a source wall socket is a live source", source_port.is_power_source and source_port.powered)
	_check("a sink wall socket starts dead", not sink_port.is_power_source and not sink_port.powered)
	_check("the loose cable back-referenced its plugs", (plug_a as Node as CablePlug).cable == cable)

	# --- WallSocket interaction surface --------------------------------------------------
	var sw := source_ws as WallSocket
	_check("empty-handed the wall socket is DISABLED", sw.get_interaction_type(null) == Interactable.InteractionType.DISABLED)
	_check("empty-handed it is not actionable", not sw.can_act_on(null))
	_check("holding a plug it becomes USE_ITEM", sw.get_interaction_type(plug_a) == Interactable.InteractionType.USE_ITEM)
	_check("holding a plug it is actionable", sw.can_act_on(plug_a))
	_check("holding a plug it prompts to plug in (got '%s')" % sw.get_interaction_text(plug_a),
		"Plug in" in sw.get_interaction_text(plug_a))

	# --- Use a plug on it: seats into the port -------------------------------------------
	sw.use_with_item(plug_a)
	await _physics_frames(2)
	_check("using a plug on the source seats it", source_port.occupied_by == plug_a)
	_check("the cable now records the source socket", cable.socket_a == source_port)
	_check("an occupied wall socket refuses another plug", not sw.can_act_on(plug_b))
	_check("an occupied wall socket says so (got '%s')" % sw.get_interaction_text(plug_b),
		"in use" in sw.get_interaction_text(plug_b))

	# --- Run the other end to the sink: power flows --------------------------------------
	(sink_ws as WallSocket).use_with_item(plug_b)
	await _physics_frames(3)
	_check("the other end seats into the sink", sink_port.occupied_by == plug_b)
	_check("a source-to-sink loose cable is powered", cable.powered)
	_check("the sink socket is fed through the cable", sink_port.powered)

	# --- Unplug the source end: power dies ----------------------------------------------
	(plug_a as Node as CablePlug).force_unseat(Vector3.ZERO)
	await _physics_frames(2)
	_check("unplugging the source kills cable power", not cable.powered)
	_check("unplugging the source kills the sink", not sink_port.powered)

	if _failures.is_empty():
		print("WALL SOCKET TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("WALL SOCKET TEST FAIL")
		quit(1)
