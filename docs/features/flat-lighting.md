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

## Screenshot capture gotcha

A capture taken too early rendered mid-settle and produced a completely different framing (a wall
corner instead of the room). Wait ~60 physics frames *and* several process frames before
`frame_post_draw`, and print the camera transform when a shot looks wrong — the pose tells you
immediately whether it is a lighting problem or a timing one.
