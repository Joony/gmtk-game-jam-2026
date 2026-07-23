extends SceneTree
# Step 10: ship-wide lighting modes.
# Run: godot --headless --path . -s tests/smoke_lighting.gd

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()
	_watchdog.call_deferred()


# A script error inside an awaited coroutine kills it silently, hanging the test
# instead of failing it.
func _watchdog() -> void:
	await create_timer(90.0).timeout
	push_error("watchdog fired: the test never finished (look for a SCRIPT ERROR above)")
	print("LIGHTING TEST FAIL")
	quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _lights() -> Array[Node]:
	return get_nodes_in_group(RoomBuilder.GROUP_LIGHT)


# Average light colour across the ship, so we assert the whole ship, not one lamp.
func _average_light_color() -> Color:
	var total := Color(0, 0, 0, 0)  # alpha 0, or the accumulator biases it
	var lights := _lights()
	for light in lights:
		total += (light as OmniLight3D).light_color
	return total / maxf(1.0, lights.size())


func _average_energy() -> float:
	var total := 0.0
	var lights := _lights()
	for light in lights:
		total += (light as OmniLight3D).light_energy
	return total / maxf(1.0, lights.size())


func _run() -> void:
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_game()

	var lighting: LightingController = game.get_node("Lighting")
	var ship: Node3D = game.get_node("Ship")
	_check("game scene has a LightingController", lighting != null)
	_check("ship has lights to drive (%d)" % _lights().size(), _lights().size() >= 3)

	# --- Modes are data, not branches ---------------------------------------
	_check(
		"every mode defines the same keys, so a new mode needs no new code",
		LightingController.MODES[LightingController.Mode.NORMAL].keys()
			== LightingController.MODES[LightingController.Mode.ALERT].keys()
	)

	# --- Starts normal -------------------------------------------------------
	await _frames(30)
	_check("starts in NORMAL", lighting.mode == LightingController.Mode.NORMAL)
	var normal_color := _average_light_color()
	var normal_energy := _average_energy()
	_check(
		"normal light is neutral/white (%s)" % normal_color,
		normal_color.r > 0.8 and normal_color.g > 0.8 and normal_color.b > 0.8
	)

	# --- Signal fires once per real change -----------------------------------
	var events: Array = []
	lighting.mode_changed.connect(func(m: int) -> void: events.append(m))

	lighting.set_alert(true)
	await _frames(2)
	_check("mode_changed fired once on change (%d)" % events.size(), events.size() == 1)
	lighting.set_alert(true)  # same mode again
	await _frames(2)
	_check("re-setting the same mode does not re-fire (%d)" % events.size(), events.size() == 1)

	# --- Alert: red, and dimmer ---------------------------------------------
	await _frames(60)  # let the transition finish
	var alert_color := _average_light_color()
	_check(
		"alert light is red (%s)" % alert_color,
		alert_color.r > 0.8 and alert_color.g < 0.4 and alert_color.b < 0.4
	)
	_check(
		"alert is dimmer than normal (%.2f vs %.2f)" % [_average_energy(), normal_energy],
		_average_energy() < normal_energy
	)

	# Emissive housings follow, or the panels stay white while the room turns red.
	var panels := get_nodes_in_group(RoomBuilder.GROUP_LIGHT_PANEL)
	_check("ship has light panels (%d)" % panels.size(), panels.size() >= 3)
	var panel_mat: StandardMaterial3D = (panels[0] as MeshInstance3D).material_override
	_check(
		"light panels turn red too (%s)" % panel_mat.emission,
		panel_mat.emission.r > 0.8 and panel_mat.emission.g < 0.4
	)

	# Ambient follows the mode, not just the fixtures.
	var env: Environment = game.get_node("WorldEnvironment").environment
	_check(
		"ambient goes red in alert (%s)" % env.ambient_light_color,
		env.ambient_light_color.r > env.ambient_light_color.b
	)

	# --- The transition is gradual, not a snap -------------------------------
	# Check PROGRESSION rather than a value at a fixed frame — how far a 0.4s blend has
	# travelled after N frames depends on the frame rate.
	lighting.set_alert(false)
	await _frames(1)
	var just_after := _average_light_color()
	_check(
		"transition does not snap (still mostly red one frame in: %s)" % just_after,
		just_after.g < 0.5
	)
	await _frames(10)
	var partway := _average_light_color()
	_check(
		"transition progresses over time (%.3f -> %.3f green)" % [just_after.g, partway.g],
		partway.g > just_after.g
	)
	await _frames(60)
	_check(
		"returns to neutral (%s)" % _average_light_color(),
		_average_light_color().is_equal_approx(normal_color)
	)

	# --- A room built WHILE in alert must come up red ------------------------
	# This is why values are applied to the groups every frame rather than tweened
	# per-light: new geometry conforms with no registration step.
	lighting.set_alert(true)
	await _frames(60)
	var before_count := _lights().size()
	ship.add_room(Rect2i(20, 20, 6, 6), {"id": "late_room", "height": 3.0})
	ship.build()
	await _frames(10)
	_check("the late room added lights (%d -> %d)" % [before_count, _lights().size()], _lights().size() > 0)

	var late_lights: Array[Node] = []
	for light in _lights():
		if String(light.name).begins_with("Light_late_room"):
			late_lights.append(light)
	_check("late room built its own lights (%d)" % late_lights.size(), late_lights.size() >= 1)
	if late_lights.size() > 0:
		var late_color: Color = (late_lights[0] as OmniLight3D).light_color
		_check(
			"a room built during alert comes up RED, not white (%s)" % late_color,
			late_color.r > 0.8 and late_color.g < 0.4
		)

	# --- Alert pulses --------------------------------------------------------
	var samples: Array[float] = []
	for i in 40:
		await process_frame
		samples.append(_average_energy())
	var lo: float = samples.min()
	var hi: float = samples.max()
	_check("alert energy pulses (%.3f..%.3f)" % [lo, hi], hi - lo > 0.02)

	if _failures.is_empty():
		print("LIGHTING TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("LIGHTING TEST FAIL")
		quit(1)
