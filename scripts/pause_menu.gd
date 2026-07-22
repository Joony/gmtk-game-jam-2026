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


func _ready() -> void:
	# Must keep running while the tree is paused, or Esc could never unpause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	get_tree().paused = false


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


func pause_game() -> void:
	if is_paused:
		return
	is_paused = true
	get_tree().paused = true
	visible = true
	MouseCapture.release()
	%ResumeButton.grab_focus()
	paused.emit()


func resume() -> void:
	if not is_paused:
		return
	is_paused = false
	get_tree().paused = false
	visible = false
	MouseCapture.capture()
	resumed.emit()


func _on_resume_button_pressed() -> void:
	resume()


func _on_quit_button_pressed() -> void:
	# Unpause before leaving, or the main menu loads into a paused tree.
	is_paused = false
	get_tree().paused = false
	visible = false
	# Cursor stays visible on purpose — the main menu needs it.
	MouseCapture.release()
	SceneManager.change_scene(MAIN_MENU_SCENE)
