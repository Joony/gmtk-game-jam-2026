# Feature: Font and UI theme

**Date:** 2026-07-22
**Status:** Done, verified

## What was done

- Font: `assets/AbolitionTest-Regular.otf` — a condensed bold display face that suits the
  industrial/sci-fi look.
- [ui/theme.tres](../../ui/theme.tres) — a Theme resource setting `default_font` and
  `default_font_size = 20`.
- Applied **project-wide** via `gui/theme/custom` in `project.godot`, so every Control picks it up
  automatically. No per-label font overrides anywhere, and new UI inherits it for free.

Existing per-node `theme_override_font_sizes` (the intro's 256px countdown, menu titles, buttons)
still apply — those override size only, not the typeface.

## How it was verified

Rendered every UI screen to PNG with [tests/capture_scene.gd](../../tests/capture_scene.gd) and
inspected each one: intro countdown, main menu, START prompt, pause menu. All render in the new
face at the right sizes and weights, with no fallback-font artifacts.

Also confirmed rendering in the exported web build.

## Notes

- Changing the game's typeface is now a one-line edit in `ui/theme.tres`.
- If a second face is ever needed (e.g. a readable body font for the interaction prompts in step 8),
  add it as a named theme type in the same resource rather than overriding fonts per node.
