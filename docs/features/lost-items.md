# Items falling through the deck

**Status:** done, verified (three mutations killed)
**Suites:** `tests/smoke_lost_items.gd`
**Diagnostics:** `tests/diag_floor_gaps.gd`, `tests/diag_floor_escape.gd`

Items could be glitched through the floor into the void and lost for good. This is what was
actually happening, and the two defences now in place.

## What it was NOT

Worth recording, because both were the obvious first guesses and both are wrong.

**Not a thin floor.** The deck is a 0.2 m slab, one box per room, top at exactly y = 0.
`diag_floor_escape.gd` slams all five prop types straight down at 12, 18, 30, 60 and **120 m/s**
— `Carry` caps release at 12 — and onto five doorway seams at 18 m/s. **Not one loss.** Every
prop scene sets `continuous_cd = true` and it holds. You cannot throw an item through this
floor.

**Not a hole in the geometry.** `diag_floor_gaps.gd` enumerates the 13 floor boxes and rains
1157 probes over every walkable square metre. **None escaped.** It does report that all 12 seams
between adjacent rooms are exact zero-overlap butt joints, and that every doorway on the ship
stands on one — but nothing falls through them at rest or under impact.

## What it actually was

**Depenetration.** A body that is *already inside* the slab when physics takes it over is
resolved to the nearest face, and past roughly the slab's midplane the nearest face is the
underside. There is nothing below the ship, so it falls for ever. Measured:

| depth into the 0.2 m slab | result |
| --- | --- |
| 0.02–0.10 m | pushed up, fine |
| **≥ 0.15 m** | **ejected downward — all five props** |

(The canister goes at 0.02 m; its collider hangs below its origin.)

So the question was never "how does it get through the floor" but **"what puts it inside the
floor"**. `Carry._clamp_to_walls()` sweeps **translation only** — the basis from
`_upright_facing_basis()` is written straight onto the body — so a long prop yawing with the
view near a corner can rotate itself into geometry, and the slide loop gives up after four
iterations regardless. `drop()` then unfroze it exactly there.

## The two defences

**1. The cause — `Carry` will not unfreeze a body that is inside something.** Every authored
pose is checked with `test_move(..., recovery_as_collision = true)` and the last clear origin
remembered; `drop()` backs the item up to it if the release pose is embedded. `recovery_as_
collision` is the whole trick: without it a zero-length `test_move` reports what a *move* would
hit, and a body sitting still inside a wall hits nothing.

**2. The net — `LostAndFound`.** Once a second, everything in the `interactables` group that is
a `RigidBody3D` and below y −0.5 is put back on the floor of the room it fell through (or at the
player's feet if it went through over no room). Carried items are skipped — their transform is
authored every frame from the hold point, so moving them would just fight `Carry`. Recovery is
silent to the player but emits a `push_warning`, so a loss is findable in a log rather than
invisible.

The net exists because the cause fix can only cover the cause we found. This is not cosmetic:
the run is balanced at thirteen spares against roughly forty-seven repairs, and the canisters
**are** the oxygen — one lost under a doorway can make a run unwinnable with no feedback at all.

## What the testing caught

The first version of `smoke_lost_items` **passed with the `Carry` guard deliberately broken.**
With the net running, those props were rescued within a second whatever `Carry` did, so the
section was testing the backstop twice and the cause not at all. The carry section now switches
the net off for its duration. Two defences are only two defences if each is proved on its own.

Three mutations killed: the `Carry` guard removed (all five props fall through), the sweep made
a no-op (nothing is recovered), and `FLOOR_ESCAPE_Y` raised so the net is over-eager (it
teleports 11 healthy props and the "disturbs nothing" check goes red).

---

## Follow-up: "look at the floor and throw" (2026-07-28)

The fix above did not stop items being lost by picking one up, looking straight down and
throwing. Playtesting kept reproducing it; roughly 200 headless throws — every prop, every
pitch, every look speed, both guards on and off — never did. What finally reproduced it was
building the smallest possible world (`tests/diag_void_repro.gd`): one room, the real player
scene, one prop, no `LostAndFound`.

### Two corrections to the account above

**The dip is real but was never the cause.** The held item does sink below the deck when you
look down — measured at −0.017 (canister) and −0.010 (hammer) in
`tests/diag_wall_vs_floor.gd`. But depenetration needs about **0.15m** to eject a body through
the underside, and 0.017 is an order of magnitude short. Two measurements were placed side by
side and a causal link asserted that neither supported.

**The old `drop()` guard was moving items on its own.** `_is_embedded()` asked
`test_move(..., recovery_as_collision)`, which answers `true` for a body resting *normally* on
the floor. So it fired on nearly every drop and silently teleported the item to
`_last_free_origin` — roughly chest height in front of the player, the last pose that had hung
clear of the deck. That relocation was visible in play and was mistaken for the item falling
through and being recovered. It is gone.

### What is there now

`_push_out()` and the release sweep, working as a pair:

- **`_push_out()`** lifts the held pose out along the contact normal every frame. The per-frame
  sweep clamps translation only, and the basis is written straight onto the body, so rotation
  can leave the shape overlapping. This closes that — every prop's dip becomes positive.
- **`_safe_release_origin()`** sweeps from the last clear origin to wherever the item actually
  is, and releases at the stopping point. In the ordinary case the sweep reaches its target, so
  nothing moves — no teleport.

They are only useful together. An earlier attempt at the sweep alone was a silent **no-op**:
without `_push_out` the remembered origins track the item down into the floor, so the sweep is
never blocked. `_push_out` is what makes "the last clear origin" mean anything.

### The launch — the actual cause

The minimal world showed the release velocity on a look-down throw was **(0, −6.1, +11.9)**. The
item was never falling through the floor. It was being **launched** at the `max_release_speed`
cap, horizontally, and whatever it hit decided where it ended up.

`_carry_velocity` was measured from the **hold point's** travel, and the hold point rides the
camera. Looking down swings it from 1.4m in front of you to under your feet in a fraction of a
second — mostly horizontal motion — so a flick of the mouse read as a fling.

Two narrower fixes were tried and both failed, in the same instructive way:

- **Sweeping the release direction** for geometry missed the player capsule entirely for narrow
  props; the canister and the spare gear still left at 11.9 m/s.
- **Projecting out the component aimed at the player** fixed those, but not the pickup crate or
  the battery cube — they are too big to fit under the player, so the sweep slides them
  *sideways* and that velocity points *away*, so nothing was projected out.

Both were about geometry when the cause was that camera rotation was being read as throw speed.
So it no longer is: release inherits the **carrier's** velocity (`Carry._release_velocity()`).
Momentum still transfers — run and let go and the item keeps your speed — and the deliberate
throw is the impulse, unchanged at 6.00 m/s forward. `_carry_velocity` is gone.

Measured after: a look-down throw is `(0, −6.0, −0.10)` for every prop, and a plain drop is
exactly zero. The downward component is left alone on purpose; the deck survives it, having
taken 120 m/s slams without a loss. Mutation-tested by restoring `_carry_velocity` verbatim,
which reproduces 11.89 m/s and fails the assertion.
