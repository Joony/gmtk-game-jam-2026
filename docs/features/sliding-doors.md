# Feature: Sliding doors

**Date:** 2026-07-23
**Status:** Done, verified

Two panels that slide apart as the player approaches, ported from GMTK 2025's
`V1/DoorManager.gd`. Step 9 originally left these behind and cut a bare opening with a lintel.

## What was ported

[scripts/level/sliding_door.gd](../../scripts/level/sliding_door.gd) — `SlidingDoor`, built by
`RoomBuilder` for every `Doorway`:

- **two panels**, each half the opening's width, meeting in the middle
- **slide apart** by `width * 0.6` on a 0.4s `TRANS_SINE` / `EASE_OUT` tween — far enough that each
  panel tucks fully into the wall, as if into a pocket
- an **`Area3D` across the opening** (reaching `door_approach` = 1.6m either side) drives open on
  enter and close on exit
- the metallic look from 2025 (`albedo 0.70,0.72,0.78`, `metallic 0.35`, `roughness 0.3`)
- `opened` / `closed` signals

Of the original 307 lines, roughly 120 mattered. Left behind: `create_door_control_panel` (already
commented out in 2025), `is_player_near_door()`'s manual distance check (the `Area3D` supersedes
it), the `player_node` reference, and `grid_boundary_to_world` (our coordinate convention differs —
see [room-builder.md](room-builder.md)).

## Two changes, not straight ports

**Panels are `AnimatableBody3D`, not `StaticBody3D`.** Moving a static body does not sweep against
other bodies, so a closing panel would clip through the player or trap them. `AnimatableBody3D` with
`sync_to_physics` pushes properly — which in turn means the tween must run on the **physics** clock
(`Tween.TWEEN_PROCESS_PHYSICS`), not the default render clock, or the sweep is skipped.

**Only the player triggers a door.** The trigger checks the `player` group (newly added to
`scenes/player.tscn`) rather than reacting to any body — otherwise a thrown crate opens doors.

## `jammed`

`SlidingDoor.jammed` makes a door refuse to open. Three lines, and it turns "the door won't open"
into a step 12d repair archetype with no new mechanics: a jammed door between the pod and a
malfunction taxes the oxygen budget directly, since the player has to route around it or fix it.

## Wiring

`RoomBuilder` gained `build_doors` (default on) and `door_approach`. Doors are grouped `room_door`
and built after walls, sized from `doorway_height` and `wall_thickness`. Setting `build_doors = false`
leaves the bare opening — which is how the wall-geometry tests still assert the gap itself.

## How it was verified

[tests/smoke_room_builder.gd](../../tests/smoke_room_builder.gd) — **ROOM BUILDER TEST PASS**:

- one door per doorway, with two panels and a trigger
- panels are `AnimatableBody3D` (asserted directly — this is the bug-prone part)
- **starts closed, and a ray across the opening is blocked**
- a `player`-grouped body entering the trigger opens it, and after the slide the ray is **clear**
- leaving closes it again, and the ray is blocked once more
- a **jammed** door stays shut and keeps blocking with the player right there

In-game check: walked the player from spawn (not teleported) toward the corridor. Captured the door
closed from across the pod bay, then open with the player through it — and the engine-room door
still closed further down the corridor (`doors open: [true, false]`).

Regression: all eight headless suites pass.

## Scene fix found while testing

The demo `Socket` sat centred directly in front of the pod-bay doorway, blocking the route to the
corridor — the player physically could not reach the door trigger. Moved to `x = -3.6`, out of the
path. Worth remembering when placing step 12's repair panels: **don't put interactables in doorways.**

## Gotcha (corrected)

Several screenshots during this work came out at wild angles, and I first blamed stale camera
interpolation after teleporting. **That was wrong.** The capture scripts call `start_game()`, which
captured the OS cursor — so the *real* mouse being used on the machine at the time was feeding
motion straight into the camera. See [mouse-capture-in-tests.md](mouse-capture-in-tests.md); script
runs no longer capture the cursor.

(Teleporting still warrants `reset_physics_interpolation()`, but it was not the cause here.)
