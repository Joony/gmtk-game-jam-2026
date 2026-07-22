# Feature: Web export (step 7)

**Date:** 2026-07-22
**Status:** Exported and running in a browser. **One item unverifiable here — see Pointer lock.**

## What was done

- [export_presets.cfg](../../export_presets.cfg) — `Web` preset targeting `build/web/index.html`:
  - `variant/thread_support=false` — no threads in game code, and no-thread builds avoid itch.io's
    cross-origin-isolation header requirements
  - `html/canvas_resize_policy=2` (adaptive), `focus_canvas_on_start=true`
  - `exclude_filter="tests/*, docs/*"` so the harness and docs don't ship
- `/build/` gitignored. [.claude/launch.json](../../.claude/launch.json) serves `build/web` on
  port 8099 for local testing.

Export command:

```
godot --headless --path . --export-release "Web" build/web/index.html
```

Output is ~38 MB, dominated by `index.wasm` (39 MB uncompressed; itch.io serves it gzipped).

## Verified in a real browser

Served over HTTP and loaded at `http://localhost:8099`:

- Boots cleanly — no errors in the console
- `OpenGL ES 3.0 (WebGL 2.0)` compatibility renderer, `single-threaded, no GDExtension support`
- The intro renders with the AbolitionTest font, correctly
- Buttons respond (SKIP, START) and `SceneManager` transitions run — the console shows
  `[SceneManager] changed scene to res://scenes/game.tscn`
- The 3D game scene renders correctly (floor, crates, shadows) under WebGL2
- The START prompt appears and starting the game hides it and reveals the game

## ⚠️ Pointer lock — could NOT be verified in this environment

The automated browser pane runs the page with `document.visibilityState === "hidden"`, and **the
browser refuses pointer lock outright** in that state. Calling `canvas.requestPointerLock()`
directly from the console — bypassing our code entirely — is rejected with:

```
WrongDocumentError: The root document of this element is not valid for pointer lock.
```

So this says nothing about whether our implementation is correct; the environment cannot grant
pointer lock to any code. **Verify by opening `http://localhost:8099` in a normal, visible browser
tab, clicking START, and confirming the cursor is captured and mouse look works.**

What *is* proven is our side of the contract: `smoke_player.gd` (run windowed) asserts that the
cursor is free while the START prompt is up and that **START itself captures it**. Capture happens
inside the button's `pressed` handler, which is a genuine user gesture — the condition browsers
require. That is the standard fix and there is no reason to expect it to fail; it simply hasn't
been observed working yet.

Same caveat for the countdown: the hidden tab throttles `requestAnimationFrame` to near zero, so
the intro appeared frozen at `10` and only advanced when a click briefly woke the tab. Timing is
verified on desktop instead; re-check it in a visible tab when convenient.

## Still to do before submitting

- [ ] Open the build in a real browser tab and confirm pointer lock + countdown timing
- [ ] Upload to itch.io and confirm it runs there (different headers/CDN than localhost)
- [ ] Re-check when step 13 adds audio — browsers block playback until a user gesture. The START
      button is a convenient place to hang audio initialisation off.
