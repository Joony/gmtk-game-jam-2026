extends SceneTree
# The two INSTRUCTION lines stop when the instruction is obeyed.
#
# Both are told to the player during the opening:
#   1. how to fix the opening fault — triggered by walking into the room it is in
#   2. go back to cryo — triggered by clearing it
#
# Both are long enough to outlast a player who acts promptly, and a voice still explaining a
# task that is done sounds like a computer that has not noticed. So each is cancelled by the
# thing it asked for. The TRIGGERS already existed (RoomVoice, _maybe_say_return_to_cryo); what
# is under test here is the stopping.
#
# Run: godot --headless --path . -s tests/smoke_instruction_voice.gd

const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []
var _game: Node
## The Audio autoload. Reached by path rather than by name: an autoload is not in scope for a
## `-s` SceneTree script, which is how every other suite here gets at it.
var _audio: Node


func _init() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("instruction voice test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_audio = root.get_node_or_null("/root/Audio")
	_check("the Audio autoload is registered", _audio != null)
	if _audio == null:
		return _finish()
	_check("the opening stasis lets go", await Opening.wake(self, _game))
	await _frames(6)

	await _test_stop_saying_is_surgical()
	await _test_tutorial_stops_when_fixed()
	await _test_cryo_line_stops_in_the_pod()

	_finish()


## The primitive, on its own. `say(interrupt: true)` clears the WHOLE queue; this must remove
## ONE line and leave everything else the computer had to say intact — a klaxon-worthy
## announcement that happened to land behind the tutorial still needs saying.
func _test_stop_saying_is_surgical() -> void:
	_audio.stop_all()
	await _frames(2)
	_audio.say(&"nav_off")
	_audio.say(&"return_to_cryo")
	_audio.say(&"life_support")
	await _frames(2)
	_check("the computer is talking", _audio.is_speaking())
	_check("and it is saying the first line (%s)" % _audio.speaking_line(),
		_audio.speaking_line() == &"nav_off")

	# Cancel one that is QUEUED, not playing.
	_check("cancelling a queued line reports that it did something",
		_audio.stop_saying(&"return_to_cryo"))
	_check("...and the line playing is untouched (%s)" % _audio.speaking_line(),
		_audio.speaking_line() == &"nav_off")
	_check("...and the rest of the queue survives", _audio.is_speaking())

	# Cancel the one that IS playing.
	_check("cancelling the playing line reports that it did something",
		_audio.stop_saying(&"nav_off"))
	_check("...and it stops (%s)" % _audio.speaking_line(), _audio.speaking_line() != &"nav_off")
	# life_support is still queued, so the computer has not been silenced altogether.
	_check("...but what was behind it is still to come", _audio.is_speaking())

	_check("cancelling a line nobody is saying is a no-op",
		not _audio.stop_saying(&"asteroids"))
	_audio.stop_all()
	await _frames(2)


## 1. The lesson stops when the fault it teaches is repaired.
func _test_tutorial_stops_when_fixed() -> void:
	var run: RunState = _game.get_node("Run")
	var fault: Malfunction = null
	for node in get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var m := node as Malfunction
		if m != null and m.starts_broken:
			fault = m
	_check("the run opens on a fault to be taught about", fault != null)
	if fault == null:
		return

	# Said the way the game says it — walking into the room, not by calling Audio directly.
	var voice: RoomVoice = _game.get_node("RoomVoice")
	var player: CharacterBody3D = _game.get_node("Player")
	player.global_position = fault.global_position + Vector3(0.0, 0.5, 2.0)
	await _frames(10)
	_check("walking in starts the lesson (%s)" % _audio.speaking_line(),
		_audio.speaking_line() == _tutorial_line())
	if _audio.speaking_line() != _tutorial_line():
		return

	fault.repair(true, run.distance_remaining)
	await _frames(4)
	_check("fixing it stops the lesson mid-sentence (%s)" % _audio.speaking_line(),
		_audio.speaking_line() != _tutorial_line())


## 2. "Go back to cryo" stops once they are in the pod.
func _test_cryo_line_stops_in_the_pod() -> void:
	var run: RunState = _game.get_node("Run")
	# Clear the ship, which is what earns the line.
	for node in get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var m := node as Malfunction
		if m != null and m.is_active:
			m.repair(true, run.distance_remaining)
	await _frames(6)
	_check("clearing the ship earns the return-to-cryo line (%s)" % _audio.speaking_line(),
		_audio.speaking_line() == &"return_to_cryo")
	if _audio.speaking_line() != &"return_to_cryo":
		return

	run.enter_stasis()
	await _frames(4)
	_check("climbing into the pod stops it (%s)" % _audio.speaking_line(),
		_audio.speaking_line() != &"return_to_cryo")


## game.gd has no class_name, so the constant is read off the instance rather than off the
## type. Read rather than duplicated as a literal: a test that hard-codes &"thingamajig" would
## keep passing if the game's own line changed underneath it.
func _tutorial_line() -> StringName:
	return _game.TUTORIAL_LINE


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("INSTRUCTION VOICE TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("INSTRUCTION VOICE TEST FAIL")
		quit(1)
