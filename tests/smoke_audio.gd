extends SceneTree
# Audio: the generated effects, the bus layout, and — the part that actually breaks — that
# the game's events reach the controller at all.
#
# Wiring is the whole risk here. A signal connected to the wrong name, or to a system that
# never emits, fails silently and sounds exactly like a game with no audio. So rather than
# assert that `play()` was called, these drive the REAL RunState and watch what the
# controller was asked to do.
#
# Run: godot --headless --path . -s tests/smoke_audio.gd

const WATCHDOG_SECONDS := 90.0

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	root.call_deferred("add_child", _Runner.new(self))


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		failures.append(label)
		print("  FAIL %s" % label)


## Peak sample and duration of a generated stream, straight out of the byte data.
func measure(stream: AudioStreamWAV) -> Dictionary:
	var bytes := stream.data
	var count := bytes.size() / 2
	var peak := 0
	var sum_squares := 0.0
	for i in count:
		var value: int = bytes.decode_s16(i * 2)
		peak = maxi(peak, absi(value))
		sum_squares += float(value) * float(value)
	return {
		"samples": count,
		"seconds": float(count) / float(stream.mix_rate),
		"peak": float(peak) / 32768.0,
		"rms": sqrt(sum_squares / maxf(count, 1)) / 32768.0,
	}


class _Runner:
	extends Node

	var suite: SceneTree


	func _init(owner_suite: SceneTree) -> void:
		suite = owner_suite


	func _ready() -> void:
		_watchdog()
		_run()


	func _watchdog() -> void:
		await suite.create_timer(WATCHDOG_SECONDS).timeout
		if is_inside_tree():
			push_error("smoke_audio: watchdog fired")
			suite.quit(1)


	func _run() -> void:
		print("== smoke_audio ==")
		_test_buses()
		_test_generated()
		_test_repair_routes_sound_different()
		await _test_wiring()
		await _test_positional()

		print("-- %d checks, %d failures --" % [suite.checks, suite.failures.size()])
		for failure in suite.failures:
			print("   FAILED: %s" % failure)
		suite.quit(1 if suite.failures.size() > 0 else 0)


	func _test_buses() -> void:
		print("[bus layout]")
		# Without these the options slider has nothing to hold and every sound lands on Master.
		suite.check(AudioServer.get_bus_index(&"Music") > 0, "a Music bus exists")
		suite.check(AudioServer.get_bus_index(&"SFX") > 0, "an SFX bus exists")

		var controller := suite.root.get_node_or_null("/root/Audio")
		suite.check(controller != null, "the Audio autoload is registered")

		# The options menu will drive these, so they have to round-trip.
		controller.set_bus_volume(&"SFX", 0.5)
		suite.check(absf(controller.get_bus_volume(&"SFX") - 0.5) < 0.02,
			"bus volume round-trips (got %.3f)" % controller.get_bus_volume(&"SFX"))
		controller.set_bus_volume(&"SFX", 0.0)
		suite.check(controller.get_bus_volume(&"SFX") == 0.0,
			"a slider at zero is silent, not just quiet")
		controller.set_bus_volume(&"SFX", 1.0)


	func _test_generated() -> void:
		print("[generated effects]")
		var expected := {
			&"door_open": {"min_s": 0.1, "max_s": 4.0},
			&"door_close": {"min_s": 0.1, "max_s": 4.0},
			&"bump": {"min_s": 1.0, "max_s": 2.0},
			&"klaxon": {"min_s": 0.5, "max_s": 2.0},
			&"click": {"min_s": 0.01, "max_s": 0.2},
			&"plug": {"min_s": 0.05, "max_s": 0.5},
			&"ratchet": {"min_s": 0.2, "max_s": 1.0},
			&"tape": {"min_s": 0.1, "max_s": 1.0},
			&"breath": {"min_s": 0.5, "max_s": 2.0},
		}
		var controller := suite.root.get_node_or_null("/root/Audio")
		for name in expected:
			var any_stream: AudioStream = controller._sounds.get(name)
			if any_stream == null:
				suite.check(false, "sound '%s' is loaded" % name)
				continue
			# The door sounds came from files, so they are MP3s and the byte-level
			# measurements below only apply to the generated WAVs.
			var stream := any_stream as AudioStreamWAV
			if stream == null:
				suite.check(any_stream.get_length() >= expected[name]["min_s"]
						and any_stream.get_length() <= expected[name]["max_s"],
					"%s is %.2fs, within %.2f-%.2f" % [name, any_stream.get_length(),
						expected[name]["min_s"], expected[name]["max_s"]])
				continue
			var m: Dictionary = suite.measure(stream)
			suite.check(m["samples"] > 0, "%s has samples (%d)" % [name, m["samples"]])
			suite.check(m["seconds"] >= expected[name]["min_s"] and m["seconds"] <= expected[name]["max_s"],
				"%s is %.2fs, within %.2f-%.2f" % [name, m["seconds"], expected[name]["min_s"], expected[name]["max_s"]])
			# Normalisation is the guarantee that layering can never clip.
			suite.check(m["peak"] <= 0.90, "%s does not clip (peak %.3f)" % [name, m["peak"]])
			suite.check(m["rms"] > 0.001, "%s is not silence (rms %.4f)" % [name, m["rms"]])

		# A klaxon that clicks every loop is worse than no klaxon.
		var klaxon: AudioStreamWAV = controller._sounds[&"klaxon"]
		suite.check(klaxon.loop_mode == AudioStreamWAV.LOOP_FORWARD, "the klaxon is set to loop")
		var count := klaxon.data.size() / 2
		var first := klaxon.data.decode_s16(0)
		var last := klaxon.data.decode_s16((count - 1) * 2)
		suite.check(absi(first - last) < 400,
			"and its loop seam is continuous (|first-last| = %d of 32768)" % absi(first - last))


	func _test_repair_routes_sound_different() -> void:
		print("[the two repair routes must not sound alike]")
		var controller := suite.root.get_node_or_null("/root/Audio")
		var ratchet: Dictionary = suite.measure(controller._sounds[&"ratchet"])
		var tape: Dictionary = suite.measure(controller._sounds[&"tape"])
		# Not a spectral test — that lives in the analysis script — but the two must at least
		# not be the same object, and must differ audibly in shape.
		suite.check(controller._sounds[&"ratchet"] != controller._sounds[&"tape"],
			"they are different streams")
		suite.check(absf(ratchet["seconds"] - tape["seconds"]) > 0.005 or absf(ratchet["rms"] - tape["rms"]) > 0.01,
			"and differ in length or level (%.2fs/%.3f vs %.2fs/%.3f)"
				% [ratchet["seconds"], ratchet["rms"], tape["seconds"], tape["rms"]])


	## The part that silently rots: does anything actually CALL the controller?
	func _test_wiring() -> void:
		print("[game events reach the audio controller]")
		var controller := suite.root.get_node_or_null("/root/Audio")
		var game: Node3D = load("res://scenes/game.tscn").instantiate()
		suite.root.add_child(game)
		suite.current_scene = game
		await suite.process_frame
		game.start_game()
		await suite.process_frame

		var run: RunState = game.get_node("Run")

		suite.check(controller.music_state == controller.Music.NORMAL,
			"starting the run asks for the NORMAL track")

		# A critical fault should move the music AND fire the alarm.
		var drive: Malfunction = game.get_node("MainDrive")
		drive.break_now()
		await suite.process_frame
		suite.check(controller.music_state == controller.Music.PANIC,
			"a CRITICAL fault switches the music to PANIC")

		# Repairing it should bring the music back and play the right route's sound.
		drive.repair(true, run.distance_remaining)
		await suite.process_frame
		# The dwell guard means the change is queued rather than immediate — that is the
		# behaviour we want, so assert the queue rather than the instant switch.
		suite.check(controller.music_state == controller.Music.PANIC
				and controller._music_pending == controller.Music.NORMAL,
			"clearing it queues the change instead of stuttering the crossfade")

		# Breathing follows the oxygen, and must stop dead in the pod.
		run.oxygen_remaining = run.oxygen_warning * 0.25
		run.oxygen_changed.emit(run.oxygen_remaining, run.oxygen_total)
		await suite.process_frame
		suite.check(controller._breath_intensity > 0.5,
			"low air starts the breathing (intensity %.2f)" % controller._breath_intensity)

		run.enter_stasis()
		run.oxygen_changed.emit(run.oxygen_remaining, run.oxygen_total)
		await suite.process_frame
		suite.check(controller._breath_intensity == 0.0,
			"and it stops in the pod — you are not gasping through a sealed lid")
		run.exit_stasis()

		# Ending the run must silence everything, or the panic track plays over the summary.
		run.oxygen_remaining = 0.0
		run._end(false)
		await suite.process_frame
		suite.check(controller.music_state == controller.Music.NONE, "the end of a run stops the music")
		suite.check(controller._breath_intensity == 0.0, "and the breathing")

		game.free()


	## Positional audio has a silent failure mode that is easy to ship: if the 3D voices are
	## not in the same World3D as the listener, every one of them plays into nothing and the
	## game simply has no door or repair sounds. Nothing errors.
	func _test_positional() -> void:
		print("[positional audio]")
		var controller := suite.root.get_node_or_null("/root/Audio")
		var game: Node3D = load("res://scenes/game.tscn").instantiate()
		suite.root.add_child(game)
		suite.current_scene = game
		await suite.process_frame
		game.start_game()
		await suite.process_frame

		var camera: Camera3D = game.get_node("Player/CameraRig/Camera3D")
		suite.check(controller._voices_3d.size() > 0, "there is a 3D voice pool")
		suite.check(controller._voices_3d[0].get_world_3d() == camera.get_world_3d(),
			"the 3D voices share the listener's World3D — otherwise they are inaudible")

		# Doors are the reason this exists. They are built at runtime, so this also proves
		# the connections were made after the Ship node had finished building them.
		var doors := suite.root.get_tree().get_nodes_in_group(RoomBuilder.GROUP_DOOR)
		suite.check(doors.size() > 0, "the ship has doors (%d)" % doors.size())

		var door := doors[0] as SlidingDoor
		door.open()
		await suite.process_frame
		var want_open: AudioStream = controller._sounds.get(&"door_open")
		suite.check(want_open != null, "the door_open sound is loaded at all")
		var heard_at := Vector3.INF
		for voice in controller._voices_3d:
			# `want_open != null` matters: an unused voice's stream is ALSO null, so without
			# it a missing sound matches every idle voice and the check passes on nothing.
			if want_open != null and voice.stream == want_open:
				heard_at = voice.global_position
		suite.check(heard_at != Vector3.INF, "opening a door plays the door_open sound")
		suite.check(heard_at != Vector3.INF and heard_at.distance_to(door.global_position) < 0.01,
			"and plays it AT the door, not at the listener")

		door.close()
		await suite.process_frame
		var want_close: AudioStream = controller._sounds.get(&"door_close")
		var closed := false
		for voice in controller._voices_3d:
			if want_close != null and voice.stream == want_close:
				closed = true
		suite.check(closed, "closing it plays the different door_close sound")

		# A repair is the other thing that must be locatable.
		var drive: Malfunction = game.get_node("MainDrive")
		drive.break_now()
		drive.repair(true, 50.0)
		await suite.process_frame
		var want_ratchet: AudioStream = controller._sounds.get(&"ratchet")
		var ratchet_at := Vector3.INF
		for voice in controller._voices_3d:
			if want_ratchet != null and voice.stream == want_ratchet:
				ratchet_at = voice.global_position
		suite.check(ratchet_at != Vector3.INF
				and ratchet_at.distance_to(drive.global_position) < 0.01,
			"a repair is heard at its own panel, across the ship")

		# The alarm must NOT be positional: it is the whole ship, and placing it would make
		# it quieter depending on which way the player happened to be facing.
		suite.check(controller._sounds.has(&"klaxon"), "the klaxon exists")
		var want_klaxon: AudioStream = controller._sounds.get(&"klaxon")
		var klaxon_placed := false
		for voice in controller._voices_3d:
			if want_klaxon != null and voice.stream == want_klaxon:
				klaxon_placed = true
		suite.check(not klaxon_placed, "the klaxon is ship-wide, never placed in the room")

		game.free()
