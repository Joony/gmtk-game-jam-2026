extends Control

const NEXT_SCENE := "res://scenes/game.tscn"
const COUNTDOWN_START := 10
# Counts down to 01 and holds there — it never reaches zero. The countdown is
# interrupted rather than completed, which is the stasis wake-up beat.
const COUNTDOWN_END := 1
## Seconds to hold on 01 before fading out.
@export var hold_seconds: float = 1.5

var _count := COUNTDOWN_START
var _finished := false


func _ready() -> void:
	_show_count()


func _on_timer_timeout() -> void:
	if _count <= COUNTDOWN_END:
		return
	_count -= 1
	_show_count()
	if _count == COUNTDOWN_END:
		$Timer.stop()
		await get_tree().create_timer(hold_seconds).timeout
		_finish()


func _on_skip_button_pressed() -> void:
	Audio.play(&"click")
	_finish()


func _show_count() -> void:
	%CountdownLabel.text = "%02d" % _count


func _finish() -> void:
	if _finished:
		return
	_finished = true
	$Timer.stop()
	SceneManager.change_scene(NEXT_SCENE)
