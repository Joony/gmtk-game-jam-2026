# Feature: Space windows (step 11)

**Date:** 2026-07-23
**Status:** Done, verified

Windows in the ship's exterior walls, looking out at stars streaming past.

## Openings generalised, not duplicated

The TODO asked that window openings reuse the door-splitting logic rather than adding a second
path. They now do: `Doorway` gained `sill` and `top`, so **a window is just an opening that does
not reach the floor**. The wall builder emits up to two pieces per split segment — wall below (the
sill) and wall above (the lintel) — and a doorway is the special case where the sill is 0.

`RoomBuilder.add_window(position, axis, width, sill, height)`. `fit_door` / `fit_window` decide
what gets fitted into the hole.

The class is still called `Doorway`, which is now inaccurate — `WallOpening` would be better.
Renaming touches six files, so it's a noted follow-up rather than mid-jam churn.

## Architecture: backdrop shell, not window panes (2026-07-23)

The windows were originally **panes**: an opaque quad in each opening with the starfield shader on
it. That gave correct parallax, but nothing was actually outside — every pixel was computed from the
view ray. Anything placed outside the hull would have been hidden behind the pane.

The starfield now lives on a single **backdrop shell**: an inverted sphere (radius 1400m) around the
ship carrying the same shader, in the `starfield` group. Windows build **no pane at all** — just the
opening and its glass — so each one is a genuine hole. Real geometry outside the hull is simply
visible through it, correctly occluded by the walls and correctly parallaxed, because it is really
there.

Nothing about the starfield itself changed: it is position-based, so the streaming motion works
exactly as before. `ShipMotion` drives the shell instead of iterating a group of panes.

**Exterior lighting is layer-separated.** The interior is lit by its own ceiling fixtures and must
stay that way, so exterior objects render on **layer 2** and `ExteriorSun` (a DirectionalLight3D)
has `light_cull_mask = 2`. The sun therefore lights the station and nothing inside the ship — no
leaking through windows, no second lighting rig to reconcile with step 10's alert mode.

**Scale limits worth knowing.** Real geometry can't sit at a realistic astronomical distance —
float precision and the camera's far plane (4000m) forbid it. The station is ~74m out at ~24m
across, which reads correctly through a window. Anything meant to look far more distant should
either be parented to the camera on a "far layer" so it never approaches, or drawn procedurally in
the shader (a planet is just a ray-sphere intersection).

## The starfield

[assets/shaders/starfield.gdshader](../../assets/shaders/starfield.gdshader), on a quad in the
opening. `unshaded` so the ship's own lighting — including red alert — cannot tint the view out.

Stars are at **fixed world positions** in a hashed 3D grid; advancing `travelled` streams them past.
The shader marches 24 cells along the view ray, so parallax comes for free — the same world offset
moves near stars much further in angular terms than far ones. The ray is built per-fragment from
`CAMERA_POSITION_WORLD`, so the field parallaxes as the player walks past a window rather than
looking like a painted backdrop.

### Rework: flicker, and making the sky look far away (2026-07-23)

Reported in play: stars flickered — *"appear, sweep past a little, then disappear"* — and looked
too big and too close. Three distinct causes:

**1. Single-depth sampling made stars pop.** Each slab tested one point at a fixed depth along the
ray, so a star was only visible while it happened to sit in that thin slice. It is now a **march**:
`STEPS` samples along the ray with step length equal to the cell size, so every cell the ray passes
through is sampled and a star stays visible for as long as the line of sight actually passes near
it.

**2. Hard range cutoffs made stars wink out.** Stars vanished abruptly on crossing the near or far
end of the sampled range (the old far fade bottomed out at 0.15, not 0). Both ends now fade to
nothing with `smoothstep`.

**3. The field was too close.** Stars are now sampled from 15m out to ~1.1km (24 steps × 45m cells),
and sized by **angular** radius (~0.0018 rad) rather than world radius — so a star's apparent size
falls off with distance the way a real one does. Distant stars barely drift; near ones sweep past.

Measured rather than eyeballed, by rendering the same window at different `travelled` values and
comparing pixels:

| advance | mean pixel change, as a fraction of "a completely different sky" |
|---|---|
| before, 30cm (one frame at cruise) | **54%** |
| after, 5cm | **4.4%** |
| after, 30cm (one frame at cruise) | **25%** |

A tiny advance now barely changes the image, which is what persistent stars moving smoothly look
like. The residual per-frame figure is inherent: stars are 1–2px and genuinely move a couple of
pixels per frame.

### Follow-up: the cross of empty sky (2026-07-23)

Reported in play: a cross-shaped region through the middle of each window with no stars in it.

Cause: star centres are confined to the middle of each cell so a star cannot be sliced by a cell
boundary (only the cell containing the sample point is tested). That margin was a **fixed 20%**,
which creates a dead band wherever a sampled coordinate falls near a cell edge — and those bands are
the world-axis planes passing through the eye, which project to exactly a cross.

The near march steps did the damage. The dead band spans `2 * margin * cell / t` radians, so at
t = 15m with a 20% margin of a 45m cell that is **~69° of view**. At 1.1km it is negligible. Hence a
thick cross fading outward.

The margin now scales with the star's world radius, which is what it actually needs to exceed:

```glsl
float margin = clamp(star_angular_size * t / cell_size * 1.5, 0.004, 0.25);
```

The dead band is then a constant ~3× the star's angular size at every distance — about 0.3°, far
below one star's width. Verified numerically as well as visually: counting bright pixels along the
window's centre row and column versus off-centre lines now shows **no deficit** (10 vs 5 and 10 vs 1,
i.e. the centre lines have more, which is ordinary sampling noise).

Smoothness after the change: a 5cm advance is **1.5%** of a whole-new-sky change, better than the
4.4% measured before it.

### The earlier bug worth remembering

The first version tested *"is this sample point inside a star?"*. That makes visibility scale with
**radius cubed**, so shrinking stars to a believable size emptied the sky almost entirely — two
faint dots in a whole window.

The correct test is *"does the line of sight pass near the star?"* — perpendicular distance from the
**ray** to the star centre, which scales with radius squared. Same star size, a full sky.

Star centres are also confined to `[0.2, 0.8]` of each cell. Only the cell containing the sample is
tested, so a star straddling a boundary was being sliced and showed as a wedge artifact.

## Ship motion

[scripts/level/ship_motion.gd](../../scripts/level/ship_motion.gd) — the single source of truth, so
windows can never disagree about speed or heading. Same pattern as `LightingController`: values are
pushed to the `space_windows` group each frame, so a window built later picks up current motion with
no registration step. All windows share **one** material, asserted in the test.

- `speed` drives `travelled`; **zero stops the stars dead**, which is what a stalled ship should look
  like. Step 12 scales speed down per active malfunction.
- `streak` grows with speed fraction, so the stars smear when moving fast and are points at rest.
- `destination_brightness` is a hook for step 12's distance countdown — a soft point of light on the
  travel axis, hidden (0) until there's a distance to show.

## Window placement

Windows sit on exterior walls only — an opening onto another room would show stars through the ship.
The pod bay has port, starboard and two **aft** windows; the engine room has a port window and a
wide **forward** window. Travel is `-Z`, so the forward window is where the destination will appear
once step 12 turns `destination_brightness` on, and the aft pair look back down the wake.

## Glass

Each opening gets a collision-only `StaticBody3D`. Without it the window is a hole: the player can't
fit through (the sill blocks them) but a **thrown crate would sail out into space**.

## How it was verified

[tests/smoke_space_windows.gd](../../tests/smoke_space_windows.gd) — **SPACE WINDOWS TEST PASS**:

- there is exactly one starfield shell, carrying the shader, large enough to enclose the ship
- windows build **no pane** (a pane would hide anything outside the hull)
- the station is outside the hull, inside the shell, and on **render layer 2**
- the exterior sun's `light_cull_mask` is 2, so it cannot light the interior
- the opening is genuinely cut: **no wall piece covers the window's vertical range** at that
  location, while wall remains below (sill) and above (lintel) — checked geometrically
- every opening is glazed
- stars advance while moving and **stop dead when speed is zero**; streak grows at cruise and
  collapses at rest
- `speed_changed` fires; `speed_fraction()` is correct
- the destination hook is off by default and can be switched on

Visual check: the pod-bay port window — a dense field of streaked stars framed by sill, lintel and
jambs.

Regression: all ten headless suites pass.

## Follow-ups

- Rename `Doorway` → `WallOpening` (six files)
- Windows are only valid on **exterior** walls; an opening onto another room would show stars
  through the ship. The builder does not check this — the layout must.
- No frame mesh; the wall's own sill/lintel/jambs do the framing. A recessed frame would add depth.
- Light spill from windows into the room isn't implemented (would need a light per window).
