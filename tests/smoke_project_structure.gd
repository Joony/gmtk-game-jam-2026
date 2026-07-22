extends SceneTree
# Headless smoke test for the project-structure setup.
# Run: godot --headless --path . -s tests/smoke_project_structure.gd


func _init() -> void:
	var failures: Array[String] = []

	InputMap.load_from_project_settings()
	if not InputMap.has_action("pause"):
		failures.append("InputMap has no 'pause' action")
	else:
		var has_escape := false
		for event in InputMap.action_get_events("pause"):
			if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
				has_escape = true
		if not has_escape:
			failures.append("'pause' action is not bound to Escape")

	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene != "res://scenes/intro.tscn":
		failures.append("main scene is '%s', expected res://scenes/intro.tscn" % main_scene)

	var packed: PackedScene = load("res://scenes/intro.tscn")
	if packed == null:
		failures.append("failed to load res://scenes/intro.tscn")
	else:
		var instance := packed.instantiate()
		if instance == null:
			failures.append("failed to instantiate intro.tscn")
		else:
			instance.free()

	for dir in ["scenes", "scripts", "ui", "assets"]:
		if not DirAccess.dir_exists_absolute("res://" + dir):
			failures.append("missing folder: %s/" % dir)

	if failures.is_empty():
		print("SMOKE TEST PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SMOKE TEST FAIL")
		quit(1)
