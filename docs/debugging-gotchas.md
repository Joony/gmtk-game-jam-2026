# Godot gotchas & debugging notes

A running list of the non-obvious traps this project hit, each with the symptom that showed
up, the actual cause, and the workaround that stuck. Most cost real time to find because the
failure looked like something else. If you are staring at one of these symptoms, start here.

The format is deliberately blunt: **symptom → cause → fix**, plus where it bit us.

---

## Scenes & the `.tscn` text format

### `Transform3D` basis literals are ROW-major

- **Symptom:** a node placed with a rotation faced the *opposite* way. Three repair panels
  ended up buried inside the walls they were mounted on; the cryo pod's door was on the
  wrong side.
- **Cause:** a `.tscn` `Transform3D(a,b,c, d,e,f, g,h,i, ox,oy,oz)` stores the basis in
  **row-major** order: `(X.x, Y.x, Z.x, X.y, Y.y, Z.y, X.z, Y.z, Z.z)`. Writing it from
  column vectors (the intuitive `[basis.x, basis.y, basis.z]` layout) produces the
  **transpose**, which for a rotation is the *inverse* rotation.
- **Fix:** for a Y-rotation of φ, the literal is
  `Transform3D(cos φ, 0, sin φ, 0, 1, 0, -sin φ, 0, cos φ, …)`. Verify against a known-good
  node before trusting a hand-written basis, and **measure the result** — `smoke_navigation`
  now asserts every repair panel faces open space and is backed by geometry, which catches a
  backwards mount.
- **Bit us in:** the cryo pod wrapper (`cryo_pod.tscn`) and every wall-mounted panel.

### Node names containing dots get sanitised

- **Symptom:** `get_node("WindowGlass_door_-5.0_2.0")` returns null even though the node is
  clearly there.
- **Cause:** Godot rewrites `.` in node names on load.
- **Fix:** address these nodes by **group** (`add_to_group` / `get_nodes_in_group`) rather
  than by a generated dotted name. The whole ship uses group-driven systems for this reason.

### Asset moves silently break scene references

- **Symptom:** a scene loads fine in a headless test, then renders as a missing placeholder
  in the editor, or breaks the moment the UID cache is rebuilt.
- **Cause:** a `.tscn` stores its dependencies as **path strings AND UIDs**. A collaborator
  renaming or relocating a `.blend` leaves the path dangling; worse, the old `.import` (and
  its UID) can get reassigned to a *different* model, so neither the path nor the UID
  fallback reaches the intended file. Git merges all of this cleanly because it does not
  understand what the strings mean, and Godot papers over a dead path at load time.
- **Fix:** `tests/smoke_scene_deps.gd` walks every `.tscn`/`.tres`, checks each
  `ext_resource` path with `ResourceLoader.exists()`, and checks any UID resolves to the
  same path. It **parses the scene text rather than loading it**, on purpose: loading a
  broken scene emits an error but frequently returns a usable placeholder, so a load-based
  check can pass on a broken reference.
- **Bit us in:** the cryo model moving to `3D-Models/` (twice), including a UID reassigned to
  the PC model.

---

## The Godot editor's re-save behaviour

Opening a scene in the editor and saving it — even with no deliberate change — rewrites the
`.tscn` and can silently drop things you put in by hand.

- **Comments are stripped.** Any `;`-prefixed lines in a `.tscn` are gone after an editor
  save. Keep the *why* in the attached script's header, not only in the scene.
- **Instanced-scene child overrides are dropped.** The crate neutralises the collider that
  its `.blend`'s `-col` suffix generates via an override node
  (`[node name="StaticBody3D" parent="Model/Crate" …] collision_layer = 0`). The editor
  dropped that override on save, re-activating a second collider on layer 1. There is a note
  in `pickup_crate.tscn` flagging it; if the crate starts snagging on nothing, check the
  override survived.
- **`unique_id=` attributes appear** on every node, and properties that now match their
  default are removed (e.g. the `Run` node lost `total_distance = 82.0` once 82 became the
  export default — harmless, but surprising in a diff).
- **Fix:** treat editor saves as lossy for hand-authored `.tscn` details. `smoke_scene_deps`
  and `smoke_navigation` catch the structural consequences; the collider override is the one
  that needs a human eye.

---

## Physics

### One frame at the world origin after a teleport

- **Symptom:** on the first rendered frame after the game loads, the camera was down at the
  world origin (floor level, middle of the ship) before snapping to the spawn. It was masked
  by the START prompt covering that frame until the game started auto-starting.
- **Cause:** with `physics/common/physics_interpolation = true`, a node's *rendered*
  transform is interpolated between its previous and current physics-tick transforms. On the
  first frame after a node is added and positioned, the "previous" transform is identity, so
  it interpolates **from the origin**. The camera reads
  `_anchor.get_global_transform_interpolated()`, so the eye rendered at `(0,0,0)` for one
  frame.
- **Fix:** call `reset_physics_interpolation()` on the body **after** setting its transform,
  and (for a camera that reads an interpolated child) snap the camera from the *real*
  transform rather than the interpolated one. `CameraController.snap_to_body()` does both;
  `Game._ready()` calls it after placing the player. The same primitive is used for the pod
  and console glides.

### A static body inside a rigid body is a solid ghost

- **Symptom:** a carryable crate seemed to fight its own physics / a second collider haunted
  it.
- **Cause:** a model authored with a `-col` suffix imports its mesh with its own
  `StaticBody3D`. Parented under a `RigidBody3D`, that static body is a **second collider on
  layer 1** that the physics engine drags around with the crate rather than simulating.
- **Fix:** zero the model's static body layers (`collision_layer = 0`, `collision_mask = 0`)
  so the `RigidBody`'s own shape is the only collider. See also the editor-drops-overrides
  note above — this override is the one that keeps getting lost.

---

## Audio

### `stream_paused` won't store on a player with no stream

- **Symptom:** a test asserting the music paused failed, even though the pause code was
  correct.
- **Cause:** Godot silently refuses to store `stream_paused = true` on an `AudioStreamPlayer`
  that has **no stream assigned**. The three music tracks do not exist yet, so their players
  are empty and the flag never sticks.
- **Fix:** verified the pause path against a player that *does* have a stream (the klaxon),
  and assert the controller's own `_paused` flag rather than the empty music players'
  `stream_paused`. The music will pause once real tracks land — it goes through the same
  `set_paused()` loop.

### Pausing the SceneTree does NOT pause audio

- **Symptom:** the klaxon and music kept playing over the pause menu.
- **Cause:** `get_tree().paused = true` pauses *nodes* (per their process mode); it does
  nothing to audio streams, which keep playing on the audio thread.
- **Fix:** `Audio.set_paused()`, wired to the pause menu, sets `stream_paused` on every voice
  explicitly. The controller runs with `PROCESS_MODE_ALWAYS` (so the menu's own click is
  audible) and therefore has to opt its own `_process` out while paused itself.

### A looping sound fired as a one-shot event never stops

- **Symptom:** the klaxon outlived its fault, played through the repair, over the pause menu,
  and out into the main menu.
- **Cause:** the klaxon is a *looping* stream, but it was triggered from the alarm **event**
  through the round-robin SFX pool. An event has no "off"; the loop was only ever silenced by
  another sound stealing its pool voice.
- **Fix:** the klaxon is driven by **state**, not event — its own dedicated player, on
  exactly while a critical fault is unrepaired. Every exit (repair, pause, pod, run end,
  leaving the scene) clears that state. One-shots (the hull bump) stay event-driven because
  an impact really is a moment.

---

## CPUParticles3D

Three separate silent no-ops, all hit while building the vent-pipe steam:

- **No `mesh` → nothing renders.** The `amount`/`lifetime`/emission all tick away invisibly.
  Assign a `QuadMesh` (or similar).
- **`material_override` is ignored for the particle draw pass.** Put the material **on the
  mesh** (`QuadMesh.material`), not as a `material_override` on the particle node, or you get
  the default lit-white material — a shower of solid grey squares.
- **`emission_shape = 3` is BOX, not sphere**, with 1 m default extents. The "jet" was
  spawning uniformly through a 2 m cube. `1` is `EMISSION_SHAPE_SPHERE`.

---

## Video

### `VideoStreamPlayer` only plays Ogg Theora

- **Symptom:** an `.mp4` assigned to a `VideoStreamPlayer` silently has no stream; the intro
  is a black screen.
- **Cause:** Godot 4 core only decodes **Ogg Theora** (`.ogv`), not MP4/H.264.
- **Fix:** transcode with ffmpeg — `tools/mp4_to_ogv.sh` wraps the exact recipe
  (`libtheora` + `libvorbis`). `smoke_intro_scene_manager` asserts the intro stream is a
  `VideoStreamTheora` specifically, so an `.mp4` slipping back in fails loudly instead of
  playing black.

---

## GDScript typing

### `self as OtherType` is a compile error across sibling branches

- **Symptom:** a script attached to a `RigidBody3D` but declared `extends Interactable` (which
  `extends Node3D`) fails to compile with *"Invalid cast. Cannot convert from 'CablePlug' to
  'RigidBody3D'"* the moment it tries `self as RigidBody3D` — even though the node genuinely *is*
  a RigidBody3D at runtime.
- **Cause:** `Interactable`/`Node3D` and `RigidBody3D` are sibling branches off `Node3D`. `as`
  raises a *compile* error (not a runtime null) when the compiler can prove the two static types
  are incompatible, and it can here — neither branch is an ancestor of the other.
- **Fix:** launder the cast through a common ancestor the compiler accepts:
  `var n: Node = self; var body := n as RigidBody3D`. `Node` is an ancestor of both, so the
  upcast is valid and the following downcast is merely runtime-checked (it succeeds because the
  node really is a RigidBody3D). The same applies to any test that needs both views of one node —
  type the handle as `Node3D`, then cast to each concrete type separately. This is the price of
  putting an `Interactable` (Node3D-branch) script on a physics body; see
  [scripts/game/cable_plug.gd](../scripts/game/cable_plug.gd).

### An editor scan registers a `class_name` even when the script won't compile

- **Symptom:** `godot --headless --editor --quit-after N` prints `update_scripts_classes |
  MyClass` and the name appears in `.godot/global_script_class_cache.cfg`, so the class looks
  ready — but a `-s` test that `load()`s it dies with *"Invalid cast…"* / *"Compile Error: Failed
  to compile depended scripts"*.
- **Cause:** the global-class registration is driven by the `class_name` **declaration line**
  during a light pre-parse; it does **not** require the body to type-check. A script with a
  compile error still gets its name cached.
- **Fix:** don't treat "the class is in the cache" as "the script compiles." The reliable compile
  check is running a headless test that actually `load()`s (or instances) the script — the error
  surfaces at load time. (New `class_name`s still need one editor scan first so *other* scripts
  can resolve the name; that scan just isn't a compile gate.)

---

## Headless testing & the test harness

### A parse error makes a `-s` test exit 0

- **Symptom:** a broken test *reports success* — green in the sweep, but it never ran.
- **Cause:** a GDScript parse error stops the script loading, and `godot --headless -s
  broken.gd` exits **0** anyway.
- **Fix:** the regression sweep greps each run's output for `Parse Error` **and** for a
  summary line (`-- N checks --` / `TEST PASS`), not just the exit code. A test that exits 0
  with no summary is treated as failed.

### A script error inside an awaited coroutine hangs the run forever

- **Symptom:** a `SceneTree` test never finishes; the harness times out at minutes.
- **Cause:** an error inside an `await`ed coroutine kills the coroutine, so the `quit()` at
  its end never runs. The process sits idle.
- **Fix:** every async suite arms a watchdog (`await create_timer(90).timeout` →
  `quit(1)`), so a stalled coroutine fails within 90 s instead of hanging. Ad-hoc probe
  scripts hit this constantly — if a probe "produces no output", it errored mid-coroutine;
  run it non-headless and read the `SCRIPT ERROR` line.

### `RenderingServer.frame_post_draw` never fires under `--headless`

- **Symptom:** a screenshot/capture script hangs on `await RenderingServer.frame_post_draw`.
- **Cause:** there is no draw in a headless run, so the signal never emits.
- **Fix:** capture scripts run **without** `--headless` (they need a real renderer). Logic
  tests run headless and never touch `frame_post_draw`.

### Test the wiring, not the call

- Signal-driven systems fail **silently** when a signal is connected to the wrong name or to
  a system that never emits — it sounds/looks exactly like the feature being absent. The
  audio suite drives the **real** `RunState` and watches what the controller was asked to do,
  rather than asserting `play()` was called on a mock. The nav test floods the **real**
  geometry with capsule casts rather than trusting placement coordinates.

### Beware measurements that confound themselves

- The starfield re-roll test kept "detecting" motion because `_process` was still
  accumulating `distance_travelled` between samples (fixed by `set_process(false)` + a manual
  `_apply()`). A shader-uniform default reads null both when unset and when queried headless,
  so those tests assert uniform **existence** only. When a numeric test surprises you, first
  suspect the harness is moving the thing it is measuring.

### Null-matches-null false positives

- **Symptom:** a positional-audio check passed while the sound was in fact missing.
- **Cause:** a missing sound is `null`, and an **idle pool voice's** `stream` is *also*
  `null`, so `voice.stream == _sounds.get(name)` matched `null == null` and reported a sound
  that never played.
- **Fix:** guard the comparison with `want != null` before matching. Then mutation-test the
  guard (point the path at a missing file and confirm it now fails).

---

## Tooling & environment

- **Working-directory drift.** `godot --path .` targets whatever the shell's cwd is; a
  drifted cwd once created files inside the *2025* project by mistake, and `--path .` built
  the wrong game. **Always use absolute paths** for `--path` and for file operations.
- **`timeout` is not on macOS by default.** `timeout 120 godot …` fails with "command not
  found" and the wrapper silently does nothing. Run the command directly and rely on the
  harness's own timeout, or `brew install coreutils` for `gtimeout`.
- **`var x := f()` fails when `f()` returns an untyped value.** GDScript can't infer the type
  of a variable assigned from a function returning an untyped `Dictionary` (or a
  `load(...).new()`), and refuses to parse — which, per the parse-error note above, exits 0.
  Annotate explicitly: `var ctx: Dictionary = build_run()`.
- **Prove a regression test can fail.** Several fixes here were mutation-tested — the code
  was deliberately re-broken to confirm the test goes red (the pod-refill rule, patch expiry,
  the instant-alarm switch, the missing-sound guard). A green test that cannot fail is not
  evidence.
