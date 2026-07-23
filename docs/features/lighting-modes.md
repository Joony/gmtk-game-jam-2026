# Feature: Lighting modes (step 10)

**Date:** 2026-07-23
**Status:** Done, verified

Ship-wide lighting states — **NORMAL** (white) and **ALERT** (red) — as a first-class system.
[scripts/level/lighting_controller.gd](../../scripts/level/lighting_controller.gd), instanced as
`Lighting` in `scenes/game.tscn` and pointed at the `WorldEnvironment` by `game.gd`.

## Modes are data

```gdscript
const MODES := {
    Mode.NORMAL: {light_color, light_energy, ambient_color, ambient_energy, pulse},
    Mode.ALERT:  {...},
}
```

Adding a third state (emergency, power loss) is a new entry, not new code. The test asserts every
mode declares the same keys, so a half-defined mode fails loudly rather than silently skipping a
property.

`set_mode()` / `set_alert(bool)` / `is_alert()`, plus a `mode_changed` signal that fires **only on a
real change** — re-setting the current mode is a no-op, so step 12 can call `set_alert(true)` on
every malfunction without spamming listeners.

## Why values are applied every frame, not tweened per light

The TODO required that the mode be *a property of the ship* — including **rooms built after the mode
was set**. Tweening each fixture at the moment of change cannot satisfy that: a room built later
would come up in whatever colour the builder hard-coded.

So the controller holds the current blended values and applies them to everything in the
`room_lights` and `room_light_panels` groups each frame. New geometry conforms automatically with no
registration step. With a dozen fixtures the cost is negligible.

Transitions are a 0.4s smoothstep blend between the two mode dictionaries, so no per-light tweens
exist to get out of sync.

## What alert changes

- fixtures → red, and **dimmer** (1.15 vs 1.6): a darker room reads as more oppressive than a
  bright red one, and keeps the emissive panels legible as the source
- the emissive ceiling housings turn red too — otherwise they stay white while the room goes red,
  which looks broken
- **ambient follows** (`0.34, 0.11, 0.11` at 0.28), not just the fixtures
- a slow pulse (`pulse_hz`, 0.55Hz). Exported, so step 12 can raise it as the countdown runs down.

The `Environment` is **duplicated** on bind, because it is a scene sub-resource — mutating it in
place leaks state between instantiations of the game scene, which would silently corrupt tests.

## How it was verified

[tests/smoke_lighting.gd](../../tests/smoke_lighting.gd) — **LIGHTING TEST PASS**. Assertions are
made on the *average across all fixtures*, so they describe the ship rather than one lamp:

- starts NORMAL and neutral; every mode declares the same keys
- `mode_changed` fires once on a real change and **not** when re-set to the same mode
- alert is red, **and dimmer than normal**; the emissive panels turn red; ambient turns red
- the transition does not snap (still red one frame in) and **progresses over time** — checked as
  progression rather than a value at a fixed frame, since how far a 0.4s blend has travelled after
  N frames depends on the frame rate
- returns exactly to the neutral values afterwards
- **a room built while in alert comes up red, not white** — the requirement that drove the
  apply-every-frame design
- alert energy actually pulses (sampled over 40 frames)

Visual check: the pod bay in alert — red walls, red glowing ceiling panels, visibly darker. The grey
reticle dot stays clearly legible against it, which was an open concern from step 8.

Regression: all nine headless suites pass.

## Follow-ups

- **Local alert** (red only in the affected room, as wayfinding toward the problem) is not
  implemented — it is ship-wide for now. Worth revisiting in step 12 once malfunctions have
  locations; the group-based apply would need per-room grouping.
- No klaxon yet (step 13 audio). `mode_changed` is the hook.
