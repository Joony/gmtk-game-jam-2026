extends SceneTree
# Headless test for SceneManager + the intro VIDEO.
# Run: godot --headless --path . -s tests/smoke_intro_scene_manager.gd
#
# The intro used to be a 10 -> 01 countdown; it is now the "Perpetual Pickle" video, which
# fades into the game when it ends. We cannot rely on the video actually decoding frames in
# a headless run, so rather than wait for playback the test drives the two paths that lead
# out of the intro — the Skip button and the video's `finished` signal — and confirms each
# reaches the game.

const INTRO_SCENE := "res://scenes/intro.tscn"
const MAX_FRAMES := 3000

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _current_scene_is(scene_name: String) -> bool:
	return current_scene != null and current_scene.name == scene_name


func _await_scene(name: String) -> bool:
	var frames := 0
	while frames < MAX_FRAMES and not _current_scene_is(name):
		await process_frame
		frames += 1
	return _current_scene_is(name)


func _run() -> void:
	Engine.time_scale = 25.0

	# -s replaces the normal game boot, so make sure the autoload exists.
	if not root.has_node("SceneManager"):
		var sm: Node = load("res://scripts/scene_manager.gd").new()
		sm.name = "SceneManager"
		root.add_child(sm)

	var intro: Control = load(INTRO_SCENE).instantiate()
	root.add_child(intro)
	current_scene = intro
	await process_frame

	# Structure: black background, a video player holding the intro stream.
	var background: ColorRect = intro.get_node("Background")
	if background.color != Color.BLACK:
		_failures.append("intro background is %s, expected black" % background.color)

	var video := intro.get_node_or_null("%Video") as VideoStreamPlayer
	if video == null:
		_failures.append("intro has no %Video VideoStreamPlayer")
	elif video.stream == null:
		_failures.append("the intro video has no stream assigned")
	elif not (video.stream is VideoStreamTheora):
		# Godot only plays Ogg Theora; an .mp4 dropped in here would silently be no stream.
		_failures.append("intro stream is %s, expected VideoStreamTheora" % video.stream.get_class())

	var scene_manager: Node = root.get_node("SceneManager")

	# Path 1: the video finishing takes us to the game. Emit the signal rather than waiting
	# out 36 seconds of playback that may not even tick headless.
	if video != null:
		while scene_manager._changing:
			await process_frame
		video.finished.emit()
		if not await _await_scene("Game"):
			_failures.append("the video finishing did not reach the game scene")

	# Path 2: the Skip button. Back to the intro, press Skip, expect the game.
	while scene_manager._changing:
		await process_frame
	scene_manager.change_scene(INTRO_SCENE)
	if await _await_scene("Intro"):
		var skip: Button = current_scene.get_node("SkipButton")
		while scene_manager._changing:
			await process_frame
		skip.pressed.emit()
		if not await _await_scene("Game"):
			_failures.append("the Skip button did not reach the game scene")
	else:
		_failures.append("could not return to Intro to test the skip button")

	if _failures.is_empty():
		print("INTRO/SCENEMANAGER TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("INTRO/SCENEMANAGER TEST FAIL")
		quit(1)
