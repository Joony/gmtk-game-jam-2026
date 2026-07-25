# Feature: A critical fault bleeds the drive, and the bodge needs a hammer

**Date:** 2026-07-25
**Status:** Done, verified

A critical fault used to take its whole `speed_penalty` on the frame it broke, and **either**
repair route gave all of it back. That made the two routes trivial to compare — both cleared it,
so the patch was free and the spare part was only ever for the second failure. There was no
reason to walk anywhere.

Two changes, and they only work together.

## 1. Critical faults ramp instead of charging in one hit

[`Malfunction`](../../scripts/game/malfunction.gd) gains `speed_decay_per_day` and a running
`speed_decay`. While a critical fault stands, `speed_decay` climbs toward `speed_penalty` — which
is now the **ceiling of a ramp** rather than an instant charge, so every balance number already
in `game.tscn` kept its meaning ("this fault ultimately costs you 45% of the drive").

| Route | What it does to `speed_decay` |
| --- | --- |
| **Patch** (hammer) | stops the ramp, **keeps** the loss. Cheap, permanent, expires later. |
| **Proper** (spare part) | clears it to **zero**. Costs the walk — during which the ramp runs. |

That is the whole trade the request asked for: bang it flat now and carry the loss for the rest
of the run, or keep bleeding speed for the length of the walk to fetch a part and get it all back.
A patch that gives out **resumes the ramp from where it stood**, not from zero — the debt is
cumulative across a run.

**Why per DAY**, and not per distance or per real second:

- **Distance would be self-limiting.** The drive slows, so distance accrues slower, so the decay
  slows — the ramp asymptotes short of its own ceiling instead of biting.
- **Real seconds would ignore stasis**, and sleeping through a failing drive is exactly the play
  this has to punish. The ship's clock runs at `stasis_time_scale` in the pod, so per-day carries
  straight into it: `smoke_drive_decay` asserts the pod bleeds **more than 4× faster** than being
  awake does.

**DEGRADING faults are unchanged** — a flat toll while broken, cleared by either route. The ramp
is what makes the two severities read as different *kinds* of problem rather than two sizes of
the same one.

## 2. Patching takes the hammer from the janitor's closet

Patching used to be the empty-handed route, which made it free: the fallback you could always
fall back to, from anywhere, having planned nothing.

[`RepairPoint`](../../scripts/game/repair_point.gd) now dispatches on what is in your hands:

```
holding hammer -> use_with_item() -> PATCH, hammer kept
holding part   -> use_with_item() -> PROPER fix, part consumed
empty hands    -> interact()      -> nothing, and the prompt says why
```

- The hammer is **not consumed**. It is a tool, one serves the whole ship, and a player who lost
  it to the first panel would have no patch route left at all — unrecoverable in a jam build.
- Empty hands still get a **prompt** (`"MAIN DRIVE: need a spare part, or the hammer to bodge
  it"`) and the panel stays lit. A dead prompt is how a player concludes a panel is scenery, and
  this is the only place the game ever tells them the hammer exists.
- The hammer's prompt names what the bodge **locks in**: `"Clamp the coupling (temporary)
  (keeps -12% drive)"`. Without that number the player cannot price the two routes against
  each other.

`CD_Hammer_v1` is modelled ~5.75 units tall with its origin at the butt of the handle, so
[hammer.tscn](../../scenes/props/hammer.tscn) scales it to 0.32 m and drops it half its height to
sit centred on the body origin — otherwise `Carry` holds it dangling by the very end of the
handle. It is laid on its side in `game.tscn`; left upright it balances on its own handle end and
reads as placed rather than put down.

### The janitor's closet

A 3×4 m room hung off the **starboard side of the spine corridor** (`x` 2..5, `z` -11..-7), added
in [ship_layout.gd](../../scripts/level/ship_layout.gd) with a 1.0 m doorway at `x = 2`. On the
corridor rather than at either end on purpose: you pass the door on every walk to the engine
room, so forgetting the hammer is a decision rather than an ambush.

## The HUD had to change with it

A bleeding fault's line is **re-texted every frame** from `HUD._process()` rather than rebuilt on
`systems_changed` — watching the number climb while you decide *is* the mechanic, and a figure
that only moved when something broke would tell the player the loss was a one-off charge. The
line shows where it is now and where it is going: `"! MAIN DRIVE — injector coupling failed
(-12% drive, falling to -45%)"`. A patched fault's line carries what the bodge kept:
`"~ MAIN DRIVE — running on a patch, -12% drive for good"`.

`_system_lines` pairs each row with its fault so the text can be swapped in place; rebuilding the
list every frame would mean a `queue_free()` and a fresh `Label` per fault per frame.

## Balance

`tests/balance_sim.gd`, with the one-off hammer trip now modelled (`HAMMER_FETCH_SECONDS`):

```
ignore   SUFFOCATED  run 600.1s   air left   0.0s   0 perm / 0 patch   67.9 million miles
patch    ARRIVED     run 249.4s   air left  10.0s   0 perm / 9 patch   82.0 million miles
proper   ARRIVED     run 187.8s   air left 101.8s   3 perm / 2 patch   82.0 million miles
```

Patch-only now scrapes in on 10 s of air where it used to be comfortable; proper wins by 62 s and
92 s of air. Ignoring still suffocates. That spread is the point — the bodge is viable, not free.

Shipped rates: `MAIN DRIVE` 0.12/day to a 0.45 ceiling, `COOLANT LOOP` 0.10/day to 0.30.

## Tests

| Suite | Covers |
| --- | --- |
| [smoke_drive_decay.gd](../../tests/smoke_drive_decay.gd) | the ramp, its ceiling, patch-freezes / proper-clears, a failed patch resuming, DEGRADING unchanged, and a **real** stasis bleeding faster than being awake. Plus the hammer's group and its position inside the closet. |
| [smoke_interaction.gd](../../tests/smoke_interaction.gd) | the hammer ridden through the real carry path — picked up, patches, survives; empty hands repair nothing |
| [smoke_run_state.gd](../../tests/smoke_run_state.gd) | prompts and dispatch at the `RepairPoint` level |
| [smoke_navigation.gd](../../tests/smoke_navigation.gd) | the hammer is walkable to — the closet is the smallest room on the ship and the easiest to seal |
| [capture_closet.gd](../../tests/capture_closet.gd) | three renders: the corridor approach, the doorway, the hammer on the floor |

**Mutation-tested, seven killed:** no ramp at all; a patch that heals; a proper fix that does not;
no ceiling; bleeding on real time instead of ship time; the hammer consumed; empty hands still
patching.

### One trap worth remembering

`smoke_drive_decay` drives bare `Malfunction` nodes by hand to check the maths. They add
themselves to the `malfunctions` group in `_ready()` like any other, so `RunState.start()` swept
them into the real run and charged the ship 65% of its drive for faults that existed nowhere in
the world. They have to be freed before the scene loads.
