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

## The starfield

[assets/shaders/starfield.gdshader](../../assets/shaders/starfield.gdshader), on a quad in the
opening. `unshaded` so the ship's own lighting — including red alert — cannot tint the view out.

Stars are at **fixed world positions** in a hashed 3D grid; advancing `travelled` streams them past.
Five slabs at increasing depth give parallax for free: the same world offset moves near stars
further in angular terms than far ones. The view ray is built per-fragment from
`CAMERA_POSITION_WORLD`, so the field parallaxes as the player walks past a window rather than
looking like a painted backdrop.

### The bug worth remembering

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

## Glass

Each opening gets a collision-only `StaticBody3D`. Without it the window is a hole: the player can't
fit through (the sill blocks them) but a **thrown crate would sail out into space**.

## How it was verified

[tests/smoke_space_windows.gd](../../tests/smoke_space_windows.gd) — **SPACE WINDOWS TEST PASS**:

- panes exist, use a `ShaderMaterial` with the shader loaded, and **all share one material**
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
