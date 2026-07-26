# Feature: 45° window corners (chamfers)

**Date:** 2026-07-26
**Status:** Done, verified

Cut the square corners off every space window so the opening reads as a chamfered rectangle —
a flat 45° face at each of the four corners — instead of a plain rectangular hole. The sci-fi
porthole look, and cheap: no change to the wall-splitting maths at all.

## The idea in one picture

The opening today is a rectangle bounded by jamb / jamb / sill / lintel. A chamfer is a small
right-triangular prism **added into each corner of the void**, its hypotenuse facing the room:

```
   lintel                      lintel
 ┌──────────┐                ┌──────────┐
 │          │                │╲        ╱│
 │          │       →        │          │
 │  (void)  │                │          │
 │          │                │╱        ╲│
 └──────────┘                └──────────┘
    sill                        sill
```

Crucially this is **additive, not subtractive**. Nothing about how walls split around openings
changes; the hole just gets four small solids dropped into its corners. That is what keeps this
a ~70-line change instead of a rewrite of `_create_wall_piece`.

## Geometry

Work in opening-local axes, as `SlidingDoor` already does — `along` (the axis the opening spans),
`up` (Y), `through` (the wall normal). One routine then covers both X- and Z-spanning windows.

Let `s = width * tile_size * 0.5`, `sill`, `top = opening.resolved_top(doorway_height)`, and `c`
the chamfer leg. The top-right wedge's cross-section is the right triangle

```
(s - c, top)   (s, top)   (s, top - c)
```

extruded through the wall depth. The other three are the same triangle mirrored in `along`
and/or `up`. Extrusion depth is the **half-thickness skin** (`wall_thickness * 0.5`) at the same
inward offset `_create_wall_piece` uses (`inward * skin * 0.5`) — windows are on exterior walls,
so only one room builds a skin there and the chamfer must sit in exactly that slab or it will
float proud of the wall face.

### Sizing

```gdscript
## Leg length of the 45° cut at each corner of a window opening. 0 disables chamfering.
@export var window_chamfer: float = 0.12
```

12cm reads as "small" against the ship's window sizes without eating the smallest ones. Clamp per
opening so a tiny window can't close up into a diamond:

```gdscript
var c := minf(window_chamfer, 0.3 * minf(span, height))
if c < 0.01: return
```

The binding case is the cryo-bay portholes — `add_window(..., 1.0, 1.2, 1.0)`, a 1.0 × 1.0 hole.
At `c = 0.12` that still leaves 76% of each edge as a flat run. The bridge's 17m window won't
notice the clamp.

## Material: the chamfer will be invisible unless it's tinted

This is the one non-obvious part, and `SlidingDoor` already learned it the hard way — see
`BEVEL_TINT` and the comment above it. Interior lighting is a grid of **shadowless** omnis
([room-builder](room-builder.md), [flat-lighting](flat-lighting.md)); under it an angled face
picks up almost no shading contrast against the wall it's cut from, so a geometrically correct
chamfer renders as a flat continuation of the wall and the whole feature is invisible.

Follow the door's solution exactly: emit the mesh with **vertex colours**, tint only the
hypotenuse face (~0.8× the wall colour is a reasonable start — the door uses a harder 0.5×
because its panels are light grey), leave the end caps white, and give the chamfers their own
material variant with `vertex_color_use_as_albedo = true`.

Two triangular **end caps** are visible: one flush with the wall's room-facing surface, one with
its outer surface, each a small triangle at the window's corner. Leaving them white (untinted)
makes them read as wall, which is right — they *are* wall. Tinting them too would put four
dark triangles on the flat wall face around each window.

The leg faces sit coincident with the jamb's and sill's inner faces, back to back and facing
opposite ways, so backface culling handles them — no z-fighting. Overlap them by ~1mm anyway,
the way `SlidingDoor.SEAM_OVERLAP` does, rather than relying on exact float equality between two
independently-computed positions.

## Implementation

All of it lands in `RoomBuilder`, plus a mesh helper.

1. **`_build_window(opening)`** ([room_builder.gd:233](../../scripts/level/room_builder.gd:233))
   gains a call to `_build_chamfers(opening)` after the glass.

2. **`_build_chamfers(opening)`** — four `MeshInstance3D`s (or one mesh with four prisms in it;
   four nodes is simpler and 17 windows × 4 = 68 nodes is nothing), each with
   `layers = room_layer(room_id)` and the chamfer material. **No collision** — the glass box
   already spans the whole opening, so nothing can pass through a corner. Add them to a new
   `GROUP_WINDOW_CHAMFER := &"space_window_chamfer"` so the test can find them.

3. **The prism mesh** — reuse the `SurfaceTool` + `_add_quad` / `_add_tri` idiom from
   `SlidingDoor._build_panel_mesh`: walk a convex 2D section, extrude, cap both ends, tint by
   edge index. Those two helpers are currently private to `SlidingDoor`; either lift them to a
   small shared static helper or copy the ~20 lines. **Copying is the right call mid-jam** —
   lifting them means touching a working, tested door.

   Watch the winding note in `SlidingDoor._add_tri`: Godot treats **clockwise** as front-facing,
   and mirroring a section for the opposite corner reverses its outline and turns the prism
   inside out. Three of the four corners are mirrored, so this *will* bite. `_add_tri` already
   handles it by checking the geometric normal against the intended one — keep that check.

4. **Which room's colour and layer?** `_build_window` doesn't know. `_create_wall` does — it has
   the room, the segment's `opening` *and* the wall's `inward` normal, which decides which side
   of the wall line the skin sits on. All three go into `_opening_walls[opening.id]`. (Interior
   doorways get claimed by both neighbours, last write wins; irrelevant here, since only windows
   are chamfered and a window is on an exterior wall.) Do **not** use `room_at()` — the opening
   sits exactly on the room boundary, where the test is ambiguous.

### Two details that only showed up in the writing

**The outward-normal shortcut doesn't port.** `SlidingDoor._build_panel_mesh` finds each edge's
outward normal by checking it points the same way as the edge's midpoint — which works only
because the door's section is convex *about the mesh origin*. A corner prism's section sits off
in one quadrant, so the same test flips two of the three faces inside out. `_chamfer_mesh`
compares against the section's **centroid** instead. `_add_tri`'s winding correction is still
needed on top of that, exactly as predicted: three of the four corners are mirrored.

**Push both legs out by the same amount.** `CHAMFER_OVERLAP` buries each leg face in the
surrounding wall so the two aren't decided by exact float equality. Displacing both legs by the
same `o` moves the hypotenuse's endpoints by `(o, o)` — so it shifts outward by 0.7mm and stays
at exactly 45°. Nudging only one leg would have skewed it.

## Scope: windows only

Doorways share the `Doorway` class and would chamfer with the same code, but a doorway's opening
is filled by two sliding panels sitting in the middle of the wall depth, and a chamfer in the
skin either side would overlap the panel at the top corners. Might look good, might look like a
bug. Out of scope — leave the code keyed on `fit_window`, and if it's wanted later it's a flag,
not a rewrite.

## What could break

- **`smoke_space_windows.gd` must stay green.** Two live assertions constrain this:
  - the "no pane" check counts `QuadMesh` instances under `Built` and requires zero. A chamfer
    is an `ArrayMesh`, so it passes — but *do not* build these as quads.
  - the "no wall covers the opening" check iterates `GROUP_WALL` and does
    `(body.get_node("Mesh") as MeshInstance3D).mesh as BoxMesh` then reads `.size`. **A chamfer
    added to `GROUP_WALL` would cast to null and crash the suite.** Own group, not `GROUP_WALL`.
- **Wall depth.** Getting the extrusion depth or inward offset wrong doesn't error — it just
  leaves the chamfer floating in front of the wall or buried behind it. Assert it.
- **Lighting layer.** Omit `layers = room_layer(...)` and the chamfer is on layer 1, lit by
  every room's fixtures — it'll read as a subtly wrong-coloured corner, and won't turn red in
  ALERT mode with the rest of the wall.

## How it was verified

Per [testing.md](../testing.md) — headless assertions for the geometry, screenshots for the look.

[tests/smoke_space_windows.gd](../../tests/smoke_space_windows.gd), all green:

- chamfer count is exactly `4 × window_count` — **17 windows, 68 chamfers**
- all four of the checked opening's chamfers sit in the wall's depth slab (`wall_thickness * 0.5`)
- all four stay **in the corners**: within the clamped leg of both an end and the sill or lintel,
  so none intrudes on the clear middle of the window
- all four tint their 45° face and use a `vertex_color_use_as_albedo` material — the assertion
  that stops the feature silently rendering as flat wall
- the four are at four **distinct** corners, which is what would catch a mirroring bug stacking
  two prisms in one place

**Proved each can fail** by re-breaking the code:

| mutation | result |
|---|---|
| `window_chamfer = 0.0` | 5 failures — count, found, depth, corners, tint |
| depth `wall_thickness` instead of `* 0.5` | `chamfers sit in the wall's depth slab (0/4)` |
| `CHAMFER_TINT = Color.WHITE` | `chamfers tint their 45° face (0/4)` |

Visual: [tests/capture_window_chamfer.gd](../../tests/capture_window_chamfer.gd), five views,
with an `off` argument that rebuilds at `window_chamfer = 0` and writes the same views suffixed
`_off` — so the before/after is diffed rather than remembered.

- **corridor window** (2.0 × 1.2m, the common case), dead on: a clean octagonal opening, all four
  corners cut, the 45° faces reading a shade darker than the wall. The `_off` shot is the same
  frame with square corners — the difference is obvious, which is the whole question the tint
  exists to answer.
- **bathroom porthole** (1.0 × 1.0m, the clamp's worst case): still reads as a chamfered opening,
  not a diamond. The clamp doesn't bite at 0.12.
- **cryo aft corner** and **bridge corner** (the 17m and 13m windows, close up): a 12cm cut is
  still clearly a facet at that scale.
- **bridge forward**, in situ: the wide window is unchanged where it matters.

The `_off` pass also settled a question the shots raised: the thin dark reveal visible around
every opening **pre-dates this change** — it's the wall's own depth, present in both sets.

Regression: **all 43 headless suites pass**.

### One gotcha in the capture script

Setting the player's position once and waiting for the scene to settle put the cryo-bay shot on a
blank side wall — gravity and the pod's collider walked them off the mark during the settle
frames. The camera is now pinned (position, velocity and look re-applied) on **every** frame of
the settle loop.

## Follow-ups this doesn't do

- No recessed frame — the chamfer sharpens the opening's edge but the window is still a hole in a
  flat wall. A recessed frame is the bigger visual win and is already noted in
  [space-windows](space-windows.md).
- Chamfering the **outer** face differently from the inner (a splayed reveal, wider outside than
  in) would sell hull thickness. The same prism builder does it with two different `c` values at
  the two ends of the extrusion.
