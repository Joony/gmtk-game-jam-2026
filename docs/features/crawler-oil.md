# The cargo crawlers, and the can of oil

**Status:** done, verified (three mutations killed)
**Suite:** `tests/smoke_crawler_oil.gd`
**Measurements:** `tests/diag_oil_crawler.gd`

## The bug that started it

"DRIVE REGULATOR — output regulator stuck open" played the voice line **"Them robots in the
garage need oil!"**. `game.tscn` had `vo_line = &"need_oil"` on the `DriveRegulator` node, and
`ShipFaults._configure()` only overrides `vo_line` when the row has that key — the DRIVE
REGULATOR row did not, so the scene's value stood.

The line describes a different machine in a different room, and the puzzle it describes did not
exist. It does now, and DRIVE REGULATOR has **no** voice line — stated explicitly in the table
(`"vo_line": &""`) rather than left absent, because an absent key is exactly what let the wrong
line survive.

## The puzzle

Two cargo crawlers were already dressed into the cargo bay as decor (`CargoCrawlerA` / `B`, at
0.71). They now seize: **CARGO CRAWLERS — loader bearings seized**, cleared by oiling either
machine with the can from the far side of the bay.

**AMBER, not red — and that is the point.** Every other fault on the ship is CRITICAL: klaxon,
ship-wide red alert, the lot. A run where everything screams has no register left to say *this
one actually matters*. `DEGRADING` gives an amber indicator and no alarm, and the drive cost
(3% rising to 6%) is small enough that this is a job you do because you are walking past.

**One fault, two repair points.** The seizure is one problem; the crawlers are two machines it
could be attended at. Two separate faults would double a chore meant to be small.

**No bodge.** `tool_group` is empty on these points, so the hammer offers nothing — you cannot
bash a dry bearing back to life. It is the only repair point on the ship with no patch route.

**The can is KEPT.** `RepairPoint.consumes_part` is new and false here. A spare part is welded
in and gone, which is the whole spares economy; a can of oil is not. There is exactly one can
and the seizure recurs (every 15 Mm), so consuming it would make the fault permanently
unfixable the second time. Mechanically it is the hammer's sibling: one trip to fetch it, then
a hand occupied for the rest of the run.

## Two pieces of machinery this needed

**`Malfunction.register_repair_point()` / `repair_points()`.** The fault could only be parented
to one crawler, and `Malfunction` found its panels by walking `get_children()` — so the second
crawler would never have repainted on a state change. Callers now ask the fault what repairs it
instead of inferring it from parentage; `smoke_run_state`'s "every malfunction is fixable" check
was doing exactly that inference and is updated.

**Adoption, again.** The script goes on the crawler model itself, not on a panel beside it.
`Interactor` resolves a hit by walking UP from whatever collider the ray struck, and the crawler
brings its own collision — so a separate node standing next to it would never be found. Same
pattern as the silos and the vending machine.

## Measured, not guessed

`tests/diag_oil_crawler.gd`, in a running scene (a freshly instanced node's `global_transform`
reports nonsense):

| | |
| --- | --- |
| `CD_Oil_v1` | 2.00 × 4.14 × 4.56 model units, origin at the base, long axis is the spout |
| at 0.17 | 0.34 × 0.70 × 0.78 m — a workshop oiler, a shade taller than the hammer |
| crawlers | dressed at 0.71, 7.8 m wide and 5.1 m tall, both in `cargo_bay`, 2 colliders each |
| crawlers | **no `Indicator` empty**, so the light is placed by hand and scale-compensated |

## Sizing

Built first at 0.085 (a 0.35m can) and **doubled** on sight: it read as a toy on the floor of a
cargo bay whose crawlers are five metres tall. Both the mesh offsets are half the model's own
extents, so they scale with it — at double the scale they are simply double. The spawn height in
`game.tscn` had to follow too: the origin is centred, so anything under half the can's height
starts it interpenetrating the deck.

`oil_can.tscn` is now in `tests/diag_prop_bounds.gd`, which is what catches a collider and a
model drifting apart when a `.blend` is re-authored. Collider and mesh agree at 1.00.

## Which way the spout points

Held, the can pointed its spout at the player's face. `Carry` aligns a held item's local axes
with the view (`_upright_facing_basis`), and `CD_Oil_v1` models its nozzle on **+Z** — measured
at +0.111 from the body origin — which is the end nearest the camera. The prop yaws the model
180 degrees, putting it at −0.111.

Worth knowing for the next prop with a front and a back: **this is invisible to every other
measurement.** The bounding box, the collider fit and the floor probe are all identical either
way round, so nothing that existed would have caught it. `smoke_crawler_oil` now asserts the
nozzle's own position, and the Z nudge that centres the lopsided mesh flips sign with the yaw
because it is half the mesh's extent — the symmetric Y drop does not.

## Mutations killed

- `consumes_part = true` — the can is eaten by the first crawler, and "you keep it" fails.
- crawler fault made CRITICAL — "amber, no klaxon" fails.
- `need_oil` put back on `DriveRegulator` — "has no voice line at all" fails, naming the line.
