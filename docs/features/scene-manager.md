# Feature: SceneManager (scene loading system)

**Date:** 2026-07-22
**Status:** Done, verified

## What was done

- [scripts/scene_manager.gd](../../scripts/scene_manager.gd), registered as autoload `SceneManager` in `project.godot`.
- `change_scene(path)`: fades to black (0.3s), swaps the scene with `change_scene_to_file`, fades back in.
- The fade layer (CanvasLayer, layer 100 + ColorRect) is built in code at `_ready` — no scene file needed.
- Re-entrancy guard: `change_scene` calls made while a transition is running are ignored (`_changing` flag).
- `process_mode = ALWAYS` and pause-immune tweens, so transitions work while the tree is paused (needed later for "Quit to Menu" from the pause menu).
- Blocks mouse input during the fade so the outgoing scene can't be clicked.
- Logs each change: `[SceneManager] changed scene to <path>` — used by tests and useful when debugging.

## How it was verified

- [tests/smoke_intro_scene_manager.gd](../../tests/smoke_intro_scene_manager.gd) drives real transitions (intro → menu → intro → menu) at 25× time scale and asserts the current scene each time. **PASS**, exit 0.
- Real-time headless run of the actual game: transition fired after the countdown. See [intro.md](intro.md).

## Notes / gotchas

- During a change, `get_tree().current_scene` is briefly `null` (old scene freed before the new one is assigned) — poll for the new scene rather than assuming.
- A `change_scene` call during an active transition is dropped by design; callers that must transition should wait until the manager is idle.
- Headless `-s` tests must defer their body (`call_deferred`) — autoload globals aren't registered yet in `_init`, and scripts referencing `SceneManager` won't compile before that.
