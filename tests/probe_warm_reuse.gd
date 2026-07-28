extends SceneTree
# Dev utility: does warming with a THROWAWAY instance of game.tscn help the next one?
#
# The 2-second first drawn frame (tests/probe_opening_frames.gd) is two different costs added
# together, and they have opposite lifetimes:
#
#   * shader variant compilation - cached by the RenderingServer for the whole PROCESS. Paid
#     once ever, no matter how many times the scene is instantiated.
#   * GPU upload of meshes and textures - cached per RESOURCE. The imported props share theirs,
#     but RoomBuilder builds its boxes in code, so a fresh instance makes fresh meshes.
#
# Which one dominates decides the design. If instance #2 is fast, a warm instance can be built
# during the menu and THROWN AWAY, and the real one loads clean and quick later. If instance #2
# is still slow, the warmed instance has to be kept alive and handed to the player.
#
# Run WITHOUT --headless:
#   godot --path . --resolution 1280x720 -s tests/probe_warm_reuse.gd

const ROUNDS := 3
const FRAMES := 40


func _init() -> void:
	_go.call_deferred()


func _go() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	# Held for the whole run so the PackedScene and its imported sub-resources stay in the
	# resource cache. Dropping it would re-load them and confuse upload cost with load cost.
	var packed: PackedScene = load("res://scenes/game.tscn")

	for round_i in ROUNDS:
		var game: Node3D = packed.instantiate()
		var t_add := Time.get_ticks_usec()
		root.add_child(game)
		current_scene = game
		var ready_ms := float(Time.get_ticks_usec() - t_add) / 1000.0

		var times: Array[float] = []
		for i in FRAMES:
			var t0 := Time.get_ticks_usec()
			await process_frame
			times.append(float(Time.get_ticks_usec() - t0) / 1000.0)

		var rest := times.slice(1)
		rest.sort()
		print("[reuse] instance %d  _ready %.0fms  frame1 %.0fms  frame2 %.0fms  median-after %.1fms"
			% [round_i + 1, ready_ms, times[0], times[1], rest[rest.size() / 2]])

		# Tear it down the way quitting to the menu would.
		current_scene = null
		game.queue_free()
		# free() is deferred; give it a frame to actually happen before the next instantiate,
		# or two ships exist at once and the second one's cost is measured against the wrong
		# baseline.
		await process_frame
		await process_frame

	quit(0)
