# Feature: Ship status map (step 19)

**Date:** 2026-07-26
**Status:** Done, verified. Both phases built.

A second page on the nav console: a **London Underground diagram of the ship**, with **pulsating
red and orange blobs in the rooms where something needs doing**.

The HUD fault list already says *what* is wrong. It has never said *where*. That is the one
question the player actually has to answer on waking — every fault is priced in walking distance,
and walking distance is priced in air — and today they answer it from memory. This is the readout
that answers it.

---

## 1. What it is

- Drawn entirely in `_draw()`, like [`NavChart`](../../scripts/ui/nav_chart.gd). No art assets.
- Lives on the **same screen as the nav plot**, as a second page: `ComputerTerminal` already owns a
  `SubViewport` whose texture is the console quad's albedo, so a second `Control` in that viewport
  is a second page of the same screen at no structural cost.
- **Octilinear**: every line runs at 0°, 90° or exactly 45°, fixed stroke weight, evenly-spaced
  stations. Beck's transformation — topology preserved, geography discarded.
- **Colour is reserved for trouble.** The diagram is drawn in the console's green ink like
  everything else on that screen; the *only* saturated pixels anywhere on the page are the blobs.
  A red blob is the single loudest thing the console can show, because nothing else competes.

### Why a second page rather than a second screen or a HUD overlay

A second prop would need a `scenes/game.tscn` edit, which is locked (see TODO 17i). A HUD overlay
would make the information free — and this game charges air for information, which is why reading
the nav plot walks the player to the console instead of opening a menu. The map costs the same walk
the nav plot does, and it should.

---

## 2. The diagram

### Topology is derived; only the drawing is authored

`ship_layout.gd` is emphatic that the room rectangles come from a drawing and must not be
hand-edited. A hand-authored map would quietly drift from the ship the first time a room moved.

So: **the schematic positions are authored, the connections are not.** Edges come from
`RoomBuilder.doorways` at runtime — for each doorway, probe 0.6 m either side of the opening with
`room_at()` and join the two rooms it separates (`Axis.X` spans X, so probe ±Z; `Axis.Z` probes
±X). A doorway that resolves to fewer than two distinct rooms is a bug in the ship, and the smoke
test says so.

That leaves exactly one thing hand-authored — where each room sits on the page — and a test that
fails the moment the ship gains, loses or renames a room.

### The plan table

The ship is already almost octilinear (rooms on a grid, corridors along X and Z), so the schematic
is close to a straightened version of the truth. Units are schematic, not metres: +x is starboard,
+y is aft, and the bow is at the top because travel is −Z.

| room id | schematic | glyph | label |
|---|---|---|---|
| `bridge` | (0.0, 0.0) | junction (double ring) | BRIDGE |
| `corridor_port` | (−1.6, 0.0) | tick | — |
| `kitchen` | (−3.0, 0.0) | station | MESS |
| `corridor_engine` | (−3.0, 1.6) | tick | — |
| `engine_room` | (−3.0, 3.0) | station | ENGINE |
| `corridor_stbd` | (1.6, 0.0) | tick | — |
| `life_support` | (3.0, 0.0) | station | LIFE SUPPORT |
| `corridor_cargo` | (3.0, 1.6) | tick | — |
| `cargo_bay` | (3.0, 3.0) | station | CARGO |
| `bathroom` | (−1.3, 1.3) | station | HEAD |
| `janitor_closet` | (1.3, 1.3) | station | CLOSET |
| `corridor` | (0.0, 1.7) | tick | — |
| `cryo_bay` | (0.0, 3.0) | terminus (double ring) | POD |

13 nodes, 12 edges, matching the ship's 12 doorways. The graph is a tree: a spine with two arms,
each running outboard and then aft to a flank room, plus two stubs off the bridge. No edge crosses
another, and the whole thing is symmetric about the spine — which is the ship's real shape, not a
flattering of it.

**Corridors are nodes, not just lines.** The tempting version draws corridors as the segments
between stations, but the O2 SCRUBBER stands in the spine corridor and a blob has to be able to
land there. Making every room — corridors included — a node means `room_at()` always resolves to
somewhere on the page and there is no special case. Corridors get an unlabelled tick; rooms get a
lozenge label.

**Lines are distinguished by weight and dash, not by hue**, because hue is spent on trouble. Three
lines — PORT, STARBOARD, SPINE. If that reads poorly on the CRT the fallback is three *shades* of
the same green (`INK`, mid, `INK_FAINT`), still not three hues.

**The player is a small pulsating white dot** on their own room, with a captioned **"YOU ARE HERE"
arrow** pointing at it. White is not a hue, so the two trouble colours keep the page to
themselves — red says repair, orange says fetch, white says *you*. The dot is deliberately about
40% of a blob's radius and pulses at a **fixed** 0.35 Hz, slower than the calmest blob: a blob's
rate carries how bad it is, and the player's location has no urgency to carry, so its rate says
nothing except that the screen is live. It must never be able to look like the most pressing thing
on the page. The arrow is drawn in green — it is the only annotation on the page about the player
rather than about the ship. It points **inward**, from a caption outside the diagram to the node,
which is what a mall map does and what makes it read as an annotation rather than as another
symbol on the line. Its direction is away from the middle of the diagram: every room on this ship
is on the perimeter, so outward is reliably the empty part of the page, and the caption is clamped
so a room near an edge cannot push it off.

*(Reversed during the build, 2026-07-26. The spec argued the marker would be a constant — the
console is bolted to the cryo bay, so the player is always in the same room when they can read
this. That is true today and it is still the wrong call: an arrow is what makes the diagram legible
as a map at all, it costs one string, and it stops being a constant the moment the map is readable
from anywhere else. `""` hides it, which is the honest rendering of a player standing in a
doorway — `RoomBuilder.room_at()` returns "" there.)*

---

## 3. The blobs

### Two colours, and they are the two verbs

The game already has exactly two responses to a problem — **repair it** or **fetch something for
it** — and the ship already colour-codes them, on every silo lamp in the world
(`Silo.LAMP_CRIT` / `LAMP_WARN`) and in every HUD row (`COLOR_CRIT` / `COLOR_WARN`):

| blob | colour | means | what to bring |
|---|---|---|---|
| **RED**, filled | `Color(1.00, 0.16, 0.12)` | an active `Malfunction` | the hammer, or a spare part |
| **ORANGE**, filled | `Color(1.00, 0.62, 0.10)` | a pressing `Silo` or `Need` | a canister, a cell, a crate |

Same values as the lamps, deliberately: the map and the room have to agree, and the player has
already been taught the code by walking past a tank.

A short legend strip along the bottom of the page spells it out — `● FAULT · REPAIR    ● WARNING ·
FETCH` — so the map teaches itself and no tutorial line has to. With a clean ship there is no key
at all, just `ALL SYSTEMS NOMINAL`: a legend for symbols that are not on the page is noise, and
without it "colour is reserved for trouble" is literally true rather than a figure of speech.

**Patched faults are not on this map** (decided 2026-07-26, during the build). A patch is not
somewhere you have to *go* — it is a bill that falls due later, and the HUD fault list already
carries it with the number that matters, the drive the bodge locked in for good. A third symbol
would dilute a page whose entire argument is that a blob means "walk here now".

### Where the blobs come from

All three sources are already on `RunState` and already emit `systems_changed` / `needs_changed`:

- `active_malfunctions()` → red, located by `room_at(malfunction.global_position)`. The
  `Malfunction` node *is* the place you walk to, so this is exact rather than approximate.
- `pressing_silos()` → orange, located by `room_at(silo.global_position)`.
- `pressing_needs()` → orange, located **by the silo that satisfies it** (`need.silo_id` →
  `silo_by_id()` → its room). A need has no position of its own, but it has a destination, and the
  destination is the answer to "where do I go" — a CO2 clock puts a blob on LIFE SUPPORT.

**Merge, don't stack.** A pressing need whose silo is also pressing is one problem to the player and
must be one blob. Dedupe by (room, silo) before drawing; the fault list on the HUD is where the
detail lives.

**Several problems in one room fan out.** The engine room can hold three faults and the fuel tank
at once. Blobs sit on a ring around the node — angle `i * TAU / count`, plus a hashed jitter so it
does not look like a clock face — because the *count* is the information. Three blobs on ENGINE
means three walks, and that should look as bad as it is.

### Shape and pulse

- A blob is **not a circle**. It is a closed polygon of ~20 points at radius `r · (1 + hashed
  wobble)`, filled with `draw_colored_polygon`, with two or three larger, fainter copies stacked
  behind it for glow. `NavChart._wobble()` is the hash to reuse — position-seeded, so the blob
  holds its shape between frames instead of crawling.
- **Pulse:** `pulse = 0.5 + 0.5 · sin(TAU · hz · t)`, driving radius (`0.85 → 1.15 · r`) and alpha
  together. Base radius is **constant** across blobs — the map must not lie about magnitude — so
  only the rate varies.
- **Rate encodes urgency**, 0.5 Hz to 2.2 Hz. This is the grammar the HUD already uses for the air
  vignette (`_update_air_pressure`, 0.6 → 2.4 Hz), where the *rate itself* is the signal:

  | source | fraction driving `hz` |
  |---|---|
  | bleeding critical fault | `speed_decay / speed_penalty` |
  | other faults | fixed: critical high, degrading low |
  | silo | `1 − headroom / warn_at`, topping out when exhausted |
  | need | `1 − fraction()`; lethal needs get the top of the range |

  A patched fault pulses slowly and steadily regardless — it is not getting worse, it is waiting.

### Redraw

`NavChart` is pushed on a 0.25 s timer because nothing on it moves fast. A pulse does. So the map
redraws per frame — **but only while there is something to pulse and the page is on screen**. With
a clean ship it is a static drawing and `set_process(false)`; a `_draw()` per frame for a diagram
that has not changed would be the same waste the nav plot's timer exists to avoid.

---

## 4. Which page the console shows

The console shows the **status map whenever anything is wrong, and the nav plot when the ship is
clean**. Walk past a console with a fault running and the damage is already on it — no press, no
menu, and the screen is doing the job a screen in a corridor should do.

While reading (`Game.NavPhase.READING`) the player flips pages with **`left` / `right`**. Those
actions are free — `_set_player_active(false)` has already switched movement off — so this needs no
new input action and no `project.godot` edit. The `NavScreen` hint becomes
`[E] STEP AWAY   ·   [A/D] FLIP`.

---

## 5. Files

| file | what |
|---|---|
| `scripts/ui/status_map.gd` | **built.** `class_name StatusMap extends Control`. `set_plan(plan)`, `set_problems(problems)`, `blob_layout()`, `_draw()`, the pulse clock. Knows nothing about `RunState`. |
| `scripts/ui/ship_plan.gd` | **built.** `class_name ShipPlan`. The table above, plus `from_builder(builder)` deriving edges from doorways, and the two drift guards. |
| `scripts/game/computer_terminal.gd` | `page` state, `set_page()`, auto-page logic, `push_to()` gains the map's counterpart `push_status_to()`. Collects problems from `RunState` and hands `StatusMap` plain dictionaries — the drawing code stays testable without a run. Also feeds `set_player_room(ship.room_at(player.global_position))`, the same call `RoomVoice` already makes. |
| `scenes/props/computer.tscn` | second `Control` in the existing `SubViewport`, `visible = false`. |
| `scripts/nav_screen.gd`, `ui/nav_screen.tscn` | hint text follows the page. |
| `scripts/game.gd` | `left`/`right` branch in `_unhandled_input` beside the existing `interact` branch. |

**No `scenes/game.tscn` edit.** Everything hangs off the console prop, the existing `RunState`
signals and group lookups — the same route `ShipSupplies` and `RoomVoice` took around the lock.

---

## 6. Verification

Per [`testing.md`](../testing.md): headless first, measure don't eyeball, and prove each check can
fail.

**`tests/smoke_status_map.gd`**

- Every room in `ShipLayout` has a node in the plan, and every node names a real room. *(the
  drift guard — this is the test the whole derived-topology decision exists for)*
- Every doorway resolves to two distinct rooms; edge count equals doorway count (12).
- Every edge is horizontal, vertical, or exactly 45°.
- No two nodes closer than the minimum spacing; no two edges cross.
- Problem collection against a live `RunState`: break a fault → exactly one red problem, at the
  room the fault node stands in. Patch it → exactly one hollow. Drain a silo past `warn_at` → one
  orange. Start a need whose silo is *also* pressing → **one** blob, not two.
- **Mutation:** add a room to a copy of the layout and confirm the coverage check fails. If it
  passes, the guard is decorative.

**`tests/capture_status_map.gd`**

- Render the 1024×640 viewport with three problems forced, at two pulse phases.
- Assert red and orange pixels appear **only** within the expected node neighbourhoods — a blob
  drawn on the wrong room is the failure mode that matters, and it is invisible to a smoke test.
- Diff the two phases: a measurable fraction of changed pixels inside the blob discs, ~0 outside.
  That proves it pulses *and* proves the rest of the page is static.
- Keep the PNG for eyeballing the tube-map legibility, which no assertion covers.

---

## 7. Build order

**Phase 1 — the drawing. DONE 2026-07-26.** `ShipPlan` + `StatusMap`, fed a hard-coded problem
list. Whole page renders, blobs pulse, `smoke_status_map` (331 checks) and `capture_status_map`
green. Nothing is wired to the run yet, so this phase was testable on its own and could not break
the game. Notes from the build are in §9.

**Phase 2 — wire it up. DONE 2026-07-26.** `ComputerTerminal` collects problems from `RunState`,
page toggle on `left`/`right`, auto-page, and the player's room fed from `Ship.room_at()`.
`smoke_status_console` (64 checks against the real `game.tscn`) and `capture_status_console`
green. Notes in §10.

Two phases, and that is the whole feature.

## 8. Not in scope

- **Walking costs on the segments** — metres, or seconds of air. Considered and dropped: the map
  answers *where*, and the segments stay unlabelled.
- Any second copy of the map (pause menu, end-of-run screen). One screen, one place to walk to.
  *(The HUD overlay was ruled out here on the same grounds and then reconsidered — the console
  turns out to be 9.8 m from the pod, so the walk it was protecting is 1.2% of the air budget.
  Specced separately in [status-displays.md](status-displays.md), which also moves the deck plan itself off this console and onto a plotting table on the bridge.)*
- Routing or pathfinding. The map shows where the problems are; the player works out the order,
  and that ordering *is* the game.
- Animating the player's position — the dot snaps between rooms rather than sliding.

## 9. Build notes — Phase 1

**`blob_layout()` is the drawing, not a description of it.** It resolves every blob to pixels
*including the current breath*, and `_draw()` consumes exactly that list. So the headless suite can
assert where every blob lands, what colour it is and that it pulses, without a renderer — and the
thing it asserts cannot drift from the thing that gets drawn.

**Three checks the spec did not ask for, added because the ones it did ask for were not enough:**

- **Orientation.** Coverage, edges, octilinearity and no-crossings between them still permit a
  *mirror image*: swap HEAD and CLOSET in the plan and every check passes while the map sends the
  player to the wrong side of the bridge. So for any two rooms genuinely apart on an axis, the
  schematic may not put them in the opposite order. Ties are fine — that is what straightening is.
  Proven by mirroring the two stubs: seven failures.
- **The graph is a tree.** 13 nodes, 12 edges, everything reachable from the bridge. A cycle would
  be a shortcut the oxygen balance does not know about.
- **A minimum check count.** A suite whose middle section dies still reaches its own summary and
  prints PASS for whatever ran. `MIN_CHECKS` closes that; it caught exactly this while the class
  names were still unregistered.

**Mutations killed:** a room added to the ship (coverage fails), a room removed (orphan fails), a
node moved off 45° (octilinear fails), the two stubs mirrored (orientation fails, 7 checks).

**Two drawing decisions the render forced.**

- *Labels are drawn last, over the blobs, with a paper-coloured outline.* Drawn in node order they
  went **under** the blobs — so ENGINE, the one room in enough trouble to be worth walking to, was
  the one room whose name you could not read.
- *The station rings are chunky* (`NODE_RADIUS` 0.145, up from 0.085). This screen is read from a
  couple of metres on the way past; a hairline ring reads as a dot and the diagram stops looking
  like a diagram.

**The legend only ever explains marks that are on the page.** Faults and warnings appear with the
first blob; the arrow appears when there is a player to point at; a clean ship says `ALL SYSTEMS
NOMINAL` and shows no colour key at all. Without that rule the capture test's strongest assertion —
*a clean ship has no saturated pixel anywhere* — would be false by construction, since the key
itself would be carrying red.

**A measurement trap worth recording.** The capture test classifies a blob pixel as `r > g`, which
works because colour is reserved for trouble. But it first attributed pixels to the *nearest* blob
within reach, and in a room with three fanned problems the glows overlap and tint each other — so
the orange DRIVE FUEL blob measured as 1444 orange against 1481 red and failed. The colour check
now reads the **core** only (within one base radius). A halo says nothing about whose blob it is.

## 10. Build notes — Phase 2

**One piece of real logic, and it is the merge.** A pressing CO2 clock and a life-support tank
running low are two rows on the HUD but **one errand** — one walk, one canister — so the collector
dedupes warnings **by silo**, not by room and not by need. Two blobs would say there were two
places to go. The merged blob pulses at whichever of the two is more pressing. Removing the dedupe
fails `smoke_status_console` on exactly that check.

**A need with no silo is skipped, and nothing is lost.** The only one is the septic countdown,
which is started by the crap tank being *full* — and a full tank is a pressing silo, so the
bathroom already has its blob from the silo pass.

**A problem whose room will not resolve is dropped, not guessed at.** `room_at()` returns `""` for
a doorway gap or a spot outside the hull. Placing the blob on the nearest room instead would be
the map telling a confident lie about where to walk. `smoke_status_console` asserts that every
fault and every silo *as actually placed in `game.tscn`* resolves to a room the diagram can draw —
which is a check nothing else in the project makes, and the one most likely to catch a real
placement bug.

**Urgency is read from what each thing already knows.** A bleeding critical fault reports how far
it has got toward its own ceiling (`speed_decay / speed_penalty`) — the same number the HUD row
shows — so **the drive's blob visibly speeds up the longer it is left**. It is floored at
`FRESH_CRITICAL` so a fault that has only just broken is not the calmest thing on the map. A need
is measured from its *warning line* rather than from full, because it only earns a blob once it is
past that line; measured from full, every blob would appear already half-lit and then barely move.

**The page logic is two lines and there is no menu.** The console shows the damage plan whenever
anything is wrong and the nav plot when nothing is, so walking past a console with a fault running
means the damage is already on it. `left`/`right` overrides it while reading — no new input action
and no `project.godot` edit, because `_set_player_active(false)` has already freed the strafe keys
— and `Game._close_nav_screen()` drops the override, or one glance at the nav plot would switch the
console off for the rest of the run.

**The HUD fault list now hides while reading the console.** Found in the first end-to-end capture:
the list runs straight across the middle of the view, and `! LIFE SUPPORT — EMPTY, NEEDS O2` was
sitting on top of the LIFE SUPPORT blob. It is the same information the page lays out spatially, so
losing it for those few seconds costs nothing. The two **clocks** stay up — reading the console
costs air, and hiding the gauge that says how much would hide the price of the thing the player is
doing.

**The end-to-end capture had to be measured RELATIVELY.** The obvious check — "is there red on the
console?" — is worthless in that room: a critical fault trips the ship-wide red alert, so the
walls, the ceiling and the HUD are all trouble-coloured and the count comes out identical whatever
is on the glass. It first reported 45,382 trouble pixels for all three pages. The test now compares
the two **pages** against each other with a control of the same page twice: 16.7% of the screen
changes on a page swap against 2.9% for the control.

**Mutations killed:** the silo dedupe removed (the merge check fails), the auto-page logic inverted
(six checks fail).
