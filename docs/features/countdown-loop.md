# Countdown loop (step 12)

The game, finally: two countdowns and the tension between them.

- **Distance** ticks down to arrival at the ship's current speed. Reaching zero wins.
- **Oxygen** ticks down in real time. Reaching zero loses.

Every unrepaired system slows the ship, so ignoring a problem does not cost you a life —
it costs you *journey*. Repairing costs air you can never get back. That is the whole game:
**is this fix worth the air?**

## Files

| File | Role |
|------|------|
| `scripts/game/run_state.gd` | Both countdowns, stasis, fault scheduling, end states, run summary |
| `scripts/game/malfunction.gd` | One breakable system: where it is, what it costs, when it fires |
| `scripts/game/repair_point.gd` | The panel you walk to; offers both repair routes |
| `scripts/game/stasis_pod.gd` | The pod interactable |
| `scripts/hud.gd`, `ui/hud.tscn` | Air and arrival clocks, fault list, low-air vignette |
| `scripts/run_end.gd`, `ui/run_end.tscn` | Win/lose screen with the run summary |
| `scenes/props/repair_panel.tscn`, `stasis_pod.tscn`, `spare_part.tscn` | Placeable props |
| `tests/smoke_run_state.gd` | 72 checks over every rule below |
| `tests/balance_sim.gd` | Plays the real numbers against three strategies |
| `tests/capture_countdown.gd` | Renders the six states to PNGs |

## Design decisions, and why

### The pod slows your breathing rather than stopping it

Originally the pod was free: air drained only outside it. That is the cleanest possible
mental model — *oxygen ≡ seconds spent outside* — and it was wrong. The balance simulation
showed the optimal play was to climb in, repair nothing, and ride a crippled ship the whole
way with the entire air budget unspent:

```
ignore   ARRIVED   run 701.5s   air left 240.0s   0 repairs   54.0 km covered
```

Nothing punished ignoring a fault, so there was no decision left in the game. The fix is
`stasis_oxygen_rate = 0.35`: the pod costs air, just cheaply. That prices the *journey* in
air as well as the excursions, which is what makes ship speed — and therefore every
repair — actually matter. The clean model survives mostly intact, and the fiction is better
for it (stasis is reduced metabolism, not suspended animation).

**The pod never refills air.** This is the load-bearing rule and it has its own test. One
pool for the whole run; the only thing that ever gives air back is a proper scrubber repair.

### Spares are generic and scarce

The first version gave every system its own named part sitting ready in the pod bay. The
simulation showed the consequence immediately: a permanent fix cost nothing beyond a patch,
so patching was never worth choosing.

Spares are now fungible (matched by the `spare_parts` group, not by name) and there are
**three of them for four scheduled faults** — plus any patch failures. So the run's central
question becomes *which systems deserve a real fix?*, and patching is the honest fallback
rather than a trap. The player carries one item at a time, so each excursion also forces
"do I take a spare, not knowing what I will find?"

### One panel, two routes, no new input

`RepairPoint` extends `Interactable`, and `Interactor` already dispatches on whether your
hands are full:

- **empty hands** → `interact()` → patch. Free and instant, but expires after
  `bodge_distance` and breaks again at the same panel.
- **carrying a spare** → `use_with_item()` → permanent, and the spare is consumed.

So the choice is expressed entirely by what you decided to bring. No second key, no radial
menu, no minigame. `interaction_type` must stay `USE_ITEM` for this to work — `ACTIVATE`
would route a held spare down the drop path instead.

`can_act_on()` is overridden to return true for any broken panel. The base class greys the
reticle out when you are not carrying an accepted item, which would have hidden the patch
route exactly when the player most needs to discover it.

### Patch expiry is measured in distance, not seconds

Otherwise patching and then sleeping would be strictly free, and the choice would evaporate.
Distance burns down during stasis too.

A patch restores **full** speed — its cost is that it expires, not that it works badly. One
consequence per choice is easier to read under pressure.

### Consequences are data, not code

Three branch types, all exported fields on `Malfunction`:

| Field | Branch | Used by |
|-------|--------|---------|
| `bodge_distance` | Patch re-breaks later | all four |
| `bodge_oxygen_cost` | Vent air to solve it | coolant loop (25s) |
| `repair_oxygen_bonus` | Proper fix recovers reserve | O2 scrubber (+30s) |
| `oxygen_drain_multiplier` | Makes you breathe harder | O2 scrubber (1.6x) |

Adding a fifth system is a node in `game.tscn`, not a new script.

Every branch appends a line to `RunState.choices`, which the end screen prints. A branch the
player cannot remember taking may as well not have branched — seeing *"Vented 25s of air to
patch COOLANT LOOP"* next to *"Your patch on MAIN DRIVE gave out"* is what makes a run into a
story, and what makes a patch failure read as your own decision rather than random
punishment.

### Stasis scales ship time, not real time

`ShipMotion.time_scale` is raised to 24x. `Engine.time_scale` would have been one line and
would have sped the player's own movement up with it. The starfield streaks at the scaled
rate, which sells the fast-forward for free.

The player's **camera keeps running** inside the pod. Disabling the whole `Player` subtree
was one line, but `CameraRig` is a child of it — the view would freeze on whatever you
happened to be facing when you climbed in, which reads as a crash. Movement, interaction and
carrying stop; looking does not.

### RunState owns ship speed during a run

Speed is a function of which systems are broken, rewritten every frame. `ShipMotion`'s debug
speed keys are therefore switched off for the duration
(`speed_driven_externally`) rather than left silently doing nothing, and `DebugReadout` no
longer pops up on gameplay-driven speed changes. The star-density keys are untouched.

## Balance

All tunable from `game.tscn` without touching code. Current values: 54 km journey, 18 m/s
cruise, 210s air, 24x stasis, 0.35 stasis air rate.

`tests/balance_sim.gd` plays three strategies against the real scene:

```
ignore   SUFFOCATED  run 600.1s  air left   0.0s  0 repairs                51.4 km covered
patch    ARRIVED     run 210.3s  air left  43.5s  0 perm / 7 patch (7 out) 54.0 km covered
proper   ARRIVED     run 170.1s  air left 144.8s  3 perm / 1 patch (1 out) 54.0 km covered
```

Doing nothing now suffocates you at 51.4 of 54 km — close enough to hurt. Pure patching
arrives on 43s of air; using the spares well arrives comfortably. That is the intended
shape: a viable-but-tight fallback and a rewarded optimal line.

Caveats: the simulation's walking times are estimates and the weakest input here, and it
models a player who never fumbles, never gets lost and never misses a panel with the
reticle. Real play will be slower, which is why `proper` deliberately keeps slack.

## Verification

`tests/smoke_run_state.gd` — 72 checks, all passing. It drives `RunState._process` by hand
rather than waiting on frames, so the rates are pinned exactly rather than measured against
whatever frame rate the machine happened to deliver.

Covered: distance rate; additive speed penalties and the floor that keeps an over-100%
run finishable; air draining only at the right rates; the pod never refilling; stasis
scaling ship time by exactly the configured factor; faults firing once on schedule and
waking the sleeper; patches expiring after their distance and re-breaking the *same* fault;
permanent repairs never re-firing; venting costing air immediately (and ending the run if it
takes the last of it); the scrubber multiplier; the recovery bonus capped at the run total;
win and lose each firing exactly once and never after the run ends; both panel routes;
group-based spare matching; and that the shipping scene has fewer spares than faults.

The two rules the design rests on were **mutation-tested** — the code was deliberately
broken to confirm the tests fail:

- made the pod refill air → 3 failures, including *"air after a long sleep is exactly what
  it was before (60.00 → 100.00)"*
- made patches never expire → 4 failures

Full regression: all 11 suites pass.

Screenshots via `tests/capture_countdown.gd` caught four things the headless tests could
not: the "vignette" was a flat full-screen wash that hid the panel being repaired (now a real
radial gradient), the debug readout was popping up on every malfunction, the four spare parts
were spaced so evenly they read as one continuous pipe, and the end-screen stats were
space-padded in a proportional font so the columns did not line up.

`tests/smoke_player.gd` caught a genuine level bug: the spares were first placed straight
across the walking line out of the pod bay, and the player could only travel 0.22m before
hitting one.

## Known gaps

- Repairs are instant once you reach the panel. The walk is the cost. A hold-to-repair
  timer would let the two routes differ in duration as well as in scarcity.
- The pod is a placeholder box. `CD_Cryo_v2.blend` is the intended model — it and its
  scratch scene are still at the repo root, so moving them needs coordinating first.
- Faults fire on a fixed distance schedule, so a second playthrough is identical.
  Randomising *which* system fires (never where the rooms are) is the cheap fix.
- Nothing yet uses `Malfunction.severity` beyond the red alert, and `SlidingDoor.jammed`
  is still unused as a fault type.
- No audio. The alarm beat in particular is carrying a lot of weight with no sound (step 13).
