# Feature: Opening stasis — the run starts inside the pod

**Date:** 2026-07-25
**Status:** Done, verified

The run used to open with the player stood in front of the cryo pod, facing it. That put the
player one beat past their own story: the premise is that you have been asleep for months and
something woke you, and the first thing the game showed you was the pod you had apparently
already climbed out of, from the outside, in silence.

Now the game starts you sealed inside it. After a beat the ship wakes you, the door lets go, and
you ride out under the pod's ordinary wake sequence.

## The sequence

1. **Frame zero.** [`Game._pose_in_pod()`](../../scripts/game.gd) puts the player's body on the
   pod's `PodView` marker, seals the door instantly, marks the pod occupied and sets
   `PodPhase.IN`. Player physics and camera input are off; the reticle derives itself away.
2. **The cold open.** No HUD, no music. See below.
3. **`OPENING_STASIS_TIME` (1.6s) later**, `_wake_from_opening_stasis()` calls
   `RunState.exit_stasis()`, which is exactly what pressing `[E]` does.
4. **The ordinary wake.** `_on_stasis_changed(false)` → `_exit_pod()` → cork pop, door swings,
   the player is glided out to `PodExit` and given control back.

Step 4 is deliberately **not** special-cased for the opening. The pod already knew how to wake
someone up; the intro just uses it, so the cork pop and the ride out cannot drift apart from the
ones you get mid-run.

## The cold open (silent and bare)

Playtest note: *"the 'IN STASIS' info box shouldn't be there and the music shouldn't be playing.
Until you're out of stasis, then the game should work as normal."*

`_in_opening_stasis` is true from load until the first wake:

- **HUD** — `start_game()` sets `_hud.visible = not _in_opening_stasis`. Hiding only the stasis
  panel would still leave the air and distance gauges up over a pod interior; and the panel's own
  text is `"… · [E] WAKE"`, the game explaining a mechanic before it has shown you anything.
- **Music** — guarded inside `_update_ship_audio()` rather than at the call sites, because three
  separate signals (stasis, systems, oxygen) reach that function while the player is still asleep
  and any one of them getting through would start the stasis track. It sets `Music.NONE`
  explicitly rather than returning early, so whatever the menu or the intro left playing is faded
  out instead of inherited.
- **Klaxon** — already off: `set_alarm(critical and not _run.in_stasis)`.

Both come in from `_on_stasis_changed()`, which is the only place that catches **both** ways out
of the opening — the timer, and the player's own `[E]`, which goes straight to `RunState` and
never touches `_wake_from_opening_stasis()`. That was the first version's bug: clearing the flag
in the wake function meant an early `[E]` left the HUD hidden for the rest of the run.

The clock is real from frame zero — `RunState` is running and draining at the stasis rate — so
this is a genuine stasis, not a cosmetic pause.

## The "01" on the door

Playtest request: a number on the inside of the door, in Abolition, in front of the camera,
attached to the door so it swings away with it.

[`StasisPod._build_door_label()`](../../scripts/game/stasis_pod.gd) builds a `Label3D` and
parents it to `Model/Door`, so it rides the same tween with nothing to keep in sync.

- **Built in code, not placed in `cryo_pod.tscn`.** `Door` lives inside the imported `.blend` and
  carries that model's baked rotation, so a hand-authored child transform would be an unreadable
  basis literal that a re-import could invalidate. Setting `global_transform` *after* the reparent
  lets the engine derive the door-local transform, so the only number written down is
  `LABEL_POSITION` — in pod space, the frame every other marker in that scene uses.
- `(0, 1.6, -0.74)`: **1.6m is the eye**, not `PodView`'s 0.95m — the camera anchor sits 0.65m
  above the body origin. Aiming at the body puts the label below the frame for the whole stasis.
  `-0.74` is 4cm clear of the door's inner face at `z = -0.782`, so the two cannot z-fight.
- Unshaded (the interior is shadowless, so a shaded label is just a different flat grey),
  `outline_size = 0` (the default 12px black halo reads as a drop shadow at this alpha),
  single-sided (so it cannot ghost through the panel once the door is open).
- Player pod only. The scenery pods are sealed for the whole run — a label none of them will ever
  show is four more transparent draws for nothing.

**Known, flagged:** the pod's shell is single-sided, so from inside there is nothing rendered
between the player and the room beyond. The "01" is correctly on the door and swings with it, but
it reads as floating in the view rather than printed on a panel. Fixing that means disabling
backface culling on the door mesh, which is a visual change to the pod itself and was not made.

## PlayerSpawn is gone

There is no `PlayerSpawn` marker any more — nothing read it once the pod became the start
position, and leaving a dead marker in the scene invites someone to "fix" the opening by moving
it. `smoke_navigation` seeds its reachability flood-fill from `pod.exit_transform()` instead,
which is where the run actually puts you on your feet.

## Tests

| Suite | Covers |
| --- | --- |
| [smoke_opening_stasis.gd](../../tests/smoke_opening_stasis.gd) | frame-zero pose, sealed door, frozen player, the cold open (HUD, panel, music, klaxon), the wake, and everything coming back on |
| [smoke_pod_label.gd](../../tests/smoke_pod_label.gd) | the "01": parentage, font, alpha, position relative to the **eye**, and that it moves when the door does |
| [capture_pod_label.gd](../../tests/capture_pod_label.gd) | look-at-it counterpart — three renders from the player's own camera |
| [opening.gd](../../tests/opening.gd) | shared helper; see below |

**Mutation-tested.** Removing the pose, removing the wake, showing the HUD from load, and dropping
the music guard all fail `smoke_opening_stasis`. Parenting the label to the pod, aiming it at
`PodView`, making it opaque, pushing it through the shell, and labelling every pod all fail
`smoke_pod_label`.

### Eleven suites broke, all for the same reason

Any suite that loaded `game.tscn` and reached for the player found them frozen inside a sealed
pod. [tests/opening.gd](../../tests/opening.gd) is the shared fix: `Opening.wake(tree, game)`
skips the beat the way the player can and rides the ordinary wake out.

It deliberately does **not** shortcut to `Game._finish_exit()`. A suite that set up its world by
performing a wake the game itself never performs would go on passing over an opening that strands
the player sealed in — which is unrecoverable in a jam build, and the single worst thing this
change could break.
