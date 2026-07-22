# Feature: Procedural room builder (step 9)

**Date:** 2026-07-22
**Status:** Done, verified

Ported from `/Users/joony/gmtk-game-jam-2025/V1/`. The valuable part — rectangular rooms with
auto-generated perimeter walls that split correctly around doorways — came over intact. Three
structural problems in the original were fixed rather than inherited.

## Files

- [scripts/level/room.gd](../../scripts/level/room.gd) — `Room` resource. `Rect2i` instead of
  four loose ints; the `GameTypes.TileType` field is gone (that autoload isn't coming over, and
  the builder never read it).
- [scripts/level/doorway.gd](../../scripts/level/doorway.gd) — `Doorway` resource, holding the
  wall-intersection maths from `V1/SlidingDoor.gd`. **Renamed** because nothing slides: it cuts an
  opening. The panels, control panel, detection area and tween state stayed behind.
- [scripts/level/room_builder.gd](../../scripts/level/room_builder.gd) — the builder.
- [scripts/level/ship_layout.gd](../../scripts/level/ship_layout.gd) — the ship, authored in code.

## Three fixes, not ports

**1. One coordinate convention.** 2025 had two — `grid_to_world` (tile centres, `+0.5`) for floors
and `grid_boundary_to_world` (tile edges) for walls — and *both subtracted `level_width / 2`*. World
position therefore depended on the level's declared size, so adding a room moved everything already
placed. That is why its level data is full of hand-tuned floats like `Vector3(11.4, 1.285, 6.07)`.

Here grid coordinates **are** boundary coordinates and map straight through: grid `(x, y)` → world
`(x * tile_size, y * tile_size)`, grid y running along world Z. Tile centres are at `+0.5`. No
centring, no level dimensions, one conversion function.

**2. One box per surface, not one per tile.** 2025 emitted a `StaticBody3D` per floor tile *and* per
ceiling tile — a 20×20 room cost 800 nodes. Rooms are rectangles, so one box each does the same job.

**3. Shared walls are built once, tracked in TWO dimensions.** Adjacent rooms each generate the wall between them. 2025 hid the
resulting z-fighting with per-side nudge offsets (`Vector3(0, 0, 0.0125)`). Instead, wall spans are
tracked per line and each new segment has the already-built spans subtracted from it
(`subtract_spans`). This handles partial overlap between differently-sized neighbours too, and the
subtraction is order-independent — whichever room builds first claims its stretch, the other fills
in the remainder.

Coverage is tracked along the line **and in height**. Tracking only the span was a bug (found in
play, fixed 2026-07-22): where a *shorter* room claimed a stretch first, the taller room's wall
above it was never built, leaving a gap you could see through into the void — most visibly above
the doorway between the 2.6m corridor and the 4.0m engine room. Each new wall piece now has its
span cut at every existing edge, and for each resulting sub-span the already-covered vertical
bands are subtracted, so only the genuinely missing bands are built.

Also: `flags_unshaded` (a deprecated 4.7 alias) isn't used, and lighting is **one omni per room** in
the `room_lights` group for step 10 to drive — not 2025's one-`OmniLight3D`-per-floor-tile, which was
a GL-compatibility-era hack costing hundreds of lights on a large level.

## API

```gdscript
builder.add_room(Rect2i(-5, -4, 10, 12), {"id": "pod_bay", "height": 3.0, "wall_color": ...})
builder.add_doorway(Vector2(0.5, -4), Doorway.Axis.X, 1.8)
builder.build()
```

`Doorway.Axis` is which axis the opening **spans**: `X` cuts north/south walls, `Z` cuts east/west.
Built nodes are grouped `room_floor` / `room_ceiling` / `room_wall` / `room_lights`; lintels carry a
`lintel` metadata flag. `build()` is idempotent — it tears down and rebuilds.

## The ship

[ship_layout.gd](../../scripts/level/ship_layout.gd) replaces the flat sandbox floor in
`scenes/game.tscn`: a **pod bay** (10×12, 3.0m) where the player spawns, a narrow lower **corridor**
(3×8, 2.6m) so walking between systems reads as a cost, and a taller **engine room** (12×10, 4.0m)
further out, joined by two doorways.

Hand-authored on purpose, per the TODO: the hook makes walking distance the oxygen cost, so
randomising the geometry would randomise the difficulty. Randomise *which systems fail*, not where
the rooms are. The builder is the construction tool, not a generator.

The old flat floor and three static crate landmarks were removed — the ship provides both.

## How it was verified

[tests/smoke_room_builder.gd](../../tests/smoke_room_builder.gd) — **ROOM BUILDER TEST PASS**:

- `subtract_spans` unit cases: empty, middle hole, fully covered, partial overlap
- one room → exactly 1 floor, 1 ceiling, 4 walls; floor centred on the room with its **top at y=0**;
  ceiling at the room height (proving the no-centring convention)
- a doorway splits its wall into three pieces (6 walls total) with exactly **one lintel**
- two equal adjacent rooms → **7 walls, not 8** (the shared wall is built once)
- differently-sized neighbours → each stretch built once, verified by summing wall lengths on the
  shared line (8m total, not 11m)
- **physically real**: a ray down hits the floor, a ray through the opening passes, the wall beside
  it blocks, and the lintel above it blocks
- `build()` twice produces identical geometry
- the real ship layout builds 3 rooms, 2 doorways and 3 lights, and the player **stands on its floor**
- **mismatched room heights** leave no gap: with the SHORTER room built first (the order that used
  to break), rays above the short room's ceiling are blocked both over the doorway and over the
  short room's wall stretch, while the opening below stays passable — and the same holds with the
  build order reversed. Verified as a true regression test: it fails against the pre-fix builder
  with exactly those two errors.

Visual check: rendered the pod bay — walls, ceiling, the socket and crates, and the lit corridor
visible through the doorway.

Regression: all eight headless suites pass.

## Two traps worth remembering

1. **A script error inside an awaited coroutine kills it silently.** `quit()` is never reached, so
   the test *hangs forever* instead of failing — and piped output can be swallowed, making it look
   like nothing happened. This test now runs a **watchdog** that fails loudly after 90s. Worth
   copying into other async tests.
2. **Every builder in a test shares one physics space.** Leftover rooms from an earlier assertion
   block sat inside the next block's geometry and blocked its doorway ray. Each builder is now freed
   before the next, and the whole test world is freed before the ship scene loads.
