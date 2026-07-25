# Testing procedure

How this project is tested, and the discipline that keeps the tests honest. The short
version: **headless smoke suites for logic, screenshots for anything visual, measure don't
eyeball, and prove every regression test can actually fail.**

For the Godot-specific traps that shaped this procedure, see
[`debugging-gotchas.md`](debugging-gotchas.md) — several of the rules below exist because a
naive approach silently lied.

---

## The one command

```bash
tools/run_tests.sh              # every tests/smoke_*.gd, truthful pass/fail
tools/run_tests.sh run_state    # only suites matching a substring
REIMPORT=1 tools/run_tests.sh   # reimport assets first (after adding art/audio/models)
```

**Do not** hand-roll `for t in tests/*.gd; do godot -s $t; done`. A GDScript **parse error
makes `godot -s` exit 0**, so a broken test reports success. `run_tests.sh` treats a suite as
green only when the exit code is 0, the output has no `Parse Error` / `SCRIPT ERROR`, *and* a
positive summary line was actually printed — the third condition is what catches a suite that
never ran. It also echoes the failing lines so you see the cause without re-running.

Run it before every commit. A green tree is the baseline everything else assumes.

---

## The kinds of tests, and when to reach for each

| Kind | Lives in | Runs | Use for |
|------|----------|------|---------|
| **Smoke suite** | `tests/smoke_*.gd` | `--headless` | logic, state machines, wiring, geometry connectivity |
| **Screenshot capture** | `tests/capture_*.gd` | **no** `--headless` | anything you have to *look* at — layout, materials, particles, UI |
| **Balance sim** | `tests/balance_sim.gd` | `--headless` | tuning design numbers by playing strategies, not asserting |
| **Throwaway probe** | `tests/_probe.gd` (delete after) | either | one-off "what is this value / where is this node" investigation |

The split matters: **headless can't render**, so it is blind to anything visual, and
`RenderingServer.frame_post_draw` never fires under `--headless` (a capture script hangs on
it). Logic goes headless; anything you'd otherwise judge by eye gets a screenshot.

---

## Writing a smoke suite

Every suite is a `SceneTree` script that ends in `quit(0)` on success or `quit(1)` on
failure, printing a summary line the runner can see. Two shapes are in use:

- **Synchronous** (`_init` → `_run.call_deferred()`): for pure-logic tests that drive a
  system by hand. `smoke_run_state.gd` builds bare `RunState`/`ShipMotion` nodes and calls
  `_process()` manually, so every assertion pins an exact rate instead of depending on frame
  timing.
- **Async with a watchdog** (an inner `_Runner` Node that `await`s frames): for anything that
  needs real frames — physics settling, input, scene transitions.

**Always arm a watchdog on an async suite:**

```gdscript
func _watchdog() -> void:
    await create_timer(90.0).timeout
    if is_inside_tree():
        push_error("suite: watchdog fired"); quit(1)
```

A script error inside an `await`ed coroutine kills the coroutine, so `quit()` never runs and
the suite **hangs forever** instead of failing. The watchdog turns a hang into a fail. (Same
symptom bites throwaway probes constantly — if a probe "produces no output", it errored
mid-coroutine; re-run it non-headless and read the `SCRIPT ERROR`.)

---

## The four verification rules

These are the habits that stopped tests from passing on nothing.

### 1. Test the real system, not a mock

Signal-driven wiring fails **silently** when a signal is connected to the wrong name or to a
system that never emits — it looks exactly like the feature being absent. So:

- `smoke_audio` drives the **real** `RunState` and asserts what the audio controller was
  *asked* to do, not that `play()` was called on a stub.
- `smoke_navigation` floods the **real** ship geometry with capsule casts at the player's own
  size, rather than trusting placement coordinates.
- `smoke_scene_deps` parses the actual `.tscn` text; it does not mock the resource system.

### 2. Measure, don't eyeball — and beware self-confounding measurements

Numbers beat impressions. But a measurement can move the thing it measures: the starfield
re-roll test kept "detecting" motion because `_process` was still accumulating
`distance_travelled` between samples (fixed with `set_process(false)` + a manual `_apply()`).
When a numeric test surprises you, **first suspect the harness**, not the code.

Anything genuinely visual — where a number can't capture "does it look right" — gets a
screenshot instead (next section).

### 3. Prove the test can fail (mutation testing)

A green test that *cannot* go red is not evidence. Several fixes here were confirmed by
deliberately re-breaking the code and watching the test fail:

- pod-refill rule → made the pod refuel → 3 failures
- patch expiry → made patches never expire → 4 failures
- the instant-alarm switch, the missing-sound guard, the row-major panel mounts…

If you add a regression test, break the fix once and confirm it goes red before trusting it.

### 4. Guard against null-matches-null

A missing thing is often `null`, and an *unused* thing is often `null` too, so `a == b` can
be a false positive (`voice.stream == _sounds.get(name)` matched `null == null` and "passed"
for a sound that never played). Guard the comparison (`want != null and …`) — then
mutation-test the guard.

---

## Screenshots: verifying the visual

Anything you would judge by looking — room layout, whether a prop clips, a material, a
particle effect, UI framing — is verified with a capture script run **without** `--headless`:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 1280x720 \
    -s tests/capture_countdown.gd -- <output_dir>
```

The script positions the camera, waits a few frames, `await RenderingServer.frame_post_draw`,
and saves a PNG; then **read the PNG back and actually look at it**. This caught things no
assertion would have: a full-screen "vignette" hiding the panel being repaired, spare parts
spaced so evenly they read as one pipe, a video that was decoding but rendering black.

When a value is what you care about but the scene is 3D, a headless **probe** that measures it
numerically is better than a screenshot — e.g. raycasting the furnace silhouette by height to
find the exact radius the pods sit flush at, or tracing the camera position per-frame to catch
the one-frame origin flash.

---

## A worked example (why the runner exists)

Writing this doc, `run_tests.sh` immediately flagged `smoke_navigation` red — the whole
engine room was unreachable from the spawn. The trail:

1. **Runner said** `FAIL smoke_navigation` and echoed `MAIN DRIVE walkable … 18.33m away`.
2. **`(opened 2 doors)` + 1510 cells reachable + NAV ARRAY (cryo bay) reachable** →
   the flood was trapped in the cryo bay, walled off at the corridor doorway.
3. **`git log` on the door/layout files** surfaced a recent commit: doors now auto-close
   ~0.1s after opening while empty (to avoid guillotining a cable run between rooms).
4. **Cause:** the nav test opens every door then waits 60 frames — the doors re-shut
   themselves before the flood ran. The *game* is fine; the test's "open them and they stay
   open" assumption was invalidated by a new feature.
5. **Fix:** `set_physics_process(false)` on each door after opening, so the auto-close never
   fires during the sweep. 2004 cells, 0 failures.

That is the loop: the runner surfaces it, the summary tells you *where*, `git log` tells you
*what changed*, and the fix goes to whichever is actually wrong — here, the test's model.

---

## Pre-commit checklist

1. `tools/run_tests.sh` → all green (`REIMPORT=1` first if you touched assets).
2. Touched anything visual? Capture a screenshot and look at it.
3. Added a regression test? Break the fix once, confirm it goes red, restore.
4. Changed the ship layout, a scene reference, or an asset path? `smoke_navigation` and
   `smoke_scene_deps` are the ones that catch layout/reference breakage — make sure they ran.
5. Commit only when green. The message records *what broke and how it was proven fixed*, not
   just what changed.
