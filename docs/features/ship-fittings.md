# Ship fittings: units, cryo bay, vent pipe, nav console

Five changes that turn the step 12 skeleton into something that reads as a spaceship.

| Feature | Files |
|---------|-------|
| Interplanetary units (million miles / days) | `scripts/game/run_state.gd`, `scripts/hud.gd` |
| Fixed-width numeric display | `scripts/ui/digit_readout.gd`, `ui/hud.tscn` |
| Cryo pod ring + camera ride in and out | `scenes/props/cryo_pod.tscn`, `scripts/game/stasis_pod.gd`, `scripts/game.gd`, `scripts/player/camera_controller.gd` |
| Vent pipe with visible patch vs repair | `scenes/props/vent_pipe.tscn`, `scripts/game/repair_point.gd` |
| Nav console with hand-drawn chart | `scenes/props/computer.tscn`, `scripts/ui/nav_chart.gd`, `scripts/game/computer_terminal.gd`, `ui/nav_screen.tscn` |

## Units: million miles and days

The voyage now has its **own** speed model, separate from `ShipMotion`'s metres per second.
Those were one value and could not stay that way: the starfield needs a speed that looks
right streaming past a window, while the journey needs one that crosses 82 million miles in
about a month. `RunState` owns the voyage (`total_distance` in million miles,
`cruise_speed_per_day`, `days_per_real_second`) and pushes only a 0–1 health fraction at
`ShipMotion`, which scales its own visual speed by it.

82 million miles at 2.6 Mm/day is a 31.5-day crossing; at 0.011 days per real second and
24x in stasis that is about two minutes of sleeping if nothing breaks.

## Fixed-width numbers

The UI font is proportional, so a live clock twitched sideways several times a second — the
whole string reflowed whenever a `1` replaced a `0`, right where the player is trying to
read it under pressure. There is no monospaced font in the project, so `DigitReadout` gives
every character its own fixed-width slot: one `Label` per character, each with a constant
`custom_minimum_size.x`, digits wide and separators narrow.

Two things this does **not** do by itself, both handled by the caller:

- **Length changes still shift the row.** `9.9` becoming `10.0` adds a character. Every
  value is zero-padded to a constant width (`%05.1f`, `%06.2f`, `%3d%%`).
- **Labels are reused, not rebuilt.** This updates every frame the oxygen changes; churning
  a dozen nodes per frame to redraw four characters would be absurd.

The exported `text` property is backed by a private `_text`, because a setter that writes to
its own property re-enters itself forever — which is exactly what it did the first time.

## Cryo bay

Five `CD_Cryo_v2` pods in a pentagon, doors facing outward, the player's at the +Z vertex
facing aft — you wake looking back down the wake through the two aft windows.

**Re-basing the model.** The `.blend` authors one pod of a five-pod ring: its meshes hang
off a shared pivot at `(0.8, 1, 0)` with the door pointing local +X. `cryo_pod.tscn` rotates
it 90° so the door faces -Z and shifts it so that pivot lands on the wrapper's origin, which
makes every placement in `game.tscn` just "position and face". The door shares the pivot, so
opening it is a plain Y rotation — the panel swings around the cylinder, which is what the
curved shell wants.

**The room had to grow.** At the original 10×12 the gap between the ring and the side walls
was 12cm and the player simply could not get past. The cryo bay is now 14×14 and 4.4m tall
(the pods are 3.25m with a ceiling pipe reaching 4.17m), with a 3.2m ring radius that leaves
a ~1m walkable gap between neighbouring pods.

**The ride in and out.** Entering freezes the player, tweens the body to the pod's `PodView`
marker, shuts the door, and *only then* starts the fast-forward — starting the clock first
would have days ticking past while the player is still visibly walking in. Waking reverses
it to `PodExit`.

`PodExit` keeps the pod's facing rather than turning the player round. An earlier version
spun them 180 degrees on the way out so they came to rest looking into the ship, which is
where they usually want to go — but being spun is disorienting, and it takes the choice of
where to look away from the player. You walk out forwards and keep looking where you were
looking.

Two details that were not obvious:

- The **camera keeps running** the whole time. Disabling the `Player` subtree was one line,
  but `CameraRig` is a child of it — the view would freeze on whatever you happened to be
  facing, which reads as a crash. Movement, interaction and carrying stop; looking does not.
- The camera is aimed through `CameraController.set_look()`, not by rotating the body. The
  controller rewrites the body basis from its own yaw every frame, so a rotation applied
  from outside is discarded on the very next one.

A four-state `PodPhase` enum replaced a bool, because the alarm can fire while the lid is
still closing and every phase has to reject the inputs belonging to the others.

**The drive spins up, it does not switch.** Ship time used to jump from 1x to 24x on a
single frame, which made the starfield snap from a slow drift to a full blur between one
frame and the next — it read as a rendering glitch rather than as acceleration. `RunState`
now ramps `time_scale` over `stasis_ramp_time` (1.8s) and pushes it at `ShipMotion` every
frame, so the stars stretch out and relax back smoothly. Three things about it:

- The interpolation is **geometric, not linear**. A linear 1 → 24 is already past 12x at
  the halfway point, so almost the whole ramp is spent at high speed and it still reads as
  a jump. Interpolating in log space is constant *proportional* acceleration, which is what
  a drive spinning up looks like. Smoothstep on top eases the two ends.
- A ramp always starts from the **current** scale, not from a fixed value, so climbing back
  into the pod part-way through a spin-down picks up smoothly rather than snapping to 1x.
- Only the ship's clock ramps. The **oxygen rate switches instantly**, because it should:
  the lid has shut, the pod is sealed, and the player is breathing pod air from that moment.

The stasis panel shows the live rate rather than the configured one — watching the number
climb is most of what sells the spin-up as acceleration rather than a cut.

## Vent pipe

The flat panels state their condition with a coloured light, which works but is a symbol.
The coolant loop is now a pipe you can read from across the room:

| State | Looks like |
|-------|-----------|
| Broken | a split in the pipe, venting vapour |
| Patched | a fat band of tape, off-centre, wrong colour |
| Fixed | a machined sleeve, square to the pipe |

Same script and the same two interaction routes as the panels — `RepairPoint` gained
`broken_nodes` / `patched_nodes` / `fixed_nodes` path lists and toggles their visibility, so
this needed no subclass. It went on the coolant loop deliberately: that is the fault whose
patch costs 25 seconds of air, so it is the one that most needs the player to *see* what
they bought.

## Nav console

A `NavChart` `Control` drawn entirely in `_draw()` — wobbly circles, a dotted arc between
two worlds, and a sketched arrowhead stuck on at the current progress and turned to follow
the path. The wobble is hashed from position rather than random, so the drawing holds still
instead of crawling. The exhaust scratches shorten as the drive degrades, which is a second
wordless readout of the same number.

Structure copied from GMTK 2025's `ComputerScreen`: the chart renders into a `SubViewport`
whose texture is the screen quad's albedo, so it is a real screen in the room rather than a
picture of one. `resource_local_to_scene` on the material and `SubViewport` as a direct
child of the scene root are both required, or the viewport path does not resolve and every
instance shares one viewport.

Interacting **walks the camera up to the console** over half a second and reads the real
screen, rather than cutting to a menu. The first version snapped straight to a full-screen
copy of the chart, which was jarring and meant two places for the same numbers to live; now
the only chart is the one on the terminal, the camera leans in to a `ViewPoint` marker set
at eye height 0.75m from the glass, and the overlay is reduced to a `[E] STEP AWAY` prompt.

It freezes the player but does **not** pause: the point of checking your progress is that
the clock keeps running while you decide, so reading the screen costs air like anything else.
A `NavPhase` enum guards the approach the same way `PodPhase` guards the pod — a second
interact press mid-glide, or the run ending while the player is stood reading, both have to
be handled.

## The bug that mattered most

**`.tscn` `Transform3D` basis literals are ROW-major.** Writing one from column vectors
produces the transpose, which for a rotation is the opposite rotation. This had buried
**three of the four repair panels inside the walls they were mounted on**, facing away from
the room, and it put the cryo pod door on the wrong side. Nothing caught it: the interaction
test relocates panels in front of the camera before looking at them, and the only screenshot
of a panel happened to be the one with an identity basis.

Two other things this round that only showed up when measured:

- The coolant pipe was mounted at 1.4m with the camera eye at 1.55m, so a level look-ahead
  ray **sailed over it**. Visible, but not targetable.
- `CPUParticles3D` renders nothing without a `mesh`, ignores a `material_override` for the
  particle pass (the material has to go on the mesh), and `emission_shape = 3` is BOX with
  1m default extents — the "jet" was spawning uniformly through a 2m cube.

## Verification

- `tests/smoke_run_state.gd` — **106 checks**, up from 72. Also asserts that leaving the pod
  preserves the player's facing, and that the console's reading position sits in front of the
  glass at eye height and points at it. The stasis ramp is checked at three points through
  the spin-up (still 1x on the frame the lid shuts, part-way at the midpoint, exact at the
  end) plus the spin-down and a reversal mid-ramp — a ramp that jumped on the first frame
  would still pass a "settles at 24x" check on its own. Mutation-tested by restoring the
  instant switch: 4 failures. New: state visuals switching with
  the fault, `DigitReadout` slot widths identical across digits and labels reused rather
  than rebuilt, the console reporting progress/distance/ETA/drive from the run, five pods
  with exactly one player pod and the other four not offering prompts, the pod facing aft,
  the exit marker clear of the shell, and the door actually moving.
- `tests/smoke_navigation.gd` — **new suite.** Floods the ship with capsule casts at the
  player's own size and flood-fills from the spawn, then checks every repair point, spare
  and the pod exit is walkable to; and that every panel has open space in front of it and
  geometry behind it. Written because the player had been blocked twice by geometry and
  nothing noticed. It immediately caught the ship being disconnected (a sampling bug in the
  test — the sliding doors had not finished opening) and now guards the panel-facing bug.
- `tests/balance_sim.gd` — re-run in the new units, balance unchanged: ignore suffocates at
  79.3 of 82 million miles; patch arrives on 45s of air; proper arrives on 147s.
- Full regression: **12/12 suites pass.**

`tests/smoke_interaction.gd` needed relocating to the middle of the engine room: its carry
and throw section walks the player 2m forward and parks items 1.4m beyond that, and the
spawn no longer has that much clear space — the thrown crate was being released inside a
cryo pod.

## Known gaps

- The pods' glass is the artist's material and reads as a solid blue block under GL
  Compatibility. Left alone deliberately — it is LoganDevz's asset.
- `CD_Cryo_v2.blend` and its scratch `node_3d.tscn` are still at the repo root rather than
  under `assets/`; moving a collaborator's files mid-jam needs coordinating first.
- The other four pods are empty. Occupants would sell the fiction cheaply.
- The nav chart's two worlds are unnamed placeholders (`TERRA STATION`, `KEPLER YARD`) and
  the game itself still has no title.
