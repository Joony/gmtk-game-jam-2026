extends Node
# Autoload "Audio": one place that owns every sound the game makes.
#
# Two halves that behave completely differently:
#
#   MUSIC   three long tracks, only ever one playing, crossfaded between states. These are
#           real files and may not exist yet — the controller must not care. A missing track
#           is logged once and the game carries on in silence.
#   SFX     short bursts, synthesised by SoundForge at startup, several at once. A fixed pool
#           of players rather than a node per sound, so a burst of alarms cannot spawn a
#           dozen nodes on a frame the game is already busy.
#
# Callers name a sound; they never touch a stream or a player. That is what lets the
# low-oxygen breathing change its own rate, and what stops a sound played from four places
# drifting into four slightly different volumes.

enum Music { NONE, NORMAL, PANIC, STASIS, LOW_OXYGEN }

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const VOICE_BUS := &"Voice"

## Real files, and the only part of the audio that is not generated. Delivered as .wav but
## transcoded to Ogg Vorbis (see tools + the .wav masters alongside): 115 MB of WAV would
## have sunk the web export, and Vorbis loops with a single `loop` flag.
const MUSIC_PATHS := {
	Music.NORMAL: "res://assets/audio/lost_in_space.ogg",
	Music.PANIC: "res://assets/audio/red_alert.ogg",
	Music.STASIS: "res://assets/audio/klaatu_barada_nikto.ogg",
	Music.LOW_OXYGEN: "res://assets/audio/crash_landing.ogg",
}

## How long a crossfade takes.
const FADE_TIME := 1.4
## How long the score must stay calm before it is allowed to relax back to NORMAL. Applies
## to de-escalation ONLY — see play_music().
const MIN_DWELL := 2.5
const SFX_VOICES := 8
## Separate pool for positional sound. Doors are the heavy user — walking the ship opens and
## shuts several, and each one is two sounds.
const SFX_3D_VOICES := 8
## Beyond this a door in the engine room is inaudible from the cryo bay, which is the point.
const SFX_3D_RANGE := 26.0

## Sounds that are real files rather than synthesised. Doors came from GMTK 2025's `Sounds/`
## folder, where they were sitting unused — nothing in that project ever played them.
##
## These are loaded AFTER _forge() and share its dictionary, so a name here OVERRIDES the
## generated sound of the same name. That is how the recorded klaxon replaces
## SoundForge.klaxon() without the generator going anywhere: the synth version stays the
## fallback for a missing file, and stays the thing the sound tests measure.
const FILE_SOUNDS := {
	&"door_open": "res://assets/audio/sfx/door_open.mp3",
	&"door_close": "res://assets/audio/sfx/door_close.mp3",
	&"klaxon": "res://assets/audio/sfx/Klaxon.mp3",
}

## The ship computer's voice lines, named by what they MEAN rather than by which take they
## came from — a caller asks for `life_support` and never learns the filename.
##
## Wiring a line to an event is DATA, not code: Malfunction has a `vo_line` export, so giving
## a fault a voice is one field in game.tscn. See say().
const VOICE_LINES := {
	# Wired to events today.
	&"intro": "res://assets/audio/voiceover/CD_Intro.mp3",
	&"oxygen_low": "res://assets/audio/voiceover/CD_OxygenLow.mp3",
	&"life_support": "res://assets/audio/voiceover/CD_LifeSupportFailing.mp3",
	&"nav_off": "res://assets/audio/voiceover/CD_NavOff.mp3",
	&"power_off": "res://assets/audio/voiceover/CD_PowerOff.mp3",
	&"pipes_engine": "res://assets/audio/voiceover/CD_PipesBroken_Engine.mp3",
	&"need_oil": "res://assets/audio/voiceover/CD_NeedOil.mp3",
	# Recorded and registered, but nothing plays them yet. Left in so wiring one up later is
	# a `vo_line` field rather than a code change — which is the whole point of the table.
	&"alarm_broken": "res://assets/audio/voiceover/CD_AlarmBroken.mp3",
	&"pipes_life_support": "res://assets/audio/voiceover/CD_PipesBroken_LifeSupport.mp3",
	&"asteroids": "res://assets/audio/voiceover/CD_AsteroidsIncoming.mp3",
	&"ate_food": "res://assets/audio/voiceover/CD_AteFood.mp3",
	&"garage_open": "res://assets/audio/voiceover/CD_GarageOpen.mp3",
	&"no_beer": "res://assets/audio/voiceover/CD_NoBeer.mp3",
	&"shitters_full": "res://assets/audio/voiceover/CD_ShittersFull.mp3",
	&"thingamajig": "res://assets/audio/voiceover/CD_Thingamajig.mp3",
}

## Beyond this the computer would be describing a situation that has already moved on. The
## OLDEST queued line is dropped, never the newest: when three things break at once the one
## worth hearing is the one that just happened.
const VOICE_QUEUE_MAX := 3
## Silence between lines, so two alerts do not run together into one sentence.
const VOICE_GAP := 0.4

## Breathing interval at the moment the warning starts, and at zero air. Getting faster is
## most of what makes it frightening — the volume barely matters.
const BREATH_SLOW := 3.4
const BREATH_FAST := 1.05

var music_state: Music = Music.NONE

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _music_tween: Tween
var _music_since_change: float = 999.0
var _music_pending: Music = Music.NONE

var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _voices_3d: Array[AudioStreamPlayer3D] = []
var _next_voice_3d: int = 0
var _sounds: Dictionary = {}

var _alarm_player: AudioStreamPlayer
var _paused: bool = false

# The computer's voice gets ONE player and a queue. Two lines at once is not two alerts, it is
# neither — a synthesised voice over itself is unintelligible, and the moment it matters most
# is exactly the moment several things are going wrong together. Non-positional, because the
# computer is speaking over the ship's PA and must be the same from every room.
var _voice_player: AudioStreamPlayer
var _voice_queue: Array[StringName] = []
var _voice_gap: float = 0.0
var _voices_by_name: Dictionary = {}

var _breath_intensity: float = 0.0
var _breath_timer: float = 0.0
var _warned_missing: Dictionary = {}


func _ready() -> void:
	# Keep running while paused: the pause menu's own click would otherwise be silent, and
	# music should not cut out because someone opened a menu.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music_a = _make_player(MUSIC_BUS)
	_music_b = _make_player(MUSIC_BUS)
	_music_active = _music_a
	for i in SFX_VOICES:
		_voices.append(_make_player(SFX_BUS))
	for i in SFX_3D_VOICES:
		_voices_3d.append(_make_player_3d(SFX_BUS))
	# The klaxon gets its own player, because it is the only sound with a LIFETIME rather
	# than a moment. Played through the round-robin pool it looped forever and was only ever
	# silenced by another sound stealing its voice — which is exactly what went wrong.
	_alarm_player = _make_player(SFX_BUS)
	_voice_player = _make_player(VOICE_BUS)

	_forge()
	_load_voice_lines()


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


func _make_player_3d(bus: StringName) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = bus
	player.max_distance = SFX_3D_RANGE
	# Inverse falloff rather than the default: a repair panel should get quieter down a
	# corridor without vanishing the moment you step through the doorway.
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size = 4.0
	add_child(player)
	return player


## Build every effect once. Roughly a quarter of a million samples in total, which costs
## milliseconds — cheap enough to do at startup and never think about again.
func _forge() -> void:
	_sounds = {
		&"bump": SoundForge.hull_bump(1.0),
		&"bump_soft": SoundForge.hull_bump(0.3, 991),
		&"klaxon": SoundForge.klaxon(1),
		&"click": SoundForge.click(),
		&"click_low": SoundForge.click(1200.0, 19),
		&"plug": SoundForge.plug_in(),
		&"ratchet": SoundForge.ratchet(),
		&"tape": SoundForge.tape_tear(),
		&"breath": SoundForge.breath(),
		&"pod_open": SoundForge.pod_door(true),
		&"pod_close": SoundForge.pod_door(false),
	}
	# File sounds LAST, so a recorded take overrides the generated one of the same name and a
	# missing file silently leaves the synth version in place (see FILE_SOUNDS).
	for name in FILE_SOUNDS:
		var path: String = FILE_SOUNDS[name]
		if not ResourceLoader.exists(path):
			_warn_once(path, "sound file missing: %s" % path)
			continue
		_sounds[name] = load(path)
	# After the override, or the alarm would keep a reference to whichever klaxon was built
	# first and the recorded one would never be heard.
	_alarm_player.stream = _sounds[&"klaxon"]
	# The klaxon is the one sound with a LIFETIME: set_alarm(true) starts it and expects it to
	# run until the fault is dealt with. A generated klaxon is authored looping; an imported
	# mp3 defaults to one-shot, so the alarm would have died after a couple of seconds and
	# left a critical fault sounding like a passing beep. Set here rather than in the .import
	# so it cannot be lost to a re-import.
	if _alarm_player.stream is AudioStreamMP3:
		(_alarm_player.stream as AudioStreamMP3).loop = true


## The voice lines are their own table, kept out of `_sounds` on purpose: play() round-robins
## a pool of eight voices and would happily start a second line over the first. Everything the
## computer says goes through say(), which owns the one player that can speak.
func _load_voice_lines() -> void:
	for line in VOICE_LINES:
		var path: String = VOICE_LINES[line]
		if not ResourceLoader.exists(path):
			_warn_once(path, "voice line missing: %s" % path)
			continue
		_voices_by_name[line] = load(path)


# --- effects ----------------------------------------------------------------------------

## Play a named effect. Unknown names are ignored rather than fatal: a typo in a wiring call
## should cost a sound, not the run.
func play(name: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _sounds.get(name)
	if stream == null:
		_warn_once(name, "no such sound '%s'" % name)
		return
	# Round-robin the pool. Stealing the oldest voice is right for short effects — better to
	# clip the tail of something that started half a second ago than to drop the new sound.
	var player := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## Play a named effect AT A POINT IN THE SHIP. Use this for anything with a location — a
## door, a panel being repaired, a plug going home. The klaxon and the hull bump deliberately
## do NOT use it: those are the whole ship, not a spot in it, and placing them would make the
## alarm quieter depending on which way you happened to be facing.
func play_at(name: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _sounds.get(name)
	if stream == null:
		_warn_once(name, "no such sound '%s'" % name)
		return
	var player := _voices_3d[_next_voice_3d]
	_next_voice_3d = (_next_voice_3d + 1) % _voices_3d.size()
	player.global_position = position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## The moment a fault fires: the hull taking it. A one-shot, because an impact IS a moment.
## The klaxon is deliberately not here — see set_alarm().
func impact(critical: bool) -> void:
	play(&"bump" if critical else &"bump_soft", -3.0 if critical else -6.0)


## The klaxon, driven by STATE rather than by the event that started it. This is the whole
## fix for an alarm that outlived its fault: an event-triggered looping sound has nothing to
## turn it off, so it ran through the repair, through the pause menu and out into the main
## menu. Now it is on exactly while a critical fault is unrepaired, and every path that ends
## that condition — repairing it, pausing, entering the pod, ending the run, leaving the
## scene — silences it without having to know the klaxon exists.
func set_alarm(active: bool) -> void:
	if active == _alarm_player.playing:
		return
	if active:
		_alarm_player.play()
	else:
		_alarm_player.stop()


# --- the ship computer ------------------------------------------------------------------

## Have the computer say something. This is the whole API — `Audio.say(&"oxygen_low")` — and
## it is safe to call from anywhere, at any time, including while another line is playing.
##
## NOT positional. The computer is on the PA: it has to be exactly as audible from the engine
## room as from inside the pod, which is the one place the player cannot walk away from.
##
## `interrupt` is for a line that makes the queued ones wrong — the run ending, say. The
## default is to queue, because cutting the computer off mid-sentence to start another
## sentence is how you end up understanding neither.
func say(line: StringName, interrupt: bool = false) -> void:
	if not VOICE_LINES.has(line):
		# A typo in a wiring call should cost a line, not the run — same contract as play().
		_warn_once(line, "no such voice line '%s'" % line)
		return
	if not _voices_by_name.has(line):
		return  # registered but the file is not on disk; already warned once at load
	if interrupt:
		_voice_queue.clear()
		_speak(line)
		return
	# `playing` is the right test here and NOT while paused — see _advance_voice().
	if not _voice_player.playing and _voice_queue.is_empty() and not _paused:
		_speak(line)
		return
	_voice_queue.append(line)
	while _voice_queue.size() > VOICE_QUEUE_MAX:
		_voice_queue.pop_front()


## True while the computer is talking or has something still to say. For anything that wants
## to wait for it — a run-end screen, a future music duck.
func is_speaking() -> bool:
	return _voice_player.playing or not _voice_queue.is_empty()


func _speak(line: StringName) -> void:
	_voice_player.stream = _voices_by_name[line]
	_voice_gap = VOICE_GAP
	_voice_player.play()


## Pull the next line off the queue once the current one has finished and its gap has passed.
##
## Driven from _process rather than from the player's `finished` signal because `playing`
## reads FALSE while a player is stream_paused (see docs/debugging-gotchas.md). On the signal
## that is merely a missed wake-up; here it would be worse — a paused line looks finished, so
## the queue would empty itself into the pause menu and the player would come back to silence
## having missed every alert.
func _advance_voice(delta: float) -> void:
	if _voice_player.playing:
		_voice_gap = VOICE_GAP
		return
	if _voice_queue.is_empty():
		return
	_voice_gap -= delta
	if _voice_gap <= 0.0:
		_speak(_voice_queue.pop_front())


## The two repair routes, which must never sound alike — see SoundForge. Positional: you
## should be able to hear which panel someone is working on.
func repair(permanent: bool, position: Vector3) -> void:
	play_at(&"ratchet" if permanent else &"tape", position)


func door(opening: bool, position: Vector3) -> void:
	play_at(&"door_open" if opening else &"door_close", position, -4.0)


## The pod's own door, which must not share the ship doors' sound — it is the one you hear
## from inside, sealing you in.
func pod_door(opening: bool, position: Vector3) -> void:
	play_at(&"pod_open" if opening else &"pod_close", position, -2.0)


# --- low oxygen -------------------------------------------------------------------------

## 0 = fine, 1 = out of air. Drives the breathing rate rather than a volume, because the
## rate is what people actually notice.
func set_breathing(intensity: float) -> void:
	_breath_intensity = clampf(intensity, 0.0, 1.0)
	if _breath_intensity <= 0.0:
		_breath_timer = 0.0


## Silence everything, without forgetting what was playing. Godot keeps streams running when
## the SceneTree pauses — pausing the tree does not pause audio — so this has to be explicit.
func set_paused(paused: bool) -> void:
	if _paused == paused:
		return
	_paused = paused
	for player in _all_players():
		player.stream_paused = paused


## Hard stop. For leaving the game scene entirely, where "resume" is not coming.
func stop_all() -> void:
	stop_music()
	set_alarm(false)
	# Queued lines outlive the player leaving the scene otherwise: the computer would carry
	# on announcing a run that has ended, over the main menu.
	_voice_queue.clear()
	set_breathing(0.0)
	set_paused(false)
	for player in _all_players():
		player.stop()


func _all_players() -> Array[Node]:
	var players: Array[Node] = [_music_a, _music_b, _alarm_player, _voice_player]
	players.append_array(_voices)
	players.append_array(_voices_3d)
	return players


func _process(delta: float) -> void:
	# The controller runs while the tree is paused so the pause menu's own click is audible,
	# which means everything below has to opt out of running while paused itself.
	if _paused:
		return
	_advance_voice(delta)
	_music_since_change += delta
	# Only ever a queued calm-down; escalations never queue.
	if _music_pending != Music.NONE and _music_since_change >= MIN_DWELL:
		var pending := _music_pending
		_music_pending = Music.NONE
		play_music(pending)

	if _breath_intensity <= 0.0:
		return
	_breath_timer -= delta
	if _breath_timer <= 0.0:
		_breath_timer = lerpf(BREATH_SLOW, BREATH_FAST, _breath_intensity)
		# Higher and tighter as it gets worse, which is what panic actually sounds like.
		play(&"breath", lerpf(-12.0, -2.0, _breath_intensity), lerpf(0.92, 1.25, _breath_intensity))


# --- music ------------------------------------------------------------------------------

## Crossfade to a track. Repeated calls for the state already playing are free.
##
## ESCALATION IS IMMEDIATE, CALMING DOWN IS NOT. The dwell guard originally applied to every
## transition, which meant a klaxon could go off and the score would take two and a half
## seconds to notice — the exact moment the music matters most, muffled by a rule meant to
## stop it stuttering. Only the return to NORMAL waits now, which still kills the
## oscillation case (a fault clearing and re-breaking) because the queued calm-down is
## simply dropped when the next alarm overrides it.
func play_music(state: Music) -> void:
	if state == music_state:
		_music_pending = Music.NONE
		return
	if state == Music.NORMAL and _music_since_change < MIN_DWELL:
		_music_pending = state
		return

	var stream := _load_music(state)
	music_state = state
	_music_pending = Music.NONE
	_music_since_change = 0.0

	var incoming := _music_b if _music_active == _music_a else _music_a
	var outgoing := _music_active
	_music_active = incoming

	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
		_music_tween = null

	var fading_in := stream != null
	var fading_out := outgoing.playing
	if fading_in:
		incoming.stream = stream
		incoming.volume_db = -40.0
		incoming.play()
	# A tween with no tweeners is an error, and with no music files present there is
	# genuinely nothing to fade — which is the normal state of this project right now.
	if not fading_in and not fading_out:
		return

	_music_tween = create_tween().set_parallel(true)
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if fading_in:
		_music_tween.tween_property(incoming, "volume_db", 0.0, FADE_TIME)
	if fading_out:
		_music_tween.tween_property(outgoing, "volume_db", -40.0, FADE_TIME)
		_music_tween.tween_callback(outgoing.stop).set_delay(FADE_TIME)


func stop_music() -> void:
	music_state = Music.NONE
	_music_pending = Music.NONE
	# A fresh run is a hard reset, not a de-escalation, so clear the dwell timer: otherwise
	# the FIRST track of the next run (NORMAL) would be dwell-gated and the run would open on
	# 2.5s of silence if the previous run had just changed the music.
	_music_since_change = 999.0
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_a.stop()
	_music_b.stop()


func _load_music(state: Music) -> AudioStream:
	var path: String = MUSIC_PATHS.get(state, "")
	if path == "" or not ResourceLoader.exists(path):
		# Not an error. A track can be absent (or a new one added later) and the game must
		# still run — a missing state simply plays silence.
		_warn_once(path, "music track not present: %s" % path)
		return null
	var stream := load(path) as AudioStream
	# Music must loop, and the tracks are not authored with loop metadata. Set it here so it
	# does not depend on each file's import settings being right. Vorbis has a plain flag;
	# a WAV master would need sample-accurate loop points, which is a second reason to ship
	# the .ogg.
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1)
	return stream


func _warn_once(key: Variant, message: String) -> void:
	if _warned_missing.has(key):
		return
	_warned_missing[key] = true
	print("[Audio] %s" % message)


# --- volume, for the options menu -------------------------------------------------------

static func set_bus_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	# Fully off means silent, not -60dB, or a slider at zero still leaks sound.
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.001, 1.0)))


static func get_bus_volume(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return 0.0
	if AudioServer.is_bus_mute(index):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))
