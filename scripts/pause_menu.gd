extends CanvasLayer

# Owns Esc and ALL mouse-capture state while in game, so there is a single source
# of truth for the cursor. The camera controller deliberately does not touch it.
#
# Only present in the game scene, so Esc is inert in the intro and main menu.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

signal paused
signal resumed

var is_paused: bool = false
## Set false to make Esc inert — the game scene disables it until the player
## clicks START, so pausing can't happen before the game has begun.
var enabled: bool = true
## Watch for the browser taking pointer lock away. Set from OS.has_feature("web") in _ready:
## only a browser can pull the cursor out from under a running game. Tests drive it directly.
var watch_pointer_lock: bool = false


func _ready() -> void:
	# Must keep running while the tree is paused, or Esc could never unpause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	watch_pointer_lock = OS.has_feature("web")
	%LostCursorHint.visible = false
	get_tree().paused = false


# The browser hands pointer lock back the moment the tab loses focus — alt-tab, a click on the
# page outside the canvas, the browser's own Esc — and there is no way to take it back without a
# user gesture. Left alone the player is stranded: still walking, still burning oxygen, mouse
# look dead. So a lost cursor pauses the game. That freezes the run and puts a button on screen,
# and CLICKING that button is the gesture that re-captures.
func _process(_delta: float) -> void:
	if not watch_pointer_lock or not enabled or is_paused:
		return
	if MouseCapture.capture_lost():
		pause_game(true)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_paused:
		resume()
	else:
		pause_game()


func pause_game(cursor_was_lost: bool = false) -> void:
	if is_paused:
		return
	is_paused = true
	get_tree().paused = true
	visible = true
	# Tell the browser we've stopped wanting the cursor, so releasing it here doesn't read as
	# another loss the moment we resume.
	MouseCapture.release()
	# Explains an unasked-for pause menu, and says what to do about it.
	%LostCursorHint.visible = cursor_was_lost
	%ResumeButton.grab_focus()
	paused.emit()


func resume() -> void:
	if not is_paused:
		return
	is_paused = false
	get_tree().paused = false
	visible = false
	%LostCursorHint.visible = false
	# On web this only ASKS for pointer lock. Coming out via the Resume button it is granted,
	# because the click that pressed the button is the gesture the browser wants. Coming out via
	# Esc it can be refused (Chrome doesn't count Esc as a gesture, and briefly blocks re-locking
	# after an Esc unlock) — in which case _process notices within SETTLE_MS and pauses straight
	# back, hint showing, so the player is never left running around cursorless.
	MouseCapture.capture()
	resumed.emit()


func _on_resume_button_pressed() -> void:
	Audio.play(&"click")
	resume()


func _on_quit_button_pressed() -> void:
	Audio.play(&"click")
	# Unpause before leaving, or the main menu loads into a paused tree.
	is_paused = false
	get_tree().paused = false
	visible = false
	%LostCursorHint.visible = false
	# Cursor stays visible on purpose — the main menu needs it.
	MouseCapture.release()
	SceneManager.change_scene(MAIN_MENU_SCENE)
