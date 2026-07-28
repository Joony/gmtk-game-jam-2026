# Aiming at things

**Status:** done, verified
**Diagnostic:** `tests/diag_aim.gd`

Reported as: items are fiddly to interact with, and it depends which angle they are at. The
hammer especially.

## Why

`Interactor._cast()` fired ONE infinitely-thin `intersect_ray` from the camera centre, first hit
wins. Zero tolerance, and deliberately so — the file's own comment says only a ray keeps the
reticle's promise that "you act on whatever the dot covers".

Measured over a ±6° aim sweep, standing 1.1m back at 1.55m eye height, the fraction of aim
directions that find each prop:

| prop | best orientation | worst | swing |
| --- | --- | --- | --- |
| pickup crate | 100% | 95% | 1.05× |
| oil can | 100% | 83% | 1.2× |
| canister | 100% | 66% | 1.5× |
| **hammer** | **82%** | **37%** | **2.2×** |
| spare screw | 28% | 19% | 1.5× |
| spare gear | 30% | 9% | 3.3× |

The hammer swings most among the normal-sized props because it is an **L**: handle across your
view is a long target, head-on is a small one. That is the angle dependence in the report.

**The collider is not at fault.** `diag_prop_bounds` has it matching the mesh at 1.00, and a box
around an L-shape is strictly *more* generous than the shape inside it. The hammer is no harder
to hit than it looks — it just looks small.

## The cone

Centre ray first; only if that comes back with nothing usable, rings of 8 rays at 1.6° and 3.2°,
walked inside-out, nearest hit wins within a ring.

**A cone of rays rather than a swept sphere**, and that is the whole reason this shape was
chosen: every ray still stops at its first hit, so a ray meeting a wall returns the wall and
contributes nothing. You cannot reach through geometry or around a crate. A swept sphere and a
nearest-within-an-angle search both leak past both and would need guarding.

Precise aim is never overruled — the centre ray wins outright whenever it finds anything, so the
reticle's promise holds in every case where it can be kept.

## What it bought, and what it cost

Modest, and worth stating plainly rather than claiming a fix:

- small spares roughly **double** their hit area (gear 9%→20%, screw 19%→35%)
- the **hammer gains about a degree** — it fails at 7° off without the cone and succeeds with it
- the big props were already fine and are unchanged

**The cost:** aim far enough off and the cone can answer with a *different* nearby prop. Rays in
a ring all share an angle, so ties break on distance-to-camera, and a neighbour closer to you
beats the thing you were pointing at. Measured in the cargo bay: aiming 8° off a hammer returns
a canister a hand's width away. Bounded by the ring radius, so `CONE_RINGS` is the knob — a
single 1.6° ring nearly removes it while keeping most of the spare-part gain.

## Two bad measurements on the way

Worth keeping, because both looked like results.

**A circular one.** The first version asked "what fraction of the silhouette hits?" and used the
same ray to decide whether an aim point was over the prop as it used to test the hit. It reported
a flat 100% for everything and could not have found anything.

**A misleading one.** The second compared the found object by identity against the prop, and read
"nothing" when the cone returned a *neighbour*. That made the hammer look completely unaffected
by the cone — an identical 618/1681 before and after — when in fact the cone was firing and
picking up something else. Printing what was actually returned, rather than whether it matched,
is what exposed the neighbour-capture behaviour above.
