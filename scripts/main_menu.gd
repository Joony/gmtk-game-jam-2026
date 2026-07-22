extends Control

const GAME_SCENE := "res://scenes/game.tscn"


func _ready() -> void:
	# Menus need the cursor back — the game captures it.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	%PlayButton.grab_focus()


func _on_play_button_pressed() -> void:
	SceneManager.change_scene(GAME_SCENE)
