extends SceneTree
# Regression test for the pod's two one-shots: a small CLICK on climbing in, and a POP the
# instant the door starts to swing open on waking.
#
# The pop used to fire from StasisPod.entered — the moment the player climbs in — which is a
# full second before the door moves, so getting in sounded like a bare pop, a long gap, and
# then the door closing. It belongs to the door OPENING, where it reads as the seal breaking.
#
# The pop must also be MIXED ABOVE the door sound it plays over: pod_open reaches ~0.84
# amplitude within 10 ms and holds ~0.75 for 300 ms, so a pop at the same level is masked and
# no transient is audible at all — which is exactly how it failed the first time.
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

	# --- Waking. The door swings open, and the pop rides it.
	game._run.exit_stasis()
	for _i in 20:
		await process_frame
		if _open_seen and _is_playing(audio, &"plug"):
			plug_with_open = true
			break
	_check("the door opened on waking", _open_seen)
	# Loud enough to cut through the door sound it lands on top of, or it may as well not play.
	_check(
		"the pop is mixed above the door sound (%.1f dB vs -2.0)" % game.POD_POP_DB,
		game.POD_POP_DB > -2.0
	)
	# 20 frames is a third of a second: "right at the start of opening", not somewhere in the
	# middle of the 0.9 s swing.
	_check("the pop plays at the start of the door opening", plug_with_open)

	if _failures.is_empty():
		print("POD AUDIO TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("POD AUDIO TEST FAIL")
		quit(1)
