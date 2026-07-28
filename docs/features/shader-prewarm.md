# Feature: Shader pre-warming — the first-turn hitch and the two-second cut

**Date:** 2026-07-28
**Status:** Done, verified (51 suites green + four measured probes)

## The problem

Two complaints that turned out to be the same fault:

1. **Turning round on the first load dropped the frame rate for about a second, once.** Never
   again in that session, from the same spot, facing the same way.
2. **The hard cut out of the intro froze on the video's last frame for over two seconds.**

Both are **first-draw cost**. Under GL Compatibility the renderer builds a material's shader
variant the first time something using it is actually rasterised, on the main thread. Standing
still only warms what is in front of you, so the first turn drags in the rest of the ship at
once; and nothing at all is warm the first time `game.tscn` is drawn.

## It was not the lights

Worth recording, because the lights were the obvious suspect and the ship carries 93 fixtures.
[tests/probe_turn_hitch.gd](../../tests/probe_turn_hitch.gd) sweeps the camera through 360° in
5° steps, three times over, vsync off, timing every frame:

| variant | pass 1 worst | pass 2 | pass 3 |
| --- | --- | --- | --- |
| baseline | **171 ms** | 13.8 ms | 11.7 ms |
| all 55 omni lights hidden | **159 ms** | 11.6 ms | 11.2 ms |
| starfield shell hidden | **172 ms** | 10.4 ms | 11.5 ms |
| imported `CD_*` props hidden | **172 ms** | 12.1 ms | 12.2 ms |
| the entire built ship hidden | **162 ms** | 10.2 ms | 11.8 ms |
| views pre-rendered once first | **11.8 ms** | 11.5 ms | 11.7 ms |

Median is ~7 ms throughout. Two things rule the lights out: passes 2 and 3 never spike from the
same angles, and hiding all 55 leaves the spike intact. **No single subsystem owns it** —
subtract any one and whatever is left in view pays it instead. That is the signature of
compilation, not of draw cost.

## What it does

### In the run: `ShaderPrewarm`

[scripts/level/shader_prewarm.gd](../../scripts/level/shader_prewarm.gd) draws the
surroundings from 12 yaws × 2 pitches into a 320×180 off-screen `SubViewport` sharing the real
`World3D`, one angle per frame. `game.gd` fires it un-awaited from `_ready`, so its 24 frames
overlap `OPENING_STASIS_TIME` — the one stretch of the run where the player is sealed in the pod
with nothing to do.

Off-screen rather than by spinning the real camera, because the only quiet moment to spend on
this is that stasis beat, and swinging the player's actual view through a full circle there
would be very hard to miss.

### Before the run: a black loading beat

[scenes/loading.tscn](../../scenes/loading.tscn) +
[scripts/loading.gd](../../scripts/loading.gd) sit between the menu and the intro video. They
build a whole copy of `game.tscn`, draw it, and **throw it away**.

That works because the 2.1 s splits in two, with opposite lifetimes:

- **~1.45 s is shader variant compilation**, cached by the RenderingServer for the whole
  *process*. Any instance can pay it, including one binned a moment later.
- **~0.67 s is per-instance GPU upload** of RoomBuilder's procedural boxes, and stays with the
  real scene.

[tests/probe_warm_reuse.gd](../../tests/probe_warm_reuse.gd) measures the split by instantiating
three times over: **2122 ms, then 496 ms, then 496 ms.**

`game.gd` gains a `warm_only` gate immediately before `start_game()` — everything above it
builds the ship, everything below starts an actual run. Set as node metadata before
`add_child()` rather than as an export or a static, so it arrives in time for that `_ready` and
cannot outlive the one instance it was meant for.

## The numbers

End to end, [tests/probe_boot_warm.gd](../../tests/probe_boot_warm.gd), M1 Max at 1280×720:

| | first drawn frame of `game.tscn` |
| --- | --- |
| control — straight into the game | **2201 ms** |
| warmed, scene not pinned | 1012 ms |
| warmed **and** pinned | **507 ms** |

The loading beat absorbs ~2030 ms of stall, on a black screen with nothing else to do.
In-run, the first turn now measures **0 spikes across all three sweeps**, worst frame 12.5 ms.

## Four things that cost time to find

**Pinning matters as much as warming.** Binning the warm copy dropped the last reference to
every mesh and texture it had pulled in, so the real load re-uploaded the lot — 1012 ms instead
of 507 ms, half the benefit thrown away at the last moment. `SceneManager.pin()` holds the
`PackedScene` for the process.

**The warm copy needs its own `World3D`.** The game scene brings a `Camera3D` and a
`WorldEnvironment` with it; in the menu's shared world those simply took over the screen.

**A warm copy is a second `Player` in the tree.** `smoke_full_loop` asserts no stray players
survive, and rightly failed. Fixed three ways: the warm runs **once per process** (static
latch), is skipped entirely under the headless display server (nothing to compile without a
rendering device), and the copy is set `PROCESS_MODE_DISABLED` so it is drawn but inert.

**`SceneManager` drops a change made during a change.** `loading.gd` chains a
`change_scene()` off the back of its own `_ready()`, while the change that brought it there is
still fading in — silently dropped, leaving the loading screen up forever. It waits on the new
`SceneManager.is_changing()` first. The warm's own frame count masked this on the first pass and
would have exposed it only on the second, when there is nothing to wait for.

## Where it was nearly put instead

Warming on the **main menu** worked, but put the stall on the Start button, which read as the
button not responding. The stall wants a screen that is doing nothing else.

Warming **during the intro video** was considered and rejected: GL Compatibility compiles on the
main thread, so the 2 s would land on the video as a freeze rather than disappearing. Hiding it
there would mean revealing the geometry in batches across the video's runtime — a real option,
but more machinery than a black beat.

## What is still paid

~500 ms on the cut, which is the per-instance upload. Only keeping a live warmed instance and
handing it to the player would remove it, at the cost of a `change_scene_to_instance` path in
`SceneManager` and a reset story for quit-to-menu and replay. Not judged worth it.

All four probes are dev utilities in the style of `tests/capture_*.gd` — none are wired into
`tools/run_tests.sh`, and all need a real display (`--headless` compiles nothing).
