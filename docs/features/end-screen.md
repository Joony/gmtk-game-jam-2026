# The end screen

**Status:** done, verified (four mutations killed)
**Suites:** `tests/smoke_end_stats.gd` (the figures), `tests/smoke_run_end.gd` (the screen)
**Spec:** TODO 24

Both endings are the SAME screen. `RunEnd.show_result(won, summary)` branches on `won` for the
title and one subtitle line; everything below is shared. So every fault here was on the arrival
screen as well as the death screen, and every check runs in both states.

## Four of the six figures were wrong

**Distance covered — wrong unit and wrong arithmetic.**
```gdscript
"%.1f km of %.1f km" % [covered / 1000.0, total / 1000.0]
```
`total_distance` is **82.0 million miles** — the unit the HUD prints beside it all run. Dividing
by 1000 and calling it km reported **"0.1 km of 0.1 km" for an entire crossing**. Reproduced
exactly by mutation: at 61.5 Mm covered it still prints `0.1 km of 0.1 km`.

**Air spent — the same number for every death.** It was `oxygen_total - oxygen_remaining`, the
tank's CURRENT DEFICIT. Canisters refill the tank, so that is not cumulative — and every
suffocation ends at zero remaining, so it printed exactly `oxygen_total` for every run that ever
ended that way. It could not tell two runs apart. Now `air_breathed`, accumulated per frame
against what was actually available, plus anything vented on bodges.

**Air total — a dishonest denominator.** `oxygen_total` is the TANK, not the run's air: eight
canisters is another 1200s. Reported with **no denominator** now, beside **Canisters used**,
which is the real scarcity figure.

**The tallies never reset.** `start()` cleared the clocks but not `choices`, `repairs_permanent`,
`repairs_patched`, `patch_failures` or `air_spent_on_repairs`. A second run in the same scene
opened with the first run's totals. Latent, because restart reloads the scene — but `start()` is
written to be safe to call twice (see its own signal guards) and `smoke_supplies` restarts a run
in place.

**Added:** *Time survived*, in in-fiction days. The countdown is the game's whole subject and it
was not on the screen.

## The list had three separate problems

**It was not a list of tasks.** Things the player CHOSE and things that HAPPENED TO them were one
undifferentiated bullet list — "Your patch on X gave out" under the same dot as "Repaired X
properly". Now two arrays on RunState (`choices` / `events`) and two headed sections. Empty
sections are omitted, so a flawless run is not told what went wrong.

**It was unbounded.** A crossing throws about forty repairs across the same handful of systems.
Identical entries now fold into one line with a count (`Patched DRIVE COUPLER (temporary)  x4`),
which takes a typical run from ~40 lines to under ten.

**It did not scroll.** `Choices` was a bare `VBoxContainer` in a `CenterContainer` with nothing
capping its height, so it grew the layout past the viewport and took the **Continue button** —
the only way out of the screen — with it. Measured: with 60 entries the button landed at
y = 2500 in a 1920-tall viewport.

Collapsing and scrolling are both needed. Forty lines that scroll are still forty lines, and
scrolling alone would have left the summary unreadable.

## A trap worth remembering

The scroll assertion was **vacuous on the first attempt**. Mutating the height cap off the
`ScrollContainer` did not fail it — a `ScrollContainer` does not grow to fit its content, so
removing the cap makes it *smaller*. The regression only reproduces by restoring the original
layout (no scroller at all), which is what the mutation does now. A test aimed at a container
has to be mutated against the structure it replaced, not against its own parameters.

## Mutations killed

- the `/ 1000.0` km arithmetic — prints `0.1 km of 0.1 km` at 61.5 Mm.
- the `ScrollContainer` removed entirely — Continue button at y = 2500 of 1920.
- repeats not collapsed — four identical patch lines.
- `start()` not clearing the lists — a restarted run reports six stale entries.
