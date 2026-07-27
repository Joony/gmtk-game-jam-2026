extends SceneTree
# Dev utility: is the OPENING smooth, now that the shader prewarm runs inside it?
#
# ShaderPrewarm deliberately spends the opening stasis beat compiling shader variants, to buy
# a hitch-free first turn (see tests/probe_turn_hitch.gd). That trade is only worth making if
# the beat it is spent in stays smooth — a stutter while the player is sealed in the pod is
# better than one mid-turn, but it is not free.
#
# Times every frame from scene load onwards and prints the worst ones, so "smooth" is a
# NUMBER rather than an impression.
#
# Run WITHOUT --headless:
#   godot --path . --resolution 1280x720 -s tests/probe_opening_frames.gd

const FRAMES := 360


func _init() -> void:
	_go.call_deferred()


func _go() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var t_load := Time.get_ticks_usec()
	var packed: PackedScene = load("res://scenes/game.tscn")
	var t_inst := Time.get_ticks_usec()
	var game: Node3D = packed.instantiate()
	var t_add := Time.get_ticks_usec()
	# _ready() runs synchronously inside add_child(), so this bracket is where RoomBuilder
	# actually builds the ship - as distinct from the first frame that DRAWS it.
	root.add_child(game)
	current_scene = game
	var t_done := Time.get_ticks_usec()
	print("[opening] load %.0fms  instantiate %.0fms  add_child/_ready %.0fms" % [
		float(t_inst - t_load) / 1000.0,
		float(t_add - t_inst) / 1000.0,
		float(t_done - t_add) / 1000.0,
	])

	var times: Array[float] = []
	for i in FRAMES:
		var t0 := Time.get_ticks_usec()
		await process_frame
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)

	var sorted := times.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	var worst: PackedStringArray = []
	var over := 0
	for i in times.size():
		if times[i] > 20.0:
			over += 1
			if worst.size() < 10:
				worst.append("f%d:%.0fms" % [i, times[i]])
	print("[opening] median %.2fms  worst %.1fms  frames over 20ms: %d  %s"
		% [median, sorted[sorted.size() - 1], over, " ".join(worst)])
	quit(0)
