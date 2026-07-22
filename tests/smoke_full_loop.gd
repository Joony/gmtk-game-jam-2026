extends SceneTree
# Step 6: walk the entire game loop TWICE in one run and prove nothing leaks.
# Intro -> (skip) -> Main Menu -> Play -> Game -> Esc -> Quit to Menu -> Main Menu
#
# Run: godot --headless --path . -s tests/smoke_full_loop.gd

const INTRO_SCENE := "res://scenes/intro.tscn"
const MAX_FRAMES := 1200

var _failures: Array[String] = []
var _scene_manager: Node


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _current_scene_is(scene_name: String) -> bool:
	return current_scene != null and current_scene.name == scene_name


func _press_escape() -> void:
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	root.push_input(event)


func _wait_for_scene(scene_name: String) -> bool:
	var frames := 0
	while frames < MAX_FRAMES and not _current_scene_is(scene_name):
		await process_frame
		frames += 1
	return _current_scene_is(scene_name)


func _wait_for_transition_idle() -> void:
	while _scene_manager._changing:
		await process_frame


# Let queue_free()d nodes actually be released before sampling counters.
func _settle() -> void:
	for i in 10:
		await process_frame


func _metrics() -> Dictionary:
	return {
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}


func _loop_once(round_number: int) -> void:
	var tag := "round %d" % round_number

	await _wait_for_transition_idle()
	_scene_manager.change_scene(INTRO_SCENE)
	_check("%s: reached the intro" % tag, await _wait_for_scene("Intro"))
	if not _current_scene_is("Intro"):
		return

	# Skip rather than sitting through the 11s countdown.
	await _wait_for_transition_idle()
	current_scene.get_node("SkipButton").pressed.emit()
	_check("%s: intro skip reached the main menu" % tag, await _wait_for_scene("MainMenu"))
	if not _current_scene_is("MainMenu"):
		return

	await _wait_for_transition_idle()
	current_scene.get_node("%PlayButton").pressed.emit()
	_check("%s: Play reached the game" % tag, await _wait_for_scene("Game"))
	if not _current_scene_is("Game"):
		return

	# The game must be live: player present, on the floor, tree not paused.
	var game := current_scene
	var player: CharacterBody3D = game.get_node_or_null("Player")
	_check("%s: game has a player" % tag, player != null)
	_check("%s: tree is not paused on entry" % tag, not paused)
	for i in 30:
		await physics_frame
	if player != null:
		_check("%s: player is standing on the floor" % tag, player.is_on_floor())

	# Pause, then quit to the menu.
	_press_escape()
	await process_frame
	var pause_menu: CanvasLayer = game.get_node_or_null("PauseMenu")
	_check("%s: Esc paused the game" % tag, paused and pause_menu != null and pause_menu.visible)
	pause_menu.get_node("%QuitButton").pressed.emit()
	await process_frame
	_check("%s: quitting unpaused the tree" % tag, not paused)
	_check("%s: Quit to Menu reached the main menu" % tag, await _wait_for_scene("MainMenu"))


func _run() -> void:
	if not root.has_node("SceneManager"):
		var sm: Node = load("res://scripts/scene_manager.gd").new()
		sm.name = "SceneManager"
		root.add_child(sm)
	_scene_manager = root.get_node("SceneManager")

	await _loop_once(1)
	await _settle()
	var after_first := _metrics()

	await _loop_once(2)
	await _settle()
	var after_second := _metrics()

	# Two identical loops should leave the tree in an identical shape. Allow a tiny
	# margin for engine-internal churn, but a leaked scene would be far larger.
	var node_growth: int = after_second["nodes"] - after_first["nodes"]
	var orphan_growth: int = after_second["orphans"] - after_first["orphans"]

	_check(
		"node count stable across loops (%d -> %d, +%d)"
			% [after_first["nodes"], after_second["nodes"], node_growth],
		node_growth <= 5
	)
	_check(
		"no orphaned nodes accumulating (%d -> %d, +%d)"
			% [after_first["orphans"], after_second["orphans"], orphan_growth],
		orphan_growth <= 0
	)

	# Nothing from the game scene should survive in the menu.
	_check("ended on the main menu", _current_scene_is("MainMenu"))
	var stray_players := 0
	for node in root.find_children("Player", "CharacterBody3D", true, false):
		stray_players += 1
	_check("no player instances left alive (%d found)" % stray_players, stray_players == 0)
	_check("tree left unpaused", not paused)

	print("loop metrics: after#1 %s / after#2 %s" % [after_first, after_second])
	if _failures.is_empty():
		print("FULL LOOP TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FULL LOOP TEST FAIL")
		quit(1)
