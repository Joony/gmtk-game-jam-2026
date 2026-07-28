# Instructions that stop when you obey them

**Status:** done, verified (three mutations killed)
**Suite:** `tests/smoke_instruction_voice.gd`

Two lines run during the opening, and both are instructions:

1. **How to fix the first fault** — triggered by walking into the room it is in (`RoomVoice`).
2. **Go back to cryo** — triggered by clearing it (`Game._maybe_say_return_to_cryo()`).

Both triggers already worked. The problem was the other end: both lines are long enough to
outlast a player who acts promptly, so you could be told how to repair a system while looking at
its green light, or told to go back to sleep while lying in the pod. A voice still explaining a
finished task is worse than no voice — the player has moved on and the computer sounds like it
has not noticed.

## Why this needed a new primitive

`AudioController` could only start lines and stop everything:

| | |
| --- | --- |
| `say(line)` | queue it |
| `say(line, interrupt: true)` | clear the WHOLE queue and say this instead |
| `stop_all()` | music, alarm, breathing, queue — for leaving the scene |

None of those is "stop saying that one thing". `interrupt` is close but wrong: it is for a line
that makes everything else wrong (the run ending). Cancelling a tutorial must not also swallow a
klaxon-worthy announcement that happened to land behind it.

**`stop_saying(line) -> bool`** stops the line if it is playing, drops it from the queue if it
is waiting, leaves the rest of the queue intact, and reports whether it found anything. It also
clears the caption — subtitles are drawn from the voice player's playhead, which has just gone
away, so without that the last frame's text sits on screen until something else speaks.

**`speaking_line() -> StringName`** answers "what is coming out of the speaker right now", so a
caller can ask without reaching into the player.

## Wiring

- `Game._on_any_repaired()` cancels the tutorial line when the fault it teaches is repaired. The
  fault is cached as `_tutorial_fault` when the room cue is wired, rather than re-scanned for
  `starts_broken` later: that question should be answered once, and a second answer in a
  different place is a silent bug waiting.
- `Game`'s `stasis_changed` handler cancels `return_to_cryo` on the way in.

## Mutations killed

- tutorial cancellation removed — the lesson runs on past the repair.
- cryo cancellation removed — the line keeps going inside the pod.
- `stop_saying` made to ignore the queue — cancelling a line that is waiting rather than playing
  silently does nothing.
