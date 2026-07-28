# Feature: Re-capturing the mouse after the browser takes it

**Date:** 2026-07-27
**Status:** Done, verified (headless suite + exported build in a browser)

## The problem

Playing the web build, the moment the page loses focus — alt-tab, a click anywhere outside the
canvas, the browser's own Esc — the browser hands pointer lock back. The game carried on running:
the player could still walk, oxygen still drained, but mouse look was dead and there was no way to
get it back short of quitting to the menu and starting again.

**The game cannot simply ask for it back.** Browsers only grant pointer lock from inside a user
gesture. Calling `Input.set_mouse_mode(CAPTURED)` from `_process` after a focus loss is rejected
(and Chrome additionally blocks re-locking for ~1.25 s after an Esc unlock). Something has to
notice the loss and put a *clickable thing* in front of the player — the click is what buys the
lock back.

## What it does

A lost cursor **pauses the game**. That is the whole design: pausing freezes the run instead of
letting oxygen burn while the player is helpless, and the Resume button is the click that
re-captures.

[scripts/mouse_capture.gd](../../scripts/mouse_capture.gd) — the existing single gate for the
cursor, now tracking *intent* as well as state:

- `capture()` records that the game wants the cursor, and when it asked.
- `capture_lost()` — wants it, asked long enough ago to have landed, still doesn't have it.
- `SETTLE_MS = 500`. On web, `capture()` only *asks*: `is_captured()` reads back
  `document.pointerLockElement`, which stays empty until the browser grants the lock a frame or
  two later. Without this window **every successful capture would read as an instant loss**.

[scripts/pause_menu.gd](../../scripts/pause_menu.gd) — already the single source of truth for
cursor state, so the watchdog lives there:

- `_process` (the node is `PROCESS_MODE_ALWAYS`) polls `MouseCapture.capture_lost()` and calls
  `pause_game(true)`.
- `watch_pointer_lock`, set from `OS.has_feature("web")` in `_ready`. Only a browser pulls the
  cursor out from under a running game; on desktop `mouse_mode` stays `CAPTURED` across alt-tab,
  so the poll would never fire anyway — but gating it keeps script runs (where capture silently
  fails) from pausing themselves. Tests set it directly.
- Gated on `enabled` too, so the deliberate cursor release during the end-of-run collapse isn't
  mistaken for a loss.
- `pause_game(cursor_was_lost)` shows a new `%LostCursorHint` label —
  *"THE BROWSER TOOK THE MOUSE BACK / CLICK RESUME TO CARRY ON"* — so an unasked-for pause menu
  explains itself. Hidden again on resume and on quit.

**Resuming with Esc may be refused** (Chrome doesn't count Esc as a gesture, and blocks re-locking
right after an Esc unlock). That's handled by the same loop rather than special-cased: the resume
goes through, the lock doesn't arrive, and within `SETTLE_MS` the watchdog pauses straight back
with the hint up. The player clicks Resume and is playing again. Self-correcting, never stranded.

## How it was verified

[tests/smoke_mouse_recapture.gd](../../tests/smoke_mouse_recapture.gd) — **headless is a faithful
stand-in for a browser refusing pointer lock**: both accept `set_mouse_mode(CAPTURED)` and never
deliver the cursor. The steal itself is simulated by setting the mode back to `VISIBLE` through
`Input` directly, bypassing `MouseCapture` exactly as the browser does behind the game's back.

- a request in flight is not reported as lost; one that never lands is
- a deliberate `release()` is not a loss
- not watching (desktop) → no auto-pause; watching → paused, menu up, hint shown, Resume focused
- Resume unpauses, hides the menu, clears the hint, and asks for the cursor back
- a **refused** re-capture pauses straight back instead of stranding the player
- a disabled pause menu (end-of-run) never auto-pauses

Proved able to fail: replacing `pause_game(true)` with `pass` fails 5 assertions.

Visual check: the paused state rendered to PNG with the hint up (`pause_game(true)` driven
directly, so no real capture is requested and the machine's cursor is never touched) — dimmed
scene, **PAUSED**, the two hint lines, Resume focused.

Then the real thing: web build exported (`tools/export_web.sh`) and **playtested by hand in a
normal browser tab** — losing focus now pauses the game, and Resume takes the mouse back.

**The automated browser pane cannot check this** — it serves the page with
`visibilityState: hidden`, and browsers suspend `requestAnimationFrame` for hidden documents, so
the Godot main loop never runs: the build paints one frame and freezes, and pointer lock is
refused there outright. It has to be a real tab. Noted in
[debugging-gotchas.md](../debugging-gotchas.md).

## Gotchas worth remembering

- **Pointer lock is asynchronous.** Checking `is_captured()` on the line after `capture()` reads
  false even on success. Any watchdog needs a settle window.
- **`mouse_get_mode()` on web is derived, not stored** — it reports whatever
  `document.pointerLockElement` currently says, so the browser silently "changes" the game's mouse
  mode without the game doing anything.
- **Don't retry the lock every frame.** The request is rejected without a gesture and the console
  fills with security errors. Wait for a click.
