extends SceneTree
# Step 14d (Phase 1): the verlet cable sim after the portal strip.
# Proves the ported Cable3D compiles and its portal-free core behaves:
#   * a slack rope settles into a stable drape with no NaNs and no stretched segments,
#   * pulling the endpoints past rest_length raises `overstretched` and grows the polyline,
#   * the render tube is actually skinned,
#   * event-driven power (set_endpoint_socket) feeds a sink and unplugging kills it.
# No portals, no plugs, no Carry here — endpoints are plain Node3D anchors so the sim is
# tested in isolation.
# Run: godot --headless --path . -s tests/smoke_cable_sim.gd

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _make_anchor(pos: Vector3) -> Node3D:
	var a := Node3D.new()
	root.add_child(a)
	a.global_position = pos
	return a


func _make_cable(a: Node3D, b: Node3D, rest: float) -> Cable3D:
	var c := Cable3D.new()
	c.rest_length = rest
	c.anchor_a_path = a.get_path()
	c.anchor_b_path = b.get_path()
	root.add_child(c)
	return c


# NaN-free finite check across the whole point buffer.
func _all_finite(c: Cable3D) -> bool:
	for p in c.points:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return false
	return true


# The longest segment relative to the rope's effective rest spacing.
func _max_segment_ratio(c: Cable3D) -> float:
	var eff: float = c._eff_segment
	var worst := 0.0
	for i in c.points.size() - 1:
		var d: float = c.points[i].distance_to(c.points[i + 1])
		worst = maxf(worst, d / eff)
	return worst


func _tube_surface_count(c: Cable3D) -> int:
	var tube := c.get_node_or_null("TubeMesh") as MeshInstance3D
	if tube == null:
		return -1
	return (tube.mesh as ImmediateMesh).get_surface_count()


func _run() -> void:
	# --- Slack drape: settles, no NaNs, no overstretch, tube built ------------
	var a := _make_anchor(Vector3(-1, 3, 0))
	var b := _make_anchor(Vector3(1, 3, 0))  # 2 m apart, rope is 4 m: slack
	var cable := _make_cable(a, b, 4.0)
	await _physics_frames(150)

	_check("slack rope has no NaN/inf points", _all_finite(cable))
	_check("slack rope keeps >= MIN_POINTS points", cable.points.size() >= Cable3D.MIN_POINTS)
	# Stretch-only constraints: a settled slack rope never holds a segment meaningfully
	# past its rest spacing (a small solver-residue band is expected).
	var ratio := _max_segment_ratio(cable)
	_check("slack rope has no stretched segment (worst %.3fx rest)" % ratio, ratio < 1.1)
	# Gravity must actually drape it: some interior point hangs clearly below the anchors.
	var lowest := INF
	for p in cable.points:
		lowest = minf(lowest, p.y)
	_check("slack rope drapes below the anchors (lowest y=%.2f)" % lowest, lowest < 3.0 - 0.5)
	_check("slack rope is not flagged overstretched", not cable.overstretched)
	_check("render tube is skinned (surfaces=%d)" % _tube_surface_count(cable), _tube_surface_count(cable) > 0)

	# Settled means SETTLED — two more seconds must not move the lowest point much.
	var lowest_before := lowest
	await _physics_frames(120)
	lowest = INF
	for p in cable.points:
		lowest = minf(lowest, p.y)
	_check("settled rope stays put (drift %.4f m)" % absf(lowest - lowest_before), absf(lowest - lowest_before) < 0.05)

	# --- Overstretch: pull the endpoints past rest_length ---------------------
	b.global_position = Vector3(6, 3, 0)  # -1..6 = 7 m apart, rope is 4 m
	await _physics_frames(90)
	_check("pulled-apart rope has no NaN/inf points", _all_finite(cable))
	_check("pulled past rest_length raises overstretched", cable.overstretched)
	var length: float = cable._polyline_length()
	_check("stretched polyline exceeds rest_length (%.2f m > 4 m)" % length, length > 4.0)

	# --- Power: event-driven feed through the sockets -------------------------
	var source := CableSocket.new()
	source.is_power_source = true
	root.add_child(source)
	var sink := CableSocket.new()
	root.add_child(sink)
	await _physics_frames(2)

	_check("a source socket reports itself powered", source.powered)
	_check("a bare sink socket starts unpowered", not sink.powered)

	# Seat end A into the source and end B into the sink (as a plug would).
	cable.set_endpoint_socket(a, source)
	cable.set_endpoint_socket(b, sink)
	await _physics_frames(2)
	_check("cable carries power with a source seated", cable.powered)
	_check("the sink socket is fed through the cable", sink.powered)

	# Unplug the source end: power dies at the cable and the sink.
	cable.set_endpoint_socket(a, null)
	await _physics_frames(2)
	_check("unplugging the source kills cable power", not cable.powered)
	_check("unplugging the source kills the sink", not sink.powered)

	if _failures.is_empty():
		print("CABLE SIM TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("CABLE SIM TEST FAIL")
		quit(1)
