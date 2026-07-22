# Feature: Main menu

**Date:** 2026-07-22
**Status:** Done, verified

## What was done

- [scenes/main_menu.tscn](../../scenes/main_menu.tscn) + [scripts/main_menu.gd](../../scripts/main_menu.gd),
  replacing the placeholder label scene.
- Dark background, large red title (`STASIS`, **working title — needs a real name**) with a
  "working title" subtitle so the placeholder is obvious on screen.
- **Play** button → `SceneManager.change_scene("res://scenes/game.tscn")` with the standard fade.
- `%PlayButton.grab_focus()` on ready, so keyboard/gamepad navigation works from the first frame.
  The focus and hover styles share a red border, so the focused control is always visible.
- `Input.set_mouse_mode(MOUSE_MODE_VISIBLE)` on ready — menus need the cursor back once the game
  starts capturing it (step 4/5).
- **No Quit button** (requested). It was also the item that needed hiding on web exports, so that
  whole branch is gone.
- **Options button deferred to step 13**, where the volume slider it would open actually lives.
  A button that opens nothing is worse than no button.
- [scenes/game.tscn](../../scenes/game.tscn) created as a bare placeholder (Node3D + a label) so
  Play has somewhere to land and can be proven. Step 3 adds the floor, lighting and spawn point.

## How it was verified

- [tests/smoke_main_menu.gd](../../tests/smoke_main_menu.gd) — **MAIN MENU TEST PASS**, exit 0:
  - Play button exists and is labelled; title text is non-empty
  - no Quit button exists (scans every Button by name and text)
  - Play has focus on the first frame
  - pressing Play actually reaches the `Game` scene
  - `game.tscn` loads and instantiates standalone
- Visual check: rendered to PNG with [tests/capture_scene.gd](../../tests/capture_scene.gd) and
  inspected. Layout, colours and the focus border all correct.
- Real-time headless run of the whole game: intro countdown → `[SceneManager] changed scene to
  res://scenes/main_menu.tscn`, no errors.
- Regression: the other two suites still pass (project structure, intro/SceneManager).

## Notes

- New dev utility: `tests/capture_scene.gd` renders any scene to a PNG for eyeballing without
  opening the editor. Must run **without** `--headless` (needs a real renderer):
  `godot --path . --resolution 1280x720 -s tests/capture_scene.gd -- <scene> <out.png>`
- The title is a placeholder chosen to fit the stasis-pod hook. Replace it once the game is named.
