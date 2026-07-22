# Feature: Project structure

**Date:** 2026-07-22
**Status:** Done, verified

## What was done

- Created folder layout: `scenes/`, `scripts/`, `ui/`, `assets/` (with `.gitkeep` placeholders), plus `docs/` and `tests/`.
- Added input action `pause` bound to physical Escape in `project.godot` (`[input]` section).
- Set the main scene to `res://scenes/intro.tscn` (`application/run/main_scene`).
- Added a stub `scenes/intro.tscn` (Control + centered "Intro (stub)" label) so the main-scene setting is valid and the project boots. The real intro replaces this in the Intro feature.

## How it was verified

- `tests/smoke_project_structure.gd` (run with `godot --headless --path . -s tests/smoke_project_structure.gd`) checks:
  - `pause` action exists and is bound to Escape
  - main scene setting points at `res://scenes/intro.tscn` and the scene loads + instantiates
  - all four folders exist
  - Result: **SMOKE TEST PASS**, exit 0
- Full headless boot: `godot --headless --path . --quit-after 3` → exit 0, no errors.

## Notes

- Godot binary on this machine: `/Applications/Godot.app/Contents/MacOS/Godot` (4.7.1 stable).
- Esc is bound via `physical_keycode` so it works across keyboard layouts.
