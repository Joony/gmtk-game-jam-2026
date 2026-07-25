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
2. **The cold open.** No HUD, no music — just the klaxon of the fault that woke you.
3. **`OPENING_STASIS_TIME` (1.6s) later**, `_wake_from_opening_stasis()` calls
   `RunState.exit_stasis()`, which is exactly what pressing `[E]` does.
4. **The ordinary wake.** `_on_stasis_changed(false)` → `_exit_pod()` → cork pop, door swings,
   the player is glided out to `PodExit` and given control back.

Step 4 is deliberately **not** special-cased for the opening. The pod already knew how to wake
someone up; the intro just uses it, so the cork pop and the ride out cannot drift apart from the
ones you get mid-run.

## The ship is already broken (2026-07-25)

Playtest note: *"When the game loads there should already be a critical engine malfunction (not a
serious one, maybe 10%), even though you're in the cryo pod you should be able to hear the
klaxon (during the rest of the game you shouldn't be able to hear sounds in the cryo pod). When
the player exits the cryo pod play the CD_Intro vo file."*

That turns the opening from "you wake up on schedule" into "something woke you", which is what
the premise always claimed. Three parts:

**`DRIVE REGULATOR`** — a new fault on the engine room's port wall, critical, `speed_penalty`
0.10 with a slow 0.03/day bleed. The cheapest critical on the ship on purpose: the opening has to
teach the whole loop (hear it, walk the ship, find the panel, choose a route) without pricing a
first run out of a win.

It is broken by `Malfunction.starts_broken`, which `RunState.start()` applies **before** it
connects its own signals. Ordering is the whole feature. Hooked up first, `break_now()` would
fire `alarm` on frame zero — a hull impact for a knock that landed hours ago, and the computer
announcing it over a cold open built to be silent — and `_on_broke` would call `exit_stasis()`,
cutting the opening beat short before it had begun. The fault is simply already true. (`start()`
calls `_update_alert()` at the end for the same reason: a fault that never went through
`_on_broke` would leave the ship critical under white lighting.)

**The klaxon comes through the shell**, and it is the only thing that does. `_update_ship_audio()`
leaves the pod unsealed and sets the alarm during the opening; every other stasis calls
`Audio.set_sealed(true)`.

**`Audio.set_sealed()`** mutes the SFX and Voice buses — a bus mute rather than a per-player one,
because "sealed" has to cover sounds nobody thought about (a fault's hull impact, a door
somewhere, anything added later). The pod does not get to be selectively soundproof. Music is
deliberately exempt: the stasis track is scored *for* the pod rather than heard through its wall.
`stop_all()` unseals, or a bus mute would follow the player out to the main menu.

**The greeting waits for `_finish_exit()`.** Played at the wake it lands under the cork pop and
the door servo — the one stretch of the opening guaranteed to be noisy. `_intro_line_pending` is
a latch rather than a call at the wake, because `[E]` and the timer both end that stasis and only
`_finish_exit()` knows when the ride out is over.

## The cold open (bare, and silent but for the alarm)

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
- **Klaxon** — the exception, and the reason the cold open exists at all. See above.

The HUD and the music come in from `_on_stasis_changed()`, which is the only place that catches **both** ways out
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

**Mutation-tested.** Removing the pose, removing the wake, showing the HUD from load, dropping
the music guard, starting the ship undamaged, silencing the klaxon in the cold open, not sealing
a later stasis, applying `starts_broken` after the signal connects, and greeting the player at
the wake instead of at the exit — all fail `smoke_opening_stasis`.

That last one only died after the assertion was strengthened. The greeting is seconds long, so
checking the voice player *after* the exit cannot tell whether the line started there or three
seconds earlier under the cork pop; the test now samples every frame of the ride out. Parenting the label to the pod, aiming it at
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
