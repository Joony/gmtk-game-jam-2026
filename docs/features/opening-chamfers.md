# Feature: 45° corners on the ship's openings (chamfers)

**Date:** 2026-07-26
**Status:** Done, verified. Windows first, doorways in a second pass the same day.

Cut the square corners off every opening in the ship — windows and doorways — so each reads as a
chamfered rectangle rather than a plain rectangular hole. The sci-fi porthole look, and cheap: no
change to the wall-splitting maths at all.

Windows were done first and doorways were explicitly scoped out, for a reason that turned out to
be real but solvable — see [Doorways](#doorways-three-differences). Both now share one knob,
`opening_chamfer`, because the point of the feature is that the ship's openings look like a set.

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
## Leg length of the 45° cut at each corner of an opening. 0 disables chamfering.
@export var opening_chamfer: float = 0.12
```

12cm reads as "small" against the ship's window sizes without eating the smallest ones. Clamp per
opening so a tiny window can't close up into a diamond:

```gdscript
var c := minf(opening_chamfer, 0.3 * minf(span, height))
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

1. **`build()`** calls `_build_chamfers(opening)` for **every** opening, next to the
   `fit_window` branch that builds the glass.

2. **`_build_chamfers(opening)`** — one `MeshInstance3D` per corner per side, each with
   `layers = room_layer(room.id)` and the chamfer material. **No collision** — a window's glass
   box already spans the whole opening, and a doorway's chamfers are at head height in the
   corners, where nothing needs stopping. They go in `GROUP_CHAMFER := &"opening_chamfer"` so the
   tests can find them.

3. **The prism mesh** — reuse the `SurfaceTool` + `_add_quad` / `_add_tri` idiom from
   `SlidingDoor._build_panel_mesh`: walk a convex 2D section, extrude, cap both ends, tint by
   edge index. Those two helpers are currently private to `SlidingDoor`; either lift them to a
   small shared static helper or copy the ~20 lines. **Copying is the right call mid-jam** —
   lifting them means touching a working, tested door.

   Watch the winding note in `SlidingDoor._add_tri`: Godot treats **clockwise** as front-facing,
   and mirroring a section for the opposite corner reverses its outline and turns the prism
   inside out. Three of the four corners are mirrored, so this *will* bite. `_add_tri` already
   handles it by checking the geometric normal against the intended one — keep that check.

4. **Which room's colour and layer?** `_build_chamfers` doesn't know. `_create_wall` does — it
   has the room, the segment's `opening` *and* the wall's `inward` normal, which decides which
   side of the wall line the skin sits on. All three are appended to `_opening_walls[opening.id]`,
   **one entry per side**: a window collects one, a doorway between two rooms collects two. Do
   **not** use `room_at()` — the opening sits exactly on the room boundary, where the test is
   ambiguous.

   `opening_skins(id)` exposes that count, which incidentally answers "is this opening on an
   exterior wall" — a question [space-windows](space-windows.md) notes nobody was checking.

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

## Doorways: three differences

Doorways share the `Doorway` class and chamfer with the same code, but three things about them
are genuinely different. All three are handled inside `_build_chamfers` rather than in a second
routine, because they are variations on the same shape, not a different one.

**1. Two corners, not four.** A doorway reaches the floor, so it has no bottom corners to cut. A
chamfer at floor level would be a moulding across the threshold that nobody asked for. The corner
list is `sill > 0.01 ? 4 : 2`.

**2. Two skins, not one.** A window is on an exterior wall, so exactly one room builds a skin
there. A doorway sits between two rooms and **both** build their own half-thickness side — so it
gets a set of chamfers per side, each in that room's own colour and on that room's own visual
layer. This is why `_opening_walls` holds a list per opening rather than a single entry; with
last-write-wins, one side of every doorway on the ship would have been left square.

**3. The panels are in the way — this is the real one.** A doorway's two panels sit centred on
the wall line and **slide sideways through exactly the region a chamfer wants to occupy**. A
full-depth chamfer, the kind a window gets, would have the panel grinding through solid geometry
every time the door opened. That is why doors were scoped out of the first pass, and the
objection was correct — it just has a fix:

```
        wall line
            │
  ╞═════════╪═════════╡   wall, 0.15 total
  │ chamfer │ chamfer │   the outer 0.03 of each 0.075 skin
      │  ╞═══════╡  │     panel, 0.08, centred — sweeps sideways
```

The chamfer is confined to the part of the skin the panel can never reach: from
`panel_thickness * 0.5 + PANEL_CLEARANCE` out to the full skin depth. With the current numbers
that is a 3cm-deep prism in a 7.5cm skin.

**Shallower does not mean less visible**, which is worth understanding rather than taking on
trust. Viewed straight on, what sells a chamfer is the **silhouette** — the hole is an octagon —
plus the end cap, which is flush with the wall face and the same colour as it. Neither depends on
the prism's depth. Depth only governs how much of the tinted 45° face you catch off-axis, and 3cm
is plenty for that. The screenshots bear it out: a door reads exactly like a window.

If the panel ever grows thick enough to fill the wall, `_build_chamfers` warns and skips that
opening rather than building geometry that clips.

## What could break

- **`smoke_space_windows.gd` must stay green.** Two live assertions constrain the geometry:
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

### Windows — [tests/smoke_space_windows.gd](../../tests/smoke_space_windows.gd)

- the chamfer count is derived from the ship's own data — `opening_skins × (4 for a window, 2 for
  a doorway)` — rather than hardcoded, so adding an opening cannot quietly leave it unchamfered
- the checked window's four chamfers sit in the wall's depth slab (`wall_thickness * 0.5`)
- all four stay **in the corners**: within the clamped leg of both an end and the sill or lintel,
  so none intrudes on the clear middle of the window
- all four tint their 45° face and use a `vertex_color_use_as_albedo` material — the assertion
  that stops the feature silently rendering as flat wall
- the four are at four **distinct** corners, which is what would catch a mirroring bug stacking
  two prisms in one place

### Doorways — [tests/smoke_door_bevel.gd](../../tests/smoke_door_bevel.gd)

Added to the suite that already owns the door panels' own bevel, so the two chamfers that meet at
a doorway are asserted in one place. Its two-room scene happens to give both skin cases: the
shared wall's doorway is cut through two, and the other opens onto nothing and is cut through one.

- `opening_skins` reports 2 for the shared doorway and 1 for the outer one
- six chamfers for the two doorways, i.e. **both sides** of the shared one
- every chamfer is at the **top**, not the threshold
- every chamfer **clears the slab the panels sweep through** — the assertion the whole doorway
  design turns on, and the one thing here that no screenshot could show
- every chamfer stays inside the wall

**Proved each can fail** by re-breaking the code:

| mutation | result |
|---|---|
| `opening_chamfer = 0.0` | 5 failures — count, found, depth, corners, tint |
| depth `wall_thickness` instead of `* 0.5` | `chamfers sit in the wall's depth slab (0/4)` |
| `CHAMFER_TINT = Color.WHITE` | `chamfers tint their 45° face (0/4)` |
| chamfer takes the full skin, ignoring the panels | `doorway chamfers clear the sliding panels (0/6)` |
| chamfer the threshold corners too | `at the top, not the threshold (6/12)` |
| one `_opening_walls` entry per opening, not per side | 3 failures — only 4 of 6 chamfers built |

That fifth mutation is worth keeping in mind: it first came back green, because the assertion
counted against a hardcoded 6 and six of the twelve chamfers *were* at the top. All three
doorway checks now count against how many chamfers actually exist, so each fails on its own terms.

### The look — [tests/capture_opening_chamfer.gd](../../tests/capture_opening_chamfer.gd)

Seven views, with an `off` argument that rebuilds at `opening_chamfer = 0` and writes the same
views suffixed `_off` — so the before/after is diffed rather than remembered.

- **corridor window** (2.0 × 1.2m, the common case), dead on: a clean octagonal opening, all four
  corners cut, the 45° faces reading a shade darker than the wall. The `_off` shot is the same
  frame with square corners — the difference is obvious, which is the whole question the tint
  exists to answer.
- **bathroom porthole** (1.0 × 1.0m, the clamp's worst case): still reads as a chamfered opening,
  not a diamond. The clamp doesn't bite at 0.12.
- **cryo aft corner** and **bridge corner** (the 17m and 13m windows, close up): a 12cm cut is
  still clearly a facet at that scale.
- **bridge forward**, in situ: the wide window is unchanged where it matters.
- **door closed**: the two panels with their V-groove, framed by cut top corners — the chamfers
  occlude the panels' own square corners, so the doorway reads as a chamfered frame.
- **door open**: the same opening with the panels retracted, framing the corridor beyond. The
  door is forced open and its `_physics_process` switched off for the shot: `door_approach` is
  1.6m, and from inside the trigger a 1.8m doorway overflows the frame.

The `_off` pass also settled a question the shots raised: the thin dark reveal visible around
every opening **pre-dates this change** — it's the wall's own depth, present in both sets.

Regression: **all 43 headless suites pass**.

### Two gotchas in the capture script, and a rule

Setting the player's position once and waiting put the cryo-bay shot on a blank side wall. Pinning
the position every frame fixed that one — but a second, subtler version survived it:
`CameraController` takes its **position** from the body's `get_global_transform_interpolated()`,
so a long jump between views makes the eye *glide* to the new spot over many frames. Two shots
came back mid-flight, aimed across the room at the wrong wall, and looked entirely plausible —
they were only caught by printing the camera pose next to each filename.

`physics_interpolation = false` for the capture helps but did not fully fix it. What did: the
script now **holds the mark until the eye is measurably on it** and refuses to save otherwise.

The rule worth keeping: *a capture script should assert its own camera pose*. A screenshot from
the wrong place is not obviously wrong — it is a picture of some other correct geometry, which
is exactly the failure mode a visual check is supposed to catch rather than produce.

## Follow-ups this doesn't do

- No recessed frame — the chamfer sharpens the opening's edge but the window is still a hole in a
  flat wall. A recessed frame is the bigger visual win and is already noted in
  [space-windows](space-windows.md).
- The door **panels** are still square-cornered; only the opening around them is cut. Chamfering
  the panels to match would mean the cut slides out of the corner as the door opens, which reads
  worse than leaving them rectangular. If it's ever wanted, it belongs in
  `SlidingDoor._build_panel_mesh`, next to the existing inner-edge bevel.
- Chamfering the **outer** face differently from the inner (a splayed reveal, wider outside than
  in) would sell hull thickness. The same prism builder does it with two different `c` values at
  the two ends of the extrusion.
