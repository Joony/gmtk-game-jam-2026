# Feature: Sliding doors

**Date:** 2026-07-23
**Status:** Done, verified

Two panels that slide apart as the player approaches, ported from GMTK 2025's
`V1/DoorManager.gd`. Step 9 originally left these behind and cut a bare opening with a lintel.

## What was ported

[scripts/level/sliding_door.gd](../../scripts/level/sliding_door.gd) — `SlidingDoor`, built by
`RoomBuilder` for every `Doorway`:

- **two panels**, each half the opening's width, meeting in the middle
- **slide apart** on a 0.4s `TRANS_SINE` / `EASE_OUT` tween, stopping so `open_reveal` (6cm) of
  each panel still shows in the opening. Retracting fully into the wall made an open doorway read
  as a plain hole; leaving a sliver keeps it legible as a door.
- an **`Area3D` across the opening** (reaching `door_approach` = 1.6m either side) drives open on
  enter and close on exit
- a **matte** finish — see below; 2025's metallic look does not survive this renderer
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

## Z-fighting fix (2026-07-23)

Reported in play: the doors flickered and tore against the walls. Cause: panels were built with
`wall_thickness` and centred on the same plane as the wall, so a panel sliding **open** ends up
inside the wall, exactly coplanar with it — overlapping surfaces at identical depth, which the
depth buffer cannot resolve.

Two seams removed, both by making surfaces never share a plane:

- **Sideways:** panels are now `door_thickness` (0.08), clamped to at most 70% of `wall_thickness`,
  and centred in the wall's depth. An open panel is then strictly *inside* the wall volume — hidden,
  with no shared faces. A closed panel reads as slightly recessed, which is how doors look anyway.
- **Top and bottom:** panels are `SEAM_OVERLAP` (2cm) taller than the opening at each end, so they
  interpenetrate the lintel above and the floor below rather than sitting flush. A flush panel put
  its top face exactly on the lintel's underside — the same coplanar-overlap problem, just rotated.

Both are asserted in the test (`panel depth < wall_thickness`, `panel height > doorway_height`),
because they are geometric invariants: a still screenshot cannot prove flicker is absent, but
"no two surfaces share a plane" can be checked exactly.

## Matte, not metallic (2026-07-23)

Reported in play: the doors were too glossy with weird reflections. 2025's material was
`metallic 0.2, roughness 0.3`, and I had ported it as `metallic 0.35, roughness 0.3`.

Under **GL Compatibility there is no reflection probe and no sky**, so a metallic, low-roughness
surface has nothing to reflect. It falls back to hard specular off the omni fixtures, which slid
across the panels as bright streaks — especially visible on the slivers left showing in an open
doorway.

Doors are now `metallic 0.0`, `roughness 0.85`, and read as distinct by being **lighter than the
walls** (`albedo 0.66, 0.69, 0.74`) rather than shinier. That is the right approach for a flat-lit
interior anyway — see [flat-lighting.md](flat-lighting.md). Both values are exported
(`door_color`, `door_roughness`) and asserted in the test, since this is the second gloss-related
regression risk in this area.

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
