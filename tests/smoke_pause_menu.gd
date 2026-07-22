extends SceneTree
# Headless test for the pause menu (step 5).
# Run: godot --headless --path . -s tests/smoke_pause_menu.gd
# Cursor assertions only run windowed — see the note at the bottom.

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const INTRO_SCENE := "res://scenes/intro.tscn"
const MAX_FRAMES := 600

var _failures: Array[String] = []
var _cursor_testable := false


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _press_escape() -> void:
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	root.push_input(event)


func _current_scene_is(scene_name: String) -> bool:
	return current_scene != null and current_scene.name == scene_name


func _run() -> void:
	if not root.has_node("SceneManager"):
		var sm: Node = load("res://scripts/scene_manager.gd").new()
		sm.name = "SceneManager"
		root.add_child(sm)

	# Can we meaningfully assert cursor state in this run?
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_cursor_testable = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

	var game: Node3D = load(GAME_SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame

	var pause_menu: CanvasLayer = game.get_node_or_null("PauseMenu")
	_check("game scene contains a PauseMenu", pause_menu != null)
	if pause_menu == null:
		_finish()
		return

	# --- Starts hidden and unpaused -----------------------------------------
	_check("pause menu starts hidden", not pause_menu.visible)
	_check("tree starts unpaused", not paused)
	_check(
		"pause menu processes while paused",
		pause_menu.process_mode == Node.PROCESS_MODE_ALWAYS
	)
	_check("pause menu has a Resume button", pause_menu.get_node_or_null("%ResumeButton") != null)
	_check("pause menu has a Quit button", pause_menu.get_node_or_null("%QuitButton") != null)
	_check("pause menu dims the background", pause_menu.get_node_or_null("Dim") != null)

	# --- Esc pauses: menu shown, tree paused, cursor released ---------------
	_press_escape()
	await process_frame
	_check("Esc shows the pause menu", pause_menu.visible)
	_check("Esc pauses the tree", paused)
	_check("is_paused flag set", pause_menu.is_paused)
	if _cursor_testable:
		_check("Esc releases the cursor", Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE)
		_check("Resume button has focus when paused", pause_menu.get_node("%ResumeButton").has_focus())

	# --- Esc again resumes: all three reversed ------------------------------
	_press_escape()
	await process_frame
	_check("Esc again hides the pause menu", not pause_menu.visible)
	_check("Esc again unpauses the tree", not paused)
	if _cursor_testable:
		_check("Esc again re-captures the cursor", Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)

	# --- Resume button does the same ----------------------------------------
	_press_escape()
	await process_frame
	_check("paused again before testing Resume", paused)
	pause_menu.get_node("%ResumeButton").pressed.emit()
	await process_frame
	_check("Resume button unpauses", not paused)
	_check("Resume button hides the menu", not pause_menu.visible)

	# --- The game keeps running after resume (pause actually reverses) ------
	var player: CharacterBody3D = game.get_node("Player")
	for i in 30:
		await physics_frame
	var pos_before := player.global_position
	_press_escape()
	await process_frame
	for i in 30:
		await physics_frame
	_check("player does not move while paused", player.global_position.distance_to(pos_before) < 0.001)
	pause_menu.get_node("%ResumeButton").pressed.emit()
	await process_frame

	# --- Quit to Menu: unpause, leave cursor visible, change scene ----------
	_press_escape()
	await process_frame
	_check("paused before Quit to Menu", paused)
	pause_menu.get_node("%QuitButton").pressed.emit()
	await process_frame
	_check("Quit to Menu unpauses the tree", not paused)

	var frames := 0
	while frames < MAX_FRAMES and not _current_scene_is("MainMenu"):
		await process_frame
		frames += 1
	_check("Quit to Menu reaches the main menu", _current_scene_is("MainMenu"))
	_check("tree is not left paused in the main menu", not paused)
	if _cursor_testable:
		_check(
			"cursor stays visible in the main menu",
			Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE
		)

	# --- Esc must be inert outside the game ---------------------------------
	_press_escape()
	await process_frame
	_check("Esc does nothing in the main menu", not paused)

	var intro: Control = load(INTRO_SCENE).instantiate()
	root.add_child(intro)
	current_scene = intro
	await process_frame
	_press_escape()
	await process_frame
	_check("Esc does nothing in the intro", not paused)

	_finish()


func _finish() -> void:
	if not _cursor_testable:
		print("  (skipped cursor checks: capture unavailable headless — run windowed)")
	if _failures.is_empty():
		print("PAUSE MENU TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("PAUSE MENU TEST FAIL")
		quit(1)
