# Feature: Flat interior lighting

**Date:** 2026-07-23
**Status:** Done, verified

The ship was still lit with an outdoor rig — a shadow-casting `DirectionalLight3D` plus a single
omni per room. That gave dramatic, uneven interiors: a hotspot in the middle of each ceiling, dark
corners, and hard shadows that read as "outdoors at night" rather than "inside a ship".

Both reference projects had already solved this, and agree:

- **Doortal ADR 0010** ("Enclosed interior room environment: flat background + color ambient +
  ceiling omnis (replaces skybox and sun)") — deletes the directional sun, uses
  `BG_COLOR` + `AMBIENT_SOURCE_COLOR` at energy 0.45, and a **grid** of *shadowless* omnis with
  emissive housings. Its own words: *"All lights are shadowless for an even, flat test-chamber
  look."*
- **GMTK 2025** `V1/LightingSystem.gd` — colour ambient at 0.4, shadowless omnis, and emissive
  unshaded ceiling panels.

## What changed

**Scene** ([scenes/game.tscn](../../scenes/game.tscn)):

- **Deleted the `DirectionalLight3D`.** This was the main culprit; it was the outdoor rig Doortal
  explicitly removed for the same reason.
- Ambient raised to Doortal's values: `Color(0.62, 0.66, 0.72)` at energy `0.45` (was
  `(0.5, 0.55, 0.65)` at `0.35`), background `Color(0.10, 0.11, 0.13)`.

**Builder** ([scripts/level/room_builder.gd](../../scripts/level/room_builder.gd)):

- **A grid of ceiling fixtures instead of one per room.** `light_spacing` (default 5m) decides how
  many go in each room, spread evenly; a single central lamp is what produced the hotspot-plus-dark-
  corners look. The ship now has 10 fixtures across its three rooms instead of 3.
- All fixtures are **shadowless** — this is the specific thing that makes the lighting read as flat.
- `light_energy` 1.6, `light_range` 9.0, cool white `(0.95, 0.96, 1.0)`.
- **Emissive light panels** under each fixture (`build_light_panels`), grouped `room_light_panels`,
  so the lights are visibly their own source. Step 10 can retint these alongside the omnis when it
  drives the alert state.

**Layout** ([scripts/level/ship_layout.gd](../../scripts/level/ship_layout.gd)):

- Ceiling colours lightened from near-black (~0.20) to mid-grey (~0.40). Even correctly lit, a
  0.22-albedo ceiling stays black and fights the flat look; both references use mid-grey or white.

## How it was verified

Rendered the pod bay from the spawn point: evenly lit walls and floor, a readable mid-grey ceiling,
two visibly glowing panels, no hard shadow edges anywhere. Also checked the corridor and the engine
room through the open door — consistent across all three rooms and both ceiling heights.

All eight headless suites still pass.

## Watch out

- **GL Compatibility caps lights per object** (`max_lights_per_object`, default 8). Each room's
  floor and ceiling are single boxes, so every fixture in a room hits the same surface. At 5m
  spacing the biggest room uses 4 — fine — but tightening `light_spacing` much further, or building
  a large room, could exceed the cap and make lights silently drop out. If that happens, either
  raise the limit or split large floors into sections.
- Shadows are off everywhere by design. If something later needs to cast one (a prop, the player),
  enable it on that light specifically rather than globally.

## Screenshot capture gotcha (corrected)

One capture came out framed on a wall corner instead of the room, which I put down to rendering
mid-settle. **That was the wrong diagnosis** — the capture had grabbed the OS cursor, so real mouse
movement on the machine was rotating the camera. Script runs no longer capture the cursor; see
[mouse-capture-in-tests.md](mouse-capture-in-tests.md).

Still worth doing when a shot looks wrong: print the camera transform. The pose distinguishes a
lighting problem from a camera-pointing-somewhere-else problem immediately.

## The ship opens ON red alert (2026-07-28)

The game loaded with white lighting and then went red — a visible flash of normal light before
the alarm.

**The alert was not being raised late.** `RunState.start()` has called `_update_alert()` for
exactly this reason for a while, with a comment saying why: a fault that `starts_broken` never
goes through `_on_broke`, so the ship-wide alert has to be brought up by hand. The mode was
correct from frame zero.

**The blend was the problem.** `set_mode()` starts the transition from `_current_values()`, which
at startup is the NORMAL defaults the rooms were built with — so the first `transition_time`
(0.4s) of every session was a white ship fading to red. That reads as the alarm going off just
after you wake, when the fiction is that the alarm is what woke you.

(No `Tween` is involved anywhere here, which is worth saying because it is the first thing anyone
will look for. `LightingController` blends manually in `_process` against `transition_time`.)

`set_mode()` and `set_alert()` take an optional `immediate`: it snaps `_from` to the destination,
sets `_blend = 1.0`, and calls `_apply()` on the spot rather than waiting for the next `_process`,
so it holds even if something renders before this node next ticks. `RunState.start()` passes it.
Every other transition — breaking a fault, repairing the last one — still blends as before.

### Two things worth keeping

**`_from` must be computed before `_to` is assigned.** The first version of this set `_to` first,
and `_current_values()` interpolates *toward* `_to` — so every blend began at its own destination
and snapped instantly. `smoke_lighting`'s existing "transition does not snap" check caught it on
the first run.

**The opening assertion now runs at ONE frame and checks the light colour**, not thirty frames and
the mode. The old version waited out the fade and only asked which mode the controller was in, so
it would have passed for as long as this bug existed. Mutation-tested: with `immediate` removed
the first frame is `(0.96, 0.74, 0.76)` — pale pink, caught mid-fade.
