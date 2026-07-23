class_name SoundForge

# Sound effects synthesised in code, as `AudioStreamWAV`s built at load time.
#
# WHY NOT FILES. The hull bump had no asset and no obvious place to get one, and the same is
# true of every other noise this game needs. Synthesising them costs no download, no licence
# and no megabytes in the web build, and it puts the sounds under the same kind of control as
# everything else here — a bump is a decay constant you can tune, not a file you re-record.
# It also matches how the rest of the project already works: the starfield is a shader, the
# nav chart is `_draw()` calls, there is not an art asset in the repo.
#
# MUSIC IS NOT THIS. Three composed tracks are not something to synthesise; those are real
# files. This covers the short, percussive, mechanical noises — which happens to be most of
# what the game needs and all of what it currently has none of.
#
# Everything is mono 16-bit at 44.1kHz and normalised to `PEAK` on the way out, so no sound
# can clip however hard its layers are pushed.

const RATE := 44100
## Headroom. Normalising to exactly 1.0 leaves no room for the mixer to sum two at once.
const PEAK := 0.85


## Deterministic by default. Noise that differs per launch is fine for a bump, but it makes
## the sounds untestable — and it means a build cannot be reproduced.
static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Normalise to PEAK and pack as little-endian 16-bit PCM.
static func _to_stream(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var peak := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain: float = PEAK / peak if peak > 0.00001 else 0.0

	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


static func _decay(t: float, tau: float) -> float:
	return exp(-t / tau)


# --- the ship ---------------------------------------------------------------------------

## The hull taking a hit. Three layers, because an impact is three sounds at once and any one
## of them alone reads as a mistake: a transient (the strike), a pitch-swept sub (the mass
## behind it), and a long filtered-noise tail (the hull ringing it off).
##
## `force` 0..1 scales the tail length and the transient bite, so the same generator makes
## both a distant knock and the one that takes the spanner out of your hand.
static func hull_bump(force: float = 1.0, seed_value: int = 20260723) -> AudioStreamWAV:
	force = clampf(force, 0.0, 1.0)
	var length := lerpf(0.55, 1.6, force)
	var count := int(RATE * length)
	var rng := _rng(seed_value)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var phase := 0.0
	var low_state := 0.0
	for i in count:
		var t := float(i) / RATE
		# Sub: swept down, because a fixed low tone reads as a musical note rather than a hit.
		var freq := lerpf(96.0, 33.0, minf(t / 0.28, 1.0))
		phase += TAU * freq / RATE
		var sub := sin(phase) * _decay(t, lerpf(0.12, 0.24, force))

		var transient := rng.randf_range(-1.0, 1.0) * _decay(t, 0.03) * lerpf(0.15, 0.45, force)

		# One-pole lowpass on white noise: the hull ringing, not a hiss.
		low_state = lerpf(low_state, rng.randf_range(-1.0, 1.0), 0.045)
		var rumble := low_state * _decay(t, lerpf(0.25, 0.8, force)) * 2.2

		samples[i] = sub * 0.9 + transient + rumble * 0.55
	return _to_stream(samples)


## Two-tone alarm, built to loop seamlessly so it can run for as long as the fault does.
## Harmonics rather than a bare sine — a pure tone reads as a test signal, and it is the
## upper partials that make it unpleasant enough to get someone out of a pod.
static func klaxon(cycles: int = 1) -> AudioStreamWAV:
	var tone_time := 0.34
	var count := int(RATE * tone_time * 2.0 * cycles)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var within := fmod(t, tone_time * 2.0)
		var high := within < tone_time
		var freq := 466.0 if high else 349.0
		phase += TAU * freq / RATE

		var tone := sin(phase) + 0.5 * sin(phase * 2.0) + 0.28 * sin(phase * 3.0) \
			+ 0.14 * sin(phase * 4.0)

		# Per-tone envelope: fast on, slightly slower off, so the two notes are distinct
		# instead of running together into one buzz.
		var local := fmod(within, tone_time)
		var env := minf(local / 0.012, 1.0) * minf((tone_time - local) / 0.045, 1.0)
		samples[i] = tone * clampf(env, 0.0, 1.0)
	return _to_stream(samples, true)


# --- the player's own hands -------------------------------------------------------------

## A switch, a button, a plug seating. Short enough to fire on every press without wearing out.
static func click(pitch: float = 2100.0, seed_value: int = 7) -> AudioStreamWAV:
	var count := int(RATE * 0.07)
	var rng := _rng(seed_value)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var body := sin(TAU * pitch * t) * _decay(t, 0.009)
		var snap := rng.randf_range(-1.0, 1.0) * _decay(t, 0.004) * 0.8
		samples[i] = body + snap
	return _to_stream(samples)


## A plug going home: a click with a low seating thunk under it, so it sounds like something
## went INTO something rather than being tapped.
static func plug_in(seed_value: int = 11) -> AudioStreamWAV:
	var count := int(RATE * 0.22)
	var rng := _rng(seed_value)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var seat := sin(TAU * 150.0 * t) * _decay(t, 0.055) * 0.9
		var snap := sin(TAU * 1750.0 * t) * _decay(t, 0.011)
		var grit := rng.randf_range(-1.0, 1.0) * _decay(t, 0.02) * 0.5
		samples[i] = seat + snap + grit
	return _to_stream(samples)


## The PROPER repair: a ratchet. Deliberately mechanical, regular and unhurried — the sound
## of doing a job correctly.
static func ratchet(teeth: int = 6, seed_value: int = 23) -> AudioStreamWAV:
	var spacing := 0.052
	var count := int(RATE * (spacing * teeth + 0.12))
	var rng := _rng(seed_value)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for tooth in teeth:
		var start := int(RATE * spacing * tooth)
		# Rising pitch across the teeth: it sounds like it is tightening, and gives the
		# gesture an obvious end rather than just stopping.
		var pitch := 1500.0 + 130.0 * tooth
		for i in int(RATE * 0.05):
			var index := start + i
			if index >= count:
				break
			var t := float(i) / RATE
			var value := sin(TAU * pitch * t) * _decay(t, 0.006)
			value += rng.randf_range(-1.0, 1.0) * _decay(t, 0.003) * 0.7
			samples[index] += value * (0.7 + 0.05 * tooth)
	return _to_stream(samples)


## The PATCH: tearing tape. Hissy, ragged and over quickly — it should sound like getting
## away with something, next to the ratchet's competence. The two repair routes are the
## game's central choice, so they must never sound alike.
static func tape_tear(seed_value: int = 41) -> AudioStreamWAV:
	var count := int(RATE * 0.42)
	var rng := _rng(seed_value)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var previous := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		# One-pole highpass: what is left is the hiss, which is what tearing sounds like.
		var high := noise - previous
		previous = lerpf(previous, noise, 0.35)
		# Ragged amplitude, so it is a tear and not a burst of static.
		var rag := 0.65 + 0.35 * sin(TAU * 37.0 * t) * sin(TAU * 13.0 * t)
		var env := minf(t / 0.015, 1.0) * _decay(t, 0.16)
		samples[i] = high * env * rag
	return _to_stream(samples)


## Running out of air. A slow, tightening breath — pitched noise with a swell, so it can be
## looped faster and faster as the oxygen drops.
static func breath(seed_value: int = 53) -> AudioStreamWAV:
	var count := int(RATE * 1.15)
	var rng := _rng(seed_value)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var band := 0.0
	for i in count:
		var t := float(i) / RATE
		band = lerpf(band, rng.randf_range(-1.0, 1.0), 0.18)
		# In, then out: two swells of different length, which is what makes it a breath
		# rather than a wave crashing.
		var inhale := exp(-pow((t - 0.22) / 0.16, 2.0))
		var exhale := exp(-pow((t - 0.72) / 0.26, 2.0)) * 0.8
		samples[i] = band * (inhale + exhale)
	return _to_stream(samples)
