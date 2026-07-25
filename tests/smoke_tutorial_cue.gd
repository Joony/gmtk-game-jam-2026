extends SceneTree
# The opening tutorial, wired up in the real game scene.
#
# smoke_room_voice.gd already proves the TRIGGER — enter a room once, get its line, and a
# doorway does not count. This suite proves the AIM: that the one cue the game ships with is
# pointed at the room holding the fault the run opens on, and that walking in there says it.
#
# Deliberately does not name a room. The tutorial line follows the opening fault (Game
# _wire_room_voice looks the room up from whichever Malfunction has `starts_broken`), so
# hard-coding "bridge" here would turn a suite about the tutorial into a suite about where the
# fault currently happens to sit — and it would go red the moment the fault is moved, which is
# precisely the change this wiring exists to survive.
#
# Run: godot --headless --path . -s tests/smoke_tutorial_cue.gd

const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []
var _said: Array[StringName] = []


func _init() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("tutorial cue test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame

	var voice: RoomVoice = game.get_node_or_null("RoomVoice")
	_check("the game builds a RoomVoice", voice != null)
	if voice == null:
		return _finish()
	voice.spoke.connect(func(_room: String, line: StringName) -> void:
		_said.append(line))

	# --- the run really does open on a fault ---------------------------------
	var opening: Malfunction = game._opening_fault()
	_check("something starts broken, or there is no tutorial", opening != null)
	if opening == null:
		return _finish()

	var ship: RoomBuilder = game.get_node("Ship")
	var fault_room := ship.room_at(opening.global_position)
	_check("the opening fault (%s) is inside a room, not in a corridor gap or the hull (%s)"
		% [opening.system_name, fault_room], fault_room != "")

	# --- and the cue is aimed at exactly that room ---------------------------
	_check("the tutorial line is on the opening fault's room (%s -> %s)"
		% [fault_room, str(voice.lines)],
		voice.lines.size() == 1 and voice.lines.get(fault_room, &"") == &"thingamajig")

	# --- nothing said while the player is still asleep in the pod ------------
	_check("the cold open stays silent (%d said)" % _said.size(), _said.is_empty())
	_check("the opening stasis lets go", await Opening.wake(self, game))
	_check("and waking up alone does not spend the cue (%d said)" % _said.size(),
		_said.is_empty() and not voice.has_spoken(fault_room))

	# --- walking in is what says it ------------------------------------------
	# Stood in the MIDDLE of the fault's room, not at the fault itself. A repair panel is
	# mounted flush on a wall, so the fault's own position sits a few centimetres inside the
	# room — well within RoomVoice's doorway margin, and correctly not counted as having
	# entered anything. The player walks in and then up to the panel; they are never inside
	# the wall it is bolted to.
	#
	# Moved rather than walked: this suite is about the wiring, and smoke_player already owns
	# the question of whether the player can get anywhere.
	var player: CharacterBody3D = game.get_node("Player")
	var inside := _centre_of(ship, fault_room)
	var outside := Vector3(0.0, player.global_position.y, 0.0)  # the pod, at the far end
	player.global_position = Vector3(inside.x, player.global_position.y, inside.z)
	await process_frame
	await process_frame
	_check("arriving in the fault's room says the tutorial line (%s)" % str(_said),
		_said == [&"thingamajig"])

	# ...and it is a lesson, not a nag.
	for i in 3:
		player.global_position = outside
		await process_frame
		await process_frame
		player.global_position = Vector3(inside.x, player.global_position.y, inside.z)
		await process_frame
		await process_frame
	_check("and only ever once (%d said)" % _said.size(), _said.size() == 1)

	_finish()


## World-space centre of a room, read off the same rects the geometry was built from.
func _centre_of(ship: RoomBuilder, room_id: String) -> Vector3:
	for room in ship.rooms:
		if room.id != room_id:
			continue
		var centre := Vector2(room.rect.position) + Vector2(room.rect.size) * 0.5
		return Vector3(centre.x * ship.tile_size, 0.0, centre.y * ship.tile_size)
	return Vector3.ZERO


func _finish() -> void:
	if _failures.is_empty():
		print("TUTORIAL CUE TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("TUTORIAL CUE TEST FAIL")
		quit(1)
