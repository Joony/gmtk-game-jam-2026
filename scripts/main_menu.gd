extends Control

# The first thing the game shows now: a bare black title screen. Start goes to the intro
# video (which then fades into the game); the old flow launched straight into the intro and
# skipped the menu entirely.

const INTRO_SCENE := "res://scenes/intro.tscn"


func _ready() -> void:
	# Menus need the cursor back — the game captures it.
	MouseCapture.release()
	# Quitting a browser tab is not a thing, so the button only makes sense on desktop.
	%QuitButton.visible = OS.get_name() != "Web"
	%PlayButton.grab_focus()


func _on_play_button_pressed() -> void:
	Audio.play(&"click")
	SceneManager.change_scene(INTRO_SCENE)


func _on_quit_button_pressed() -> void:
	Audio.play(&"click")
	get_tree().quit()
