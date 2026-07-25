class_name RoomVoice
extends Node

# The ship computer reacting to WHERE the player is: walk into a room for the first time and it
# says its piece, once.
#
# Built for the opening tutorial. The run starts on a fault that is already broken, and the
# player has to be told what to do about it at the moment it is in front of them — not while
# they are still in the pod, where the instruction is abstract and unactionable, and not on a
# timer, which fires whether they found the room or not. Arriving in the room IS the cue.
#
# WHY THIS IS NOT AN Area3D IN THE SCENE. Two reasons. The rooms are authored in code and built
# at runtime, so there is no editor-time box to attach a trigger to; and a trigger volume would
# have to be kept in sync by hand with rectangles that move every time the drawing is redrawn.
# Asking RoomBuilder which room a point is in cannot drift, because it reads the same rects the
# geometry was built from.
#
# One line per room, said once per run. `say()` queues rather than interrupts (see
# AudioController.say), so a line triggered while the computer is already talking waits its
# turn instead of clipping.

## Emitted when the player crosses into a different room. `from` is "" on the first reading and
## when leaving the hull. Useful well beyond the tutorial — first-visit hooks, music, telemetry.
signal room_changed(from: String, to: String)

## Emitted when a room's cue is actually SPOKEN — once per room per run. Distinct from
## `room_changed`, which fires on every crossing: a test (or a subtitle log) wants to know what
## the computer said, not where the player walked.
signal spoke(room_id: String, line: StringName)

## room id -> voice line, spoken the first time the player enters that room. Data, not code:
## a new cue is an entry here, and an entry naming a room that does not exist is inert.
@export var lines: Dictionary = {}

## Needs to be this far INSIDE a room before it counts as entered, in metres. A doorway sits on
## the shared wall line, so without it a player loitering in a door would flip between the two
## rooms every frame and burn the cue on a near-miss.
@export var margin: float = 0.6

var _builder: RoomBuilder = null
var _occupant: Node3D = null
var _current: String = ""
var _spoken: Dictionary = {}
var _enabled: bool = true


## Point it at the ship and whoever is walking around it. Without this it does nothing, which
## is the right behaviour for a test that builds a bare RoomBuilder.
func bind(builder: RoomBuilder, occupant: Node3D) -> void:
	_builder = builder
	_occupant = occupant
	_current = ""


## Stop reacting — for the run ending, or a cutscene.
func set_enabled(on: bool) -> void:
	_enabled = on


## Forget what has been said, so a fresh run speaks its cues again.
func reset() -> void:
	_spoken.clear()
	_current = ""


## Has this room's cue already been used this run?
func has_spoken(room_id: String) -> bool:
	return _spoken.has(room_id)


func _process(_delta: float) -> void:
	if not _enabled or _builder == null or _occupant == null:
		return
	if not is_instance_valid(_builder) or not is_instance_valid(_occupant):
		return

	var here := _builder.room_at(_occupant.global_position)
	if here == _current:
		return
	# Only accept a change once the player is properly inside, so standing in a doorway does
	# not toggle. Leaving the hull entirely (here == "") is accepted immediately.
	if here != "" and not _well_inside(here):
		return

	var previous := _current
	_current = here
	room_changed.emit(previous, here)

	if here == "" or _spoken.has(here) or not lines.has(here):
		return
	_spoken[here] = true
	var line: StringName = lines[here]
	spoke.emit(here, line)
	_speak(line)


## Say a line through the ship computer.
##
## Resolved by NODE PATH rather than through the `Audio` global. A `-s` test script loads its
## dependencies before the autoloads are registered, so a compile-time reference to `Audio`
## here fails with "Identifier not found" the moment a suite does `RoomVoice.new()` — even
## though the same reference is fine in game.gd, which is loaded later as part of a scene. The
## existing suites reach the controller the same way (`root.get_node("/root/Audio")`).
func _speak(line: StringName) -> void:
	var audio := get_node_or_null(^"/root/Audio")
	if audio == null:
		return
	audio.say(line)


## True when the position is at least `margin` inside the room's own rect.
func _well_inside(room_id: String) -> bool:
	for room in _builder.rooms:
		if room.id != room_id:
			continue
		var scale := _builder.tile_size
		var x0 := float(room.rect.position.x) * scale + margin
		var z0 := float(room.rect.position.y) * scale + margin
		var x1 := x0 + float(room.rect.size.x) * scale - margin * 2.0
		var z1 := z0 + float(room.rect.size.y) * scale - margin * 2.0
		var at := _occupant.global_position
		return at.x >= x0 and at.x <= x1 and at.z >= z0 and at.z <= z1
	return false
