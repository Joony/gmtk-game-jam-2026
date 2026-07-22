# Fix: script runs must not steal the real cursor

**Date:** 2026-07-23
**Status:** Done, verified

## The problem

Running the game windowed for a test or a screenshot (`godot -s <script>`) called `start_game()`,
which captured the OS cursor. That did two bad things:

1. **It stole the mouse from whoever was using the machine.**
2. **Their mouse movement was fed to the game camera.** Captures and tests then saw phantom input.

This was not hypothetical — it corrupted real work. Screenshots during the sliding-door and lighting
changes came out framed on the ceiling, on a wall corner, and at a skewed angle. I diagnosed those
as camera-interpolation timing and wrote that up as a gotcha in two feature logs. **That diagnosis
was wrong**; both logs are now corrected. The angles were the user's mouse.

## The fix

[scripts/mouse_capture.gd](../../scripts/mouse_capture.gd) — one gate for grabbing the cursor:

```gdscript
MouseCapture.capture()   # no-op in a script run unless explicitly allowed
MouseCapture.release()
```

`capture()` does nothing when `-s` / `--script` is on the command line — that is always a test or a
capture, never the real game. Tests that specifically verify capture opt in with
`MouseCapture.allow_in_script_runs = true` (currently `smoke_player.gd` and `smoke_pause_menu.gd`).

Every `Input.set_mouse_mode` call in `scripts/` now routes through this; there are no direct callers
left.

## Verified

- A windowed script run that calls `start_game()` now reports mouse mode **VISIBLE** — the cursor is
  left alone.
- All eight headless suites still pass.
- The two opted-in suites still exercise real capture when run windowed.

## Consequence to remember

The two opted-in suites **do** still take the cursor for a few seconds when run windowed. Run those
deliberately, and say so first — don't fire them off while someone is working. Everything else,
including every screenshot capture, is now safe to run at any time.
