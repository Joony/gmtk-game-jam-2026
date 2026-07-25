extends SceneTree
# RoomVoice: the ship computer speaking when the player walks into a room.
#
# Built for the opening tutorial — the run starts on an already-broken fault, and the
# instruction has to land when the thing is in front of the player rather than while they are
# still in the pod. Arriving in the room is the cue.
#
# Builds its OWN ship rather than loading game.tscn, for the same reason smoke_cable_drag now
# frees the Decor node: a test about a trigger must not be decided by whatever furniture or
# room rectangles happen to be in the scene this week.
#
# Run: godot --headless --path . -s tests/smoke_room_voice.gd

var _failures: Array[String] = []
var _said: Array[StringName] = []


func _init() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("room voice test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	# Two rooms sharing the x=10 wall, so "standing in the doorway" is a real position.
	var builder := RoomBuilder.new()
	builder.build_doors = false
	builder.build_lights = false
	world.add_child(builder)
	builder.add_room(Rect2i(0, 0, 10, 10), {"id": "first"})
	builder.add_room(Rect2i(10, 0, 10, 10), {"id": "second"})
	builder.build()

	var player := Node3D.new()
	world.add_child(player)

	var voice := RoomVoice.new()
	world.add_child(voice)
	voice.lines = {"second": &"thingamajig"}
	voice.bind(builder, player)
	# Listen to `spoke`, NOT `room_changed`. room_changed fires on every crossing, so recording
	# from it counts walk-throughs rather than utterances and can never catch a cue repeating.
	# A headless run has no audio device, so the signal is the observable.
	voice.spoke.connect(func(_room: String, line: StringName) -> void:
		_said.append(line))

	# --- point -> room lookup ------------------------------------------------
	_check("a point in the first room resolves", builder.room_at(Vector3(5, 0, 5)) == "first")
	_check("a point in the second room resolves", builder.room_at(Vector3(15, 0, 5)) == "second")
	_check("a point outside the hull resolves to nothing",
		builder.room_at(Vector3(50, 0, 50)) == "")

	# --- entering the untagged room says nothing -----------------------------
	player.global_position = Vector3(5, 0, 5)
	await process_frame
	await process_frame
	_check("no line for a room with no cue (%d said)" % _said.size(), _said.is_empty())

	# --- loitering in the doorway must NOT burn the cue ----------------------
	# The shared wall is x=10; this is a hair inside `second` but well within the margin.
	player.global_position = Vector3(10.2, 0, 5)
	await process_frame
	await process_frame
	_check("standing in the doorway does not fire the cue (%d said)" % _said.size(),
		_said.is_empty() and not voice.has_spoken("second"))

	# --- walking properly in DOES ---------------------------------------------
	player.global_position = Vector3(15, 0, 5)
	await process_frame
	await process_frame
	_check("entering the room speaks its line (%s)" % str(_said), _said == [&"thingamajig"])
	_check("and the room is marked spoken", voice.has_spoken("second"))

	# --- and only once, however many times you come back ----------------------
	for i in 3:
		player.global_position = Vector3(5, 0, 5)
		await process_frame
		await process_frame
		player.global_position = Vector3(15, 0, 5)
		await process_frame
		await process_frame
	_check("re-entering does not repeat it (%d said)" % _said.size(), _said.size() == 1)

	# --- reset() re-arms it for a fresh run -----------------------------------
	voice.reset()
	player.global_position = Vector3(5, 0, 5)
	await process_frame
	await process_frame
	player.global_position = Vector3(15, 0, 5)
	await process_frame
	await process_frame
	_check("reset re-arms the cue for the next run (%d said)" % _said.size(), _said.size() == 2)

	if _failures.is_empty():
		print("ROOM VOICE TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("ROOM VOICE TEST FAIL")
		quit(1)
