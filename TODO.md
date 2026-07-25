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

- [x] ~~**START prompt** gates the game~~ — **removed.** With the flow now menu → intro video →
      game, a second "press START" screen was a redundant click, so the game auto-starts on load
      (`start_game()` from `Game._ready()`; `ui/start_prompt.tscn` deleted). The one thing the
      prompt did that this loses is the browser pointer-lock gesture: a video that plays to the end
      leaves no user activation, so on web the mouse capture defers to the player's first click
      rather than happening instantly. Desktop is unaffected.
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

## 11. ✅ Space windows — done ([log](docs/features/space-windows.md))

- [x] **Approach: shader on a quad** (no extra camera, no geometry). Hashed 3D star grid sampled
      along a per-fragment view ray, five depth slabs for parallax.
- [x] **RoomBuilder support reuses the door-splitting path** — `Doorway` gained `sill`/`top`, so a
      window is just an opening that doesn't reach the floor; segments emit sill and lintel pieces
- [x] Built by `RoomBuilder.add_window()` rather than a `space_window.tscn` — consistent with how
      doors and lights are built (deviation from the original plan, noted)
- [x] **Shared ship-motion parameters** — `ShipMotion` node pushes speed/heading to the
      `space_windows` group each frame; all windows share one material, asserted
- [x] Parallax: near stars sweep faster than far ones (24-cell ray march, angular star sizing)
- [x] **Fore and aft windows** as well as port/starboard — the forward one is where the destination
      will appear
- [x] Flicker fixed: stars were sampled at a single depth per slab and cut off hard at the range
      limits. Now marched cell by cell with both ends faded, field pushed out to ~1.1km. Measured:
      a 5cm advance changes 4.4% as much as a whole new sky (was 54% for 30cm).
- [x] Cross of empty sky removed: the cell margin that stops stars being sliced was a fixed 20%,
      which at close range spans ~69° of view along the world axes through the eye. It now scales
      with the star's angular size, leaving a ~0.3° band. Smoothness improved to 1.5%.
- [x] Star speed driven by actual ship speed — **zero stops the stars dead**
- [x] Streaking grows with speed
- [x] Destination hook (`destination_brightness`) ready for step 12's distance countdown
- [x] **Glass** in each opening, or thrown items fly out into space
- [x] Tested: shader loads, opening genuinely cut (geometric check), glazing, motion advances and
      stops, streak responds, destination toggles

- [x] **Windows are real holes** — the starfield moved from per-window panes to a backdrop shell
      (inverted sphere, `starfield` group), so real exterior geometry shows through them
- [x] **Space station outside the hull**, on render layer 2 with an `ExteriorSun` whose
      `light_cull_mask` keeps it off the interior

### Follow-ups (not blocking)

- [ ] Rename `Doorway` → `WallOpening` (six files) now that it models windows too
- [ ] A planet is still best done procedurally in the shader (ray-sphere) — real geometry can't
      sit at a believable distance given the 4000m far plane
- [x] Nebula / Milky Way band — procedural, direction-only so it sits at infinity
      ([log](docs/features/space-exterior.md))
- [x] Runtime controls: `=`/`-` speed (multiplicative, up to 60x cruise), `]`/`[` star count, with
      a transient readout. Debug/tuning aids — step 12 drives speed from malfunctions instead.
- [x] Stars vanishing mid-view: grid is now walked with a 3D DDA (exact cell traversal), and the
      field depth scales with speed so a star is not crossing the whole range in under a second.
      Measured 0.2% -> 0.0% vanished at 20x cruise. `field_stretch_with_speed` dials persistence
      against the sense of speed.
- [x] Field stretching removed — changing `cell_size` re-rolled the whole grid, so every speed
      change flickered. Near field brought in to 10–260m so its stars actually stream.
      Measured: 28% sky change per second at cruise, 0.0% re-roll on speed change.
- [x] Distant star layer: a ~60km shell of non-streaking, effectively stationary stars for the near
      field to move against. One sample per ray; angular density so it fills the sky independently
      of the near grid. Let `field_stretch_with_speed` drop 0.35 -> 0.2.
- [x] Warp streaks radiate from the vanishing point (smearing along the travel axis did nothing
      head-on); star density defaults to 15%
- [ ] Nebula cost is unprofiled on the web build (~6 noise evals per sky pixel). If it bites: drop
      the dust-lane layer to two octaves, or bake the band to a small cubemap at startup.
- [ ] Windows are only valid on **exterior** walls — the builder doesn't check; the layout must
- [ ] No frame mesh (the wall's sill/lintel/jambs frame it) and no light spill into the room
- [ ] The glazing is invisible — collision only, no mesh. A faint Fresnel sheen is specced as
      **step 16**; opening trim geometry is part of step 15.
- [ ] Optional polish from the original plan not done: passing debris, a distant planet

## 12. ✅ Countdown mechanic — done ([log](docs/features/countdown-loop.md))

The actual game, on top of a ship you can already walk through, pick things up in, light, and
look out of.

> **This section's own warning turned out to be the whole story.** It read: *"if sitting in the
> pod is ever the smart play, the malfunction penalties are too weak."* The first balance
> simulation found exactly that — ignoring every fault arrived with the entire air budget
> unspent. Two changes fixed it: the pod now costs air at 0.35x (so the journey is priced in
> air, and speed matters), and spares are generic and scarcer than the faults (so a permanent
> fix is not free and patching is a real option). Full reasoning in the log.

### 12a. Distance countdown (the win condition) — **done**

- [x] Distance-to-destination value that decreases over time at the current ship speed
- [x] Ship speed degrades per active malfunction (penalties add; floored at 6% of cruise so
      an over-100% run stays finishable rather than becoming an unwinnable wait)
- [x] Reaching zero = arrival = win
- [x] Target run length picked and tuned backwards from it — see the balance table below

### 12b. Oxygen (one finite pool for the whole run) — **done**

- [x] Single run-scoped oxygen value
- [x] Shown in *time remaining* (m:ss), never a percentage
- [x] Escalating feedback: radial red vignette that pulses faster the lower it gets, gauge
      turns amber then red. **Sound still missing — step 13, and it is doing the most work.**
- [x] Zero = run over
- [x] **Findable oxygen**: a proper O2-scrubber repair recovers 30s of reserve, capped at
      the run total. The only thing in the game that gives air back.
- [ ] ~~Drains **only** while outside the pod~~ — **changed after the balance simulation.**
      A free pod meant sleeping through every fault won the run with the air budget
      untouched. The pod now drains at 0.35x, so the journey costs air too and ship speed
      matters. The pod still NEVER refills.

### 12c. Stasis pod (the loop anchor) — **done**

- [x] `Interactable` pod — enter to slow the oxygen drain and fast-forward at 24x
- [x] **The pod does not refill oxygen** (mutation-tested — this is the load-bearing rule)
- [x] The trip back costs air too, so the pod's distance from the action is a tuning knob
- [ ] Wake-up sequence reuses the intro countdown, pod lid, klaxon (step 13)
- [ ] Swap the placeholder box for `CD_Cryo_v2.blend` — coordinate first, the .blend and its
      scratch scene are still at the repo root

### 12d. Malfunctions & repairs — **done (single-solution + all three branch types)**

- [x] `Malfunction` — location, state, severity, and every cost as exported data
- [x] **Two repair archetypes**, both on one panel: patch (empty-handed) and fit-a-spare
      (carrying a part). No new input action, no minigame.
- [x] Faults fire on a distance schedule and can stack while you are in stasis
- [x] Repaired systems restore full speed; the light goes green (amber while patched)
- [x] Signals on every state change — lighting, HUD and the summary all react without polling

#### Multiple solutions with consequences — **all three shipped**

- [x] **Patch vs proper fix** — `bodge_distance`; the patch re-breaks at the same panel
- [x] **Scarcity instead of cannibalising** — spares are generic (`spare_parts` group) and
      there are only 3 for 4 scheduled faults. Chosen over cannibalising because the
      simulation showed named one-per-system parts made the permanent fix free, so patching
      was never worth choosing. Cannibalising is still open as a later addition.
- [x] **Spend a resource to solve it** — `bodge_oxygen_cost`; venting 25s of air patches the
      coolant loop
- [x] Consequences are visible and attributable — same location, same panel, and a named
      line in the run summary
- [x] Run summary of the choices made, shown on the end screen

### 12e. Wiring & end states — **done**

- [x] Malfunction state → alert lighting; ship speed → starfield
- [x] Win at distance zero, lose at oxygen zero, both to a summary screen and back to the menu
- [x] Tests: `tests/smoke_run_state.gd`, 72 checks, all passing. Full regression: 11/11 suites.
      The pod-refill and patch-expiry rules were mutation-tested to prove the tests can fail.
- [x] **Balance pass.** `tests/balance_sim.gd` plays three strategies against the real scene:

      ignore   SUFFOCATED  600s  air left   0s   51.4 km of 54 km
      patch    ARRIVED     210s  air left  44s   0 permanent / 7 patches (7 gave out)
      proper   ARRIVED     170s  air left 145s   3 permanent / 1 patch

      Doing nothing suffocates you just short of the destination; patching survives on 44s;
      spending the spares well arrives comfortably. All values exported on `game.tscn`.

### 12f. Ship fittings — **done** ([log](docs/features/ship-fittings.md))

- [x] Distance in **millions of miles**, time in **days**. The voyage has its own speed model
      (`cruise_speed_per_day`, `days_per_real_second`) separate from ShipMotion's metres per
      second, which stays tuned for how the starfield should look.
- [x] **Fixed-width numeric display** (`DigitReadout`) — one slot per character so the clocks
      stop twitching sideways as digits change. Values zero-padded to constant width, since
      fixed slots alone do not stop 9.9 -> 10.0 shifting the row.
- [x] **Five CD_Cryo_v2 pods in a pentagon**, doors outward, the player's facing aft at the
      +Z vertex. Cryo bay widened to 14x14x4.4 — at the old size the ring left a 12cm gap
      against the wall and the player could not walk past.
- [x] **Smooth camera ride into and out of the pod**, with the door swinging shut behind you.
      The camera keeps running inside the pod so you can look around.
- [x] **Visual puzzle**: the coolant loop is a cracked pipe venting vapour. A patch is visibly
      a patch (crooked tape); a permanent repair is a machined sleeve.
- [x] **Nav console** in the cryo bay, in the spirit of GMTK 2025's computer: a hand-drawn
      chart on a real SubViewport screen, with a full-screen version on interact.

#### Step 12 follow-ups

- [ ] Repairs are instant once you reach the panel — a hold-to-repair timer would let the
      two routes differ in duration as well as in scarcity
- [ ] Faults fire on a fixed schedule, so run two is identical to run one. Randomise *which*
      system fires (never where the rooms are).
- [ ] `SlidingDoor.jammed` is still unused as a fault type
- [ ] Optimal play is ~3 minutes; the 5-10 minute target relies on real players being slower
      than the simulation. Re-check against an actual playthrough.
- [ ] The four scenery pods are empty — occupants would sell the fiction cheaply
- [x] ~~Move `CD_Cryo_v2.blend` out of the repo root~~ — LoganDevz did it, into `3D-Models/`.
      `cryo_pod.tscn` followed. `node_3d.tscn` is still a scratch scene at the root.
- [x] Real models swapped in: `CD_CryoStation_v1` (the furnace at the centre of the pod
      ring), `CD_PipeBroken_v1` + `CD_PipeDecor_v1` (the coolant line — the permanent fix now
      literally swaps the ruptured pipe for the intact one), `CD_Crate_v1.1` (the pickups).
- [ ] Still unused from `3D-Models/`: `CD_Pc_v2.1` (would replace the box nav console),
      `CD_Plug_v1` (for the cables, 14d), `CD_Hammer_v1` (a tool — repair, or a carryable).
      Also `Perpetual Pickle Intro.mp4` for the intro rework.
- [ ] Name the two worlds on the nav chart, and the game
- [ ] **`.tscn` Transform3D basis literals are ROW-major.** Writing one from column vectors
      gives the transpose, i.e. the opposite rotation. This buried three repair panels inside
      walls. `tests/smoke_navigation.gd` now guards it.

## 12g. ✅ Opening stasis — done ([log](docs/features/opening-stasis.md))

Playtest: *"the player should start inside the cryo pod like they're in stasis. After a quick
pause they should be brought out of stasis and the game begins."*

- [x] The run opens with the player sealed in the pod, not stood in front of it
      (`Game._pose_in_pod()`). `PlayerSpawn` deleted — nothing read it any more.
- [x] **The ship is already broken:** `DRIVE REGULATOR`, critical, 10% with a slow 0.03/day
      bleed, on the engine room's port wall. `Malfunction.starts_broken`, applied by
      `RunState.start()` BEFORE it connects its signals — otherwise frame zero fires an alarm
      event and `_on_broke` wakes the player out of the opening beat.
- [x] Its klaxon carries into the pod. That is the ONE stasis that is not soundproof; every
      other one calls `Audio.set_sealed(true)` (mutes SFX + Voice, not music).
- [x] `CD_Intro` plays at `_finish_exit()`, once the player is stood in the room — at the wake
      it lands under the cork pop and the door servo.
- [x] The ship wakes them after `OPENING_STASIS_TIME` (1.6s) through the pod's **ordinary** wake
      — cork pop, door swing, ride out — with no branch for the first one. `[E]` skips it.
- [x] **Cold open:** no HUD, no "IN STASIS · [E] WAKE" panel, no music until that wake. Both
      routes out (the timer and the player's `[E]`) funnel through `_on_stasis_changed()`, which
      is the only place that catches both.
- [x] **"01" stencilled inside the door** in Abolition, semi-transparent, at eye height
      (1.6m — *not* `PodView`'s 0.95m), parented to `Model/Door` so it swings away with the panel.
- [ ] The pod shell is single-sided, so from inside there is no door rendered behind the "01" —
      it reads as floating rather than printed. Fix is `cull_mode` on the door mesh; not done,
      because it changes how the pod itself looks.
- [x] Tested: `smoke_opening_stasis.gd`, `smoke_pod_label.gd`, `capture_pod_label.gd` (3 renders).
      Nine mutations killed. Eleven suites that assumed the player starts on their feet now share
      `tests/opening.gd`.

## 12h. ✅ Drive decay + the hammer — done ([log](docs/features/drive-decay-and-hammer.md))

Playtest: *"Critical failures should count-down the drive-speed... A quick patch should only stop
the count-down for that specific critical issue, and not restore the drive speed to 100%... The
quick patch shouldn't be free... [the hammer] should be found in the janitor's closet and it
should be used for the quick patch."*

- [x] A CRITICAL fault RAMPS: `speed_decay` climbs at `speed_decay_per_day` toward
      `speed_penalty`, which is now the ceiling rather than an instant charge.
- [x] Per DAY, so the pod's time scale carries into it — sleeping through a failing drive is the
      worst play, not the cheapest. (Distance would be self-limiting; real seconds would make
      stasis free.)
- [x] A patch FREEZES the loss and keeps it. Only a fitted spare clears it. A failed patch
      resumes the ramp from where it stood.
- [x] DEGRADING faults unchanged — a flat toll, cleared by either route.
- [x] **The hammer** (`scenes/props/hammer.tscn`, `CD_Hammer_v1`) is now required to patch, via
      `RepairPoint.tool_group`. Not consumed: one tool, whole ship. Empty hands get a prompt
      naming what is missing, which is the only place the game mentions the hammer at all.
- [x] **Janitor's closet**: 3x4m room off the corridor's starboard side (x 2..5, z -11..-7),
      1.0m doorway. On the corridor, so you pass it on every walk to the engine room.
- [x] HUD re-texts a bleeding fault's line every frame ("-12% drive, falling to -45%") and shows
      what a patch locked in ("-12% drive for good").
- [x] Re-balanced and re-simulated: patch-only now scrapes in on 10s of air (was comfortable),
      proper wins by 62s and 92s of air, ignoring still suffocates.
- [x] Tested: `smoke_drive_decay.gd` (new), plus `smoke_interaction`, `smoke_run_state`,
      `smoke_navigation`, `capture_closet.gd`. Seven mutations killed.
- [ ] Dressing: the closet is a bare box. `CD_Locker_v1` would sell it as a store cupboard.

## 13. Polish / remaining

### Audio

**Music — three tracks, real files.** Not synthesisable; these need composing or sourcing.

- [ ] `normal` — walking the ship, nothing wrong
- [ ] `panic` — a CRITICAL fault is active
- [ ] `stasis` — in the pod
- [ ] Crossfade between them, do not cut. State comes straight off signals that already
      exist: `RunState.stasis_changed` and `Malfunction.is_critical()` via `systems_changed`.
      2025's `AudioController.gd` is only a `play_music()`/`stop_music()` pair on a single
      track, so the crossfading part is from scratch — two `AudioStreamPlayer`s and a tween.
- [ ] Tracks must loop seamlessly, and the loop points matter more than the composition does
- [ ] Guard the transition: a fault clearing and re-breaking quickly must not machine-gun the
      crossfade. Minimum dwell time per state.

**Voiceover — recorded.** `assets/audio/voiceover/`, fifteen ship-computer lines
([log](docs/features/voiceover-and-klaxon.md)).

- [x] `Audio.say(&"name")` — one player, one queue (max 3, drops the oldest), non-positional so
      it carries from anywhere including inside the sealed pod, on its own `Voice` bus.
- [x] Wiring is DATA: `Malfunction.vo_line` is an exported StringName, so a system's voice is one
      field in `game.tscn`. Five faults wired, plus `intro` on the opening wake and `oxygen_low`
      on the air threshold (latched — `oxygen_changed` fires every frame).
- [x] The recorded `sfx/Klaxon.mp3` replaces the generated klaxon by name; `SoundForge.klaxon()`
      stays as the fallback and keeps its own assertions.
- [ ] Duck the music while the computer speaks. The `Voice` bus is at +3 dB as a starting point;
      not judged by ear yet.
- [ ] Eight lines recorded but unwired: `alarm_broken`, `pipes_life_support`, `asteroids`,
      `ate_food`, `garage_open`, `no_beer`, `shitters_full`, `thingamajig`.

**Sound effects — synthesised, already built.** `scripts/audio/sound_forge.gd` generates
these as `AudioStreamWAV`s at load: no files, no licences, nothing in the web build. Dump
them to disk with `tests/forge_sounds.gd` to listen.

- [x] `hull_bump(force)` — transient + pitch-swept sub + filtered-noise tail. 74% of its
      energy is under 200Hz and it decays to 11% by the second half. `force` scales it, so
      the same generator gives a distant knock and the one that costs you your grip.
- [x] `klaxon()` — two-tone 466/349Hz with harmonics, loops seamlessly (seam discontinuity
      0.0003). Fires on a CRITICAL fault.
- [x] `ratchet()` vs `tape_tear()` — **the two repair routes must never sound alike.** The
      ratchet is 6 mechanical teeth at 52ms, 63% above 2kHz; the tear is a 98.7% hiss. Doing
      the job properly should sound like competence and a patch should sound like getting
      away with something.
- [x] `click()`, `plug_in()` — a press and a plug seating (the latter has a low thunk under
      it so it sounds like it went *into* something)
- [x] `breath()` — for the low-oxygen loop, played faster as the air runs down
- [x] Wired: klaxon + bump on `RunState.alarm`, ratchet/tear on `Malfunction.repaired` keyed
      on `permanent`, click on pickup/drop/START/menu buttons, plug on entering the pod,
      breath under `oxygen_warning` (and silenced in the pod)
- [x] Bus layout: Master → Music / SFX, with `Audio.set_bus_volume()` ready for the slider
- [x] `AudioController` autoload: two crossfading music players, an 8-voice SFX pool,
      `PROCESS_MODE_ALWAYS` so a pause menu's own click is audible
- [x] Test — `tests/smoke_audio.gd`, 44 checks. Drives the real `RunState` and watches what
      the controller was asked to do, because a signal wired to the wrong name fails silently
      and sounds exactly like a game with no audio.

- [x] **Positional audio.** An 8-voice `AudioStreamPlayer3D` pool with inverse falloff and a
      26m range, so a door in the engine room is inaudible from the cryo bay. Doors, repairs,
      pickups, drops and the pod all play *where they happen*.
- [x] The klaxon and the hull bump deliberately stay **non-positional** — they are the whole
      ship, and placing them would make the alarm quieter depending on which way the player
      was facing. There is a test for that, because it is an easy thing to "fix" wrongly.
- [x] **Door sounds** from GMTK 2025's `Sounds/` folder, where they were sitting unused —
      nothing in that project ever played them. 0.81s each, 34 KB the pair.
- [x] **The cryo pod has its own door sound**, synthesised rather than borrowed: it is a
      curved panel driven round a cylinder and sealed, not a door sliding in a frame, and it
      is the one you hear from the inside. Servo + pneumatics + latch, with the hiss and the
      latch swapping ends by direction — opening releases and unlatches at the start,
      closing seals home at the end. `StasisPod.door_moved` carries it, so the pod still
      knows nothing about audio, and the instant set-up call that poses all five pods at
      startup deliberately stays silent.

- [x] **The klaxon is state-driven, not event-driven.** It has its own player and is on
      exactly while a critical fault is unrepaired — so repairing it, pausing, entering the
      pod, ending the run and leaving the scene all silence it without knowing it exists.
- [x] `Audio.set_paused()` on the pause menu, `Audio.stop_all()` on `Game._exit_tree()`.
      **Pausing the SceneTree does NOT pause audio in Godot** — streams carry on regardless.

#### Audio follow-ups

- [ ] A looping klaxon runs for as long as the fault does, which may prove maddening over a
      long walk to the engine room. If so it is a volume or duration tweak, not a redesign.
- [ ] Godot silently refuses to store `stream_paused` on a player with **no stream**, so the
      music's pause behaviour is untestable until the tracks exist. Verified directly; the
      music goes through the same `set_paused()` loop and will pause once there is a stream.
- [ ] **A GDScript parse error makes a test exit 0**, i.e. a broken test reports success.
      The regression sweep now greps for `Parse Error` and a summary line as well as the
      exit code. Worth folding into a single runner script.
- [x] **`tests/smoke_scene_deps.gd`** walks every `.tscn`/`.tres` and asserts each
      `ext_resource` path resolves, and that any UID agrees with its path. This is the guard
      for the asset-move breakage that hit the cryo pod twice — a stale path or a reassigned
      UID that git merges cleanly and Godot papers over at load time. Mutation-tested against
      both real failures.

- [x] **Music tracks — done.** FOUR states now: `lost_in_space` (normal), `red_alert`
      (critical fault), `klaatu_barada_nikto` (stasis), and `crash_landing` (low oxygen — a
      new state that outranks even a critical fault, since the air timer is the death clock).
      Delivered as `.wav` (115 MB total) but **transcoded to Ogg Vorbis** (~7 MB) — WAV that
      big would sink the web export, and Vorbis loops with one flag. The `.wav` masters are
      still in `assets/audio/`; **safe to `git rm` if nobody needs them as editing masters.**
- [ ] The vent pipe's hiss should be a positional loop — the one sound you ought to hear
      before you can see it. Needs a looping 3D voice rather than the one-shot pool.
- [ ] Nothing plays on arrival or on suffocation — both end screens are silent
- [ ] More of 2025's `Sounds/` is reusable: `error sound`, `machine_final`, `printer sound`,
      `elevator ding`, `coin in slot`. Its four music tracks could stand in for normal/panic
      /stasis until the real ones exist.
- [ ] Options menu: master volume slider, plus the **Options button** on the main menu that opens
      it (deliberately deferred from step 2 — no button until there's something behind it)
- [x] **Flow reworked: menu → intro video → game.** The main menu is now the entry point (bare
      black screen, title, Start + Quit), Start plays `Perpetual Pickle Intro.mp4`, and the game
      fades in when it ends. The old 10 → 01 countdown intro is gone.
      - The `.mp4` cannot be used directly — Godot 4 only plays Ogg Theora — so it was converted
        to `assets/video/perpetual_pickle_intro.ogv` (1.15 MB, with audio) via ffmpeg.
      - The source `Perpetual Pickle Intro.mp4` (a collaborator's file) is left in the repo but is
        now dead weight; safe to `git rm` if nobody needs it as an editing master.
- [ ] Re-run the web export from step 7 with the finished game before submitting — **and confirm
      video playback works in the web export.** VideoStreamTheora on the Web/Compatibility target
      is the one part of this flow the headless tests cannot vouch for.

## 14. Ship feel & new systems

Four additions, ordered cheapest first. The first two are pure feel and share one trigger;
the last two are real mechanics and should only start once step 13's audio is in, because a
lurching ship with no sound is worse than a still one.

### 14a. Screen shake on a critical fault

- [ ] Trauma-based shake: an event adds trauma (0–1), it decays every frame, and the offset
      applied is `trauma²` (or cubed) so small values stay subtle and only a real hit throws
      the camera about
- [ ] Trigger from `RunState.alarm`, weighted by `Malfunction.severity` — a CRITICAL fault
      shakes hard, a DEGRADING one barely registers
- [ ] **Apply it in `CameraController._process()` as an offset added AFTER the two-clock
      transform is computed** — never by moving the player body. The body drives movement
      wishdir and the physics-side hold point, so shaking it would shove the player and
      whatever they are carrying.
- [ ] Positional *and* rotational, but keep the roll small; rolling a first-person camera
      more than a couple of degrees reads as nausea rather than impact
- [ ] Must not fire while `NavPhase.READING` or `PodPhase.IN` — the camera is being driven
      by a tween in both, and shake would fight it
- [ ] Test: trauma decays to zero within its stated duration; the camera returns exactly to
      its unshaken transform (a shake that leaves a permanent offset is a real risk here)

> **Note:** GMTK 2025 does **not** have a screen shake — I grepped the whole project for
> `shake` / `trauma` / camera noise and it has none. This is from scratch, but it is only
> ~30 lines.

### 14b. Hull bump

- [ ] Everything loose gets a small upward impulse at once, like the ship struck something
- [ ] `apply_central_impulse()` over the `interactables` and `spare_parts` groups, with a
      little random lateral scatter so it does not look like a single scripted jolt
- [ ] **A hard bump knocks the carried item out of the player's hands.** Threshold on the
      bump's magnitude, so a light knock rattles the room and a real impact costs you your
      grip — losing a spare mid-corridor and having to chase it is exactly the right kind of
      *Martian* indignity.
- [ ] That has to be an explicit `Carry.drop()` call, not an impulse: `Carry` authors the held
      item's position every frame, so an impulse applied to it is simply overwritten. Drop
      first, THEN impulse, or the item will not move at all.
- [ ] Give the player a matching vertical nudge, or the room bounces and they do not
- [ ] Pairs with 14a and with the same alarm event; needs a sound more than it needs anything
      else (step 13)
- [ ] Test: every loose body has upward velocity on the frame after a bump, and none of them
      end up inside geometry a second later

### 14c. Zero gravity

A fault where gravity fails. Fits the malfunction system as-is: severity CRITICAL, a speed
penalty, and a repair panel that switches it back on.

- [ ] Gravity off for **items only** — the player has magnetic boots and keeps walking
      normally. That keeps the failure readable without making movement miserable.
- [ ] The one thing the player loses is **jumping**. `Player.gd` already gates on
      `is_on_floor()`; this is a flag it checks before applying the jump impulse.
- [ ] Items: `gravity_scale = 0` across the loose bodies, plus a gentle drift and enough
      linear damping that the room does not turn into a blender
- [ ] Items drifting out of reach is **fine and intended** — no drift clamp. Restoring gravity
      drops everything back, so a floating spare is a delay, not a loss, and "I cannot reach
      that until I fix the gravity" is a better puzzle than anything a clamp would give.
- [ ] What makes that safe is worth stating, because it is the thing that must not regress:
      **the gravity fault can always be cleared empty-handed.** `RepairPoint`'s patch route
      needs no spare, so a player whose only spare is floating past the ceiling can still
      switch gravity back on. Give this fault a wall panel like the others and never make it
      require a carried part, or a stranded spare becomes an unwinnable run.
- [ ] Carrying still works — `Carry` authors position directly and never asked for gravity
- [ ] Ties into the theme nicely: floating is also how you *notice* the fault, before the HUD
      tells you
- [ ] Test: with the fault active, loose bodies do not fall over several seconds and the jump
      input does nothing; repairing it restores both

### 14d. Cables, sockets and a portable battery

The biggest of the four by a wide margin — treat it as its own step, not a polish item.

**Port from Doortal (`/Users/joony/Games/doortal`):**

| File | Size | Notes |
|------|------|-------|
| `addons/cables/scripts/cable_3d.gd` | **87 KB** | Verlet rope with tension, breakaway, overstretch. The prize, and the problem. |
| `addons/cables/scripts/cable_socket.gd` | 4.9 KB | Nearly usable as-is |
| `addons/cables/scripts/cable_portal_link.gd` | 8 KB | **Not needed** — delete |
| `scripts/CablePlug.gd` | — | Extends Doortal's `PickableObject`; must be rebased |
| `scripts/PortalPowerAdapter.gd` | — | Not needed, but it is the reference for how a socket powers a thing |

- [x] **Strip the portal handling.** Done (Phase 1) — `cable_3d.gd` rewritten portal-free,
      1868→1280 lines: `side[]` collapsed to identity, `CablePortalLink`/`_link`/`_portals`
      layer and the two-real-room renderer removed, single tube. Verified by
      `tests/smoke_cable_sim.gd` (settle, overstretch, power). See
      [docs/features/cables-and-battery.md](docs/features/cables-and-battery.md).
- [x] **Rebase `CablePlug`** off `PickableObject` onto our `Interactable` + `Carry`. Phase 3:
      `scripts/game/cable_plug.gd` — held-state from Carry's `on_pickup`/`on_drop`, seat-on-drop,
      re-grab-to-unseat, `force_unseat` for breakaway. Verified end-to-end through the real input
      path by `tests/smoke_cable_plug.gd` (24 checks); no regression on `smoke_interaction.gd`.
      (Watch the `self as RigidBody3D` cross-branch cast trap — see docs/debugging-gotchas.md.)
- [x] `CableSocket` already has what is needed: `is_power_source`, `powered`,
      `plugged` / `unplugged` / `power_changed`, `snap_radius`, `seat()` / `unseat()` — Phase 2:
      copied unchanged, full API verified by `tests/smoke_cable_socket.gd` (25 checks). Seating
      confirmed to stay on the **proximity-release** model.
- [x] Wall sockets placed by `RoomBuilder`, or hand-placed like the repair panels — Phase 4:
      `scenes/props/power_cable.tscn` hand-placed on the engine-room forward wall, socket flush,
      `CD_Plug_v1.blend` plug model, breakaway lowered to 1.2× (screenshot-verified).
- [x] Some cables start permanently plugged in at one end — one plug seated and non-removable,
      so the player only ever handles the free end. Phase 4: `CablePlug.fixed` +
      `fixed_socket_path`; unbreakable + non-grabbable. Verified by `tests/smoke_cable_placement.gd`.
- [x] **Battery cube** (new, not in Doortal): charges while plugged into a live wall socket,
      discharges while powering something. Carryable, so it reaches things no cable can. Phase 5:
      `scripts/game/battery_cube.gd` + `scenes/props/battery_cube.tscn`; flow read off the cable
      graph (far end source → charge, sink → drain). Needed `CableSocket.set_source` +
      `Cable3D.refresh_power`. Verified by `tests/smoke_cable_battery.gd`.
- [x] Charge indicator: a row of small emissive bars on the cube. Same trick as
      `RepairPoint`'s status light — a **per-instance** `StandardMaterial3D` per bar. Phase 5:
      built at runtime on the top face; lit count = round(charge_fraction × bars). Screenshot-verified.
- [x] **Make it earn its place in the countdown design.** Phase 6: the `AUX POWER` device
      (`scenes/props/powered_device.tscn`) — a power-ONLY malfunction with no patch panel, ~11 m
      from the outlet, fixed only by feeding its inlet. `scripts/game/socket_power_repair.gd`
      bridges inlet power → permanent repair (+ red/green status light). Pre-Phase-6 also added
      `WallSocket` (look+E wall sockets, source/sink) and a loose two-ended cable. The full loop
      (charge battery at the outlet → carry → cable into the device → light goes green) is assembled.
- [x] Test: a cable plugged source-to-sink powers the sink and unplugging kills it; the battery
      gains charge on a live socket, loses it under load, and reads empty at zero — covered by
      `smoke_cable_battery.gd`, `smoke_wall_socket.gd`, `smoke_powered_device.gd`.

## 15. Ship surfaces — procedural sci-fi panelling

Playtest: *"the walls/floor/ceiling look flat — can they look like a spaceship?"*

Right now every interior surface is one `BoxMesh` wearing a `StandardMaterial3D` with nothing but
an albedo colour and `roughness = 0.95` (`RoomBuilder._material()`,
`scripts/level/room_builder.gd:453`). Under the shadowless omni grid (step 9's flat lighting) a
flat colour has **no** internal detail and no shading gradient, so a 21m wall reads as a grey
plane. The fix is a material, not geometry: the boxes stay exactly as they are.

**Droppable.** This is dressing. `use_paneling = false` restores today's look in one flag, and
nothing else in the game reads these materials.

### What the reference images settle

Nine references reviewed (2026-07-25): seven photographs of real data-centre interiors, plus two
stock CG renders and one clean-sci-fi corridor render. The images themselves are not in the repo, so
the conclusions are recorded here rather than by reference.

**The headline is not a texture.** Every reference inverts our value structure: a near-white shell
(walls *and* ceiling), a light or mid-grey deck, and the only dark mass in the room is *equipment* —
racks, cabinets, cable bundles. Ours is the opposite: mid-grey walls at 0.42–0.50 over darker floors
at 0.22–0.28 (`ship_layout.gd`). That is a large part of why the interiors read as a grey box rather
than a room full of machinery, and it also fixes the readability risk noted below — repair panels,
cables, pods and the battery become dark objects against a bright shell instead of mid-grey on
mid-grey.

- [ ] **Do this first, before any shader work.** Raise wall and ceiling base colours toward
      0.72–0.82, keep the deck mid-grey, and reserve dark values for props. It is four numbers in
      `ship_layout.gd` and it answers the question "how much of *flat* was actually a value problem?"
      for free. Capture the baseline shots, change the four values, capture again.

What the references contradict in the plan below — amend as noted, don't build both:

- [ ] **Walls carry almost no small detail.** Large flat panels (~1.2m wide, full height), one
      horizontal joint around 2m, a plain skirting band at the bottom, thin dark seams, and nothing
      else. No rivets anywhere on a wall in any photograph. Rivets move to the engine room only.
- [ ] **Seams are shadow lines, not bevels** — 5–10mm, low contrast, no bright lip. The lit-lip
      treatment belongs to the *other* look in the set (the sci-fi render: wide chamfers, inset
      panels, coffered ceiling). **Pick one and commit**; blending flat-panel seams with chamfered
      insets reads as neither.
- [ ] **The panel grid is calmer than specced.** Fewer, larger cells; drop the sub-divided-panel
      variation, or keep it rare enough to read as an access hatch rather than as pattern.
- [ ] **Room identity comes from equipment and accent colour, not wall hue** — every reference is the
      same white shell, differentiated by what is bolted to it. Reconsider the per-room wall palette
      (a decision, not a given: the current palette is deliberate and does aid navigation).

What to take wholesale:

- [ ] **The floor is the cheapest win in the whole feature.** 600mm tiles, fine grout line, subtle
      speckle in the tile face — visible in most of the photographs and near-free given the noise the
      shader needs anyway.
- [ ] **Soft darkening where wall meets floor and meets ceiling.** Present in every photograph, and
      the single strongest "real room" cue that shadowless lighting throws away. The builder knows
      each room's `Rect2i` and height, so pass the room bounds as uniforms and fake the junction
      gradient directly — no SSAO, no shadows, no cost.
- [ ] **Safety yellow / orange, on services and hazards only, never on architecture.** The most
      characterful element in the set and the cheapest to adopt, because the game is already full of
      the right objects: cables, wall sockets, the battery cube, the AUX POWER device, the vent pipe.

Out of reach, so nobody chases it:

- [ ] The two stock CG renders get most of their look from **mirror-gloss floors reflecting the
      racks**. GL Compatibility has no SSR and no reflection probes — not available, at any effort.

**The tone caveat, which matters more than any of the above.** These are spotless, functioning,
well-maintained rooms. This game is *The Martian*: a failing ship, improvised fixes, a janitor's
closet with a hammer lying on the floor. Take the brightness and the panel discipline; do **not**
take the cleanliness. Bright shell for readability, with wear and grime concentrated at floor level,
in the corners, and around the repair panels — where the story is.

### Approach: one procedural shader, world-space projected

`assets/shaders/ship_surface.gdshader`, shared by every wall, floor and ceiling; per-surface
`ShaderMaterial` instances differing only in uniforms (one compiled program, which matters under
Compatibility).

Why procedural rather than texture assets:

- **The boxes are arbitrary sizes.** `BoxMesh` UVs are 0..1 per face, so one tiled texture would
  stretch differently in the 21x21 cryo bay, the 3m corridor and the 3x4m closet. Projecting from
  **world position** instead makes panel scale identical everywhere *and* makes seams line up
  across adjacent surfaces — a wall's panel grid continues onto the floor.
- **Nothing in the web build.** Same reasoning as `SoundForge` for audio and `starfield.gdshader`
  for the sky: no files, no licences, no megabytes on top of the 38 MB wasm.
- **Per-room identity survives.** `Room.floor_color` / `wall_color` / `ceiling_color` feed a
  `base_color` uniform, so the existing room-by-room palette (`ship_layout.gd`) still does its job
  — the panelling sits on top of it rather than replacing it.

### Continuity across split wall pieces — the load-bearing requirement

A wall with an opening in it is **not one box**. `wall_segments()` splits the wall line at the
opening bounds and `_create_wall_piece()` emits each piece separately, so a window is surrounded by
four independent `StaticBody3D`s — the full-height piece to its left, the sill below, the lintel
above, the full-height piece to its right (`room_builder.gd:336-344`). The ship has seven openings,
so this is the normal case, not an edge case. If the material doesn't agree across those pieces the
wall reads as patchwork and the whole feature is worse than the flat colour it replaced.

World-space projection is what makes this work, *provided* nothing ever shifts the grid phase per
node. Concretely:

- [ ] **Grid phase comes from the world origin and nothing else** — `floor(world_coords / cell)`.
      No per-node UV, no per-piece offset, no `MODEL_MATRIX` in the panel maths. Two pieces of the
      same wall then sample the same cells and the seam between them is invisible.
- [ ] **`seed` feeds the per-cell hash only, never the phase**, and is **per room**, not per node —
      four pieces of one wall must share it, or one wall grows four different panel patterns. (The
      cell id is already world-anchored, so hashing `cell_id + seed` is safe; adding `seed` to the
      coordinates is not.)
- [ ] **Rows anchor to the deck (`y = 0`)**, so the sill piece, the lintel and the pieces either
      side line up vertically, and rooms of different heights (2.4 / 2.6 / 4.0 / 9.3m) still agree
      at eye level. The top row gets clipped by the ceiling — that is what a real bulkhead looks
      like, leave it.
- [ ] **`panel_size` is per role, fixed ship-wide** — never per room. Two adjacent rooms each build
      their own half-thickness skin, so differing cell sizes would misalign at every doorway you
      can see through.
- [ ] **Pick the cell size from the dimensions the layout already uses.** Openings are 1.0 / 1.8 /
      3.0 / 4.0 / 5.0 / 9.0m wide at positions like x = 0.5, 2, ±10, 11 (`ship_layout.gd`). A 1.0m
      cell (with a 0.5m sub-grid) puts most opening edges **on** a seam, which reads as deliberate
      framing; 1.2m puts almost none of them there. Costs nothing but choosing the number.

**The reveals are the part projection cannot fix.** Each wall piece is a full box, so the faces
looking *into* the opening — the two vertical jambs, the underside of the lintel, the top of a
window sill — face along the wall line, not out of it. Triplanar axis selection projects those onto
a different plane, and they are only `wall_thickness * 0.5` = 7.5cm deep, so each gets a random
7.5cm slice of a 1m panel grid. You stand and look straight at them every time you walk through a
door.

- [ ] Pass the piece's **outward axis** as a uniform (the builder already knows: `_create_wall_piece`
      computes `runs_along_x` and receives `inward`). Any face whose normal isn't on that axis is a
      reveal, and gets flat trim colour with no grid, no rivets. This is the only way the shader can
      tell a jamb from a wall — normal direction alone can't, since a floor and a lintel underside
      both point along Y.
- [ ] **Frame every opening with trim geometry.** Even with perfect continuity the grid is *cut* at
      an arbitrary place — half a rivet at the jamb, a seam 3cm from the door edge. `RoomBuilder`
      already knows every opening's bounds, so emit thin jamb / lintel / sill trim boxes in a flat
      trim material (~4 boxes per opening, 7 openings). This hides the cut, gives the openings a
      fitted look, and covers the junction where two rooms' differently-coloured skins meet inside
      a shared doorway.
- [ ] Rejected alternative: pass the openings to the shader as a uniform array and draw the border
      per fragment. Compatibility can do it, but it costs a per-fragment loop over every opening on
      the ship for a result no better than four trim boxes.

**Anything that moves must project from model space, not world space.** `SlidingDoor` tweens each
panel's `position` (`sliding_door.gd:353`), so a world-projected pattern would swim across the door
as it opens — the single most obvious way this could look broken. Doors are a follow-up below, but
whoever picks them up needs this written down.

### The two constraints that shape the shader

1. **GL Compatibility, no reflections.** There is no reflection probe or sky, so metallic /
   low-roughness surfaces fall back to hard specular off the omnis — the exact bug already
   recorded for the doors (`room_builder.gd:52-57`, bright streaks sliding across the panels).
   So: **detail lives in albedo**, plus faked AO and a lit lip. Do not reach for metallic.
2. **Shadowless lighting.** The lighting supplies no depth cues at all, so the shader has to
   supply its own — a seam has to be *drawn* dark with a bright edge, not lit dark.

### Shader features, cheapest first

- [ ] **Axis-projected coordinates.** Pick the projection plane from the world normal (triplanar
      selection, no blend needed — the boxes are axis-aligned), giving 2D coordinates in metres.
- [ ] **Panel grid.** A thin, low-contrast recessed shadow line with a soft gradient either side —
      **not** a bevel with a bright lip, per the reference review above. Large calm cells.
- [ ] **Junction darkening from room bounds.** Pass the room's rect and height as uniforms and darken
      toward the wall/floor and wall/ceiling joins. This is the reference feature with the best
      ratio of "reads as a real room" to cost, and it is the one thing the flat lighting cannot
      supply for itself.
- [ ] **Per-panel hash variation.** Slight brightness/tint jitter per cell, plus occasional
      darker "different alloy" panels. Sub-divided panels only if rare enough to read as an access
      hatch rather than as pattern.
- [ ] **Rivets — engine room only.** No reference photograph has them on a wall. Keep them for the
      one room that is supposed to look like machinery.
- [ ] **Grunge.** 2–3 octave value noise into albedo and roughness. Lift `hash13` / `value_noise`
      / `fbm` out of `starfield.gdshader` into `assets/shaders/noise.gdshaderinc` and `#include`
      it from both, rather than copy-pasting them.
- [ ] **Role variants** (`surface_role` uniform: wall / floor / ceiling), because the same grid on
      all three is what would make it read as wallpaper:
      - floor — **600mm tiles with a fine grout line and speckle in the tile face**, straight off
        the references; the cheapest convincing surface in the feature
      - ceiling — a tile grid to match, since the references' lights sit flush *in* one (see the
        ceiling-services item below, which is the real fix)
      - wall — large panels ~1.2m wide and full height, one horizontal joint at ~2m, a plain
        skirting band at the bottom. Calm; the interest is meant to be the equipment.
- [ ] **`seed` uniform per room**, so the engine room's hash pattern isn't the cryo bay's — hash
      input only, never a coordinate offset, and shared by every piece of that room (see the
      continuity requirement above).
- [ ] **Trim treatment for reveal faces**, selected by the piece's outward-axis uniform.
- [ ] **Distance LOD** — fade rivets and fine grunge out past ~12m and skip their maths. See the
      perf risk below; this is the mitigation, so build it in rather than bolting it on.
- [ ] Anti-alias the seams by widening the smoothstep with camera distance
      (`length(world_position - CAMERA_POSITION_WORLD)`) rather than `fwidth` — derivative-free,
      predictable, and it doubles as the LOD input.

### Builder integration

- [ ] `RoomBuilder._material(key, color)` → `_material(key, color, role)`, returning a
      `ShaderMaterial` when panelling is on
- [ ] New exports: `use_paneling: bool = true`, `panel_size`, `seam_width`, `detail_strength`
- [ ] Doors keep their `StandardMaterial3D` — the chamfer seam is drawn with vertex colour
      (`room_builder.gd:208`) and that trick would have to be ported into the shader. A separate
      follow-up, not part of this.

### Known breakage to fix in the same change

- [ ] **`tests/smoke_room_builder.gd:123` casts `material_override` to `StandardMaterial3D`** and
      compares `albedo_color` to prove each room's walls wear their own colour. A `ShaderMaterial`
      makes that cast `null`. Add a static `RoomBuilder.surface_base_color(mesh) -> Color` that
      reads `albedo_color` *or* `get_shader_parameter("base_color")`, and switch the test to it —
      the assertion is still worth keeping, it just needs a material-agnostic reader.
- [ ] `smoke_lighting.gd:108` reads the light-panel material, which stays `StandardMaterial3D` —
      unaffected, but check it, because it is the same shape of cast.
- [ ] `LightingController` only touches lights and emissive panels, so ALERT still works. Confirm
      by eye that red light on panelled grey doesn't turn to mud.

### Risks

- **Fill-rate on the web build.** Unlike the nebula (whose unprofiled cost is already flagged in
  step 11), interior surfaces cover the whole screen every frame of the game. ~6 noise evaluations
  per pixel is the thing most likely to hurt the itch.io build. Budget for measuring it, and the
  distance LOD above is the first knob.
- **Panel scale in small rooms.** A 2m grid in a 3m-wide corridor and a 3x4m closet will look
  wrong before it looks right. Cell sizes are per *role*, not per room — resist per-room tuning,
  or the seams stop lining up between adjacent rooms, which is the whole point of world-space.
- **The openings are where this feature visibly succeeds or fails.** Seven of them, all at eye
  level, all made of four separate boxes. Judge the result standing in a doorway and standing at
  the 9m aft window, not looking at a blank wall.
- **Over-detailing.** The repair panels, status lights and cables have to stay readable against
  the walls. If the panelling competes with them it has gone too far; grunge strength down, not
  props up.

### Verification

- [ ] `tests/capture_surfaces.gd` (new dev utility, run **without** `--headless`): six shots —
      cryo-bay wall from mid-room, bay floor looking down, bay ceiling with the fixtures in frame,
      down the corridor (all three surfaces close to), an engine-room corner, and the closet.
      Capture **before** the change as a baseline, then after, and actually look at both.
- [ ] **Plus four alignment shots, which are the ones that matter**: square-on to the 9m aft window
      (sill, lintel and both flanking pieces in one frame), square-on to the corridor doorway,
      *inside* a doorway looking at the jamb and lintel underside, and a door caught mid-slide
      (proves the panel isn't swimming). A mismatch across split pieces is invisible in a
      blank-wall shot and obvious in these.
- [ ] **Headless check of the continuity rule, not the pixels.** For every piece in a room's wall
      group, assert the grid-defining uniforms are byte-identical (`panel_size`, `seed`, anchor) —
      that is the invariant, and it can go red without anyone having to look at a PNG. Mutation
      test it by seeding per node instead of per room.
- [ ] **Assert openings land on the grid**: every opening edge in `ship_layout.gd` within a few cm
      of a panel seam for the chosen cell size. Cheap, and it goes red the moment someone adds a
      window at an off-grid position — which is exactly when the framing would silently degrade.
- [ ] Extend `smoke_room_builder.gd`: the shader resource loads (a compile error is otherwise
      silent at runtime — `smoke_space_windows.gd` has the pattern), and every node in the wall /
      floor / ceiling groups carries its own room's base colour via the new reader.
- [ ] Mutation test: give two rooms identical colours and confirm the per-room check goes red.
- [ ] Measure FPS in the cryo bay before and after (the debug readout is already there), and
      re-check the web export — step 13's "re-run the web export" item covers the build, but this
      is the change most likely to move the frame time.
- [ ] Log it as `docs/features/ship-surfaces.md`, referenced from `docs/LOG.md`.

### 15b. Ceiling services — the biggest gap, and not a material

The reference review made this plain: **every** photograph puts its visual interest overhead, either
as a suspended tile grid with light fixtures recessed *flush into it*, or as an open service ceiling
of cable trays, ducts and conduit runs. Ours is a flat plane with 0.9 × 0.06 emissive boxes sitting
*proud* of it (`room_builder.gd:281`). No shader can fix that; it wants geometry. Separate chunk of
work from the panelling, and plausibly higher value per hour than the walls.

- [ ] **Recess the light panels** into a ceiling grid instead of hanging them below it — the single
      change most responsible for the reference ceilings looking built rather than painted.
- [ ] **Tray and conduit runs** as thin boxes along the ceiling, in safety yellow, with occasional
      drop-downs to wall level. The builder already walks each room's rect, so a run down the middle
      of the ceiling and one along each long wall is a loop, not a set of hand placements.
- [ ] This also gives the corridor something to do: the references' corridors are almost entirely
      ceiling, and ours is 2.6m high with a bare one.
- [ ] Watch the pod bay — 9.3m to the ceiling, so services up there are barely visible and are
      pure cost. Run them at a lower height, or skip that room.

### Follow-ups (out of scope here)

- [ ] Doors and hand-placed props (repair panels, the nav console box, the closet) still wear flat
      colours — once the walls have panelling, those become the flat-looking things
- [ ] **Adopt the safety-yellow/orange accent on the existing service props** — cables, wall
      sockets, battery cube, AUX POWER device, vent pipe. Cheap, characterful, and it is where the
      references get most of their personality. Keep it off the architecture.
- [ ] Emissive strip lighting along the corridor wall/floor junction, which the shader could draw
      for free but which wants a real light to match
- [ ] Hazard stripes / stencilled room numbers as a uniform, off by default — wayfinding, and it
      would pair with step 10's "local alert" follow-up

## 16. Window glass — make it read as glass

Playtest: *"can the glass in the windows be slightly visible, maybe a little sheen?"*

**There is no glass mesh today.** `_build_window()` emits a `StaticBody3D` with a `CollisionShape3D`
and nothing else (`room_builder.gd:167-182`) — the glazing exists purely so a thrown crate can't
leave the ship, and it is completely invisible. So this is additive: nothing to change, only a pane
to add. Small enough to do in an hour, and independent of step 15.

### Approach: a thin pane with a Fresnel sheen

`assets/shaders/window_glass.gdshader`, one shared `ShaderMaterial` across all six windows (the
starfield shell already sets that precedent, and `smoke_space_windows.gd` asserts sharing for it).

- [ ] `MeshInstance3D` child of the existing glass body — a `QuadMesh` sized to the opening's span
      and height, which `_build_window` already computes. `QuadMesh` faces +Z, so an `Axis.X`
      opening needs no rotation and an `Axis.Z` one rotates 90° about Y.
- [ ] `render_mode cull_disabled` so the pane reads from either side — the same reason the starfield
      material does it, and the station outside means windows do get seen from the far side.
- [ ] **Fresnel-driven visibility is the entire effect.** `pow(1.0 - abs(dot(NORMAL, VIEW)), p)`,
      from ~0.02 looking straight through to ~0.3 at a grazing angle. That is what glass actually
      does, and it is self-limiting: the view out is never obscured when you are looking *out*, only
      when you are walking past. Everything below is seasoning on top of this one term.
- [ ] **Use `abs()` on that dot product.** With `cull_disabled` the back face keeps its front-facing
      normal, so an unsigned Fresnel inverts on one side — bright head-on, invisible at a grazing
      angle, i.e. exactly wrong and only visible from one side of the ship.
- [ ] **Keep the material shaded and fairly smooth, and let the ceiling omnis do the sheen.** A real
      specular highlight that slides across the pane as the player walks is the effect being asked
      for, and it costs nothing — the light grid is already there. It also turns red in ALERT for
      free, since `LightingController` drives those fixtures.
      - This is the mirror image of the walls' constraint (`room_builder.gd:52-57`): hard specular
        off an omni looks wrong on a painted bulkhead and is exactly right on glass. Worth a comment
        in the shader saying so, or someone will "fix" it later.
- [ ] Faint dust and smudges from low-frequency noise, strongest toward the pane's edges (a border
      mask on the quad's clean 0..1 UVs), so the glass looks fitted into its frame and grubby in the
      corners rather than uniformly hazy. Reuse `noise.gdshaderinc` if step 15 has landed; otherwise
      lift the same three functions out of `starfield.gdshader`.
- [ ] A few sparse, thin scratches that catch the highlight. Cheap, and it is what stops the pane
      reading as a clean CG plane.
- [ ] Local/UV coordinates, not world position — the panes are quads with usable UVs, so none of
      step 15's world-projection machinery is needed here.

### The one thing that must not regress

The windows are the *point*: the starfield, the nebula, the station, and the destination growing
brighter as distance counts down (`destination_brightness`, step 11). A pane that milks the view
breaks the best thing in the game.

- [ ] **Start additive (`render_mode blend_add`), not alpha blend.** Additive can only ever *add*
      light, so the stars and the destination can never be dimmed, however wrong the tuning gets.
      The cost is that grime reads as pale dust rather than dark dirt — which is how dust on a lit
      pane against a black sky actually looks, so it is arguably the right choice anyway.
- [ ] If a dark tint turns out to be wanted, that means switching to alpha blend, and then the
      brightness check below stops being a formality and becomes the thing holding the feature
      honest.
- [ ] Transparent surfaces don't write depth, so the pane can't occlude anything — fine here, but it
      does mean sorting is per-object. The engine room has both a window and the coolant vapour;
      check that pair specifically, and reach for `render_priority` only if it actually breaks.

### Verification

- [ ] `tests/capture_windows.gd`: the 9m aft window **head-on** (the shot that proves the view is
      still clear), the same window at a grazing angle (the shot that proves the sheen exists at
      all), one framed so a ceiling fixture reflects in it, and one in ALERT so the red sheen is
      confirmed rather than assumed.
- [ ] **Measure the brightness, don't just look.** Sample the PNG through the pane with the sheen at
      zero and at its tuned value; the starfield's mean brightness through the glass must not drop.
      `docs/testing.md`'s rule applies — this is a number, so make it one.
- [ ] Headless, extending `smoke_space_windows.gd` (it already counts glazing per window): every
      glass body carries exactly one `MeshInstance3D`, the shader resource loads, and **all panes
      share one material instance** — a per-pane duplicate is invisible in a screenshot and is the
      same class of bug the starfield sharing assertion exists to catch.
- [ ] Mutation: push the sheen to full and confirm the head-on shot goes milky. If it doesn't, the
      shot is framed wrong and proves nothing.
- [ ] Update the `_build_window` comment: it currently says "No pane", meaning no *starfield* pane.
      Once there is glazing geometry that sentence reads as a contradiction.

### Cheaper fallback, if the shader turns into a time sink

A `StandardMaterial3D` with `transparency = ALPHA`, a very low albedo alpha and roughness ~0.1 gets
the omni highlight and a faint tint with no shader work at all — perhaps fifteen minutes. What it
cannot do is the Fresnel, so the glass is equally visible head-on as at an angle, which reads as a
dirty perspex sheet rather than glass. Acceptable as a submission-day compromise; not the target.
