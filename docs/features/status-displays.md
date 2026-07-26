# Feature: Three status displays (step 20) — SPEC, not yet built

**Date:** 2026-07-26
**Status:** Specified. No code written. Replaces the HUD-only spec that was briefly at
`hud-status-map.md`. Builds on [ship-status-map.md](ship-status-map.md), which is done and verified.

Three displays, each with one job, instead of one console with two pages:

| | where | shows | answers |
|---|---|---|---|
| **NAV PLOT** | the console, cryo bay | `NavChart` | *where is the ship going* |
| **DECK PLAN** | the bridge console bank | `StatusMap` | *what is wrong with the ship* |
| **DECK PLAN, compact** | the HUD corner | `StatusMap` | *which way do I walk, now* |

> **A naming note first.** `ShipPlan` is already taken: it is the class holding the schematic node
> positions and the derived edges. The *drawing* is `StatusMap`. This document says **deck plan**
> for the thing on the screen and reserves `ShipPlan` for the data. `StatusMap` would be better
> named `DeckPlan`, but renaming it touches `computer.tscn`, `hud.tscn` and three test files, so it
> is a post-jam follow-up — the same call this repo already made for `Doorway`/`WallOpening`.

## 1. What this changes about what is already built

Almost nothing is thrown away. Phase 2 of the console gave `ComputerTerminal` two pages, an
automatic choice between them and a manual flip. **That becomes the behaviour of a screen that
declares both pages** — and the new arrangement is simply screens that declare one each:

```gdscript
@export var pages: Array[Page] = [Page.NAV, Page.STATUS]
```

- A screen with **one** page never flips, has no automatic choice, and its prompt names that page.
- A screen with **both** behaves exactly as the console does today.

That is the "option" in the request, expressed as one exported array rather than as a fork in the
code. The console ships as `[NAV]`, the bridge display as `[STATUS]`, and the current two-page console stays
a valid configuration that the existing tests already cover.

## 2. Why the bridge is the right home for the deck plan

This is the part that makes the split better game design rather than just more props.

Today the deck plan is on a console in the **cryo bay** — the room the player is already standing
in when they wake. It answers "which way do I walk" in the one room where the question has not been
asked yet.

The ship's own shape says where it belongs. From `ship_layout.gd`:

> *"The bridge is the hub: the cryo bay has exactly ONE door, up the spine to the bridge, and every
> other room hangs off the bridge or off a corridor that does. That makes every trip out pass
> through the bridge."*

So **every** excursion crosses the bridge, and the bridge is where the direction is actually
chosen. A deck plan there is read at the moment of the decision instead of three seconds before
it. It is also on the way back, which is when you find out what else broke while you were
out.

## 3. The deck plan on the bridge console bank

### Not a new prop — an adopted one

`CD_BridgeTerminals_v1` is already dressed on the bridge, and it is a better host than a table
would have been. From `scenes/game.tscn`:

```
[node name="CD_BridgeTerminals_v1" parent="Decor" ...]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.46991146, 0, -19.922993)
```

Unscaled 1:1, and the model is **15 × 1 × 5 units** — so it is a **waist-height bank of consoles
running the full width of the bow**, spanning x ≈ −7.03..7.97 and z ≈ −22.42..−17.42, with the
13 m forward window above it. Its centre sits at x ≈ 0.47 against the spine's centreline of 0.5.

That is as close to dead ahead of the spine door as makes no difference. Come up from the pod,
through the door at `(0.5, −12)`, walk forward, and **the centre panel of the bank is what you walk
into**. No new furniture, no clearance problem to solve, and a 1 m working height is exactly chart
height.

### It needs no new script either

`computer_terminal.gd` has nothing console-specific left in it — the interaction text is already
derived from the page, and the rest is "host a SubViewport, push it data on a timer, let the player
lean in". So the deck plan is that script, `pages = [STATUS]`, attached to the adopted node.

**Adopting decor is an idiom this project already has.** `ShipSupplies` takes the dressed silos and
the vending machine this way — reading the decor node's own position and rotation rather than
spawning a duplicate on top of it — and the same pass can take the terminal bank. `ComputerTerminal`
then becomes a misleading class name; renaming touches the locked `scenes/game.tscn`, so it is a
noted follow-up rather than mid-jam churn.

### What gets added to it

As **children of the decor node, in its local frame**:

- a `StaticBody3D` + collider over the chart panel, so the interaction ray finds it;
- a `SubViewport` (1024 × 640, as the console) with a `StatusMap` child;
- a `QuadMesh` on the panel surface carrying the viewport texture, unshaded;
- a `ViewPoint` marker for the reading pose.

**Parenting to the decor node is load-bearing, not tidiness.** `CD_BridgeTerminals` has an
outstanding bug — it is the only decor at unscaled 1:1, and at 5 m deep it reaches z = −22.42
against a fore wall at z = −21, so it currently passes through the hull and the forward window
(TODO step 9 list, and 17i). The fix is a scale on the node or a shallower model. **A display
parented in local space rides along with either**, so this feature does not have to wait on it and
cannot be broken by it.

The one thing that *would* break is a **shallower model**, which changes the panel geometry. Which
brings us to:

### The measurement this spec cannot make

I cannot read `.blend` geometry from here, so **the local offset and rotation of the chart panel
have to be measured, not guessed** — where on the 15 m bank the panel is, how far proud of it, and
whether the reading face is flat, sloped or upright. Take it from the editor, or render the bank
from the reading position and step the quad until it sits on the surface.

The capture test in §7 is what proves it landed, and it is the reason that test is not optional.

### Which panel, and which way the map points

**The centre panel**, because it is on the ship's centreline and therefore straight ahead as you
come through the spine door.

The reader stands **aft of the bank looking forward** — around `(0.5, -16.6)`, facing −Z — because
that is the only side of it there is. If the panel is flat or sloped, lay the map out **bow-up**
and two things hold at once, for free:

- map-up = away from the reader = **−Z = the ship's actual heading**, so the diagram and the ship
  physically agree and MESS really is on your left;
- the labels are upright, because the reader is on the one side they are drawn for.

If the panel turns out to be **upright**, the map reads like the console does, the labels are
upright automatically, and the ship-alignment idea simply does not apply — worth knowing before the
test in §7 asserts it. That is the first thing the measurement above settles.

### The camera has to look down, and today it cannot

`Game._open_nav_screen()` calls
`_glide_player(view.origin, view.basis.get_euler().y, 0.0, NAV_MOVE_TIME)` — **pitch hardcoded to
zero**, which was invisible while every readable thing was a wall-mounted CRT and is wrong the
moment a display is waist height. Take the pitch from the marker too, so `view_transform()`
describes the whole pose instead of half of it. `_glide_player_to()` also passes `0.0`, for the
stasis pod; that one is deliberate and stays.

Needed for a sloped or flat panel; harmless if the panel turns out upright.

### v1 or v2

The scene points at `v1`; `v2` was pushed and is dimensionally identical. The display is parented
to whichever node is there, so it does not care — but if the clipping fix swaps the reference, the
adoption should look the node up by a path that survives it.

## 4. The HUD copy

Unchanged in substance from the previous spec, and now with a clearer job because the bridge
display carries the detail.

**A `compact` flag on `StatusMap`, not a second class** — two would drift, the same argument that
keeps the console's two views of the chart on one class. When set: no title, no rule line, no
legend; a `PAPER` backing panel at ~0.8 alpha with a thin `INK` border, because the HUD sits over
the lit world instead of owning a screen; tighter margins; **labels only on rooms carrying a blob**;
and pixel floors on the label size and the thinnest stroke.

**Worked numbers at 1920 × 1080**, in a 460 × 260 rect — uniform scale 70.8 px/unit:

| | schematic | pixels |
|---|---|---|
| blob base radius | 0.190 | **13.5** (glow to ~35) |
| station ring | 0.145 | 10.3 |
| player dot | 0.075 | 5.3 |
| spine weight | 0.085 | 6.0 |
| arm weight | 0.060 | 4.2 |
| stub weight | 0.032 | **2.3** ← the pixel floor exists for this row |

Bottom-left at **`(60, -340)`–`(520, -80)`** is genuinely free: `Oxygen` is top-left
`(60,50)`–`(560,210)`, `Arrival` top-right, `SystemList` right at y 285–520, `StasisPanel` and
subtitles bottom-centre. §7 asserts the non-overlap from the real control rects, because every one
of those is liable to move.

Visible when there is at least one problem on it, the player is out of the pod, they are not
leaning into a screen, and the run has not ended — following the HUD's established rule that the
readout grows as things go wrong (TODO 17e) rather than shipping a permanent fixture and a toggle
key to teach.

## 5. The honest problem with having all three

**If the HUD map ships, the bridge display stops being a tool and becomes set dressing.** Anything
it tells you, the corner of your eye already told you, and you never have to stop walking. Better
to say that now than to discover it afterwards. It costs less here than it would have with a new
prop — the bank is already standing on the bridge either way — but the design point stands.

There is a resolution, and it is an onboarding arc rather than a restriction:

- the **bridge display** is the only place the ship's shape is *named* — every room labelled, the
  legend, and the rooms that are fine, which is how a player learns what the corner diagram means;
- the **HUD** map is deliberately stripped to marks and the two or three names you need right now.

So the bridge teaches the map and the HUD uses it. First excursion you stop and read; by the third
you glance at the corner. That is how signage works everywhere else, and it is a real reason for
both to exist.

**If that does not hold up in play, the lever is the HUD.** Make the corner map the thing that is
earned — it appears only once the player has read the bridge display at least once — and the bridge
is load-bearing again for the price of one boolean. Worth prototyping before it is worth building.

## 6. Files

| file | what |
|---|---|
| `scripts/game/ship_status.gd` | new. `class_name ShipStatus`, `static func collect(run, ship)` plus the three urgency statics, moved off `ComputerTerminal`. **Three consumers now, so one collector.** |
| `scripts/game/computer_terminal.gd` | `pages` export; delegates collection to `ShipStatus`; a single-page screen skips the flip and the automatic choice. Name becomes wrong — follow-up. |
| `scripts/level/ship_supplies.gd` *(or a sibling)* | adopts `Decor/CD_BridgeTerminals_v1` and hangs the collider, SubViewport, quad and `ViewPoint` off it in local space — the same adoption pass the decor silos and the vending machine already go through. |
| `scenes/props/computer.tscn` | `pages = [NAV]`, and its `StatusMap` child goes. |
| `scripts/ui/status_map.gd` | the `compact` flag and its pixel floors. |
| `ui/hud.tscn`, `scripts/hud.gd` | the corner map, `bind_status(plan)`, the visibility rules. `set_list_visible()` already exists. |
| `scripts/game.gd` | build **one** `ShipPlan` and hand it to all three; take the reading pitch from `view_transform()`; bind the bridge display alongside the console. |

No `scenes/game.tscn` edit.

## 7. Verification

Run the two measurements first — if the compact map is not legible and the quad does not sit on
the panel, the rest is wasted work.

**`tests/smoke_status_displays.gd`** *(headless)*

- **One collector, three consumers, never disagreeing**: table, console and HUD are fed from the
  same `ShipStatus.collect()` result on the same tick. *Mutation: give the HUD its own collector
  and confirm this fails.*
- **Page configuration**: a screen with `[NAV]` never shows the plan, never flips, and its prompt
  says so; `[STATUS]` likewise; a screen with both behaves exactly as `smoke_status_console`
  already asserts — **that suite must pass unchanged**, or the `pages` export changed behaviour
  rather than parameterising it.
- **The deck plan is ship-aligned** *(only if the panel is flat or sloped — see §3)*: transform the
  map's up direction by the quad's global basis and assert it points along **−Z**, so the diagram
  and the ship agree about which way is forward.
- **It is readable from its own marker**: the `ViewPoint` is aft of the bank, faces it, and its
  pitch is negative and non-zero — the bug the hardcoded `0.0` would otherwise hide.
- **The display rides with its host**: move or rescale the decor node and assert the quad, the
  collider and the `ViewPoint` all move with it. This is what makes the feature independent of the
  outstanding `CD_BridgeTerminals` hull-clipping fix, so it is worth asserting rather than assuming.
- **It is reachable**, via the existing `smoke_navigation` route: the reading position is somewhere
  the player can actually stand, and getting to it does not require squeezing past the bank.
- **HUD non-overlap**, computed from the real control rects: no intersection with `Oxygen`,
  `Arrival`, `SystemList` or `StasisPanel`.
- **HUD visibility**: hidden when clean, in stasis, while leaning into a screen, and after the run
  ends; visible the moment a fault breaks.

**`tests/capture_status_displays.gd`** *(needs a real renderer)*

- The bank shot from its own `ViewPoint`: the deck plan upright, sitting **on** the panel surface
  rather than floating above or sunk into it, the whole page in frame, and the camera actually
  pitched down. **This is the test that settles the measurement §3 cannot make** — it is not
  optional, and the offset is tuned against it rather than guessed.
- The HUD map at the real **1920 × 1080** with four problems across three rooms: every blob covers
  a floor of pixels, blobs on different rooms do not touch, the 2.3 px bridge stubs are still
  drawn, and a label appears for each blobbed room and no other.
- **Frame cost**, budget ~0.5 ms/frame. The console's map already costs nothing while the nav plot
  is up, because `_refresh_processing()` tests `is_visible_in_tree()`.

> **A shared optimisation, if the frame cost disappoints.** Every map redraws each frame while
> anything pulses. The fastest pulse on the page is `PULSE_MAX_HZ` = 2.2 Hz and the slowest is the
> player's dot at 0.35 Hz, so a **20–30 Hz** redraw is indistinguishable from 60 and costs a half
> to a third as much — across all three displays. Reach for that before cutting anything.

## 8. Build order

**Phase 1 — one collector.** `ShipStatus`; `ComputerTerminal` delegates. No visible change, and
`smoke_status_console` must pass **unchanged**.

**Phase 2 — `pages` as data.** Single-page screens; console set to `[NAV]`. At the end of this
phase the deck plan is temporarily nowhere, which is why Phase 3 follows immediately.

**Phase 3 — the deck plan on the bridge.** Adopt the terminal bank, measure the panel, fit the
quad and the `ViewPoint`, fix the reading pitch. The deck plan is back, on the bridge, where the
decision is made.

**Phase 4 — compact mode.** The flag and its pixel floors, measured at HUD size in isolation.

**Phase 5 — the HUD corner.** The control, the visibility rules, the shared plan.

Phases 3 and 5 are each independently shippable: the bridge display alone is a complete feature,
and so is the corner map. **If time runs out, build the bridge one** — it is the one that changes
where a decision gets made.

## 9. Not in scope

- The nav plot anywhere but the console. The voyage does not change fast enough to need watching.
- A fourth display (pause menu, end-of-run screen).
- Fixing `CD_BridgeTerminals`' hull clipping. It is a real bug and it is already on the list twice
  (step 9 and 17i), but the display is parented in local space precisely so this feature neither
  waits on it nor breaks when it lands.
- Routing, distances or walk times. The map says where the problems are; working out the order
  **is** the game.
