# Feature: Interaction & item pickup (step 8)

**Date:** 2026-07-22
**Status:** Done, verified

Interface and detection from GMTK 2025; carry physics from Doortal.

## 8a. Interactable — [scripts/interaction/interactable.gd](../../scripts/interaction/interactable.gd)

Ported from `/Users/joony/gmtk-game-jam-2025/Player/Interactable.gd`. Types
(`PICKUP` / `USE_ITEM` / `ACTIVATE` / `DISABLED`), prompt text, `accepted_item_names`, the
signals, and auto-registration in the `interactables` group all survive.

- **Dropped:** `interaction_range` / `interaction_angle` — detection is a ray now.
- **Kept `accepted_item_names` + `use_with_item()`**, previously marked "cut unless needed": the
  hook's repair loop *is* "carry the right part to the panel".
- **Added `can_act_on(held_item)`** — whether pressing E right now would actually do something.
  A `PICKUP` with full hands, or a socket the held item doesn't fit, returns false. This is what
  the green dot keys off; see 8d.

One concept, not two: the script attaches to whatever node owns the collider. For a carryable
prop that's the **RigidBody3D itself** — legal, since RigidBody3D *is* a Node3D — so
`get_item_node()` returns that body for Carry to hold. Doortal's separate `PickableObject` class
isn't needed; it existed for portal clip-shader meshes.

## 8b. Detection — [scripts/interaction/interactor.gd](../../scripts/interaction/interactor.gd)

Camera-forward ray (2.5m) each physics frame, then `find_interactable_in_hierarchy()` walks up
from the collider. Excludes the player body **and the held item** — without the latter the thing
in your hands blocks every ray.

Emits `focus_changed(interactable, prompt, actionable)`, and re-emits when the *prompt or
actionability* changes even though the target hasn't: looking at a crate while carrying one turns
"[E] Pick up crate" into "Hands full" with no change of focus.

Owns the `interact` / `throw` input. Priority order matters: if you're holding something and
looking at a `USE_ITEM`, E **uses** rather than drops — that's the repair loop.

## 8c. Carry — [scripts/interaction/carry.gd](../../scripts/interaction/carry.gd)

Doortal's `Carry.gd` is 755 lines, of which roughly 80% is portal machinery — beam forwarding
through portal chains, clip-clone meshes, cross-room physics-server sets, transit tick budgets,
cable-plug cooperation. None applies here. The extracted mechanism is ~180 lines:

- while held the item is a **frozen KINEMATIC RigidBody3D** whose transform is authored every
  `_process` from the HoldPoint under the camera — 1:1 with the view, no physics-clock lag
- `physics_interpolation_mode = OFF` while held, or interpolation fights the per-frame authoring
- **wall-sweep clamping**: a per-frame `test_move` collide-and-slide so items are pushed aside by
  walls instead of clipping through
- **break-free** when a wall holds the item beyond `break_distance` for `break_grace`
- release keeps a smoothed, capped carry velocity so items can be flung; `throw` adds an impulse
- `process_priority = 10` so it runs *after* CameraController (priority 0) — otherwise the held
  item renders a frame behind the view

Simplified from Doortal: the held orientation is yaw-only upright (their `upright_facing_basis`
mapped local +Z to world up for their cube's axis convention), and the item's hold state lives in
Carry rather than in a `PickableObject` subclass.

## 8d. Reticle — [ui/reticle.tscn](../../ui/reticle.tscn) + [scripts/reticle.gd](../../scripts/reticle.gd)

Centre dot, **grey normally and green when you can interact**, tweened over 0.1s so sweeping a
room doesn't strobe. Prompt below it with a heavy outline so it stays legible against bright
surfaces (and later, the starfield through windows).

Green means *actionable*, not merely *present* — "Hands full" shows the prompt but keeps the dot
grey. That matches the promise the dot makes.

Wired in `game.gd`: bound to the Interactor, hidden while the START prompt is up, and hidden while
paused (the cursor is visible then, so the reticle would be a second, misleading pointer).

## How it was verified

[tests/smoke_interaction.gd](../../tests/smoke_interaction.gd) — **INTERACTION TEST PASS**, exit 0.
Drives the real input path (`InputEventAction`), not the API directly:

- the Interactable script on a RigidBody3D genuinely works (`is Interactable` *and* `is RigidBody3D`)
- the ray finds the target, and **a wall interposed between camera and item clears it**
- reticle goes green with the right prompt, and back to grey when the target is lost
- E picks up: item frozen, interpolation off, its own interactable disabled while carried
- the item **flies in and then tracks the hold point** (<0.15m after 40 frames)
- the held item does not block its own ray
- hands-full: prompt says so, dot stays **grey**, target is not actionable
- **wall sweep**: walking the player at a wall leaves the held item clamped to the near side
- drop restores freeze/interpolation/gravity and the player collision exception
- throw launches it (velocity and actual travel both asserted)
- USE_ITEM: socket reads "Needs a part" and is not actionable empty-handed; carrying the part
  changes it to "[E] Fit the part", fires `used_with_item`, and does **not** drop the item

Visual check: rendered the actionable state — green dot, outlined `[E] PICK UP CRATE`.

Regression: all seven headless suites pass, plus the two cursor suites windowed.

## Two test-design traps worth remembering

1. **The wall sweep can't be tested by spawning a wall around an already-held item.** `test_move`
   clamps *motion into* geometry; it cannot rescue an item already on the far side. The test had
   to walk the player at a wall instead — the real scenario.
2. **Impulses need a physics tick.** Asserting thrown velocity two *render* frames after release
   read 0.00 m/s. The test now awaits physics frames and checks the item actually travelled.

## Demo content added to `scenes/game.tscn`

`PickupA` / `PickupB` ([scenes/props/pickup_crate.tscn](../../scenes/props/pickup_crate.tscn),
RigidBody3D with `continuous_cd`) and a `Socket` StaticBody3D configured as `USE_ITEM` — a
stand-in for step 12's repair panels. Input actions added: `interact` (E), `throw` (left mouse).
