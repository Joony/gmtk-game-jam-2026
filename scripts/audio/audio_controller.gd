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

enum Music { NONE, NORMAL, PANIC, STASIS }

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"

## Real files, and the only part of the audio that is not generated.
const MUSIC_PATHS := {
	Music.NORMAL: "res://assets/audio/music_normal.ogg",
	Music.PANIC: "res://assets/audio/music_panic.ogg",
	Music.STASIS: "res://assets/audio/music_stasis.ogg",
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
const FILE_SOUNDS := {
	&"door_open": "res://assets/audio/sfx/door_open.mp3",
	&"door_close": "res://assets/audio/sfx/door_close.mp3",
}

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

	_forge()


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
	_alarm_player.stream = _sounds[&"klaxon"]
	for name in FILE_SOUNDS:
		var path: String = FILE_SOUNDS[name]
		if not ResourceLoader.exists(path):
			_warn_once(path, "sound file missing: %s" % path)
			continue
		_sounds[name] = load(path)


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
	set_breathing(0.0)
	set_paused(false)
	for player in _all_players():
		player.stop()


func _all_players() -> Array[Node]:
	var players: Array[Node] = [_music_a, _music_b, _alarm_player]
	players.append_array(_voices)
	players.append_array(_voices_3d)
	return players


func _process(delta: float) -> void:
	# The controller runs while the tree is paused so the pause menu's own click is audible,
	# which means everything below has to opt out of running while paused itself.
	if _paused:
		return
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
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_a.stop()
	_music_b.stop()


func _load_music(state: Music) -> AudioStream:
	var path: String = MUSIC_PATHS.get(state, "")
	if path == "" or not ResourceLoader.exists(path):
		# Not an error. The tracks are composed last, and the game has to be playable and
		# testable long before they land.
		_warn_once(path, "music track not present yet: %s" % path)
		return null
	return load(path) as AudioStream


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
