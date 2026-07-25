extends Control

# The intro is the "Perpetual Pickle" video. It plays once, full-screen, and when it ends the
# game HARD CUTS in. Reached from the main menu's Start button, not on launch — the menu
# comes first now.
#
# The cut is the point. The game opens on a cold open — no HUD, no music, the player sealed in
# a pod with the klaxon of a fault that has already happened — and a fade would announce the
# change as a scene transition. Cutting straight from the last frame of the video to the
# inside of the pod lands it as something that happens TO the player instead.
#
# There is no countdown here any more; the old 10 -> 01 title card was replaced by the video.

const NEXT_SCENE := "res://scenes/game.tscn"

@onready var _video: VideoStreamPlayer = %Video

var _finished := false


func _ready() -> void:
	# The video carries its own audio; the game's music does not start until the run begins,
	# so there is nothing to fight with here.
	MouseCapture.release()
	_video.finished.connect(_finish)
	# Play from _ready rather than an autoplay flag, so a failed load (a missing .ogv on a
	# broken build) falls straight through to the game instead of hanging on a black screen.
	if _video.stream != null:
		_video.play()
	else:
		_finish()


func _on_skip_button_pressed() -> void:
	Audio.play(&"click")
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_video.stop()
	# No fade — see the note at the top of this file.
	SceneManager.change_scene(NEXT_SCENE, false)
