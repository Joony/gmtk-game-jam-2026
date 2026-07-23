extends SceneTree
# Dev utility: writes every synthesised sound to WAVs so they can actually be listened to.
#   godot --headless --path . -s tests/forge_sounds.gd -- <out_dir>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "user://"
	var sounds := {
		"bump_hard": SoundForge.hull_bump(1.0),
		"bump_soft": SoundForge.hull_bump(0.25),
		"klaxon": SoundForge.klaxon(2),
		"click": SoundForge.click(),
		"plug_in": SoundForge.plug_in(),
		"ratchet": SoundForge.ratchet(),
		"tape_tear": SoundForge.tape_tear(),
		"breath": SoundForge.breath(),
		"pod_door_open": SoundForge.pod_door(true),
		"pod_door_close": SoundForge.pod_door(false),
	}
	for name in sounds:
		var stream: AudioStreamWAV = sounds[name]
		var path := "%s/%s.wav" % [dir, name]
		if stream.save_to_wav(path) != OK:
			push_error("could not write %s" % path)
		else:
			print("%-12s %5.2fs  %d samples" % [name, stream.data.size() / 2.0 / 44100.0, stream.data.size() / 2])
	quit(0)
