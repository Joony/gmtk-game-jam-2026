extends SceneTree
# Regression test for the pod's two one-shots: a small CLICK on climbing in, and the cork POP
# the instant the door starts to swing open on waking.
#
# The pop used to fire from StasisPod.entered — the moment the player climbs in — which is a
# full second before the door moves, so getting in sounded like a bare pop, a long gap, and
# then the door closing. It belongs to the start of the door OPENING, as the seal lets go.
#
# The pop must also LEAD the door sound rather than play under it. pod_open is at ~0.84
# amplitude within 10 ms and holds ~0.75 for 300 ms, and the cork's 150 Hz seat sits inside
# the servo's 188-262 Hz range, so playing them together masks the pop however loud it is
# mixed — that is exactly how this failed the first time round. So the ordering below is the
# point of the test, not an incidental detail.
#
# This watches the positional voices for the plug stream rather than trusting the wiring, so
# it fails if the sound is reconnected to the wrong event OR silently stops being played. Run:
#   godot --headless --path . -s tests/smoke_pod_audio.gd

var _failures: Array[String] = []
# A member, not a local: a GDScript lambda captures locals BY VALUE, so a signal handler
# assigning to a captured local updates only its own copy and the test reads false forever.
var _open_seen := false


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


## True while any positional voice is playing the named sound.
func _is_playing(audio, name: StringName) -> bool:
	var stream: AudioStream = audio._sounds.get(name)
	for player in audio._voices_3d:
		if player.stream == stream and player.playing:
			return true
	return false


func _run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame

	var audio = root.get_node("Audio")
	_check("the plug sound exists", audio._sounds.has(&"plug"))

	var plug_with_open := false
	game._pod.door_moved.connect(func(opening: bool) -> void:
		if opening:
			_open_seen = true)

	# --- Climbing in. The door is already open (every player pod starts that way), so the
	# only pod-door sound here is the close; the clunk must NOT appear.
	var plug_during_entry := false
	var click_during_entry := false
	var close_during_entry := false
	game._on_pod_used(null)
	for _i in 900:
		await process_frame
		if _is_playing(audio, &"plug"):
			plug_during_entry = true
		if _is_playing(audio, &"click"):
			click_during_entry = true
		if _is_playing(audio, &"pod_close"):
			close_during_entry = true
		if game._run.in_stasis and game._pod_phase == game.PodPhase.IN:
			break
	_check("player reached stasis", game._run.in_stasis)
	_check("no pop while climbing in", not plug_during_entry)
	_check("climbing in makes a click", click_during_entry)
	# Moving the clunk must not have taken the door's own sound with it.
	_check("the door still closes audibly", close_during_entry)

	# --- Waking. The pop fires first, and the door sound comes in AFTER it.
	var plug_frame := -1
	var open_frame := -1
	var frame := 0
	game._run.exit_stasis()
	for _i in 400:
		await process_frame
		frame += 1
		if plug_frame < 0 and _is_playing(audio, &"plug"):
			plug_frame = frame
		if open_frame < 0 and _is_playing(audio, &"pod_open"):
			open_frame = frame
		if plug_frame >= 0 and open_frame >= 0:
			break
	_check("the door opened on waking", _open_seen)
	_check("the pop plays when the door starts opening", plug_frame >= 0)
	_check("the door's own sound still plays", open_frame >= 0)
	# The ordering IS the fix: same frame means they are mixed together and the pop vanishes.
	_check(
		"the pop leads the door sound (pop f%d, door f%d)" % [plug_frame, open_frame],
		plug_frame >= 0 and open_frame > plug_frame
	)
	_check(
		"the lead is a real gap, not a rounding artefact (%.3fs)" % game.POD_POP_LEAD,
		game.POD_POP_LEAD >= 0.05
	)

	if _failures.is_empty():
		print("POD AUDIO TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("POD AUDIO TEST FAIL")
		quit(1)
