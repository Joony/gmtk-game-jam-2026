# Feature: Player controller (step 4) — ported from Doortal

**Date:** 2026-07-22
**Status:** Done, verified

## What was done

Ported the first-person controller from `/Users/joony/Games/doortal`, ~140 lines total.

- [scripts/player/player.gd](../../scripts/player/player.gd) — copied essentially verbatim.
  Source/Quake-style movement: friction-then-accelerate on the ground, capped air acceleration
  (air-strafe). Two pure static helpers (`apply_friction`, `accelerate`) stay unit-testable.
- [scripts/player/camera_controller.gd](../../scripts/player/camera_controller.gd) — ported with
  the portal machinery removed:
  - **stripped** `resync_now()` and `_post_teleport_snap` (portal teleport pop fixups)
  - **stripped** its own mouse capture — it used to capture on any click and release on
    `ui_cancel`. The pause menu (step 5) owns cursor state so there is one source of truth.
    The `_unhandled_input` guard now simply ignores motion unless the cursor is captured.
  - **kept** `adopt_body_yaw()` — not portal-specific; needed by anything that rotates the body,
    since this controller overwrites the body basis every frame and would otherwise discard it
  - **kept** `event.screen_relative` (NOT `relative`) — under `window/stretch/mode="canvas_items"`
    the viewport `relative` delta is rescaled by the stretch/DPI matrix and produces visible
    rotation stepping on slow mouse movement
- [scenes/player.tscn](../../scenes/player.tscn) — Doortal had **no player scene**; this rebuilds
  the rig that lived inline in its `test.tscn` (lines 206–241):
  `Player(CharacterBody3D)` → `MeshInstance3D`, `CollisionShape3D`, `CameraAnchor(Marker3D, y=0.65)`,
  `CameraRig(Node3D, top_level, physics_interpolation_mode=Off)` → `Camera3D` → `HoldPoint`.
  - swapped Doortal's 41-point `ConvexPolygonShape3D` for a plain `CapsuleShape3D` (r=0.4, h=1.8)
  - `collision_layer = 1` (dropped Doortal's 32769; layer 16 was its portal "Teleportable" layer)
  - `HoldPoint` kept under the camera for the step 8 carry system
- Input actions added to `project.godot`: `forward`, `back`, `left`, `right` (WASD + arrows),
  `jump` (Space), all by **physical** keycode so they work on non-QWERTY layouts.
- `physics/common/physics_interpolation = true` enabled.

## Decisions

**Renderer: staying on GL Compatibility.** Doortal is Forward+, and the TODO flagged this as needing
a deliberate choice. Doortal's ADR 0024 shows it switched *purely* for portal SubViewport quality —
LDR clipping and no AO/glow through portal cameras under GL Compatibility. We have no portals, and
the web export for itch.io (step 7) needs GL Compatibility, since Forward+ on the web requires
WebGPU. So the reason Doortal switched does not apply and the reason to stay does.

**`physics_interpolation` is a silent prerequisite.** The camera's two-clock design reads
`get_global_transform_interpolated()` for position while applying rotation at render rate. Without
the setting the camera merely feels subtly wrong, with no error — so the test asserts the project
setting directly rather than trusting it to stay on.

## How it was verified

[tests/smoke_player.gd](../../tests/smoke_player.gd) — **PLAYER TEST PASS**, exit 0:

- *Movement maths:* acceleration ramps rather than snapping, converges near max speed over ~1s,
  friction decays to zero, air-strafe adds perpendicular velocity without changing forward speed
- *Project settings:* `physics_interpolation` is on; all six input actions exist
- *Scene contract:* CharacterBody3D root, `CameraAnchor`, `CameraRig/Camera3D`, `HoldPoint`;
  rig is `top_level` with interpolation off; collision layer 1; capsule collision shape
- *Live physics (real scene, real ticks):* spawns on the marker, falls, lands on the floor at
  y≈0.9 with `is_on_floor()` true, walks >1m while `forward` is held, does not fall through the
  floor, and comes to rest under friction once input stops
- *Mouse look:* synthesized `InputEventMouseMotion` changes yaw and pitch, and pitch clamps within
  ±89° after 40 large downward deltas

Visual check: rendered [scenes/game.tscn](../../scenes/game.tscn) to PNG via
[tests/capture_scene.gd](../../tests/capture_scene.gd) — correct first-person view, floor, crates,
shadows, and the player's own capsule shadow.

Regression: all four suites pass (project structure, intro/SceneManager, main menu, player).

## Gotchas for later

- **The mouse-look checks skip under `--headless`** — cursor capture is unavailable there, and the
  test prints a skip line rather than silently passing. To exercise them, run windowed:
  `godot --path . --resolution 640x360 --position 3000,3000 -s tests/smoke_player.gd`
  Do this after any camera change; the headless run alone will not catch a mouse-look regression.
- The camera writes `_player.global_transform.basis` every `_process`. Anything else that rotates
  the body (knockback, a cutscene look-at, the stasis pod placing the player) must call
  `adopt_body_yaw()` afterwards or the rotation is discarded next frame.
- `Carry` (step 8) must sit as a sibling of `CameraRig` with `process_priority = 10` so it runs
  after the camera; otherwise a held item lags a frame behind the view.
