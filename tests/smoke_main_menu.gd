extends SceneTree
# Headless test for the main menu.
# Run: godot --headless --path . -s tests/smoke_main_menu.gd

const MENU_SCENE := "res://scenes/main_menu.tscn"
const INTRO_SCENE := "res://scenes/intro.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const MAX_FRAMES := 600

var _failures: Array[String] = []


func _init() -> void:
	# Deferred so autoload globals (SceneManager) exist before scripts load.
	_run.call_deferred()


func _current_scene_is(scene_name: String) -> bool:
	return current_scene != null and current_scene.name == scene_name


func _run() -> void:
	if not root.has_node("SceneManager"):
		var sm: Node = load("res://scripts/scene_manager.gd").new()
		sm.name = "SceneManager"
		root.add_child(sm)

	var menu: Control = load(MENU_SCENE).instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame

	# Structure.
	var play: Button = menu.get_node_or_null("%PlayButton")
	if play == null:
		_failures.append("no PlayButton in the main menu")
	elif play.text.strip_edges() == "":
		_failures.append("PlayButton has no label")

	var title: Label = menu.get_node_or_null("Center/VBox/Title")
	if title == null or title.text.strip_edges() == "":
		_failures.append("main menu has no title text")

	# Keyboard/gamepad navigation needs an initial focus.
	if play != null and not play.has_focus():
		_failures.append("PlayButton does not have initial focus")

	# Start now goes to the INTRO (the video), not straight to the game — the intro fades
	# into the game once the video ends.
	if play != null:
		play.pressed.emit()
		var frames := 0
		while frames < MAX_FRAMES and not _current_scene_is("Intro"):
			await process_frame
			frames += 1
		if not _current_scene_is("Intro"):
			_failures.append("Start did not reach the Intro scene within %d frames" % MAX_FRAMES)

	# The game scene must exist and instantiate on its own too.
	var game: PackedScene = load(GAME_SCENE)
	if game == null:
		_failures.append("failed to load %s" % GAME_SCENE)
	else:
		var instance := game.instantiate()
		if instance == null:
			_failures.append("failed to instantiate %s" % GAME_SCENE)
		else:
			instance.free()

	if _failures.is_empty():
		print("MAIN MENU TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("MAIN MENU TEST FAIL")
		quit(1)
