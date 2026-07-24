# Feature: Cables, sockets & a portable battery (step 14d)

**Date:** 2026-07-24
**Status:** In progress — Phase 1 done & verified

Ported from Doortal's `addons/cables/`. The plan is seven testable phases (see
[TODO.md](../../TODO.md) §14d): strip the rope of portals, bring the socket over, rebase the
plug onto our `Interactable`+`Carry`, place wall sockets, add the battery cube, wire it into the
countdown design, then document. This log grows a section per phase.

## Phase 1 — Vendor the addon, strip portals from the rope ✅

Copied `plugin.cfg`, `plugin.gd`, `materials/cable_clip.gdshader` and `scripts/cable_socket.gd`
verbatim; **did not** copy `cable_portal_link.gd` (deleted from the port). Rewrote
[addons/cables/scripts/cable_3d.gd](../../addons/cables/scripts/cable_3d.gd) with all portal
machinery removed.

The verlet core is untouched — integrate → pin → stretch/bend constraints → collision, plus the
three endpoint mechanisms (tension, breakaway, one-hop power). What came out:

- **The `side[]` room-partition array** and everything that threaded through it. Every
  `_map_to_side(points[j], side[j], side[i])` collapsed to `points[j]` (one world frame, so the
  cross-room isometry is identity). This touched `_constrain_pass`, `_bend_pass`,
  `_polyline_length`, `_apply_endpoint_tension`, `_break_away`, `_collide_midpoints`, `_rest_snap`.
- **The `CablePortalLink` + `_link` + `_portals` layer:** `refresh_portals`,
  `_update_crossings`, `_repair_sides`, `_collapse_link`, `_has_split`, `_set_point_side`,
  `_assign_endpoint`, `_explain_endpoint_jump`, `notify_plug_teleport`, `_pull_tail_through`,
  `_pull_tail_end`, and the `_link` deactivation guard in `_physics_process` — all gone.
- **The two-real-room renderer:** the far-room clone mesh (`_clone`/`_far_mesh`), `_render_runs`,
  `_build_runs`, `_pin_room`, `_seam_point`, and the cross-room `_void_guard_runs`. Replaced by a
  single `_render_polyline()` → one Catmull-Rom-smoothed tube.
- **Portal-only constants:** `ENDPOINT_JUMP`, the `TAIL_PULL_*` set, `VOID_GUARD_*`,
  `void_guard_hits`.

Kept the hard-authored-jump warm-up (`_update_endpoint_pins` → `_resettle_check`, gated on
`PIN_RESETTLE_JUMP`): a test/script reset or a seat-authoring still needs to blank tension for a
few ticks so a force computed off the stale drape can't drag a hard-reset body. The
`cable_clip.gdshader` needed no edit — it was already a plain lit-tube material in Doortal (the
portal clip had been retired there by ADR 0045).

Net: **1868 → 1280 total lines** (995 → 710 excluding comments/blanks — the surviving length is
mostly the preserved tuning docstrings).

### Verified — [tests/smoke_cable_sim.gd](../../tests/smoke_cable_sim.gd)

`godot --headless --path . -s tests/smoke_cable_sim.gd` → **CABLE SIM TEST PASS** (15 checks).
Endpoints are plain `Node3D` anchors (no plugs/Carry yet), so the sim is tested in isolation:

- a slack rope (2 m anchors, 4 m rope) settles with no NaN/inf, no segment stretched past 1.1×
  rest spacing, drapes below the anchors, and is stable (< 5 cm drift over 2 more seconds);
- the render tube is actually skinned (surface count > 0);
- pulling the anchors 7 m apart raises `overstretched` and grows `_polyline_length` past
  `rest_length`;
- event-driven power: a source socket reads powered; seating it via `set_endpoint_socket` lights
  the cable and feeds a downstream sink socket; unplugging the source kills both.

## Phase 2 — CableSocket ✅

The socket ([addons/cables/scripts/cable_socket.gd](../../addons/cables/scripts/cable_socket.gd))
came over from Doortal **unchanged** — it is pure occupancy bookkeeping plus a runtime-built
receptacle/preview torus, and duck-types its plug as a bare `Node3D`, so nothing about it was
portal- or game-specific. No edits; this phase is a dedicated test that proves the whole surface
in isolation, and establishes the stub-plug fixture Phase 3 builds on.

**Decision (confirmed):** seating stays on Doortal's **proximity-release** model (bring the held
plug within `snap_radius`, release to seat), not our USE_ITEM idiom. Phase 3's `CablePlug` will
hook `Carry`'s drop, not the socket's interaction.

### Verified — [tests/smoke_cable_socket.gd](../../tests/smoke_cable_socket.gd)

`godot --headless --path . -s tests/smoke_cable_socket.gd` → **CABLE SOCKET TEST PASS** (25 checks):

- a source socket is powered **synchronously** at ready and announces `power_changed(true)`
  **deferred** (so a listener connecting in its own `_ready` still catches the initial state);
  a source ignores `set_fed(false)`;
- an external feed drives `powered` + the signal, is idempotent, and unfeeds symmetrically;
- `seat`/`unseat` record `occupied_by`, fire `plugged`/`unplugged`, gate `can_accept`, and
  `unseat` on a free socket is a no-op;
- the runtime `SnapPreview` starts hidden and `set_preview` toggles it;
- `mount_body()` returns null free-standing but finds the owning `RigidBody3D` when the socket is
  a child of one (the moving-mount case — a battery-cube face, later);
- `snap_transform()` is the socket's own global transform.

## Phase 3 — Rebase CablePlug onto Interactable + Carry ✅

[scripts/game/cable_plug.gd](../../scripts/game/cable_plug.gd) — `class_name CablePlug extends
Interactable`, attached to a `RigidBody3D` (the same "Interactable script on a RigidBody3D"
convention `pickup_crate.tscn` uses). Rebased from Doortal's `PickableObject` subclass:

- **Held-state** is no longer self-authored. Carry freezes and drives the body; the plug learns
  it is held through `on_pickup()`/`on_drop()` and exposes `is_held()` from that flag (the cable's
  tension/breakaway ask for it). `carry_did_teleport`/`on_teleport`/`notify_plug_teleport` — all
  portal hooks — are gone.
- **Seat-on-release** hooks `on_drop()` (Carry calls it last, after unfreezing): if a socket is
  lit in snap range, the plug re-freezes kinematic, is server-authored onto `snap_transform()`,
  and claims the socket — otherwise it drops normally. Re-grabbing a seated plug unseats it in
  `on_pickup()` first. `force_unseat()` (the cable's breakaway) is unchanged.
- **`cable_render_pin()` simplified.** Doortal's held mesh was `top_level` and authored ahead of
  the lagging body, so the render pin read `render_body_transform()`. Our Carry authors the whole
  **body** transform each render frame, so the body pose *is* the render pose — `global_position`
  serves held and free alike.

### The `self as RigidBody3D` trap

The script's static base is `Interactable` (a `Node3D`); the node is a `RigidBody3D`. Those are
**sibling** branches off `Node3D`, so `self as RigidBody3D` is a **compile error**, not a runtime
null. It is laundered through a common ancestor — `var n: Node = self; _body = n as RigidBody3D` —
which compiles and succeeds at runtime. The test needs both views of the same object and does the
same: it types the handle as `Node3D`, then casts to `RigidBody3D` (body ops) and `CablePlug`
(plug API) separately. (Godot's `as` only errors when it can *prove* the cast impossible.)

**Gotcha for verification:** an editor `--editor` scan registers a `class_name` from its
declaration line even when the script fails to fully compile — so "the class appears in the cache"
is **not** proof it compiles. The reliable compile check is running a test that `load()`s it.

### Verified — [tests/smoke_cable_plug.gd](../../tests/smoke_cable_plug.gd)

Drives the **real input path** (Interactor → Carry) against the shipping `game.tscn` →
**CABLE PLUG TEST PASS** (24 checks): the ray finds the plug and E picks it up; a held plug in
snap range lights the socket preview; releasing seats it (not a floor drop), powers the cable from
a source socket, freezes the body and clears the preview; a seated plug follows a moved socket;
re-grabbing unseats it and kills power; and sustained overstretch pops the seated end loose via
the cable's breakaway → `force_unseat`. The player is added to `cable_ignore` so the rope never
shoves it (Doortal did the same). `smoke_interaction.gd` still passes — no regression on the
shared Interactable/Carry path.

## Phase 4 — Wall sockets & permanently-seated ends ✅

Three pieces:

- **`cable_ignore` on the player** ([scenes/player.tscn](../../scenes/player.tscn)). The cable's
  default `exclude_groups` is `[cable_ignore]`; without the player in it, the rope would collide
  with and shove the player, and a tension-dragged plug would push it around. Doortal put the
  player in the same group. (Phase 3's test added it in code; now it ships on the scene.)
- **`fixed` plugs** ([scripts/game/cable_plug.gd](../../scripts/game/cable_plug.gd)). A plug with
  `fixed = true` + a `fixed_socket_path` is bolted to the ship: it freezes and seats into that
  socket at startup (deferred, so the cable back-ref and the socket's `_ready` land first), sets
  `is_enabled = false` so it is never a ray target, and its `force_unseat` is a **no-op** so the
  cable's breakaway can never pop it. The player only ever handles the free end.
- **A reusable [scenes/props/power_cable.tscn](../../scenes/props/power_cable.tscn)**: a source
  `CableSocket`, a `FixedPlug` bolted into it, a loose `FreePlug`, and the `Cable3D` between them.
  One instance is hand-placed in the engine room in [game.tscn](../../scenes/game.tscn) (like the
  repair panels — the ship walls are procedural, so the spot was screenshot-verified rather than
  wall-snapped). Plug visual is `CD_Plug_v1.blend` scaled to ~0.19 m (its prongs point down -Z,
  the nose convention, so it needs no rotation; the model's nested `-col` StaticBody has its layers
  zeroed like the crate's, leaving the RigidBody's own box the only collider).

### Verified — [tests/smoke_cable_placement.gd](../../tests/smoke_cable_placement.gd)

`... -s tests/smoke_cable_placement.gd` → **CABLE PLACEMENT TEST PASS**. Part A drives
`power_cable.tscn` in isolation: the fixed end seats into the source, powers the cable, is frozen
and non-targetable; the free end is loose, grabbable, and falls under gravity; and pinning the
free end 8 m out (massive overstretch, held past several breakaway windows) **cannot** pop the
bolted-in end. Part B loads `game.tscn` and confirms the player carries `cable_ignore` and the
in-ship `PowerCable`'s fixed end is seated and powering the cable. `smoke_interaction.gd` still
passes after the `player.tscn` group change.

**Visual proof:** a capture of the engine-room cable ([tests/capture_cable.gd](../../tests/capture_cable.gd))
shows the wall socket, the rope draping to the floor **glowing warm** (the powered emission — so
power reads visually too), and the free plug resting at its end.

### Phase 4 follow-up — playtest fixes

Two issues from playing the build:

- **Cable spawned inside the wall and thrashed.** The first placement was at `x=-6`, which is
  *exactly* the engine room's port wall plane (`Rect2i(-6, -22, 12, 10)`) — so the rope seeded
  inside the wall and the depenetration passes fought it forever. Moved to the **forward wall**
  (`z=-22`, where "into the room" is `+Z` so identity basis needs no rotation), starboard side
  `x=3` — clear of the forward window (`x -2.5..2.5`) and the MainDrive (`x=-3.5`). The free plug's
  local offset is now `(0, -0.3, 0.5)` so it and the slack rope settle in open room space, never
  in the mounting wall. Re-captured — it drapes cleanly now.
- **Overstretch had no give.** Breakaway used to pop only a *seated* end and explicitly never
  yanked the player's grip, so a cable bolted at one end and held at the other just went dead-taut.
  Now `Cable3D._break_away` releases **whichever end can give**, and the endpoint decides how via a
  duck-typed `break_connection(recoil, allow_drop_held)`: a seated plug pops, a **held plug drops
  from the player's hands**, a bolted (`fixed`) end still never gives. Two passes sacrifice a
  socketed end before the grip (`allow_drop_held` only on the second), and in every case the plug
  gets an impulse **toward the far end** for a little elastic snap-back. The plug finds its carrier
  through a new `carries` group that `Carry` registers in. Verified by a new held-drop section in
  [smoke_cable_plug.gd](../../tests/smoke_cable_plug.gd) (pulling a held plug past the ratio drops
  it with a measured recoil); the seated-pop and fixed-never-breaks cases still pass.

### Phase 4 polish (playtest round 2)

- **Socket nudged flush** to the forward wall (`z` −21.8 → −21.95): the receptacle now sits on the
  wall surface with the plug's prongs seated into it, instead of floating ~0.2 m proud.
- **Real plug model** (`CD_Plug_v1.blend`) replaces the placeholder boxes on both ends.
- **Breakaway threshold lowered `1.6 → 1.2`** (`Cable3D.BREAKAWAY_RATIO`): overstretch now releases
  at 1.2× rest instead of 1.6×, so the drop/pop triggers with a gentler pull (~4.8 m on the 4 m
  ship cable). Note for Phase 6: a cable plugged at *both* ends must span less than 1.2× rest or it
  breaks itself at rest — sink sockets need to sit within that of their source.

All five cable/interaction smoke tests still pass; re-captured screenshots confirm the flush socket
and the plug model on both ends.

## Phase 5 — The battery cube ✅

[scripts/game/battery_cube.gd](../../scripts/game/battery_cube.gd) +
[scenes/props/battery_cube.tscn](../../scenes/props/battery_cube.tscn). A carryable ~0.4 m cube
(an `Interactable` PICKUP on a `RigidBody3D`, same laundered-`self` pattern as `CablePlug`) with a
`CableSocket` **port** on its +Z face — the cube is that socket's `mount_body()`, so a taut cable
drags the cube by its port.

**Power model.** The port is a `CableSocket` whose `is_power_source` the cube drives from its
charge (a source while `charge > 0`, dead when flat). A single socket can't be both *fed* and
*sourcing*, so which way energy flows is read off the **cable graph**, not the port's own feed —
the cube looks at the far end of the plugged cable:

- far end is an external powered **source** (a wall socket) → **charging** (`+charge_rate`),
- far end is anything else (a device **sink** it's feeding) → **draining** (`−drain_rate`),
- nothing plugged, or flat with only a sink → **idle**.

When the charge crosses zero the port's source flag flips and the cable **re-propagates power**, so
a device dies the instant the cube runs flat. This needed two small addon additions:
`CableSocket.set_source(on)` (toggle a source at runtime; tracks `_fed` so `powered` stays correct)
and `Cable3D.refresh_power()` (public re-propagation hook).

**Charge bars.** A row of `bar_count` (5) small emissive bars built on the top face at runtime,
each with its **own** `StandardMaterial3D` — the `RepairPoint` status-light trick, or every cube in
the ship would show the same charge. Lit count = `round(charge_fraction × bars)`.

One cube is placed in the engine room near the wall cable.

### Verified — [tests/smoke_cable_battery.gd](../../tests/smoke_cable_battery.gd)

**BATTERY TEST PASS**: wiring real cables into the port, the cube charges from a live wall source
(and its port becomes a source), holds charge unplugged, powers a sink when charged, drains under
load, and at empty stops sourcing so the sink loses power; `charge_fraction` reads 0 empty / 1
full. Screenshot confirms 3/5 bars lit green at 60% with the port ring on the face. All prior
cable/interaction smoke tests still pass.

## Notes for later phases

- New `class_name`s (`Cable3D`, `CableSocket`) only register after a full editor filesystem scan,
  not `--check-only`/`-s` alone. If a run reports *Could not find type "Cable3D"*, do one editor
  pass first: `godot --headless --path . --editor --quit-after 400`.
- The cables plugin does not need to be enabled in `project.godot` for the classes to work — the
  `class_name` globals are picked up by the project-wide scan regardless.
