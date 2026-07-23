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

## How it was verified

[tests/smoke_space_windows.gd](../../tests/smoke_space_windows.gd) — **SPACE WINDOWS TEST PASS**:

- exactly one starfield shell, carrying the shader, large enough to enclose the ship
- windows build **no pane** — a pane would hide anything outside the hull
- openings still genuinely cut (no wall covers the window's vertical range) and still glazed
- the station is outside the hull, inside the shell, on **render layer 2**
- the exterior sun's `light_cull_mask` is 2, so it cannot light the interior
- the shader exposes the nebula uniforms

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
