# Feature: Ship-computer voiceover, and the recorded klaxon

**Date:** 2026-07-25
**Status:** Done, verified

New audio delivered: `assets/audio/sfx/Klaxon.mp3` and fifteen computer-voice lines in
`assets/audio/voiceover/`.

## The klaxon: recorded, generator kept

`AudioController.FILE_SOUNDS` is loaded **after** `_forge()` into the same dictionary, so a file
registered under a name that already exists simply overrides the generated sound. Adding
`&"klaxon": ".../Klaxon.mp3"` was the whole change — `SoundForge.klaxon()` is untouched and
stays the fallback for a missing file.

Two ordering details that were not optional:

- `_alarm_player.stream = _sounds[&"klaxon"]` had to move **after** the `FILE_SOUNDS` loop. Left
  where it was, the alarm kept a reference to whichever klaxon was built first and the recording
  would never have been heard.
- **The stream has to loop.** `set_alarm(true)` starts it and nothing stops it until the fault is
  dealt with, but an imported mp3 is one-shot by default — a critical fault would have sounded
  like a passing beep. `AudioStreamMP3.loop` is set in code rather than in the `.import`, so a
  re-import cannot quietly undo it.

`smoke_audio.gd` now measures the **generator** directly (`SoundForge.klaxon(1)`: length, no
clipping, a continuous loop seam) instead of reading `_sounds[&"klaxon"]`, which is the mp3 and
is 3.97 s — outside the 0.5–2.0 s the generated one is held to. Separately it asserts that what
the alarm actually holds is the shipped stream and that it loops. The old test would have gone
on passing while measuring a file nobody wrote.

## The voiceover system

```gdscript
Audio.say(&"oxygen_low")
Audio.say(&"intro", true)   # interrupt: clears the queue first
Audio.is_speaking()         # talking, or still has something to say
```

- **One player and a queue.** Two computer voices over each other is not two alerts, it is
  neither — and the moment it matters most is exactly the moment several things are going wrong
  together. Lines queue up to `VOICE_QUEUE_MAX` (3) with `VOICE_GAP` (0.4 s) between them, and
  the queue drops the **oldest**: when everything breaks at once, the line worth hearing is the
  one that just happened.
- **Audible from anywhere.** A plain `AudioStreamPlayer`, never positional. The computer is on
  the PA and has to be identical from the engine room and from inside a sealed pod — the one
  place the player cannot walk away from.
- **Its own `Voice` bus**, added to `default_bus_layout.tres` at +3 dB. It speaks over the very
  klaxon it is explaining, so the two have to be mixable against each other, and a later
  duck-the-music pass now has somewhere to live that does not fight the crossfade for the music
  players' `volume_db`.
- **Its own table**, deliberately not `_sounds`. `play()` round-robins a pool of eight voices and
  would happily start a second line over the first; everything the computer says goes through
  `say()`, which owns the one player that can speak.

### The queue drains from `_process`, not from `finished`

`AudioStreamPlayer.playing` reads **false** while `stream_paused` is true (see
[debugging-gotchas.md](../debugging-gotchas.md)). On the `finished` signal that would only be a
missed wake-up; draining a queue on it is worse — a paused line looks finished, so the queue
would empty itself into the pause menu and the player would come back to silence having missed
every alert. `_advance_voice()` runs from `_process()`, which already returns early while paused.

`stop_all()` clears the queue too, or the computer carries on narrating a run that has ended,
over the main menu.

## Wiring is data, not code

`Malfunction.vo_line` is an exported `StringName`, so giving a system a voice is one field in
`game.tscn`:

| System | Line |
| --- | --- |
| MAIN DRIVE | `need_oil` |
| O2 SCRUBBER | `life_support` |
| COOLANT LOOP | `pipes_engine` |
| NAV ARRAY | `nav_off` |
| AUX POWER | `power_off` |

Plus two events that are not faults: `intro` on waking out of the opening stasis (the first thing
you hear after the cork pop), and `oxygen_low` when the air crosses its warning threshold.

The low-air call is **latched**, not compared against the threshold each frame — `oxygen_changed`
fires every frame of the run, so an unlatched line would have the computer stuck repeating itself
for the last minute of it. Never re-armed, because air only goes one way.

The remaining eight lines (`alarm_broken`, `pipes_life_support`, `asteroids`, `ate_food`,
`garage_open`, `no_beer`, `shitters_full`, `thingamajig`) are registered but unwired, so hooking
one up later stays a one-field edit.

### The klaxon is suppressed in stasis; the voice is not

Deliberate, and the two are different kinds of sound. The klaxon is a loop that would run for the
whole of a stasis; one line telling you what just broke is exactly the thing that should get you
out of bed.

## Tests

[smoke_voice.gd](../../tests/smoke_voice.gd) — every registered line resolves to a file that
exists and loaded (a typo'd path otherwise fails in a build, at the moment a fault fires, with
nothing on screen to say so); the klaxon is the recording, is what the alarm holds, and loops;
one line at a time with a bounded queue that keeps the newest; `interrupt` clears it; `stop_all`
empties it; every shipped fault's `vo_line` names a real line; breaking a fault speaks through
the real `alarm` signal; and the low-air call happens exactly once.

**Mutation-tested, six killed:** a non-looping klaxon, the old load order, a second line cutting
the first off, an unbounded queue, `stop_all` leaving the queue standing, and an unlatched
low-air call.

One trap, twice now: a `_check` that indexes an array can kill the coroutine and **hang** the
suite instead of failing it. Guard the index, not just the loop bound.

## Not done

No music ducking while the computer speaks. The `Voice` bus is at +3 dB, which is a starting
point I cannot judge by ear — if the computer is hard to make out over `red_alert` plus the
klaxon, that constant is the first thing to move, and a proper duck is the second.
