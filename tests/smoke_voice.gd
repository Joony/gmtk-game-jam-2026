extends SceneTree
# The ship computer's voice, and the recorded klaxon that replaced the generated one.
#
# Three things this has to hold, and each is a way the feature quietly stops working:
#
#   1. Every line in VOICE_LINES resolves to a file that exists. A table of names is only
#      useful if a name is a promise; a typo'd path fails at the moment the fault fires, in
#      a build, with nothing on screen to say so.
#   2. ONE line at a time, queued. Two computer voices over each other is not two alerts, it
#      is neither — and the moment it matters is exactly when several things break together.
#   3. The klaxon the alarm plays is the RECORDED file and it LOOPS. An imported mp3 is
#      one-shot by default, which would leave a critical fault sounding like a passing beep.
#      The generator stays as the fallback and keeps working.
#
# Run: godot --headless --path . -s tests/smoke_voice.gd

const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("voice test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	var audio = root.get_node("/root/Audio")

	# --- Every registered line is real ------------------------------------
	_check("there are voice lines at all", audio.VOICE_LINES.size() > 0)
	for line in audio.VOICE_LINES:
		var path: String = audio.VOICE_LINES[line]
		_check("voice line '%s' points at a file that exists (%s)" % [line, path],
			ResourceLoader.exists(path))
		_check("voice line '%s' loaded" % line, audio._voices_by_name.has(line))

	# --- The klaxon: recorded, and looping ---------------------------------
	var klaxon: AudioStream = audio._sounds.get(&"klaxon")
	_check("the klaxon is the recorded file, not the generated one",
		klaxon is AudioStreamMP3)
	_check("the alarm player holds it", audio._alarm_player.stream == klaxon)
	if klaxon is AudioStreamMP3:
		# set_alarm(true) starts this and nothing stops it until the fault is dealt with.
		_check("and it loops (%.2fs)" % klaxon.get_length(), (klaxon as AudioStreamMP3).loop)
	# The generator is still there and still works — it is the fallback for a missing file.
	var generated := SoundForge.klaxon(1)
	_check("the klaxon generator still produces a looping stream",
		generated != null and generated.data.size() > 0
			and generated.loop_mode == AudioStreamWAV.LOOP_FORWARD)

	# --- One at a time, queued --------------------------------------------
	audio.stop_all()
	audio.say(&"nav_off")
	_check("saying something starts the computer talking", audio._voice_player.playing)
	_check("and it is on the Voice bus, not SFX", audio._voice_player.bus == audio.VOICE_BUS)
	# Non-positional: the computer is on the PA and must sound the same from every room,
	# including from inside a sealed pod the player cannot walk out of.
	_check("the voice is not positional", not (audio._voice_player is AudioStreamPlayer3D))

	var first: AudioStream = audio._voice_player.stream
	audio.say(&"power_off")
	_check("a second line does not cut the first off", audio._voice_player.stream == first)
	_check("it queues instead", audio._voice_queue.size() == 1)
	_check("and is_speaking() covers the queue too", audio.is_speaking())

	# The queue is bounded, and drops the OLDEST — when everything breaks at once the line
	# worth hearing is the one that just happened.
	for _i in 10:
		audio.say(&"life_support")
	_check("the queue is capped (%d)" % audio._voice_queue.size(),
		audio._voice_queue.size() <= audio.VOICE_QUEUE_MAX)
	# Guarded: on a regression that never queues, indexing an empty array kills this
	# coroutine and the suite HANGS instead of failing. Bounded loops are worth nothing if
	# the test can die before reaching one.
	_check("the newest line survives the cap",
		not audio._voice_queue.is_empty()
			and audio._voice_queue[audio._voice_queue.size() - 1] == &"life_support")

	# `interrupt` is for a line that makes the queued ones wrong.
	audio.say(&"oxygen_low", true)
	_check("interrupting clears the queue", audio._voice_queue.is_empty())
	_check("and switches to the new line",
		audio._voice_player.stream == audio._voices_by_name[&"oxygen_low"])

	# An unknown name costs a line, not the run — same contract as play().
	audio.say(&"no_such_line_at_all")
	_check("an unknown line does not crash anything", true)

	# stop_all() has to take the queue with it, or the computer carries on narrating a run
	# that has ended, over the main menu.
	audio.say(&"nav_off")
	audio.say(&"power_off")
	audio.stop_all()
	_check("stop_all silences the computer", not audio._voice_player.playing)
	_check("and empties the queue", audio._voice_queue.is_empty())

	# --- Wired to the real run --------------------------------------------
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	_check("the opening stasis lets go", await Opening.wake(self, game))

	# Every fault that names a line must name one that exists. A silent typo here is the
	# whole feature failing at the only moment it was for.
	var voiced := 0
	for node in game.get_tree().get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var fault := node as Malfunction
		if fault == null or fault.vo_line == &"":
			continue
		voiced += 1
		_check("%s's line '%s' is a real one" % [fault.system_name, fault.vo_line],
			audio.VOICE_LINES.has(fault.vo_line))
	_check("the shipped faults have voice lines (%d)" % voiced, voiced >= 4)

	# Breaking one makes the computer speak, through the real alarm signal.
	audio.stop_all()
	var drive: Malfunction = game.get_node("MainDrive")
	drive.break_now()
	await process_frame
	_check("a fault firing makes the computer announce it", audio.is_speaking())
	_check("and it is that fault's line",
		audio._voice_player.stream == audio._voices_by_name[drive.vo_line])

	# The low-air call fires ONCE. oxygen_changed runs every frame, so a line compared
	# against the threshold rather than latched would repeat for the rest of the run.
	audio.stop_all()
	var run: RunState = game.get_node("Run")
	run.oxygen_remaining = run.oxygen_warning * 0.5
	run.oxygen_changed.emit(run.oxygen_remaining, run.oxygen_total)
	await process_frame
	_check("crossing the air threshold calls it", audio.is_speaking())
	audio.stop_all()
	for _i in 5:
		run.oxygen_remaining -= 1.0
		run.oxygen_changed.emit(run.oxygen_remaining, run.oxygen_total)
		await process_frame
	_check("and does not repeat itself every frame after", not audio.is_speaking())

	if _failures.is_empty():
		print("VOICE TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("VOICE TEST FAIL")
		quit(1)
