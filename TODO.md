# TODO — GMTK Game Jam 2026

Godot 4.7 project. Core flow: Intro → Game (START) ⇄ Pause Menu → Quit to Menu → Play.

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

- [x] `scenes/intro.tscn` — black screen, big red two-digit countdown `10, 09 … 01` (1s per tick)
- [x] Holds 1.5s on `01` (never reaches `00`), then fades into the **game** scene
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

- [x] Intro is a 10 → 01 red countdown that now leads straight into the game — still worth dressing
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
  - [x] Title label (currently `PERPETUAL PICKLE` over a `WORKING TITLE` subtitle)
  - [x] **Play** button → `SceneManager.change_scene("res://scenes/game.tscn")`
  - [x] ~~Options button~~ — deferred to step 13, where the volume slider it opens lives
  - [x] ~~Quit button~~ — not required (also removes the web-export special case)
- [x] Keyboard/gamepad navigation: set initial focus with `grab_focus()`
- [x] Cursor set visible on entry (the game will capture it in steps 4–5)
- [x] ~~Name the game~~ — tracked in step 7a

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

## 6. ✅ Verify the loop — done ([log](docs/features/loop-verification.md))

- [x] Intro → Main Menu (intro suite) — auto-advance and skip
- [x] Main Menu → Play → Game (main menu suite)
- [x] Game → Esc → Quit to Menu → Main Menu (pause menu suite)
- [x] Mouse capture correct at every stage (verified windowed)
- [x] `tests/smoke_full_loop.gd` walks the whole loop **twice** in one run — node count and orphan
      count identical between rounds (12/0 → 12/0), no player instances left alive, tree unpaused
- [x] ~~Quit button exits cleanly~~ — no Quit button (step 2)

## 7. ✅ Web export — done ([log](docs/features/web-export.md))

- [x] Web export preset for itch.io (`export_presets.cfg`, no-threads, adaptive canvas,
      tests/docs excluded); `/build/` gitignored
- [x] Compatibility audit: `gl_compatibility` renderer (correct for web); no threads or
      platform-specific APIs in game code
- [x] Export templates installed; build produced (~38 MB, mostly `index.wasm`)
- [x] Loaded in a browser over HTTP: boots clean, WebGL2, font renders, buttons work,
      SceneManager transitions work, 3D scene renders
- [x] **Pointer lock addressed** by the START prompt (step 7a below) — capture now happens inside
      a button `pressed` handler, which is the user gesture browsers require
- [ ] **Confirm pointer lock in a normal browser tab.** The automated browser pane runs the page
      with `visibilityState: hidden`, where the browser refuses pointer lock to *any* code (a direct
      `canvas.requestPointerLock()` from the console fails with `WrongDocumentError`). Serve with
      `.claude/launch.json` (port 8099), open a real tab, click START, check mouse look.
- [ ] Upload to itch.io and confirm it runs there (different headers/CDN than localhost)
- [ ] Re-check when step 13 adds audio: browsers block audio until a user gesture — the START
      button is the natural place to initialise it

## 7a. ✅ START prompt + font/theme + intro rework ([logs](docs/features/start-prompt.md))

- [x] **START prompt** gates the game: cursor free and player frozen until clicked, Esc disabled
      until then, capture happens in the button handler
      ([start-prompt.md](docs/features/start-prompt.md))
- [x] **Font** `AbolitionTest-Regular` applied project-wide via `ui/theme.tres` +
      `gui/theme/custom` — no per-node font overrides
      ([font-and-theme.md](docs/features/font-and-theme.md))
- [x] **Intro** counts `10, 09 … 01` zero-padded, holds 1.5s on `01` (never reaches `00`), then
      fades into the game ([intro.md](docs/features/intro.md))
- [x] **Flow change:** the intro now leads straight into the game, not the main menu. The menu is
      reached via pause → Quit to Menu, and its Play returns to the game. Both routes are covered
      by the loop test. One-line revert if wanted: `NEXT_SCENE` in `scripts/intro.gd`.
- [ ] Name the game — the menu currently reads `PERPETUAL PICKLE` over a `WORKING TITLE` subtitle

---

## 8. ✅ Interaction & item pickup — done ([log](docs/features/interaction-and-carry.md))

Interface + detection from GMTK 2025, carry physics from Doortal.

- [x] **8a Interactable** — ported; kept `accepted_item_names` + `use_with_item()` (the repair
      loop needs them), dropped `interaction_range`/`interaction_angle`, added `can_act_on()`
- [x] **8b Detection** — camera ray (2.5m), `find_interactable_in_hierarchy()`, excludes the
      player body **and the held item**, emits `focus_changed(interactable, prompt, actionable)`
- [x] **8c Carry** — Doortal's render-frame kinematic follow extracted (~180 lines from 755):
      frozen kinematic body authored per `_process`, wall-sweep clamping, break-free, capped
      release velocity, throw impulse, `process_priority = 10`
- [x] **8d Reticle** — grey dot, green **when you can act** (not merely when something is
      there), 0.1s tween, outlined prompt; hidden while paused and before START
- [x] Input actions `interact` (E) and `throw` (left mouse)
- [x] Demo content: two pickup crates and a `USE_ITEM` socket in `scenes/game.tscn`
- [x] Tested: detection, occlusion, pickup/track/drop/throw, wall sweep, hands-full, and the full
      carry-a-part-to-a-socket flow — all driven through real input events

### Follow-ups (not blocking)

- [ ] `DISABLED` interactables are currently never targeted (`can_interact()` filters them out).
      If step 12 wants "can't use that yet" feedback, surface them and add the red dot state.
- [ ] If precise aiming feels finicky in playtest, swap the ray for a `ShapeCast3D` with a small
      sphere (~0.15m). Cheap change; only do it if it actually feels bad.
- [ ] Held-item rotation is not swept, only translation — a fast turn can clip a long item into
      a wall corner. Fine for small props; revisit if the repair parts get big.

## 9. ✅ Procedural room builder — done ([log](docs/features/room-builder.md))

- [x] Port `V1/Room.gd` → `scripts/level/room.gd` (Rect2i, `GameTypes.TileType` dropped)
- [x] Port `V1/SlidingDoor.gd` → `scripts/level/doorway.gd` — **renamed `Doorway`**, nothing
      slides; kept the wall-intersection maths, left the panels/animation behind
- [x] Port `V1/RoomBuilder.gd` — perimeter walls with door-aware splitting, material cache
- [x] **ONE coordinate convention.** Grid coords *are* boundary coords: grid (x,y) → world
      (x·tile, y·tile), centres at +0.5. Dropped 2025's dual convention AND its `level_width/2`
      centring, which made world position depend on the level's declared size.
- [x] One box per surface instead of one per tile (2025: 800 nodes for a 20×20 room)
- [x] **Shared walls built once** via per-line span subtraction — handles partial overlap between
      differently-sized rooms; replaces 2025's z-fighting nudge offsets
- [x] No `flags_unshaded`; **flat interior lighting** — a shadowless grid of ceiling omnis plus
      emissive panels, no directional sun, ambient 0.45, per Doortal ADR 0010 and GMTK 2025
      ([log](docs/features/flat-lighting.md)). Grouped `room_lights` / `room_light_panels`.
- [x] Code-first API: `add_room(Rect2i(...), {...})` / `add_doorway(...)` / `build()`
- [x] **Hand-authored ship** (`scripts/level/ship_layout.gd`): pod bay, corridor, engine room,
      two doorways — replaces the flat sandbox floor in `scenes/game.tscn`
- [x] **Left behind:** `ItemManager.gd`, `Puzzles/`, `items/`, `Models/`, `AudioController`,
      `GameTypes`, and `V1/LevelManager.gd` (~300 of its 453 lines are the 2025 day-loop)
- [x] Tested: span maths, counts, no duplicate shared walls, doorway passable + lintel solid,
      idempotent rebuild, and the real ship walkable

### Follow-ups (not blocking)

- [x] **Sliding doors** — done ([log](docs/features/sliding-doors.md)). Two panels per opening,
      slide apart on approach via an `Area3D`, 0.4s sine tween, metallic finish. Upgraded to
      `AnimatableBody3D` (2025 used `StaticBody3D`, which doesn't sweep and would clip the player)
      with the tween on the physics clock. Only the `player` group triggers them.
  - [x] `SlidingDoor.jammed` — a door that refuses to open, ready for a step 12d repair
  - [ ] Sound: the slide is silent (step 13 audio)
  - [ ] Doors are ship-wide identical; if the engine room wants a heavier bulkhead, add a
        per-doorway style later
- [ ] Copy `smoke_room_builder.gd`'s **watchdog** into the other async tests: a script error inside
      an awaited coroutine silently hangs the test instead of failing it

## 9a. ✅ Window size → 1920×1080 — done ([log](docs/features/window-size.md))

- [x] `viewport_width = 1920`, `viewport_height = 1080` in `project.godot`
- [x] Scaled every hand-tuned UI size by 1.667 to preserve the tuned look — theme font, intro
      countdown, menu/pause titles, buttons, reticle prompt, separations, offsets
- [x] Re-rendered every UI screen and compared: proportions unchanged, 3D visibly crisper
- [x] Reticle dot 9px → 15px (the specific risk called out) — still reads correctly
- [x] Web canvas re-checked in a browser: adaptive resize + `aspect=expand` means **no
      letterboxing**; canvas matches the window exactly at DPR 2
- [x] ~~`window_width_override` / fullscreen defaults~~ — deliberately none; the OS clamps the
      window on smaller displays and the web canvas adapts

## 10. ✅ Lighting modes — done ([log](docs/features/lighting-modes.md))

- [x] `LightingController` — a node in the game scene (not an autoload: it drives scene-scoped
      lights and the scene's `WorldEnvironment`)
  - [x] `enum Mode { NORMAL, ALERT }`, `set_mode()` / `set_alert()`, `mode_changed` signal that
        fires only on a real change
  - [x] Lights are driven by group (`room_lights`, `room_light_panels`) rather than each
        subscribing — see below
- [x] Normal: neutral white, energy 1.6
- [x] Alert: red **and dimmer** (1.15) so it reads oppressive rather than merely red
- [x] 0.4s smoothstep transition, not a snap
- [x] **Mode is a property of the whole ship** — values are applied to the light groups every
      frame, so a room built *while in alert* comes up red. Asserted in the test; this requirement
      is what ruled out per-light tweens.
- [x] Ambient/environment follows the mode too (the `Environment` is duplicated on bind, or state
      leaks between game-scene instantiations)
- [x] Modes are **data** (`MODES` dict: colour, energy, ambient, pulse) — a third state is a new
      entry, not new code. The test asserts all modes declare the same keys.
- [x] Slow pulse on alert (`pulse_hz`, exported so step 12 can speed it up as time runs down)
- [x] Emissive ceiling panels turn red with the fixtures
- [x] Tested: mode values, signal semantics, gradual transition, late-built room, pulsing

### Follow-ups (not blocking)

- [ ] **Local alert** — red only in the affected room, as wayfinding toward the problem. Ship-wide
      for now; revisit in step 12 when malfunctions have locations (needs per-room light groups).
- [ ] Alert klaxon — step 13 audio. `mode_changed` is the hook.

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

> **Asset available:** `CD_Cryo_v1.2.blend` (cryo chamber, added by LoganDevz) with a scratch
> scene at `node_3d.tscn`. This is the pod model. Worth moving both under `assets/` and
> `scenes/props/` when it's wired up — coordinate first, since moving a collaborator's files
> mid-jam causes merge pain.

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
