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

## Notes for later phases

- New `class_name`s (`Cable3D`, `CableSocket`) only register after a full editor filesystem scan,
  not `--check-only`/`-s` alone. If a run reports *Could not find type "Cable3D"*, do one editor
  pass first: `godot --headless --path . --editor --quit-after 400`.
- The cables plugin does not need to be enabled in `project.godot` for the classes to work — the
  `class_name` globals are picked up by the project-wide scan regardless.
