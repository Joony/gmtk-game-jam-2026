# Feature: START prompt (click-to-begin)

**Date:** 2026-07-22
**Status:** Done, verified on desktop; browser pointer lock still to be confirmed

## Why it exists

Browsers only grant pointer lock from inside a **user-gesture handler**. The game previously
captured the mouse from `game.gd._ready()`, which on web would likely be rejected, dropping the
player into the game with a free cursor and no mouse look.

Gating the game behind a START button solves it structurally: capture is requested inside the
button's `pressed` handler, which *is* a user gesture. It also gives a natural place to state the
controls, and a hook for audio initialisation later (browsers block audio until a gesture too).

## What it does

[ui/start_prompt.tscn](../../ui/start_prompt.tscn) + logic in [scripts/game.gd](../../scripts/game.gd).

- CanvasLayer (layer 60) above the pause menu: dim, a large **START** button, and a controls hint
  (`WASD TO MOVE · MOUSE TO LOOK · ESC TO PAUSE`).
- Shown on entry to the game scene. While it's up:
  - the cursor is **visible**
  - the player is frozen (`process_mode = DISABLED`) so it can't be moved behind the overlay
  - the pause menu is disabled via its new `enabled` flag, so Esc can't pause a game that hasn't
    begun (which would otherwise leave the START prompt and pause menu fighting over the cursor)
- On START: hides the overlay, re-enables the player and pause menu, captures the cursor, and
  emits `started`.

`game.gd` exposes `is_started` and `start_game()`, so tests can begin the game without synthesising
a click.

## How it was verified

`smoke_player.gd` (windowed) and `smoke_pause_menu.gd`:

- the player is frozen and the prompt visible before START
- the cursor is **free** while the prompt is up, and **START itself captures it** (windowed only —
  headless silently refuses capture, so the test probes with `MOUSE_MODE_CAPTURED` specifically to
  decide whether the assertion is meaningful)
- after START the prompt hides and the player runs
- Esc does nothing before START, and works after it
- `smoke_full_loop.gd` asserts the prompt gates the game on **both** entry routes (from the intro
  and from the main menu), twice over, with no leaks

In the exported web build the prompt appears and starting reveals the game. Pointer lock itself
could not be observed — see [web-export.md](web-export.md).

## Gotcha found while testing

A click that lands **during a SceneManager fade** is swallowed: the fade ColorRect sets
`mouse_filter = STOP` for the duration. Harmless (the player just clicks again), but it cost a
confusing minute during browser testing — the first START click did nothing because the fade-in was
still running.
