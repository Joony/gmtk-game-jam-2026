# Feature: The ship, redrawn from a plan image

**Date:** 2026-07-25
**Status:** Done, verified
**Branch:** `ship-layout`

The ship went from four rooms to thirteen (eight rooms, five corridor rectangles), transcribed
from a PNG the designer drew rather than authored by hand. Two side effects dominated the
work: the engine room moved to the other end of the ship and took ten props with it, and the
light count quadrupled, which broke GL Compatibility's renderer limits in two separate ways.

## The drawing is the source of truth

`room_layout_3.png`, 84x84 RGBA. **One pixel is one metre.** Five layers:

| Layer | Meaning |
|---|---|
| fully transparent (alpha 0) | hull / empty space |
| a room colour | that room's floor |
| opaque black (alpha 255) | corridor |
| white | a window, drawn on the room's own perimeter |
| grey | a door, drawn straddling the wall it cuts |

**Transparent and opaque black are different things and the distinction carries the corridor
network.** The first decode of this image flattened it to RGB, which turned both into black,
erased every corridor, and produced a confident but completely wrong reading of the ship as
nine rooms separated by 5–6m halls. If you re-derive the layout, decode the alpha channel.

Anchor: `grid_x = px_x - 42`, `grid_z = px_y - 41`. That offset is chosen so the cryo bay lands
exactly on its existing rect, which means every prop already placed in it keeps its
coordinates. Image up is forward (-Z), matching travel direction.

## Rooms

| id | Rect2i | height |
|---|---|---|
| `bridge` | `(-9, -22, 19, 10)` | 3.4 |
| `kitchen` | `(10, -17, 11, 11)` | 3.0 |
| `bathroom` | `(-8, -12, 7, 8)` | 2.4 |
| `janitor_closet` | `(2, -9, 6, 5)` | 2.4 |
| `life_support` | `(-29, -6, 13, 13)` | 3.6 |
| `pod_bay` | `(-10, -4, 21, 21)` | 9.3 — unchanged |
| `engine_room` | `(-39, 7, 21, 21)` | 4.0 — moved from `(-6, -22, 12, 10)` |
| `cargo_bay` | `(19, -1, 21, 33)` | 6.0 |

Corridors, all 3m wide and 2.6m high: `corridor` `(-1, -12, 3, 8)` (unchanged),
`corridor_fore` `(2, -12, 8, 3)`, `corridor_life` `(-16, -1, 6, 3)`, `corridor_engine`
`(-18, 10, 8, 3)`, `corridor_cargo` `(11, 10, 8, 3)`.

Eleven doors, sixteen windows. The drawing marks both one pixel wide; doors are built at the
ship's existing 1.8m, centred on the mark.

### The corridor bend is two rectangles, not one L

The drawing shows a single L-shaped corridor forward of the pod bay. It is built as two
rectangles because **RoomBuilder assumes rooms do not overlap** — each room raises its own
closed wall skin, so two overlapping rects each build a wall through the other's floor. The
split is at `x=2` (vertical) rather than at the bend's other diagonal, so the spine keeps its
original rect and its original comments stay true.

That leaves a seam where the two meet. It is closed with an opening that is deliberately not a
door:

```gdscript
var bend := add_doorway(Vector2(2, -10.5), Doorway.Axis.Z, 3.0)
bend.top = 2.6        # the corridor ceiling: no lintel is built above it
bend.fit_door = false # and no sliding panel is fitted
```

Full wall width, full wall height, so `_create_wall` builds neither a sill below nor a lintel
above and the corner reads as continuous floor.

## Moving the engine room

The room turned 90 degrees: it used to be entered from its aft wall with the drive on the
forward wall opposite; it is now entered from the east wall with the drive on the west wall
opposite. All ten props were carried by one rigid transform about the drive-wall centre:

```
(x, z) -> (z - 17, 17.5 - x)     basis: compose with R_y(90 deg)
```

so relative spacing — the 1m socket pitch, the ~11m gap from the outlet to the aux device that
makes the cable puzzle work — is untouched. Two props needed hand-seating afterwards:
`DriveRegulator` and `CoolantLoop` were mounted on the old side walls, and the room grew from
10m deep to 21m, so the rigid map left them floating mid-room. They are on the new aft and
fore walls at the same 0.17m clearance they had before.

**The basis literals are row-major** (see `debugging-gotchas.md`). Writing them from column
vectors produces the transpose, which for a rotation is the *inverse* rotation. This was
written wrong the first time and caught by `smoke_navigation`'s panel-facing assertions —
which is exactly the failure that assertion was added for.

## Lighting: two separate renderer limits

Thirteen rooms come to **93 omni lights**, up from about 23. Under `gl_compatibility` that
broke two caps at once, and they need different fixes.

**1. `max_renderable_lights` (was 32).** The renderer draws only its preferred subset for the
current view, so the set changed as the camera turned. Fixed by *culling per room* —
`LightingController.bind_occupancy()` lights only the room the player is in plus any room
within `cull_margin` (7m) of them, measured to the room's **rect**, not its centre. Gating is
per room and never per light: switching individual fixtures by distance would pop them on and
off as the player walks a long room. The set is recomputed only when the player crosses a
metre boundary.

**2. `max_lights_per_object` (was 8).** RoomBuilder emits **one box per floor and ceiling**, so
the cargo bay's 21x33 floor is a single mesh under 28 fixtures. Per-room culling does nothing
for this — the lights are all in the same room. Raised to 32 in `project.godot`.

**3. Light bleeding through walls.** Not a cap at all. The fixtures are shadowless on purpose
(shadows are what GL Compatibility cannot afford), and a shadowless omni with a 9m range
passes straight through a wall into the room beyond. Fixed with **one visual layer per room**:
each room's floor, ceiling, walls and light housings go on its own layer, and each fixture's
`light_cull_mask` is set to that layer plus layer 1. Layer 1 stays the shared layer for props
and the player, so a carried crate is still lit wherever it is taken — only the room *shell*
is confined, which is where the bleed was visible.

**Layer 2 is not free, and taking it broke ALERT mode.** `ExteriorSun` in `game.tscn` is a
DirectionalLight3D with `light_cull_mask = 2`, and `space_station.tscn` puts its meshes on
layer 2 to match — that pairing is what lets the sun light the station outside without leaking
into the interior. Numbering rooms from layer 2 handed the pod bay to the sun, so its shell
picked up a white directional light: the floor and the two walls facing the sun stopped
turning red in ALERT while the two facing away still did. Rooms now start at layer 3, leaving
18 of them; past that `RoomBuilder` warns and falls back to no confinement.

The general lesson: visual layers are a *shared* namespace across the whole project, and
nothing declares ownership. Before assigning a layer, grep for `layers` and `cull_mask`.

## Verified

`tests/smoke_ship_layout.gd` is new and checks the layout against the *drawing*, not against
`ship_layout.gd`, so the code failing to match the image is a test failure:

- all 13 rects exact, and no two rooms overlap
- 12 doors and 16 windows, each door on a wall shared by exactly two spaces
- every window faces open hull — none looks through into another room
- the corridor bend leaves no wall box across it
- every room reachable from the pod bay through doors alone
- every light's cull mask hits its own room's layer and no other room's
- no room sits on the exterior layer

**Proven able to fail.** Mutation-tested: moving the engine room 1m, giving the bend a normal
lintel, putting a window on an interior wall, turning `confine_lights_to_rooms` off, and
setting `FIRST_ROOM_LAYER` back to 2 each produce a failure; reverting each produces a pass.

ALERT mode is checked separately, because a surface lit by something other than its room's own
fixtures still *looks* lit — it just does not turn red with the rest of the ship. Measured as
redness, `r / (g + b)`, at the pod bay's floor and all four walls: 2.49–3.64 after the layer
fix, where a white-lit surface reads about 0.5.

Lighting measured rather than eyeballed, with `tests/capture_lighting.gd` — mean floor
luminance from four yaws on the spot, in three rooms:

| | before | after |
|---|---|---|
| cargo bay | 0.040 / spread 23% | 0.183 / spread **1%** |
| pod bay | 0.019 / spread 39% | 0.350 / spread **1%** |
| engine room | 0.068 / spread 44% | 0.249 / spread **5%** |

Two measurement traps worth recording, because the first two runs reported nonsense:
whole-frame luminance measures the *windows* (the nebula outside is far brighter than any
interior surface — point the camera at the floor), and the run opens in ALERT mode, which is
red at 1.15 energy and reads as near-black whatever the light count is. Force `Mode.NORMAL`
and hide the HUD before measuring.

Eye-level screenshots of all eight rooms, the corridor bend and two through-door views:
`tests/capture_ship.gd`.

## Tests changed

- `smoke_navigation.gd` — the flood-fill box was hardcoded to the old footprint, so the new
  engine room and cargo bay fell outside it and reported as unreachable rather than as
  out-of-bounds. Widened, with a comment saying to widen it whenever the ship grows.
- `smoke_space_windows.gd` — assumed the ship's first window was Z-spanning and filtered walls
  along a fixed axis. The bridge's forward pane became `doorways[0]` and the filter looked
  along the wrong one, reporting the opening as having neither sill nor lintel. Generalised to
  either orientation.
- `smoke_drive_decay.gd` — the hammer's world box follows the closet to its new rect.
