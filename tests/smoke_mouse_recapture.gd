extends SceneTree
# Headless test for re-capturing the mouse after the browser takes pointer lock away.
# Run: godot --headless --path . -s tests/smoke_mouse_recapture.gd
#
# WHY THIS IS TESTABLE HEADLESS. A browser that refuses pointer lock and a headless Godot are
# the same thing from the game's side: set_mouse_mode(CAPTURED) is accepted and the cursor never
# actually arrives. So "the browser took the mouse back" is simulated exactly — ask for capture,
# then set the mode straight back to VISIBLE through Input (bypassing MouseCapture, which is
# precisely what the browser does behind the game's back).

const GAME_SCENE := "res://scenes/game.tscn"
## Comfortably past MouseCapture.SETTLE_MS, in wall-clock ms.
const PAST_SETTLE_MS := 700

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


## The browser handing the cursor back without telling the game.
func _steal_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await process_frame


func _run() -> void:
	# This suite drives real capture state. Headless can't take the cursor, so nothing is stolen
	# from the machine — but run it headless, not windowed, or it will grab for real.
	MouseCapture.allow_in_script_runs = true

	# --- MouseCapture: intent vs. actually having it -------------------------
	MouseCapture.release()
	_check("nothing is lost before the game asks for the cursor", not MouseCapture.capture_lost())

	MouseCapture.capture()
	_check(
		"a capture request in flight is not reported as lost",
		not MouseCapture.capture_lost()
	)
	await _wait_ms(PAST_SETTLE_MS)
	_check("a request that never lands is reported as lost", MouseCapture.capture_lost())

	MouseCapture.release()
	_check("releasing on purpose is not a loss", not MouseCapture.capture_lost())

	# --- The game scene -------------------------------------------------------
	if not root.has_node("SceneManager"):
		var sm: Node = load("res://scripts/scene_manager.gd").new()
		sm.name = "SceneManager"
		root.add_child(sm)

	var game: Node3D = load(GAME_SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame

	var pause_menu: CanvasLayer = game.get_node_or_null("PauseMenu")
	_check("game scene contains a PauseMenu", pause_menu != null)
	if pause_menu == null:
		_finish()
		return
	_check("the hint starts hidden", not pause_menu.get_node("%LostCursorHint").visible)

	# --- Off the web, a released cursor is not the browser's doing -----------
	_check("pointer-lock watching is off outside a browser", not pause_menu.watch_pointer_lock)
	_steal_cursor()
	await _wait_ms(PAST_SETTLE_MS)
	_check("no auto-pause when not watching (desktop)", not paused)

	# --- On the web, losing the cursor pauses the game ----------------------
	pause_menu.watch_pointer_lock = true
	await process_frame
	_check("a lost cursor pauses the game", paused)
	_check("a lost cursor shows the pause menu", pause_menu.visible)
	_check("is_paused flag set", pause_menu.is_paused)
	_check("the hint explains the unasked-for pause", pause_menu.get_node("%LostCursorHint").visible)
	_check(
		"Resume has focus so the click target is obvious",
		pause_menu.get_node("%ResumeButton").has_focus()
	)

	# --- Resuming asks for the cursor back ----------------------------------
	pause_menu.get_node("%ResumeButton").pressed.emit()
	await process_frame
	_check("Resume unpauses", not paused)
	_check("Resume hides the menu", not pause_menu.visible)
	_check("Resume clears the hint", not pause_menu.get_node("%LostCursorHint").visible)
	_check("Resume asks for the cursor back", not MouseCapture.capture_lost())

	# --- A refused re-capture pauses straight back, rather than stranding ----
	# Headless never grants it, which is the browser-refuses case.
	await _wait_ms(PAST_SETTLE_MS)
	_check("a refused re-capture pauses again instead of stranding the player", paused)
	_check("the hint is back with it", pause_menu.get_node("%LostCursorHint").visible)

	# --- A disabled pause menu never auto-pauses ----------------------------
	# This is the state during the end-of-run collapse, where the cursor is released on purpose.
	pause_menu.get_node("%ResumeButton").pressed.emit()
	await process_frame
	pause_menu.enabled = false
	_steal_cursor()
	await _wait_ms(PAST_SETTLE_MS)
	_check("a disabled pause menu does not auto-pause", not paused)

	MouseCapture.release()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("MOUSE RECAPTURE TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("MOUSE RECAPTURE TEST FAIL")
		quit(1)
