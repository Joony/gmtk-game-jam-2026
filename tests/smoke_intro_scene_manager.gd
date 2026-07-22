extends SceneTree
# Headless test for SceneManager + intro countdown/skip.
# Run: godot --headless --path . -s tests/smoke_intro_scene_manager.gd
# Time is sped up so the 11s countdown finishes in under a second of real time.

const INTRO_SCENE := "res://scenes/intro.tscn"
const MAX_FRAMES := 3000

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _current_scene_is(scene_name: String) -> bool:
	return current_scene != null and current_scene.name == scene_name


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

	# Structure: black background, big red countdown starting at 10.
	var background: ColorRect = intro.get_node("Background")
	if background.color != Color.BLACK:
		_failures.append("background is %s, expected black" % background.color)
	var label: Label = intro.get_node("%CountdownLabel")
	if label.text != "10":
		_failures.append("countdown starts at '%s', expected '10'" % label.text)
	var font_color: Color = label.get_theme_color("font_color")
	if not (font_color.r > 0.5 and font_color.g < 0.3 and font_color.b < 0.3):
		_failures.append("countdown color %s is not red" % font_color)
	if label.get_theme_font_size("font_size") < 100:
		_failures.append("countdown font size %d is not big" % label.get_theme_font_size("font_size"))

	# Countdown ticks down in two digits, holds on 01 (never reaches 00), then
	# advances to the game. current_scene is briefly null mid-change, so only
	# test the name when it is set.
	var seen_two_digit := false
	var seen_one := false
	var seen_zero := false
	var frames := 0
	while frames < MAX_FRAMES and not _current_scene_is("Game"):
		if is_instance_valid(label):
			match label.text:
				"09": seen_two_digit = true
				"01": seen_one = true
				"00", "0": seen_zero = true
		await process_frame
		frames += 1
	if not seen_two_digit:
		_failures.append("countdown is not zero-padded to two digits (never displayed '09')")
	if not seen_one:
		_failures.append("countdown never displayed '01'")
	if seen_zero:
		_failures.append("countdown reached zero — it should hold on 01 and never show 00")
	if not _current_scene_is("Game"):
		_failures.append("countdown did not auto-advance to the game scene within %d frames" % MAX_FRAMES)

	# Skip button: go back to the intro, press Skip, expect a transition
	# triggered by the button (countdown timer stopped), not the countdown.
	var scene_manager: Node = root.get_node("SceneManager")
	while scene_manager._changing:
		await process_frame
	scene_manager.change_scene(INTRO_SCENE)
	frames = 0
	while frames < MAX_FRAMES and not _current_scene_is("Intro"):
		await process_frame
		frames += 1
	if _current_scene_is("Intro"):
		var skip: Button = current_scene.get_node("SkipButton")
		var countdown_timer: Timer = current_scene.get_node("Timer")
		while scene_manager._changing:
			await process_frame
		skip.pressed.emit()
		if not countdown_timer.is_stopped():
			_failures.append("skip did not stop the countdown timer")
		frames = 0
		while frames < MAX_FRAMES and not _current_scene_is("Game"):
			await process_frame
			frames += 1
		if not _current_scene_is("Game"):
			_failures.append("skip button did not reach the game scene")
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
