# Feature: Full loop verification (step 6)

**Date:** 2026-07-22
**Status:** Done, verified

## What was done

[tests/smoke_full_loop.gd](../../tests/smoke_full_loop.gd) walks the entire game loop **twice** in
a single run and asserts nothing leaks between rounds:

```
Intro -> (skip) -> Main Menu -> Play -> Game -> Esc -> Quit to Menu -> Main Menu
```

Steps 2–5 each verified their own slice; this proves they compose, and that going round again
behaves identically. Scene changes that orphan nodes are a classic jam bug — they don't error, they
just accumulate until the game mysteriously slows down late in a session.

Per round it checks: the intro is reached and skippable, Play reaches the game, the game is
genuinely live (player present, standing on the floor after 30 physics frames, tree unpaused), Esc
pauses, and Quit to Menu unpauses and returns to the menu.

Across rounds it compares `Performance.OBJECT_NODE_COUNT` and `OBJECT_ORPHAN_NODE_COUNT`, then
confirms no `Player` instance survives anywhere in the tree and the tree is left unpaused.

## Result

**FULL LOOP TEST PASS**, exit 0. Metrics were *identical* between rounds:

```
after#1 { "orphans": 0.0, "nodes": 12.0 } / after#2 { "orphans": 0.0, "nodes": 12.0 }
```

Zero orphans and no node growth, so `SceneManager.change_scene` is releasing scenes cleanly.

## Notes

- The test allows up to +5 nodes of drift between rounds to tolerate engine-internal churn; a
  leaked scene would be dozens of nodes, so the threshold is far below the signal.
- It waits for `SceneManager._changing` to clear between transitions — calls made mid-fade are
  dropped by the manager's re-entrancy guard, which would otherwise cause a flaky hang.
- The intro is skipped via its Skip button rather than waiting out the 11s countdown.
