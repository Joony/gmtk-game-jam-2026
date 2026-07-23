# Feature: Space exterior — backdrop shell, station, nebula

**Date:** 2026-07-23
**Branch:** `space-exterior`
**Status:** Done, verified

Three related changes that turn the windows from painted panes into real openings onto a scene.

## 1. Backdrop shell (the enabling change)

Windows were opaque quads with the starfield shader drawn on them. The parallax was real, but
**nothing was actually outside** — every pixel came from the view ray, so anything placed beyond
the hull would have been hidden behind the pane.

The starfield now lives on one **inverted sphere** (radius 1400m) around the ship, in the
`starfield` group. `RoomBuilder` builds no pane at all — just the opening and its glass — so each
window is a genuine hole.

Nothing about the starfield changed: it is position-based, so the streaming motion works as before.
`ShipMotion` drives the shell instead of a group of panes.

## 2. Space station

[scenes/props/space_station.tscn](../../scenes/props/space_station.tscn) — hub, ring, solar panels,
spar, and a couple of emissive strips, ~24m across and ~74m off the port side. Visible through the
pod bay's port window, correctly occluded by the hull and correctly parallaxed, because it is really
there.

**Exterior lighting is layer-separated.** The interior is lit by its own ceiling fixtures and must
stay that way (step 10's alert mode depends on it), so exterior geometry renders on **layer 2** and
`ExteriorSun` has `light_cull_mask = 2`. The sun lights the station and nothing inside — no leaking
through windows, no second lighting rig to reconcile.

**Scale limits.** Real geometry cannot sit at an astronomical distance: float precision and the
camera's 4000m far plane forbid it. 74m at 24m across reads correctly through a window. Anything
meant to look far more distant should be parented to the camera on a "far layer" so it never
approaches, or drawn procedurally — a planet is just a ray-sphere intersection.

## 3. Nebula band

A dark blue galactic band with cloud structure, added to the starfield shader.

Computed from the view **direction only**, never from position, so it behaves as if infinitely far
away: it does not slide past as the ship travels, which is correct for a galaxy. That is exactly
what a skybox would give — without needing one, an asset, or an Environment change.

- band: `smoothstep` on the angle from a galactic plane, whose pole is tilted off every world axis
  so it doesn't read as artificial
- clouds: 3-octave fbm on the ray direction; a second, coarser layer carves dust lanes so it isn't
  a smooth smear
- colour ramps from deep blue into a purple core, kept dim — this is depth *behind* the stars, not
  a light source

Everything is exported (`nebula_pole`, `nebula_color`, `nebula_core_color`, `nebula_strength`,
`nebula_width`, `nebula_scale`) for tuning by eye.

## Tuning: what is controllable, and where

**In game (debug keys, unpaused only):**

| key | effect |
|---|---|
| `=` / `-` | speed up / down — **multiplicative** (x1.5 per press), 0 to **60x cruise** |
| `]` / `[` | more / fewer stars, 5% of density per press |

A transient readout ([ui/debug_readout.tscn](../../ui/debug_readout.tscn)) shows the current values
for a second or so on change, then fades. It is a tuning aid, not part of the game HUD.

**In the inspector, on the `Motion` node** (`ShipMotion`): `cruise_speed`, `star_density`
(default **0.15**), `star_brightness`, `streak_at_cruise`, `travel_direction`,
`max_speed_multiplier` (60), `speed_step_factor` (1.5), `max_streak` (22).

Speed steps are **multiplicative**, not additive: additive steps cannot span 0 to 60x cruise in a
usable number of presses, whereas multiplying gives fine control when slow and a fast climb when
fast. From a standstill it starts at 4% of cruise, and stepping down below 2% snaps to zero.

**In the inspector, on the starfield material** (`assets/materials/starfield.tres`): `cell_size`
(smaller = denser field), `near_distance`, `star_angular_size`, `space_color`, and every `nebula_*`
value.

### ⚠️ Which uniforms are driven, and which are not

`ShipMotion` **overwrites** `travel_direction`, `travelled`, `brightness`, `streak`, `star_density`
and `destination_brightness` on the material **every frame**. Editing those in the inspector looks
like it does nothing — change them on the `Motion` node instead. Everything else on the material is
static and edits stick.

`speed_fraction()` stays clamped to 0..1 for game logic ("how healthy are we?"); `speed_ratio()` is
unclamped so the stars keep stretching above cruise.

## Warp streaks radiate from the vanishing point

First attempt smeared stars along the **travel direction**. That works out of a side window but
does nothing head-on: looking along the travel axis, a star's offset from the view ray is
perpendicular to the ray and therefore to the travel direction too, so the term cancelled and stars
stayed as points however fast the ship went.

Stars appear to move *away from the point you are travelling toward*. Projecting the travel
direction into the plane perpendicular to the view ray gives that apparent-motion direction, and one
expression then produces **radial** streaks ahead and **lateral** ones out of a side window. Dead
ahead the projection vanishes, which is correct — a star at the vanishing point does not move.

`max_streak` caps the smear (22), or past a point the sky becomes a white wash rather than lines.

## Stars vanishing mid-view

Reported in play. Two changes, and it is worth being clear about what each did.

**1. Exact grid traversal (a correctness fix that measured as no change).** The shader sampled the
star grid at fixed intervals along the ray. That skips cells whenever the ray is diagonal — a
diagonal ray crosses up to three cells per cell-length of travel, and only one was sampled — and
*which* cells get skipped shifts as the ship moves. It now walks the grid with a **3D DDA**
(Amanatides–Woo), visiting every cell the line of sight passes through, in order.

Measured with an "orphan" test — advance a fraction of a metre, then count bright pixels with no
bright pixel nearby in the next frame, i.e. stars that vanished rather than moved. At cruise the
result was **0.00% both before and after**, so this did not reproduce the reported symptom. It is
kept because it is strictly correct and removes a whole class of direction-dependent artifact.

**2. Field depth scaling with speed (the change that measured).** The field spans a fixed depth
range, so at speed a star crosses the *whole* range in well under a second: it fades in, streaks and
fades out almost at once. At 60x cruise the 15–700m range is covered in 0.63s.

`ShipMotion` now scales `cell_size`, `near_distance` and `far_distance` together with speed, which
leaves angular density and star size untouched but makes each star last proportionally longer.
Measured at 20x cruise over a quarter-second of travel: **0.2% of stars vanished before, 0.0%
after**.

**3. A distant star layer (the better answer).** Parallax was already depth-dependent — a star at
700m moves ~47x slower than one at 15m — but the field ended at `far_distance`, so *everything*
eventually streamed past. There was nothing to move against.

A **shell of stars at ~60km** now sits behind the near field. At that range their parallax over a
whole voyage is a fraction of a cell, so no marching is needed: one sample per ray, one hash. They
also **do not streak**, so at speed the near stars smear into radial lines while these stay as
points — which is precisely what makes the near ones read as fast.

Density is set in **angular** terms (`far_layer_angular_cell`, radians) rather than world units, so
the distant sky fills out independently of the near field's grid — important at 15% near density.

Because the shell supplies a permanent backdrop, `field_stretch_with_speed` was dialled back from
0.35 to **0.2**, recovering some of the sense of speed it was trading away. Still 0.0% vanished at
20x cruise.

### The trade-off, and the dial

Apparent motion is roughly `speed / cell_size`, so scaling the cell fully with speed would cancel
the sense of speed entirely — warp would look like cruise with longer streaks.
`field_stretch_with_speed` (default **0.35**) is the dial: **0** restores the old behaviour, full
speed sensation and short-lived stars; **1.0** gives maximum persistence and the flattest sense of
speed. The streaking carries much of the speed impression regardless.

## How it was verified

[tests/smoke_space_windows.gd](../../tests/smoke_space_windows.gd) — **SPACE WINDOWS TEST PASS**:

- exactly one starfield shell, carrying the shader, large enough to enclose the ship
- windows build **no pane** — a pane would hide anything outside the hull
- openings still genuinely cut (no wall covers the window's vertical range) and still glazed
- the station is outside the hull, inside the shell, on **render layer 2**
- the exterior sun's `light_cull_mask` is 2, so it cannot light the interior
- the shader exposes the nebula uniforms
- the four debug input actions exist; speed rises above cruise and the streak keeps growing with it;
  speed clamps at 0 and at 4x cruise; star density adjusts, reaches the shader, and clamps to 0..1

Visual checks: the forward window (nebula sweeping across a dense starfield) and the port window
(the station silhouetted against the band).

Regression: all ten headless suites pass.

## Two limitations worth knowing

- **Shader default values can't be asserted headlessly.** `get_shader_parameter()` returns null for
  any uniform never explicitly set — the value lives in the shader — and
  `RenderingServer.shader_get_parameter_default()` returns null with no rendering device. The test
  asserts the uniforms *exist*; their values are verified by screenshot.
- **The nebula costs ~6 noise evaluations per sky pixel** (two 3-octave fbm) on top of the 24-step
  star march. Godot sorts opaque geometry front-to-back, so walls reject most shell fragments by
  depth and the cost lands only on sky visible through windows — but this has **not been profiled
  on the web build**. If it bites, drop the dust-lane layer to two octaves or bake the band into a
  small cubemap once at startup.
