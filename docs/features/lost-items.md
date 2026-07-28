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
