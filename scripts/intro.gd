extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const COUNTDOWN_START := 10

var _count := COUNTDOWN_START


func _ready() -> void:
	_show_count()


func _on_timer_timeout() -> void:
	if _count == 0:
		_finish()
		return
	_count -= 1
	_show_count()


func _on_skip_button_pressed() -> void:
	_finish()


func _show_count() -> void:
	%CountdownLabel.text = str(_count)


func _finish() -> void:
	$Timer.stop()
	SceneManager.change_scene(MAIN_MENU_SCENE)
