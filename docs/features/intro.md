# Feature: Intro (countdown splash)

**Date:** 2026-07-22 (updated same day — two-digit countdown, holds on 01, now leads into the game)
**Status:** Done, verified

## What it does

- [scenes/intro.tscn](../../scenes/intro.tscn) + [scripts/intro.gd](../../scripts/intro.gd)
- Black full-screen background, big red numerals in the AbolitionTest display face.
- **Zero-padded two-digit countdown: `10, 09, 08 … 01`**, one tick per second.
- **Holds on `01` for `hold_seconds` (1.5s, exported), then fades out.** It never reaches `00` —
  the countdown is *interrupted*, not completed, which is the stasis wake-up beat.
- **Fades into `scenes/game.tscn`**, not the main menu (see below).
- **Skip** button (bottom-right) stops the countdown and transitions immediately.

## Flow change worth knowing about

The intro now leads **straight into the game**, so the launch route is:

```
Intro (10 → 01) ──► Game (START prompt) ──► play
```

The main menu is no longer part of the launch path. It is reached by pausing and choosing
**Quit to Menu**, and its Play button returns to the game. Both routes are covered by
`smoke_full_loop.gd`. If the menu should come first instead, it's a one-line change:
`NEXT_SCENE` in `intro.gd`.

## How it was verified

[tests/smoke_intro_scene_manager.gd](../../tests/smoke_intro_scene_manager.gd) — **PASS**, exit 0:

- background is black; the label is red with a large font
- the countdown is zero-padded (asserts it displays `09`, not `9`)
- it displays `01`
- **it never displays `00` or `0`** — asserted, since holding on 01 is the whole point
- it auto-advances to the **Game** scene
- Skip stops the countdown timer and reaches the game

Also verified rendered (PNG capture) and running in the web build.

## Notes

- `_finished` guards `_finish()`, so a Skip press landing during the 1.5s hold can't fire a second
  scene change.
- Total intro length is ~10.5s (nine ticks from 10 down to 01, plus the 1.5s hold).
- On web, a backgrounded/hidden tab throttles the frame loop and the countdown will appear frozen —
  a browser behaviour, not a bug. See [web-export.md](web-export.md).


## Hard cut into the game (2026-07-25)

Playtest: *"Transition from intro to game shouldn't fade but be a hard-cut instead."*

`SceneManager.change_scene()` takes a `fade` argument now, defaulting to true — most
transitions want the wipe to cover a load and give the player a moment. `intro.gd` passes
`false`.

The cut is the point. The game opens on a cold open — sealed in the pod, no HUD, no music, and
the klaxon of a fault that has already happened — and a fade announces that as a *scene change*.
Cutting straight from the last frame of the video to the inside of the pod lands it as something
happening TO the player instead.

A cut still zeroes the fade rect on the way through. The rect is shared, and a transition
interrupted part-way could leave it opaque — a hard cut onto a black screen is not a hard cut,
it is a hang.

`smoke_intro_scene_manager.gd` measures this rather than trusting the call site: it samples the
rect's alpha **every frame** of a transition and reports the peak. Reading it before and after
would prove nothing, since a fade is 0 → 1 → 0 and ends where it started. It asserts a peak of 0
for intro → game *and* a peak above 0.9 for a normal change — otherwise "hard cut" and
"SceneManager quietly lost its transition" look identical. Both mutations die.
