extends SceneTree
# TODO 21a, the presentation half. Deliberately short — it covers only the two things that fail
# SILENTLY, because those are the ones worth spending time on in a jam:
#
#   * an adopted model that never had setup() run is an ordinary node that simply never offers
#     a prompt, and nothing anywhere complains
#   * an indicator sized in a prop's LOCAL units comes out a quarter-size on a prop dressed at
#     0.25 — it still lights up, so it looks like it works
#
# Colours and flashing are not tested: they are visible the moment you look at the thing.
#
# Run: godot --headless --path . -s tests/smoke_indicator.gd

var _failures: Array[String] = []


func _init() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("indicator test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	await process_frame

	# A stand-in for an imported model: dressed at 0.25 like the silos, carrying the
	# `Indicator` empty the art now ships.
	var prop := Node3D.new()
	world.add_child(prop)
	prop.scale = Vector3.ONE * 0.25
	var empty := Node3D.new()
	empty.name = "Indicator"
	empty.position = Vector3(0.0, 4.0, 1.0)
	prop.add_child(empty)

	# --- the model becomes the repair point ----------------------------------
	var fault := Malfunction.new()
	fault.system_name = "NAV COMPUTER"
	fault.severity = Malfunction.Severity.CRITICAL
	world.add_child(fault)

	prop.set_script(load("res://scripts/game/repair_point.gd"))
	var point := prop as RepairPoint
	point.setup()
	point.bind(fault)
	point.refresh()

	_check("an adopted model joins the interactables", point.is_in_group(&"interactables"))
	_check("as a USE_ITEM target, so the hammer/part dispatch works",
		point.interaction_type == Interactable.InteractionType.USE_ITEM)
	_check("a healthy system is not a ray target", not point.is_enabled)
	fault.break_now()
	point.refresh()
	_check("breaking it makes the model the thing you walk up to", point.is_enabled)
	# A bodge leaves the system down on power, so the part route has to stay reachable.
	fault.repair(false, 50.0)
	point.refresh()
	_check("and a bodged system stays a target", point.is_enabled)

	# --- the indicator is metre-sized, on the empty --------------------------
	var light := empty.get_node_or_null("IndicatorLight") as IndicatorLight
	_check("the indicator mounts on the model's own empty", light != null)
	if light != null:
		var mesh := light.get_child(0) as MeshInstance3D
		if mesh != null:
			var size: float = mesh.global_transform.basis.get_scale().y * IndicatorLight.SIZE
			_check("and comes out metre-sized on a prop dressed at 0.25 (%.3f m)" % size,
				absf(size - IndicatorLight.SIZE) < 0.005)

	if _failures.is_empty():
		print("INDICATOR TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("INDICATOR TEST FAIL")
		quit(1)
