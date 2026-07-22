# Feature: Intro (countdown splash)

**Date:** 2026-07-22
**Status:** Done, verified

## What was done

- [scenes/intro.tscn](../../scenes/intro.tscn) + [scripts/intro.gd](../../scripts/intro.gd) (replaces the earlier stub).
- Black full-screen background, big red numbers (font size 256, `Color(0.9, 0.1, 0.1)`) counting down 10 → 0, one tick per second.
- After showing 0 for one tick, transitions to `scenes/main_menu.tscn` via `SceneManager.change_scene` (fade).
- **Skip** button (bottom-right): stops the countdown timer and transitions immediately.
- `scenes/main_menu.tscn` is currently a placeholder (label only) — the real menu is the next feature.

## How it was verified

- [tests/smoke_intro_scene_manager.gd](../../tests/smoke_intro_scene_manager.gd) (headless, 25× time scale):
  - background is black; countdown label starts at "10", is red, font ≥ 100
  - countdown reaches "0" and auto-advances to MainMenu
  - Skip stops the countdown timer and reaches MainMenu
  - Result: **INTRO/SCENEMANAGER TEST PASS**, exit 0
- Real-time proof: ran the actual game headless for 14s — `[SceneManager] changed scene to res://scenes/main_menu.tscn` appeared after the 11s countdown (10..0 at 1s per tick).

## Notes

- Total intro length is 11s (10 → 0 inclusive, then advance on the next tick).
- The Skip button works during the countdown; a press that lands mid-fade is ignored by SceneManager's re-entrancy guard.
