extends SceneTree
# Dev utility: end-to-end proof that the menu's throwaway warm pays for the cut into the game.
#
# Walks the real boot path — main_menu.tscn (which warms in _ready) and then a FRESH
# game.tscn, exactly as SceneManager would load it — and times both halves.
#
# What to look for:
#   menu   - one big stall, by design. This is the cost being moved.
#   game   - the frame that used to cost ~2.1s. Should now be a few hundred ms.
#
# Run WITHOUT --headless:
#   godot --path . --resolution 1280x720 -s tests/probe_boot_warm.gd [-- nowarm]

const MENU_FRAMES := 45
const GAME_FRAMES := 60


func _init() -> void:
	_go.call_deferred()


func _frames(n: int, label: String) -> void:
	var times: Array[float] = []
	for i in n:
		var t0 := Time.get_ticks_usec()
		await process_frame
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)

	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	var worst: PackedStringArray = []
	for i in times.size():
		total += times[i]
		if times[i] > 40.0 and worst.size() < 6:
			worst.append("f%d:%.0fms" % [i, times[i]])
	print("[boot] %-5s total %.0fms  median %.1fms  worst %.0fms  %s" % [
		label, total, sorted[sorted.size() / 2], sorted[sorted.size() - 1], " ".join(worst)])


func _go() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "warm"
	var warm := mode != "nowarm"

	# "hold" keeps the PackedScene referenced across the menu teardown. Freeing the warm copy
	# drops the last reference to every imported mesh and texture it pulled in, so without this
	# the real load re-uploads them all and the warm buys less than it should.
	var kept: PackedScene = null
	if mode == "hold":
		kept = load("res://scenes/game.tscn")

	if warm:
		# loading.tscn is where the warm lives now — the black beat between Start and the intro.
		var loading: Control = load("res://scenes/loading.tscn").instantiate()
		root.add_child(loading)
		current_scene = loading
		await _frames(MENU_FRAMES, "load")
		# It hands off to the intro on its own once warmed; bin whatever is current by then.
		if current_scene != null:
			var leaving := current_scene
			current_scene = null
			leaving.queue_free()
		await process_frame
		await process_frame
	else:
		print("[boot] menu  SKIPPED (control run - straight into the game)")

	# A fresh instance, the way SceneManager.change_scene_to_file() would make one.
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames(GAME_FRAMES, "game")
	quit(0)
