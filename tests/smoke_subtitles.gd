extends SceneTree
# Captions for the ship computer's voice lines.
#
# The thing this feature fails at is failing SILENTLY. Every one of these checks exists because
# the broken state looks exactly like the working one from the outside:
#
#   1. A line with no .srt, or an .srt whose name drifted from its mp3, plays with no caption.
#      Nothing errors; a player with the sound off simply never learns what the ship said.
#   2. A cue timed past the end of its clip never shows, and a cue that overlaps the next one
#      makes which caption you see depend on scan order.
#   3. .srt is NOT a Godot resource. Without `include_filter` in export_presets.cfg it is left
#      out of the exported build — so captions work all through development and are gone in
#      the web build, which is the only build anybody plays.
#   4. The pod seals the player in and mutes the Voice bus. A caption still running underneath
#      hands them a line they cannot hear.
#
# Run: godot --headless --path . -s tests/smoke_subtitles.gd

var _failures: Array[String] = []


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("subtitle test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	var audio = root.get_node("/root/Audio")
	var overlay = root.get_node("/root/Subtitles")

	# --- every line is captioned, and the captions fit the audio -----------
	_check("there are voice lines to caption", audio.VOICE_LINES.size() > 0)
	for line in audio.VOICE_LINES:
		var path: String = audio.VOICE_LINES[line]
		var srt: String = path.get_basename() + audio.SUBTITLE_EXT
		_check("'%s' has a caption file (%s)" % [line, srt], FileAccess.file_exists(srt))
		_check("'%s' has a loaded track" % line, audio._subtitles_by_name.has(line))
		if not audio._subtitles_by_name.has(line):
			continue

		var track: SubtitleTrack = audio._subtitles_by_name[line]
		_check("'%s' has at least one cue" % line, track.cues.size() > 0)

		# Ordered, positive, and not on top of each other. Overlapping cues are not a crash,
		# they are a caption that depends on which one the scan happens to reach first.
		var previous_end := -1.0
		for i in track.cues.size():
			var cue: Dictionary = track.cues[i]
			var start := float(cue["start"])
			var end := float(cue["end"])
			_check("%s cue %d is positive length" % [line, i + 1], end > start)
			_check("%s cue %d starts after the last one ends" % [line, i + 1],
				start >= previous_end)
			_check("%s cue %d has text" % [line, i + 1], str(cue["text"]).strip_edges() != "")
			previous_end = end

		# A cue past the end of the clip is a caption nobody ever sees.
		var stream: AudioStream = audio._voices_by_name[line]
		var length := stream.get_length()
		_check("%s's last cue ends inside the clip (%.2fs of %.2fs)" % [
			line, track.last_end(), length], track.last_end() <= length + 0.05)
		# And the reverse: a clip that runs on well past its final caption is a line whose
		# tail was never written down. Half a second of slack for a fade-out.
		_check("%s is captioned to the end (%.2fs of %.2fs)" % [
			line, track.last_end(), length], track.last_end() >= length - 0.6)
		_check("%s's first cue starts at the top of the clip (%.2fs)" % [
			line, float(track.cues[0]["start"])], float(track.cues[0]["start"]) <= 0.5)

	# --- the parser is forgiving -------------------------------------------
	# Every wrinkle here has come off a real subtitling tool at some point: a BOM from Notepad,
	# CRLF from Windows, numberless cues, WebVTT's `.` separator, notes left in the file.
	var awkward := "﻿1\r\n00:00:00,000 --> 00:00:01,500\r\nFirst line\r\nsecond row\r\n\r\n"
	awkward += "00:00:02.000 --> 00:00:03.000\nNo cue number here\n\n"
	awkward += "NOTE this is not a cue\n\n"
	awkward += "3\n00:00:04,000 --> 00:00:04,000\nZero length, dropped\n\n"
	awkward += "4\n00:00:05,000 --> bananas\nUnreadable stamp, dropped\n"
	var parsed := SubtitleTrack.parse(awkward)
	_check("the parser keeps the cues it can read (%d)" % parsed.cues.size(),
		parsed.cues.size() == 2)
	_check("a BOM does not eat the first cue", parsed.text_at(0.5) == "First line\nsecond row")
	_check("a multi-line cue keeps its own line break",
		str(parsed.cues[0]["text"]).contains("\n"))
	_check("a cue with no number still parses", parsed.text_at(2.5) == "No cue number here")
	_check("and a dot decimal separator is read as a comma one",
		float(parsed.cues[1]["start"]) == 2.0)
	_check("a zero-length cue is dropped", parsed.text_at(4.0) == "")
	_check("an unreadable timestamp is dropped", parsed.text_at(5.0) == "")

	# Boundaries: a cue covers its start and stops AT its end, so back-to-back cues never both
	# match and never leave a one-frame hole between them.
	_check("a cue covers its own start", parsed.text_at(0.0) != "")
	_check("and stops at its end", parsed.text_at(1.5) == "")
	_check("the gap between cues is blank", parsed.text_at(1.75) == "")
	_check("before the first cue is blank", parsed.text_at(-1.0) == "")
	_check("after the last cue is blank", parsed.text_at(99.0) == "")
	_check("an empty file parses to nothing", SubtitleTrack.parse("").cues.is_empty())
	_check("a missing file is null, not a crash",
		SubtitleTrack.load_srt("res://no/such/file.srt") == null)

	# --- captions follow the voice -----------------------------------------
	audio.stop_all()
	var seen: Array[String] = []
	audio.subtitle_changed.connect(func(text: String) -> void: seen.append(text))

	var intro_track: SubtitleTrack = audio._subtitles_by_name[&"intro"]
	var first_cue := str(intro_track.cues[0]["text"])
	audio.say(&"intro")
	_check("saying a line puts its first caption up on the same frame",
		audio.subtitle == first_cue)
	_check("and announces it", seen.has(first_cue))

	# The caption is read off the stream's position, so asking the track directly is asking the
	# same question the game asks — this is what pins the text to the audio rather than to a
	# clock that could drift.
	var late := str(intro_track.cues[intro_track.cues.size() - 1]["text"])
	_check("a later moment in the same line reads a later caption",
		intro_track.text_at(intro_track.last_end() - 0.1) == late and late != first_cue)

	# Interrupting swaps the caption with the voice. A caption left over from a line that was
	# cut off is worse than none: it is the computer's last emergency, still on screen, while
	# it describes a new one.
	var nav_first := str((audio._subtitles_by_name[&"nav_off"] as SubtitleTrack).cues[0]["text"])
	audio.say(&"nav_off", true)
	_check("interrupting swaps the caption too", audio.subtitle == nav_first)

	# --- the pod's shell covers the captions too ----------------------------
	audio.set_sealed(true)
	_check("sealing the pod takes the caption with the voice", audio.subtitle == "")
	audio.set_sealed(false)
	_check("and unsealing brings it back", audio.subtitle == nav_first)

	# --- and nothing survives the run ending --------------------------------
	audio.stop_all()
	_check("stop_all clears the caption", audio.subtitle == "")
	_check("and says so, rather than leaving the display holding the last one",
		seen[seen.size() - 1] == "")

	# --- the overlay draws it ----------------------------------------------
	_check("the Subtitles overlay is an autoload", overlay != null)
	_check("it sits above the HUD and below the pause menu",
		overlay.layer > 35 and overlay.layer < 50)
	var label: Label = overlay.get_node("%Line")
	audio.say(&"power_off")
	_check("the overlay shows what the computer is saying", label.text == audio.subtitle)
	_check("and is visible while it does", label.visible)
	_check("the caption is not empty", label.text != "")

	overlay.enabled = false
	_check("turning captions off hides them", not label.visible)
	overlay.enabled = true
	_check("turning them back on picks up the line already playing",
		label.visible and label.text == audio.subtitle)

	audio.stop_all()
	_check("and the overlay hides when the computer stops", not label.visible)

	# --- the exported build gets the files ----------------------------------
	# .srt is not a Godot resource, so `export_filter="all_resources"` does NOT sweep it up.
	# Without this line in the preset every caption works in the editor and none of them exist
	# in the web build — the one that gets played.
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	_check("export_presets.cfg exists", presets != "")
	for preset_line in presets.split("\n"):
		if not preset_line.begins_with("include_filter="):
			continue
		_check("the export preset ships the .srt files (%s)" % preset_line.strip_edges(),
			preset_line.contains("*.srt"))

	if _failures.is_empty():
		print("SUBTITLE TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("SUBTITLE TEST FAIL")
		quit(1)
