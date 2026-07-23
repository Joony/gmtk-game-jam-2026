# Feature: Window size → 1920×1080 (step 9a)

**Date:** 2026-07-23
**Status:** Done, verified

The project had never set a viewport size, so it ran on Godot's default **1152×648**.

## Why this had to happen before more UI

With `window/stretch/mode = "canvas_items"`, the viewport size is **both** the design resolution for
UI *and* the render resolution for 3D:

- Leaving it at 1152×648 and just enlarging the window would upscale the 3D — blurry.
- Raising it to 1920×1080 renders 3D crisply, but every hand-tuned pixel size in the UI becomes
  proportionally smaller on screen, because the same screen now spans 1920 units instead of 1152.

So the UI was scaled by the same factor (1920 / 1152 = **1.667**) to preserve the appearance that
had already been tuned by eye. Doing this later would have meant re-tuning type twice.

## What changed

`project.godot`: `display/window/size/viewport_width = 1920`, `viewport_height = 1080`.

Scaled by 1.667 across `ui/theme.tres`, `scenes/intro.tscn`, `scenes/main_menu.tscn`,
`ui/pause_menu.tscn`, `ui/start_prompt.tscn`, `ui/reticle.tscn`:

| | before | after |
|---|---|---|
| theme default font | 20 | 33 |
| intro countdown | 256 | 427 |
| menu title | 96 | 160 |
| buttons | 22–32 | 37–53 |
| reticle prompt / outline | 24 / 6 | 40 / 10 |
| reticle dot | 9px | 15px |
| button min sizes | 260×56 etc. | 433×93 etc. |

Button offsets, container separations and corner radii were scaled to match.

## How it was verified

Re-rendered every UI screen at 1920×1080 and compared against the earlier captures: main menu,
intro, START prompt, and the reticle with an interaction prompt. Proportions are unchanged — the
title spans the same fraction of the width, the reticle dot reads the same size — and the 3D is
visibly crisper.

The **reticle dot was the specific risk** (9px is small) and it holds up at 15px.

**Web export re-checked** (the open question from step 7): rebuilt and loaded in a browser. The
canvas is 1280×720 CSS / 2560×1440 backing at DPR 2, exactly matching the window — `adaptive`
resize plus `stretch/aspect = "expand"` means **no letterboxing** at any aspect ratio; a non-16:9
window simply sees more or less horizontally.

All nine headless suites pass.

## Not done deliberately

No `window_width_override` and no fullscreen default. The window opens at 1920×1080 and the OS
clamps it on smaller displays, which is fine — and the itch.io web build is the primary target,
where the canvas adapts anyway. Worth revisiting only if desktop builds become a real deliverable.
