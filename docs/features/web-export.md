# Feature: Web export (step 7)

**Date:** 2026-07-22
**Status:** ⚠️ **BLOCKED** — preset ready, export templates not installed

## What was done

- [export_presets.cfg](../../export_presets.cfg) — a `Web` preset targeting `build/web/index.html`,
  suitable for an itch.io upload:
  - `variant/thread_support=false` — no threads are used anywhere in game code (verified by grep),
    and no-thread builds avoid itch.io's cross-origin-isolation header requirements
  - `html/canvas_resize_policy=2` (adaptive) and `focus_canvas_on_start=true`
  - `exclude_filter="tests/*, docs/*"` so the test harness and docs don't ship
- `/build/` added to `.gitignore`.

## The blocker

Export templates for **4.7.1.stable are not installed**. Only `4.0.3`, `4.2.1` and `4.4.1` are
present in `~/Library/Application Support/Godot/export_templates/`.

Attempting the export fails at exactly that point — the preset itself validates:

```
ERROR: Cannot export project with preset "Web" due to configuration errors:
No export template found at the expected path:
  .../export_templates/4.7.1.stable/web_nothreads_debug.zip
  .../export_templates/4.7.1.stable/web_nothreads_release.zip
```

**To unblock:** install the 4.7.1 templates, either from the editor (Editor → Manage Export
Templates → Download and Install) or by placing the official `.tpz` contents in the path above.
Then run:

```
godot --headless --path . --export-release "Web" build/web/index.html
```

## Compatibility audit (done without exporting)

- **Renderer: OK.** `gl_compatibility` is already set, which is what the web needs — Forward+ on
  the web requires WebGPU. This was chosen deliberately in step 4; see
  [player-controller.md](player-controller.md).
- **Threads: OK.** No `Thread`, `OS.execute`, `FileAccess`, `DirAccess` or `DisplayServer` use in
  game code.
- **No Quit button**, so the usual `OS.has_feature("web")` special case doesn't arise.

### ⚠️ Known risk to check the moment templates exist

`game.gd:15` calls `Input.set_mouse_mode(MOUSE_MODE_CAPTURED)` from `_ready()`. **Browsers only
grant pointer lock from within a user-gesture handler**, and `_ready()` after a scene transition may
not qualify — the player could land in the game with a free cursor and no mouse look until they
click. Desktop is unaffected.

The standard fix is a click-to-capture fallback in the game scene (capture on first click when not
paused), or a "click to play" overlay. Deliberately **not implemented yet**: it can't be verified
without a working export, and if the browser does accept the capture it's needless complexity.
Verify first, then fix.

Also worth re-checking on web when step 13 adds audio: browsers block audio playback until a user
gesture too.
