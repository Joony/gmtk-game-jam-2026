# Feature: In-game pause menu (step 5)

**Date:** 2026-07-22
**Status:** Done, verified

## What was done

[ui/pause_menu.tscn](../../ui/pause_menu.tscn) + [scripts/pause_menu.gd](../../scripts/pause_menu.gd),
instanced into [scenes/game.tscn](../../scenes/game.tscn).

- CanvasLayer (layer 50), hidden on ready, `process_mode = ALWAYS` so it keeps running while the
  tree is paused — otherwise Esc could pause but never unpause.
- Semi-transparent black `Dim` ColorRect over the game, then `PAUSED` + **Resume** / **Quit to Menu**.
- **Esc does all three things at once:** `get_tree().paused = true`, show the menu, release the
  cursor to `MOUSE_MODE_VISIBLE`. Esc again (or Resume) reverses all three, re-capturing the cursor.
- Resume grabs focus when the menu opens, so keyboard/gamepad navigation works immediately.
- The Esc event is consumed with `get_viewport().set_input_as_handled()`.
- **Quit to Menu** unpauses *before* changing scene (otherwise the main menu loads into a paused
  tree and is dead on arrival), and deliberately leaves the cursor visible for the menu.
- Emits `paused` / `resumed` signals for later systems — step 12's oxygen countdown must not drain
  while paused, and it can subscribe rather than polling `get_tree().paused`.

## Design decision: one owner for the cursor

The pause menu owns Esc **and all mouse-capture state**. The camera controller had its own
capture/release in Doortal (click to capture, `ui_cancel` to release); that was stripped in step 4.
`game.gd.capture_mouse()` only runs on entry to the game scene. Everything else routes through the
pause menu, so cursor state has a single source of truth and can't be fought over.

Esc is inert in the intro and main menu for free: the pause menu only exists inside the game scene,
so nothing listens for the action elsewhere. This is asserted rather than assumed — see below.

## How it was verified

[tests/smoke_pause_menu.gd](../../tests/smoke_pause_menu.gd) — **PAUSE MENU TEST PASS**, exit 0,
both headless and windowed:

- starts hidden, tree unpaused, `process_mode == ALWAYS`, has Resume/Quit/Dim
- Esc shows the menu, pauses the tree, releases the cursor, and focuses Resume
- Esc again hides, unpauses, and re-captures the cursor
- the Resume button does the same as Esc
- **the pause is real**: the player does not move over 30 physics frames while paused
- Quit to Menu unpauses, reaches the main menu, leaves the tree unpaused and the cursor visible
- Esc does nothing in the main menu, and nothing in the intro

Visual check: rendered the paused game to PNG (dimmed scene, PAUSED, focused Resume) via
`capture_scene.gd`, which now takes an optional third argument — an input action to fire before
capturing — so input-dependent states can be eyeballed:

```
godot --path . --resolution 1280x720 -s tests/capture_scene.gd -- res://scenes/game.tscn out.png pause
```

Regression: all five suites pass headless; the two cursor-touching suites also pass windowed.

## Gotchas

- **Cursor assertions are skipped under `--headless`** (capture is unavailable there) and the test
  says so rather than silently passing. Always re-run this one windowed after touching cursor code:
  `godot --path . --resolution 640x360 --position 3000,3000 -s tests/smoke_pause_menu.gd`
- Anything added to the game scene that must keep running while paused (or must *not*) needs its
  `process_mode` set deliberately — the default inherits and will freeze.
