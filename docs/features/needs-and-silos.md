# Needs & silos — six countdowns, three scripts

TODO 17 turns survival itself into countdowns, and — the part that matters — makes solving one
**start** another. Six systems were specified: CO2 → narcosis, hunger, thirst, bladder, the crap
tank, and power. They are all the same mechanic: *a thing that runs down (or fills up), and a
consumable you fetch to reset it*.

So there are three scripts, not six systems.

| Script | What it is | Lives on |
| --- | --- | --- |
| [`Need`](../../scripts/game/need.gd) | A countdown on the **player** — CO2 in your blood, hunger, thirst, bladder | a plain `Node` |
| [`Silo`](../../scripts/game/silo.gd) | The fixed container you walk to — life support, the beer silo, the vending machine, the toilet's tank | the `StaticBody3D` the ray hits |
| [`Consumable`](../../scripts/game/consumable.gd) | The carryable you fetch and spend on a silo | the `RigidBody3D`, like every other prop |

Adding a seventh system is a prop scene and a data row. It is never a new script — the same
reasoning that made `Malfunction`'s character data rather than code.

## Supply and waste are the same object

This is the trick the whole section rests on. `Silo.level` always means *how much stuff is in
it*, 0..1. A supply silo starts full and using it empties it; a waste silo starts empty and
using it **fills** it. That is the only difference, and it is one sign:

|  | supply (life support, beer, vending, power) | waste (the toilet) |
| --- | --- | --- |
| `use()` | level goes **down** | level goes **up** |
| `service(can)` | level goes **up** (bring a full canister) | level goes **down** (bring an empty one) |
| trouble | `level == 0`, nothing left to breathe | `level == 1`, nowhere left to put it |

`headroom()` — how much of the thing you can still do — therefore reads the same for both, and
the HUD, the `Need` and the tests are written once. `accepts` is still stated explicitly rather
than derived from the mode, because a waste tank wants an *empty* canister.

**Nothing in a `Silo` ticks.** A silo's level changes only when the player uses or services it.
The countdowns belong to `Need`, which is a body clock, not a tank — which is what stops "the
beer silo evaporates while you sleep" being something anyone has to think about.

## `becomes`: the canister cycle

Spending a canister does not have to destroy it. `Consumable.becomes` maps a kind to what it
turns into:

```
o2 --(fill life support)--> empty --(pump out the toilet)--> shit --> (get rid of it)
```

One exported dictionary, and it means the four canister models in `3D-Models`
(`CD_Canister_Air` / `_Empty` / `_Shit` / `_Beer`) can be **one prop scene** rather than four —
`kind_models` swaps which mesh is showing, the same technique as `RepairPoint`'s state visuals.

It is also the cheapest possible version of the tone this game is going for: solving one problem
hands you the next one, as an object, in your hands.

A consumable whose kind maps to nothing is used up entirely and leaves the world. `Silo` reports
that through `Interactable.consumed_last_item()` — the hook `Interactor` already uses to take a
fitted spare part out of the player's hands, so no new machinery was needed.

## Time is awake seconds

The single most important decision in `Need`.

- **Not real seconds.** A need that ticks in the pod kills a player who did the correct thing
  and slept through a long haul.
- **Not ship days**, unlike `Malfunction.speed_decay`. A fault degrades on the ship's clock
  because a drive keeps failing while you sleep; a body does not get hungry in stasis.

Awake seconds is the unit oxygen already uses, so the player can compare them directly: "180
seconds of CO2" and "240 seconds of air" are the same kind of number, and budgeting one trip
against the other is arithmetic they can actually do.

The guard itself lives with the **caller** — `RunState` already knows about `in_stasis`, so
`Need.advance(delta)` is simply not called in the pod, rather than `Need` reaching back through
a reference to ask.

## Not every need runs

`Need.active` is false by default. Six live countdowns do not fit in the oxygen budget, and that
is measured rather than guessed: the cargo bay is **67.1 m** from the pod, `Carry` holds exactly
one item, and at `max_speed = 7.0` a round trip is ~19 s — so six supply runs is ~115 s, **48% of
the entire 240 s budget**, before a single repair.

TODO 17d settles it as **stagger + long fuses**: only one or two needs are in play per run, and
their fuses are long enough that one trip services a need for a good while. Both are pure
`RunState` logic, so neither needs anything placed in the scene. Multi-carry is the better
long-term answer and is still on the list, but it needs a crate in the cargo bay.

`start()` is deliberately **idempotent**, and that is load-bearing for the chain below: drinking
a second beer must not silently reset a bladder that is already running, or the second beer is
free.

## The chain

Drink the beer → you need the toilet → the tank fills → it needs pumping out.

**Fixing thirst is what creates the toilet problem, and using the toilet is what creates the
explosion problem.** Nothing else in the game currently does this, which is why TODO 17c says
that if any of section 17 gets cut for time, cut *around* this chain rather than through it.

`Need.triggers` names the need that satisfying this one starts, and `satisfied(need, triggers)`
carries it out — but `Need` does **not** do the lookup itself. It has no business knowing about
the other needs; the set that owns them does. `smoke_needs.gd` assembles the whole chain from
the three components with no extra script, which is the evidence that Phase 1 is enough to build
it out of.

## Interaction

Two verbs, dispatched on what is in your hands — the split `Interactable` already does and
`RepairPoint` already uses:

```
empty hands             -> interact()      -> USE it. Breathe, drink, eat, flush.
holding a matching can  -> use_with_item() -> SERVICE it. The trip from the cargo bay.
```

Holding anything *else* makes a silo un-actionable, and that is not a limitation to work
around: `Interactor` sends a held item on an `ACTIVATE` target down the **drop** path, so a
green reticle there would promise a drink and deliver a dropped hammer. You need your hands free
to eat, and the prompt says so.

A full silo **rejects** a canister rather than swallowing it — a mistimed press would otherwise
cost the player a whole trip to the cargo bay.

## Tests

`tests/smoke_needs.gd` — one suite for the component set, not six near-identical ones, which is
the claim of 17a stated as a test. If it ever needs a seventh section per system, the claim was
false and the design should be revisited rather than the suite extended.

Every fixture is built in code (the `_make_plug()` technique from `smoke_cable_drag.gd`). Two
reasons and both matter: `scenes/game.tscn` is locked for editing elsewhere so there is nothing
placed to test against, and a suite about component logic must not be decided by whatever
furniture is in the ship this week — which is exactly how the cable suite broke when the bridge
was furnished.

Mutation-tested six ways, all of which go red:

| Mutation | What it proves |
| --- | --- |
| `_use_direction()` always `-1` | waste really is the sign-flipped supply, not a stub |
| `advance()` ignores `active` | the staggering actually gates ticking |
| `service()` skips the `matches` check | a silo does not take any old canister |
| `start()` always resets | the second beer is not free |
| `service()` skips the full check | a full silo does not swallow the can |
| `becomes` lookup returns `&""` | the canister cycle is real |

### Two gotchas found writing it

Both are in [debugging-gotchas.md](../debugging-gotchas.md), and the first is the dangerous one:

- **A GDScript lambda captures by value**, so `var hits := 0; sig.connect(func(): hits += 1)`
  increments a copy and the outer counter never moves. Four signal-count assertions read zero —
  and a test asserting `hits == 0` passes *vacuously* whether or not the signal works. Counters
  have to live in an `Array`.
- **`body as Consumable` is a parse error** when `body` is a `RigidBody3D`, because
  `Interactable` extends `Node3D`. Re-view through a `Node3D`-typed variable first.

## Phase 2 — the CO2 countdown, end to end

The first of the six systems, wired up in the real ship.

### Where the supplies come from

[`ShipSupplies`](../../scripts/level/ship_supplies.gd) is the supply counterpart to
`ship_layout.gd`: one table you can read down and rebalance, rather than sixty transforms
scattered through a scene file. It makes things real two different ways, and the difference is
whether the thing moves.

- **Adopt.** A silo is fixed furniture and is *already in the scene* as decor. So rather than
  spawning a second one on top of it, `ShipSupplies` reads the decor node's position and puts a
  functional `Silo` body there. Nothing is duplicated and nothing looks different — the prop the
  player can see becomes the prop the player can use. Positions are read off the decor node
  rather than copied into the table, so the two cannot drift apart.
- **Spawn.** A canister has to be picked up, and a decor `Node3D` cannot become a `RigidBody3D`.
  Loose supplies are spawned fresh at declared positions.

[`scenes/props/canister.tscn`](../../scenes/props/canister.tscn) is **one scene that is all four
canisters**. That is not tidiness for its own sake: a canister changes kind *in the player's
hands*, so the four models have to live on the same body or the swap would mean destroying and
respawning the thing being held, mid-interaction.

### Where the countdown comes from

`RunState.NEEDS` declares the needs and `start()` spawns them, alongside the faults it already
collects by group — the silos are found by group too, because those genuinely are objects in
rooms. A need has no position and no model; it is a number attached to the player's body, so
there was never anything for the scene to hold.

Three connections make the loop:

| | |
| --- | --- |
| the scrubber breaking | starts the CO2 clock (`Malfunction.broke` → `Need.start`) |
| using the life-support silo | resets it (`Silo.used` → `Need.satisfy`) |
| a canister from the cargo bay | recharges the silo (`Silo.service`) |

Neither the silo nor the need knows the other exists — `RunState` connects them by `silo_id`.

A **patch** on the scrubber does not put the air back. It stops the fault getting worse and
nothing more, so the countdown you are already on keeps running; only a fitted cartridge clears
it. That is the same bargain every other fault offers.

Dying of it says so. `Need.fatal_title` reaches the end screen through the run summary, so
`run_end.gd` never had to learn what a need is — it just stopped hardcoding "OUT OF AIR".

### The scaffolding, and how to remove it

Per TODO 17b the O2 SCRUBBER should stop attacking the drive and start this countdown instead,
but that is an edit inside the locked `scenes/game.tscn`. Two pieces stand in for it, and both
are one deletion each when the lock lifts:

- `"starts_with": "O2 SCRUBBER"` — the need names the fault that starts it, instead of the fault
  naming the need.
- `"neutralise": {...}` — strips the `speed_penalty` and `oxygen_drain_multiplier` the need is
  replacing, so the two effects do not both apply.

### Tests

`tests/smoke_supplies.gd`, against the real scene — deliberately, because the whole question is
whether the pieces find each other inside it, which a hand-built fixture cannot answer. It
covers: the silo landed in life support, canisters are in the cargo bay and are what the
scrubber takes, the clock does not run until the scrubber fails, it ticks awake and **stops dead
in stasis**, the HUD row appears only past the warning line, using the silo clears the need and
costs a charge, a canister recharges it and leaves you holding an empty, and running out ends
the run named `CO2 NARCOSIS` with air still in the tank.

Mutation-tested nine ways, including needs ticking in stasis, the scrubber keeping its old
penalties, the silo not clearing the need, and the supplies never being built.

**Two pre-existing bugs it caught**, both in `RunState.start()`:

- `finished` was cleared *after* the needs were spawned, and `_start_need()` refuses to act on a
  finished run — so a second run silently opened with its opening need switched off. Only on the
  second run, which is the worst kind of bug.
- `broke`/`repaired` were re-connected unguarded, so a second `start()` left every fault wired
  twice: double-counted patch failures and two klaxons for one impact. The run currently
  restarts by reloading the scene so it never bit, but `start()` reads as re-runnable and now is.

## Phase 3 — power, and the one tank that empties itself

The sixth system, and the only one that runs down without the player doing anything.

### Stasis stops being free

Every other silo is inert until someone touches it. The drive's fuel tank burns because the
**ship** is moving, so `Silo.drain_per_day` runs on the ship's clock — the same unit as
`Malfunction.speed_decay_per_day`, and for the same reason.

That is the whole point rather than an implementation detail. The pod was the cheap half of the
loop: oxygen drains at a reduced rate in there and nothing else moved against you. Now sleeping
burns fuel at **24×**, so a long stretch of stasis is a decision with a price, and the price is
a walk to the cargo bay.

At `0.11`/day against a ~31-day crossing, a tank is about nine days of travel — three or four
supply runs across a full voyage if you never sleep through a stretch, more if you do.

### Running dry stops the ship, but does not strand it

`stops_the_drive` makes an empty tank a **100% speed penalty** rather than a hard zero, so it
lands on the same `min_speed_fraction` floor that a pile-up of faults would. A drive frozen at
exactly nothing is an unwinnable run that the player still has to sit through, and the floor
exists precisely to stop that — power should not be the one thing that dodges it.

It is a flag on the silo rather than `RunState` matching on `silo_id`, so the tank can be moved,
renamed or duplicated without the consequence being wired to its name.

The recorded `power_off` line names the battery, so the computer now says it when the tank runs
dry — one of the nine idle voice lines from TODO 17j, wired.

### Where it stands

`scenes/props/silo.tscn` is a **spawnable** tank with its own model, for rooms that have no decor
silo to adopt. The engine room is one: its model was pulled when the animation turned out to be
broken, so the only thing dressed in there is four wall pipes.

It stands *off* the aft wall rather than against one, because every wall in that room is already
spoken for — DRIVE REGULATOR owns the port wall, MAIN DRIVE the aft, COOLANT LOOP the starboard —
and each panel needs 0.9 m of clear air in front of it. `smoke_navigation` caught the first
placement stealing exactly that from MAIN DRIVE.

`scenes/props/power_cell.tscn` is a `Consumable` of kind `battery`, which goes through the same
`Silo.service()` path an air canister does. **Not a `BatteryCube`** — that is the cable puzzle's
power source, which you plug a cable into to carry electricity somewhere. This is fuel: it goes
in and it stays in. They look alike and do entirely different jobs, so they are separate scenes
rather than one with a mode.

### Reading a tank without walking to it

Two readouts, because the tank is the first thing that can go wrong while you are nowhere near it.

- **A HUD row**, sharing the need rows. A tank running low and a body clock running down are the
  same problem to the player — *something needs fetching* — so they read as one list. Shown as a
  **percentage**, unlike both clocks: fuel is not convertible into "can I get there and back",
  and what the player needs is how much is left and what to bring, so the row says both.
- **An emissive lamp on the tank**, green through amber to red.

The lamp is a substitute for the thing the art invites, and the substitution is worth recording.
`CD_Silo_Base_v1` has a glass window with a liquid level in it, and driving that from
`Silo.level` looked nearly free — it is not. There is no separate liquid mesh, and the model's
geometry is offset from its own origin (at the ship's 0.171429 the drum occupies x −0.57..0.34,
z −0.34..1.42), so a code-built mesh would have to be hand-aligned against art that may move.
The lamp's own default offset is measured from those numbers rather than guessed, and it still
took a render to get it onto the tank rather than floating 11 cm beside it. The real fix is a
named liquid mesh from the modeller — TODO 17i.

### Tests

`smoke_needs` gains the draining tank in isolation: a day burns a tenth, ten days empties it,
`exhausted` fires exactly once and then goes quiet, a cell recharges it, and **a silo with no
drain emits nothing at all** rather than announcing a change of zero — which matters because
every silo is advanced every frame and `RunState` recomputes ship speed and rebuilds the HUD off
that signal.

`smoke_supplies` covers the wiring: the tank is in the engine room, cells are in the cargo bay,
emptying it drops the ship to the floor speed, and a cell gets it moving again.

The assertion worth naming is **that the run itself burns the fuel**. The first version called
`tank.advance()` by hand, which proved nothing about `RunState`, and a mutation that deleted the
burn loop entirely still passed. It now measures fuel-per-**ship-day** rather than per-frame — so
it does not depend on the headless frame rate, and because ship days already carry the pod's 24×
scale, proving the rate is per-day is also what proves that sleeping burns fuel faster.

## What is next

Phase 4 (the chain, as one unit) and Phase 5 (hunger). Plus the placements waiting on the scene
lock — TODO 17i, which also carries two things these renders turned up: `CD_Silo_Base_v1` ships
with no collider, so only the adopted silo is solid; and its glass level needs a driveable mesh.
