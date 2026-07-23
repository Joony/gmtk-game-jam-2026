extends SceneTree
# Every ext_resource in every scene must still resolve.
#
# This exists because an asset move has silently broken a scene reference TWICE: a .tscn
# stores its dependencies as path strings (and UIDs), git merges them without understanding
# them, and Godot papers over a dead path at load time — so the scene looks fine in a
# headless test right up until the moment someone opens it or clears the UID cache. Both
# breakages were a collaborator renaming or relocating a .blend the pod and pipe scenes
# pointed at.
#
# It parses the scene text rather than loading each scene, on purpose. Loading a scene with a
# missing dependency emits an error but frequently returns a usable placeholder, so a load
# can PASS on a broken reference; reading the `path=` string and checking it directly cannot.
#
# Covers .tscn and .tres alike — the failure mode is identical, a resource file referencing
# another by a path that no longer points at anything.
#
# Run: godot --headless --path . -s tests/smoke_scene_deps.gd

var failures: Array[String] = []
var checks := 0
var _ext_line := RegEx.new()
var _path_attr := RegEx.new()
var _uid_attr := RegEx.new()


func _init() -> void:
	_ext_line.compile("^\\[ext_resource ")
	_path_attr.compile("path=\"([^\"]+)\"")
	_uid_attr.compile("uid=\"([^\"]+)\"")
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		failures.append(label)
		print("  FAIL %s" % label)


## Recursively collect every .tscn/.tres under res://, skipping the import cache.
func _scene_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_scene_files(full, out)
		elif name.ends_with(".tscn") or name.ends_with(".tres"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _run() -> void:
	print("== smoke_scene_deps ==")
	var files: Array[String] = []
	_scene_files("res://", files)
	files.sort()
	# A guard on the guard: if the walk finds nothing, this test would pass by doing nothing.
	_check(files.size() >= 15, "found the project's scenes to check (%d)" % files.size())

	var total_refs := 0
	for path in files:
		total_refs += _check_scene(path)
	print("-- %d scenes, %d ext_resources, %d checks, %d failures --"
		% [files.size(), total_refs, checks, failures.size()])
	for failure in failures:
		print("   FAILED: %s" % failure)
	quit(1 if failures.size() > 0 else 0)


## Returns the number of ext_resources checked in this scene.
func _check_scene(scene_path: String) -> int:
	var text := FileAccess.get_file_as_string(scene_path)
	if text.is_empty():
		_check(false, "%s is readable" % scene_path)
		return 0

	var short := scene_path.trim_prefix("res://")
	var count := 0
	for line in text.split("\n"):
		if _ext_line.search(line) == null:
			continue
		var path_match := _path_attr.search(line)
		if path_match == null:
			# Every ext_resource has a path; one without is itself a malformed reference.
			_check(false, "%s: ext_resource with no path — %s" % [short, line.strip_edges()])
			continue
		count += 1
		var dep := path_match.get_string(1)

		# The check that matters: can Godot actually load this dependency? A dead path is
		# exactly what the two real breakages left behind.
		if ResourceLoader.exists(dep):
			_check(true, "%s → %s" % [short, dep])
		elif FileAccess.file_exists(dep):
			# The source file is there but not importable — e.g. a .blend that never got
			# imported, or a broken .import. Different cause, same broken scene.
			_check(false, "%s → %s exists but is not loadable (unimported or bad .import?)" % [short, dep])
		else:
			_check(false, "%s → %s DOES NOT EXIST" % [short, dep])
			continue

		# When a UID is also written, it must agree with the path. The cryo break was
		# precisely this: the path went stale AND the old UID had been reassigned to a
		# different model, so neither route reached the intended file.
		var uid_match := _uid_attr.search(line)
		if uid_match == null:
			continue
		var uid_text := uid_match.get_string(1)
		var uid_id := ResourceUID.text_to_id(uid_text)
		if not ResourceUID.has_id(uid_id):
			# Not fatal on its own — Godot falls back to the path, which we already know
			# resolves — but it means the UID cache and the scene disagree, which is the
			# early warning the cryo case never got.
			_check(false, "%s: %s references unknown %s (path still works, UID is stale)" % [short, dep, uid_text])
			continue
		var uid_path := ResourceUID.get_id_path(uid_id)
		_check(uid_path == dep,
			"%s: %s and its UID agree (UID → %s)" % [short, dep, uid_path])

	return count
