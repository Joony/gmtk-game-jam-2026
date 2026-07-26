# Feature: Ship status map (step 19) — SPEC, not yet built

**Date:** 2026-07-26
**Status:** Specified. No code written.

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

**No "you are here" marker.** The console is bolted to the cryo bay and the player is standing at
it whenever they can read this, so the marker would be a constant. The POD terminus is the anchor
the player actually navigates from, and it gets the emphasis instead.

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
| **RED, hollow ring** | same red | a fault running on a patch | nothing yet — it will come back |

Same values as the lamps, deliberately: the map and the room have to agree, and the player has
already been taught the code by walking past a tank.

A short legend strip along the bottom of the page spells it out — `● FAULT · REPAIR    ● SUPPLY ·
FETCH    ○ PATCHED` — so the map teaches itself and no tutorial line has to.

### Where the blobs come from

All three sources are already on `RunState` and already emit `systems_changed` / `needs_changed`:

- `active_malfunctions()` → red, located by `room_at(malfunction.global_position)`. The
  `Malfunction` node *is* the place you walk to, so this is exact rather than approximate.
- malfunctions with `is_patched` → hollow red ring, same location.
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
| `scripts/ui/status_map.gd` | new. `class_name StatusMap extends Control`. `set_plan(nodes, edges)`, `set_problems(problems)`, `_draw()`, the pulse clock. Knows nothing about `RunState`. |
| `scripts/ui/ship_plan.gd` | new. `class_name ShipPlan`. The table above, plus `from_builder(builder) -> {nodes, edges}` deriving edges from doorways. |
| `scripts/game/computer_terminal.gd` | `page` state, `set_page()`, auto-page logic, `push_to()` gains the map's counterpart `push_status_to()`. Collects problems from `RunState` and hands `StatusMap` plain dictionaries — the drawing code stays testable without a run. |
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

**Phase 1 — the drawing.** `ShipPlan` + `StatusMap`, fed a hard-coded problem list. Whole page
renders, blobs pulse, `smoke_status_map` and `capture_status_map` green. Nothing wired to the run
yet, so this phase is testable on its own and cannot break the game.

**Phase 2 — wire it up.** `ComputerTerminal` collects problems from `RunState`, page toggle,
auto-page. This is the phase that makes it a feature.

**Phase 3 — the walking costs (optional, and the best idea here).** Label each segment with its
length in metres, computed from the real geometry — then convert to **seconds of air** at the
current drain rate and walk speed. The ship is 7 m/s and air drains at 1.0/s, so a 20 m leg is
~3 seconds of the run's 240-second budget, and the map becomes a TfL walking-times diagram for a
currency the player is already counting. Better still, `RunState.player_speed_scale()` means **a
full bladder makes every number on the map go up** — the cost of ignoring your body, stated in the
units the player budgets in, on the readout they are already looking at.

Phase 3 is severable. Phases 1–2 are the feature the request asked for.

## 8. Not in scope

- Any second copy of the map (HUD overlay, pause menu, end-of-run screen). One screen, one place
  to walk to.
- Routing or pathfinding. The map shows where the problems are; the player works out the order,
  and that ordering *is* the game.
- Animating the player's position. See §2.
