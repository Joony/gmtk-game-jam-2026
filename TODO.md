# TODO — GMTK Game Jam 2026

Godot 4.7 project. Core flow: Intro → Main Menu → Game ⇄ Pause Menu.

**THEME: "Countdown"**

**Setting:** first-person, aboard a spaceship travelling through space. Interiors are
procedurally built rooms with occasional windows looking out at passing stars.

**Hook (decided):** You're in stasis on a long haul to a destination — **distance to arrival counts
down**. Malfunctions wake you, and repairs are only possible while you're awake. **Oxygen is
literally time spent outside the pod, drawn from one finite supply for the whole run** — the pod
doesn't refill it, it just stops the drain. So every trip out is a permanent spend against a budget
you can never fully recover. Tone: *The Martian* — improvised fixes, cascading problems, and
solutions that create tomorrow's problem.

**Sections are ordered by implementation order** — work top to bottom. Steps 2–7 finish the
theme-agnostic shell and leave the game submittable at any point after; steps 8+ are the game
itself.

**One exception to the ordering:** prototype step 12's core loop (oxygen drains → fix something →
get back to the pod) with placeholder geometry right after step 5. It's the riskiest assumption in
the design and it's cheap to test — see the callout in step 12.

If the clock gets tight, the droppable scope is the *number of repair types* (step 12d) and
procedural generation in step 9 — a hand-built ship is fine, and arguably better. The player
controller, the oxygen loop, and one solid repair type are not optional.

---

## ✅ Done

### Project structure ([log](docs/features/project-structure.md))

- [x] Create folder layout: `scenes/`, `scripts/`, `ui/`, `assets/`
- [x] Add input map action `pause` bound to Esc (physical keycode, in `project.godot`)
- [x] Set the main scene in Project Settings (stub `scenes/intro.tscn` for now — replaced by the Intro feature)

### Scene loading system ([log](docs/features/scene-manager.md))

- [x] `SceneManager` autoload (`scripts/scene_manager.gd`)
  - [x] `change_scene(path)` — swaps the current scene
  - [x] Fade-out / fade-in transition (CanvasLayer + ColorRect, tween alpha)
  - [ ] Optional: `ResourceLoader.load_threaded_request` for async loading if scenes get heavy
- [x] Register autoload in Project Settings → Globals

### Intro ([log](docs/features/intro.md))

- [x] `scenes/intro.tscn` — black screen, big red countdown 10 → 0 (1s per tick)
- [x] Auto-advance to main menu when countdown hits 0
- [x] Skip button (bottom-right) transitions immediately
- [x] Fade in/out via SceneManager transition

---

## 1. ✅ Theme hook — DECIDED

**Stasis / oxygen / distance.** Long haul to a destination; distance-to-arrival counts down.
Malfunctions wake you from the stasis pod. Repairs happen only while awake, and being awake burns
oxygen from **one finite supply for the entire run**. The pod stops the drain; it does not refill.

Why it works: the two countdowns do different jobs. **Oxygen is a budget you allocate across the
whole run** — not a per-trip timer, so every second outside is a permanent spend and the question
is always "is this fix worth the air?". **Distance is the win condition**, the long arc. That's a
real twist on the theme rather than the crowded "10 minutes to escape" reading.

### ⚠️ The one thing that can break this design

If oxygen only drains outside the pod and distance ticks down on its own, then **staying in the pod
forever is the optimal strategy**. The entire design hinges on malfunctions making inaction cost
more than action. Get this right before anything else in step 12:

- [ ] Unfixed malfunctions must degrade progress — **confirmed required**, not optional
- [ ] Mix two severities so triage is a real decision, not arithmetic:
  - **Critical** — ship stopped/slowed hard; distance barely moves until fixed. You must go.
  - **Degrading** — a partial speed penalty. Genuinely optional; maybe cheaper to live with it.
- [ ] Some degrading faults should worsen over time if ignored, so deferring is a gamble rather
      than a free choice

### Open questions — settle these before step 12

- [x] ~~Does the pod refill oxygen?~~ **No.** One finite supply for the run; the pod pauses the drain.
- [ ] Can oxygen be *found*? Yes as a later reward — canisters, or repairing the O2 scrubber as a
      malfunction that pays out air instead of speed. Keeps the endgame from being purely terminal.
- [ ] What happens at oxygen zero — run over. (Confirm: with a finite pool this is the natural
      lose condition, and it makes every early trip matter retroactively.)
- [ ] Is a run finite (reach the destination = win)? Yes — finite gives an ending, which a jam wants.
- [ ] **Scope cap: how many distinct repair types?** "Several malfunctions" is content-heavy.
      Recommend **2–3 repair archetypes**, reused with varying locations and difficulty, not a
      bespoke minigame each. This is the most likely thing to blow the schedule.
- [ ] Oxygen readout: diegetic (suit gauge on the arm / a HUD element on the helmet) vs plain HUD.
      Suit gauge fits first-person, but must stay glanceable under pressure.
- [ ] Distance readout: probably a bridge display and/or visible through the windows — see step 11.

### Already on-theme (leverage these)

- [x] Intro is literally a 10 → 0 red countdown — reframe it as the **stasis wake-up sequence**
      (pod cycling, klaxon) rather than a title card. Already built; just needs dressing.
- [ ] Alert lighting (step 10) maps directly onto **active malfunctions** — red while something is
      broken, back to white once repaired. Doubles as a wayfinding cue toward the problem.
- [ ] Space windows (step 11) sell **both** countdowns diegetically: starfield speed reflects
      current ship speed (degraded by unfixed malfunctions), and the destination can grow visibly
      closer as distance drops.
- [ ] Room builder (step 9) is confirmed needed — travel distance between the pod and a malfunction
      *is* the oxygen cost, so the ship layout is a core mechanic, not set dressing.
- [ ] Carry system (step 8c) is confirmed needed — fetching a part to a broken panel is the repair
      loop, and it makes distance cost double (go get it, carry it back).

## 2. ✅ Main menu — done ([log](docs/features/main-menu.md))

- [x] `scenes/main_menu.tscn` — Control-based UI
  - [x] Title label (`STASIS` — **placeholder, needs a real name**)
  - [x] **Play** button → `SceneManager.change_scene("res://scenes/game.tscn")`
  - [x] ~~Options button~~ — deferred to step 13, where the volume slider it opens lives
  - [x] ~~Quit button~~ — not required (also removes the web-export special case)
- [x] Keyboard/gamepad navigation: set initial focus with `grab_focus()`
- [x] Cursor set visible on entry (the game will capture it in steps 4–5)
- [ ] Name the game and replace the placeholder title

## 3. ✅ Game scene — done ([log](docs/features/game-scene.md))

- [x] `scenes/game.tscn` — 40×40 floor, directional light + environment, three crate landmarks
- [x] Spawn point marker for the player, applied in `game.gd._ready()`
- [x] **Dev convenience:** `godot --path . scenes/game.tscn` boots straight in, skipping the intro.
      No debug flag needed — Godot takes a scene path directly.

## 4. ✅ Player controller — done ([log](docs/features/player-controller.md))

- [x] Copy `Player.gd` + `CameraController.gd` into `scripts/player/`
  - [x] Strip the portal-only `resync_now()` (kept `adopt_body_yaw()` — it isn't portal-specific)
  - [x] Keep `event.screen_relative` (NOT `relative`) — required under our `canvas_items` stretch mode
- [x] Build `scenes/player.tscn` — rebuilt the rig that was inline in Doortal's `test.tscn`
  - [x] `Player(CharacterBody3D)` → `CameraAnchor`, `CameraRig(top_level, interpolation Off)` →
        `Camera3D` → `HoldPoint`
  - [x] Swapped the 41-point ConvexPolygonShape3D for a CapsuleShape3D (r=0.4, h=1.8)
  - [x] `collision_layer = 1`
- [x] Input actions `forward`, `back`, `left`, `right` (WASD + arrows), `jump` (Space), by
      physical keycode
- [x] Enabled `physics/common/physics_interpolation = true` (asserted in the test, since a
      regression here is silent)
- [x] **Renderer decided: stay on GL Compatibility.** Doortal's ADR 0024 switched to Forward+ purely
      for portal SubViewport quality; we have no portals, and web export (step 7) requires GL
      Compatibility because Forward+ on the web needs WebGPU.
- [x] Stripped CameraController's own mouse capture — the pause menu (step 5) owns cursor state
- [x] Instanced into `scenes/game.tscn` at the spawn marker, mouse captured on game start
- [x] **Left behind:** `Carry.gd`, `PortalTeleportFixup.gd`, `PickableObject.gd`, `player_old.gd`
- [x] Test: pure movement maths, project settings, scene contract, live physics (spawn/fall/land/
      walk/stop), and mouse look with pitch clamping
- [ ] Tune once there are real rooms: `floor_snap_length` may need reducing so bunny-hops aren't
      snapped back to the floor (carried over from Doortal's note)

## 5. ✅ In-game pause menu — done ([log](docs/features/pause-menu.md))

> **Testing note:** cursor capture doesn't work under `--headless`, so anything cursor-related must
> be verified windowed:
> `godot --path . --resolution 640x360 --position 3000,3000 -s tests/<test>.gd`
> The headless run *skips* those checks (it says so) rather than failing, so a headless-only pass
> does not prove cursor behaviour.

- [x] `ui/pause_menu.tscn` — CanvasLayer, hidden by default
  - [x] `process_mode = ALWAYS` so it works while paused
  - [x] **Resume** button (also Esc again), focused on open
  - [x] **Quit to Menu** button → unpause, then `SceneManager.change_scene` to main menu
  - [x] Dim background (semi-transparent ColorRect)
- [x] Instanced into `scenes/game.tscn`
- [x] **Esc behaviour — one action does all three:** release the cursor, show the menu, pause
  - [x] Esc again (or Resume) reverses all three
  - [x] The pause menu owns Esc and *all* cursor state (camera's capture stripped in step 4)
  - [x] Quit to Menu leaves the cursor visible — the main menu needs it
  - [x] Consume the input event (`get_viewport().set_input_as_handled()`)
- [x] Esc is inert in the intro/main menu (the pause menu only exists in the game scene) — asserted
- [x] Emits `paused` / `resumed` signals — step 12's oxygen countdown must not drain while paused

## 6. Verify the loop

Most of this is already covered piecewise by the step 2–5 suites (intro→menu, menu→game,
game→Esc→Quit to Menu→menu, cursor state at each stage). What's left is proving it end-to-end in
one run, and that going round *twice* leaks nothing.

- [x] Intro → Main Menu (intro suite) — auto-advance and skip
- [x] Main Menu → Play → Game (main menu suite)
- [x] Game → Esc → Quit to Menu → Main Menu (pause menu suite)
- [x] Mouse capture correct at every stage (verified windowed)
- [ ] One test that walks the whole loop **twice** in a single run, asserting no orphaned nodes,
      no leaked players, and that the second Play behaves identically to the first
- [ ] ~~Quit button exits cleanly~~ — no Quit button (step 2)

## 7. Web export smoke test

Deliberately early. Leaving this to jam-day is how you find out at hour 46 that the export is
broken. ~20 minutes against the trivial shell, and it de-risks submission entirely. Matters more
than usual here because the renderer choice (step 4) interacts with it.

- [ ] Web export preset for itch.io, exported and actually loaded in a browser
- [ ] Confirm the Quit button is hidden on web
- [ ] Note any renderer/shader constraints this imposes before step 10 and 11 build on them

---

## 8. Interaction & item pickup

Two reference implementations exist. Take the **interface + detection** from GMTK 2025 and the
**carry physics** from Doortal.

- `/Users/joony/gmtk-game-jam-2025/Player/Interactable.gd` (81 lines) — live, clean, zero game
  deps. Interaction types, per-item prompt text, signals, group registration. Port nearly as-is.
- `/Users/joony/gmtk-game-jam-2025/Player/Player.gd:200-232` `check_for_interactables()` — a
  camera-forward **raycast**, 2.0m, `exclude = [self]`, `collide_with_areas = true`, then
  `find_interactable_in_hierarchy()` walks up parents to find the `Interactable`. Solid; port it.
  - **Decided: raycast, not proximity+angle.** Note the 2025 code already settled this — it has an
    `interaction_angle = 60.0` export and a facing-cone check at `Player.gd:222-227` that is
    **commented out**. The cone was tried and abandoned; `interaction_angle` is now vestigial.
    A reticle is a promise that you interact with whatever the dot covers, and only a ray keeps it.
  - Re-add the change guard at `Player.gd:230` (also commented out) so the UI updates on change
    rather than every physics frame.
- Doortal's `Carry.gd` (755 lines) — the physics carry we want, but portal-entangled. Extract, don't
  copy wholesale.

### 8a. Interactable base

- [ ] Port `Interactable.gd` → `scripts/interaction/interactable.gd`
  - [ ] Keep: `enum InteractionType { PICKUP, USE_ITEM, ACTIVATE, DISABLED }`, `interaction_text`,
        `is_enabled`, the `interacted_with` / `picked_up` / `dropped` signals, `get_item_node()`
        override hook, and auto `add_to_group("interactables")` in `_ready`
  - [ ] Drop `interaction_range` / `interaction_angle` — raycast detection makes them dead
  - [ ] **Keep `accepted_item_names` + `use_with_item()` — the hook needs it.** "Carry the right
        part to the broken panel" is the repair loop, and this is exactly that check. The
        "Can't use X here" prompt it already returns is free feedback.

### 8b. Detection — raycast (decided)

- [ ] Camera-forward ray, ~2.0–2.5m. Either a `RayCast3D` child of `Camera3D` (auto-follows the
      reticle, inspectable in-editor) or 2025's direct `intersect_ray` query — prefer the node.
- [ ] Port `find_interactable_in_hierarchy()` — the ray hits a CollisionShape/StaticBody, so walk
      up parents to find the owning `Interactable`. Keep the loop's infinite-loop safety check.
- [ ] `exclude`/collision mask must skip the player's own body, and the **currently held item**
      (otherwise the thing in your hands blocks every ray)
- [ ] Update `current_interactable` only on change, and emit `interactable_changed` so the UI
      subscribes instead of polling
- [ ] If precise aiming feels finicky in playtest, swap the `RayCast3D` for a `ShapeCast3D` with a
      small sphere (~0.15m) — that adds a few degrees of tolerance while still being "what the dot
      is on". Cheap change; do it only if it actually feels bad.

### 8c. Carry — Doortal's physics follow (decided)

Extracting from `/Users/joony/Games/doortal/scripts/Carry.gd`. Keep the render-frame kinematic
follow and wall sweeping; strip everything portal-related.

- [ ] Port the core: `_try_pickup` / `_grab` / `_drop` and the `_process` follow loop
- [ ] Keep: kinematic follow of the held RigidBody3D at render rate, **wall-sweep clamping** (item
      pulls in toward the player instead of clipping through geometry), break-free on obstruction,
      throw with capped release speed
- [ ] Keep the `HoldPoint` marker under `Camera3D` (Doortal has it at z=-2, y=-0.30)
- [ ] `Carry` must stay a sibling of `CameraRig` with `process_priority = 10` so it runs *after*
      the camera's priority-0 `_process` — otherwise the held item lags a frame behind the view
- [ ] `add_collision_exception_with` the player body while carrying (Doortal does this via
      `get_parent()` — replace that assumption with an exported NodePath to the body)
- [ ] **Strip:** every `Portal3D` reference, `_clip_clone` and the `cube_clip.gdshader` preload,
      portal-forwarding beams, transit tick budgets, chain arrays, the `get_tree().current_scene`
      portal auto-discovery walk (`Carry.gd:91-96, 750-754`)
- [ ] Replace the `&"pickable"` group check with the `Interactable` type check, so 2025's
      interface drives it and there's one concept of "interactable", not two
- [ ] Add input actions: `interact` (E) to pick up/drop, `throw` (mouse left, as in Doortal)
- [ ] Decide whether "hands full" blocks new pickups — leaning yes; `Interactable` already returns
      a "Hands full" prompt for that case

### 8d. Reticle & interaction UI

- [ ] `ui/reticle.tscn` — small dot centred on screen, always visible during play
  - [ ] **Grey** normally, **green** when the ray is on something interactable (decided)
  - [ ] Optional third state later: red/dim for `DISABLED` interactables ("can't use that yet").
        2025 shipped `red.png` and `grey.png` but never wired them up — all four interaction types
        preload the same green dot, so its indicator never actually changed colour.
  - [ ] Draw it in code or as a simple TextureRect — don't port 2025's HUD.tscn wholesale
  - [ ] Tween the grey→green change (~0.1s) so it doesn't strobe when sweeping across a room
- [ ] Interaction prompt near the reticle: item name + key hint (e.g. `[E] Pick up keycard`)
  - [ ] Pull the text from `Interactable.get_interaction_text()`
  - [ ] Fade in/out on change rather than popping (2025 tweened `modulate:a` over 0.1s)
- [ ] Hide reticle + prompt whenever the pause menu is open (cursor is visible then)
- [ ] Keep the reticle readable against both white and red alert lighting (step 10), and against
      the bright starfield through windows (step 11) — outline or blend mode may be needed
- [ ] Test: headless — ray hits a spawned Interactable and sets `current_interactable`, and misses
      when a wall is interposed; pickup sets the held reference and the item tracks the hold point
      over several frames; a held item swept into a wall clamps toward the player rather than
      passing through it; drop/throw releases cleanly and restores collision with the player;
      the reticle goes grey → green and the prompt text matches the targeted interactable

## 9. Procedural room builder (port from GMTK 2025)

Confirmed needed by the hook — walking distance between the pod and a malfunction *is* the oxygen
cost, so the ship layout is core mechanic, not set dressing.

**But: prefer a hand-authored layout over random generation.** The hook depends on carefully tuned
travel distances (pod → each malfunction site), and randomising those randomises the difficulty.
Use the room builder as a *construction tool* — build one deliberately designed ship in code, where
distances are chosen — rather than as a generator. Randomise *which* systems fail and when, not the
geometry. This also cuts scope: no need for connectivity/solvability guarantees.

Source: `/Users/joony/gmtk-game-jam-2025/V1/`. **Note:** there is no level editor in that project —
levels are authored by typing GDScript. What's worth taking is the runtime geometry kit: rectangular
rooms with auto-generated perimeter walls that split correctly around doors. That project is Godot
**4.4**, ours is 4.7. Beware: the root-level `LevelGenerator.gd`/`LevelManager.gd`/`Room.gd` etc. are
100% commented-out dead code — the live implementation is in `V1/` despite the name.

- [ ] Port `V1/Room.gd` (65 lines, Resource + `get_perimeter_walls()`)
  - [ ] Delete the `GameTypes.TileType` reference (autoload we're not bringing over; never read anyway)
- [ ] Port `V1/SlidingDoor.gd` (91 lines, Resource + wall-intersection math)
- [ ] Port `V1/RoomBuilder.gd` (252 lines — floors/ceilings/wall segments, material cache,
      door-aware wall splitting). Zero game-specific references; the genuinely non-trivial part.
- [ ] **Pick ONE coordinate convention up front.** 2025 has two subtly different ones —
      `grid_to_world` (tile centres, `+0.5`) vs `grid_boundary_to_world` (tile edges, no offset) —
      defined in three files with different signatures. That inconsistency is why Level 1's item
      positions are hand-tuned floats like `Vector3(11.4, 1.285, 6.07)`. Don't inherit it.
- [ ] Replace `flags_unshaded` (deprecated alias in 4.7) where it appears
- [ ] Write our own thin `LevelBuilder` — take only `build_rooms()`/`build_doors()` and the grid
      helpers from `V1/LevelManager.gd`. Do NOT port that file: ~300 of its 453 lines are the 2025
      day-loop, puzzles, HUD and audio, including `hud_node = current.get_child(2)`.
- [ ] Code-first API goal: build a room in a few lines, e.g.
      `builder.add_room(Rect2i(0, 0, 8, 6), {height = 3.0, wall_color = ...})`
- [ ] Skip `V1/LightingSystem.gd` as-is — one OmniLight3D **per floor tile** is a GL-compatibility
      hack (hundreds of lights on a 50×50 level). Write something appropriate for our renderer,
      and wire the lights to step 10 rather than hardcoding white.
- [ ] **Leave behind:** `ItemManager.gd` (hardcodes 24 office props + their .blend models),
      `Puzzles/`, `items/`, `Models/`, `AudioController`, `GameTypes`
- [ ] Test: headless — build a known room, assert floor/ceiling/wall counts, wall segments split
      around a door, and that room bounds match the requested Rect2i

## 10. Lighting modes

Cheap immediately after step 9 since it attaches to the room builder's lights, and it's where
the alert-state drama comes from.

Ship-wide lighting states — **normal** (white) and **alert** (red) — as a first-class system, since
the alert state is likely to carry a lot of the game's tension. Build alongside the room builder's
lighting so rooms subscribe rather than each managing its own lights.

**Driven by malfunctions:** red while any malfunction is active, white once all are repaired.
Consider making alert *local* to the affected room as well as ship-wide — a red-lit corridor is
free wayfinding toward the problem, which matters when oxygen is ticking and the player is lost.

- [ ] `LightingController` (autoload or a node in the game scene — decide when building it)
  - [ ] `enum Mode { NORMAL, ALERT }` + `set_mode(mode)` and a `mode_changed` signal
  - [ ] Room/light nodes subscribe to `mode_changed` instead of being poked individually
- [ ] Normal: white/neutral light, standard energy
- [ ] Alert: red light, and consider lower energy so it reads as darker and more oppressive
- [ ] Tween the transition rather than snapping (colour + energy over ~0.3–0.5s)
- [ ] Make the mode a property of the whole ship, not per-room, so it stays consistent as the
      player moves between rooms — including rooms built after the mode was set
- [ ] Ambient/environment light should follow the mode too, not just the light fixtures
- [ ] Design the modes as data (colour + energy + optional pulse) so adding a third state later
      (e.g. emergency/power-loss) is a new entry, not new code
- [ ] Optional polish if time allows: slow pulse or throb on alert, alert klaxon audio hook,
      emissive material on light panels switching colour to match
- [ ] Test: headless — set each mode and assert the resulting light colour/energy on built rooms,
      that `mode_changed` fires once per change, and that a room built *while* in alert mode comes
      up red rather than white

## 11. Space windows (starfield)

Highest visual payoff per hour in the list — this is the screenshot that sells the game on itch,
which is why it comes before the countdown mechanic despite reading as "polish". Needs step 9's
wall-splitting to punch openings.

Small windows in ship interiors looking out at stars streaking past, selling the "moving through
space" feeling.

**Now mechanically load-bearing, not just polish.** The windows are the diegetic readout for both
countdowns: starfield speed = current ship speed (degraded while malfunctions are unrepaired, so
the player can *see* the cost of ignoring a problem), and the destination growing closer = distance
remaining. A glance out of a window should answer "how am I doing?"

- [ ] Decide the approach — leaning toward a shader on a quad (cheap, no geometry, no extra camera):
      raymarched/hashed star field in the fragment shader, scrolled over time along the travel axis.
      Alternatives if that falls short: GPUParticles3D streaks in a small room behind the window, or
      a SubViewport rendering a real starfield scene.
- [ ] `RoomBuilder` support: punch a window opening into a wall segment (same splitting logic that
      already handles doors — reuse it rather than writing a second path)
- [ ] `scenes/props/space_window.tscn` — frame mesh + the star quad, placeable on any wall
- [ ] Ship-motion parameters shared across all windows so every window agrees on speed/direction
      (autoload or a single exported Resource — decide when building it)
- [ ] Parallax: stars nearer the window plane move faster than distant ones, so it reads as depth
- [ ] Drive star speed from actual ship speed, so unrepaired malfunctions visibly slow the view
- [ ] Destination visible ahead (a growing point of light / planet) tied to distance remaining —
      the cheapest possible progress readout, and it needs no UI
- [ ] Optional polish if time allows: subtle warp/streak stretch at speed, occasional passing debris,
      faint interior light spill from the window
- [ ] Test: headless — shader/material compiles without error, window opening actually appears in
      the wall geometry, star motion advances over time (sample the motion parameter across frames),
      and star speed responds to a changed ship-speed value

## 12. Countdown mechanic — stasis / oxygen / distance

The actual game, on top of a ship you can already walk through, pick things up in, light, and
look out of.

> **Prototype the core loop early — don't wait for step 12.** The whole game rests on one question:
> with a finite air budget for the entire run, is "is this fix worth the air?" actually a tense
> decision? Testable with a bare room, one draining number, a pod to stand in, and two placeholder
> repair points at different distances — right after step 5. Specifically check the failure mode
> above: if sitting in the pod is ever the smart play, the malfunction penalties are too weak.
> Steps 8–11 make it *good*; this tells you whether it's *worth* making good.

### 12a. Distance countdown (the win condition)

- [ ] Distance-to-destination value that decreases over time at the current ship speed
- [ ] Ship speed degrades per active malfunction — this is what makes ignoring problems costly
- [ ] Reaching zero = arrival = win
- [ ] Pick a target run length and tune backwards from it (jam games want ~5–10 minutes)

### 12b. Oxygen (one finite pool for the whole run)

- [ ] Single run-scoped oxygen value; drains **only** while outside the pod, at a flat rate
      (so oxygen ≡ time outside, and the player can reason about it in seconds)
- [ ] Readout per step 1's decision (suit gauge vs HUD) — must be glanceable under pressure
- [ ] Show it in *time remaining*, not a percentage — the whole decision is "can I make it there
      and back", which is a time question
- [ ] Escalating feedback as it runs low: audible breathing, heartbeat, vignette, colour drain.
      Sound does more work than UI here.
- [ ] Zero = run over
- [ ] **Findable oxygen** (later-game reward, per step 1): canisters as `Interactable` pickups, or
      an O2-scrubber malfunction that pays out air instead of speed. Gives the endgame a comeback
      and a reason to explore rather than beeline.

### 12c. Stasis pod (the loop anchor)

- [ ] `Interactable` pod — enter to stop the oxygen drain and skip ahead to the next malfunction
- [ ] **The pod does not refill oxygen** — it pauses the bleed. It's a stop button, not a refuel.
- [ ] The trip back to the pod costs air too, so the pod's distance from the action is a core
      tuning knob. Every excursion's real price is *there and back*.
- [ ] Wake-up sequence reuses the intro countdown (step 13), pod lid, klaxon

### 12d. Malfunctions & repairs — *The Martian* problem-solving

The tone target: improvised fixes under pressure, where solving today's problem cheaply creates
tomorrow's. Sequencing matters — build the single-solution version first, then layer branches onto
the repairs that are already working.

- [ ] `Malfunction` — a ship system that can break, with a location, a state, and a severity
      (critical vs degrading, per step 1)
- [ ] **2–3 repair archetypes only** (step 1 scope cap), reused at different locations. Candidates:
      fetch-and-fit a part (uses carry + `use_with_item` from step 8), a physical
      switch/valve sequence, and something timing-based. Resist a bespoke minigame per system.
- [ ] Malfunctions fire over time / on a schedule, and can stack while you're in stasis
- [ ] Repaired systems restore full speed; the light goes white (step 10)
- [ ] Signal on state change so lighting, windows and audio all react without polling

#### Multiple solutions with consequences

Only worth doing on 2–3 problems, not every one. Ranked by implementation cost — start at the top:

- [ ] **Patch vs proper fix** (cheapest, do this first). Same repair, two interaction options: a
      fast bodge that costs little air but re-breaks after N minutes, or a slower permanent fix.
      Implementation is one boolean and a re-fire timer, and it's already a real decision.
- [ ] **Cannibalise** (cheap, high drama). Fix system A using a part taken from system B; B is now
      broken or degraded. Reuses the carry system entirely — no new mechanics, and it produces the
      best *Martian* moments because the player authors their own next crisis.
- [ ] **Spend a resource to solve it** (best fit for the theme). Vent oxygen to smother a fire,
      dump reserve air to repressurise a section. Makes oxygen a currency spendable *in fiction*,
      not just a timer — the strongest tie between mechanic and story here.
- [ ] Consequences must be *visible and attributable* — when the bodged coolant line fails an hour
      later, the player has to recognise it as their own earlier choice, or it reads as random
      punishment. Log/telegraph it: same location, same sound, a line of text.
- [ ] Keep a short run summary of the choices made, for the end screen (step 12e) — cheap to build
      and it makes the branches feel like they mattered

### 12e. Wiring & end states

- [ ] Malfunction state → alert lighting (step 10), ship speed → starfield (step 11)
- [ ] Win at distance zero; lose at oxygen zero — both route back to the main menu with a summary
      (distance covered, repairs made, air spent, and the choices made per 12d)
- [ ] Test: headless — distance decreases at the expected rate and slows per active malfunction;
      oxygen drains only while outside the pod and does **not** refill on entering; a repair clears
      its malfunction and restores speed; a bodged repair re-fires after its interval; win fires
      exactly once at distance zero and lose exactly once at oxygen zero
- [ ] **Balance pass — the whole game is in these numbers.** Total oxygen must be tight enough that
      you can't fix everything, but loose enough to finish. Expose oxygen total, drain rate, speed
      penalties and malfunction intervals as exported values so they're tunable without code edits.

## 13. Polish / remaining

- [ ] Audio: menu music, button click SFX (AudioController pattern from 2025 project)
- [ ] Options menu: master volume slider, plus the **Options button** on the main menu that opens
      it (deliberately deferred from step 2 — no button until there's something behind it)
- [ ] Rework the intro into the **stasis wake-up sequence** — the existing 10 → 0 red countdown
      becomes the pod's revival cycle (klaxon, lid opening) instead of a title card
- [ ] Re-run the web export from step 7 with the finished game before submitting
