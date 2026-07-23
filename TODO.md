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
- [ ] Unused models now sitting in `3D-Models/`: `CD_PipeBroken_v1` (a direct upgrade for the
      vent pipe's placeholder box-and-slab), `CD_Crate_v1.1` (replaces the yellow box pickups),
      `CD_PipeDecor_v1`. Also `Perpetual Pickle Intro.mp4` for the intro rework.
- [ ] Name the two worlds on the nav chart, and the game
- [ ] **`.tscn` Transform3D basis literals are ROW-major.** Writing one from column vectors
      gives the transpose, i.e. the opposite rotation. This buried three repair panels inside
      walls. `tests/smoke_navigation.gd` now guards it.

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

#### Audio follow-ups

- [ ] **The three music tracks.** Everything else is done and waiting; drop the `.ogg`s into
      `assets/audio/` (see the README there) and they start working with no code change.
- [ ] The vent pipe's hiss should be a positional loop — the one sound you ought to hear
      before you can see it. Needs a looping 3D voice rather than the one-shot pool.
- [ ] Nothing plays on arrival or on suffocation — both end screens are silent
- [ ] More of 2025's `Sounds/` is reusable: `error sound`, `machine_final`, `printer sound`,
      `elevator ding`, `coin in slot`. Its four music tracks could stand in for normal/panic
      /stasis until the real ones exist.
- [ ] Options menu: master volume slider, plus the **Options button** on the main menu that opens
      it (deliberately deferred from step 2 — no button until there's something behind it)
- [ ] Rework the intro into the **stasis wake-up sequence** — the existing 10 → 0 red countdown
      becomes the pod's revival cycle (klaxon, lid opening) instead of a title card
- [ ] Re-run the web export from step 7 with the finished game before submitting

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

- [ ] **Strip the portal handling.** `cable_3d.gd` is 87 KB and the portal logic is woven
      through it (`_link`, `_portals`, `carry_did_teleport`, `on_teleport`, the void guard).
      Budget real time for this; it is the single biggest port in the project and unlike the
      room builder it cannot be taken in pieces.
- [ ] **Rebase `CablePlug`** off `PickableObject` onto our `Interactable` + `Carry`. Our carry
      is Doortal's, so the physics side should line up; it is the pickup base class that differs.
- [ ] `CableSocket` already has what is needed: `is_power_source`, `powered`,
      `plugged` / `unplugged` / `power_changed`, `snap_radius`, `seat()` / `unseat()`
- [ ] Wall sockets placed by `RoomBuilder`, or hand-placed like the repair panels
- [ ] Some cables start permanently plugged in at one end — one plug seated and non-removable,
      so the player only ever handles the free end
- [ ] **Battery cube** (new, not in Doortal): charges while plugged into a live wall socket,
      discharges while powering something. Carryable, so it reaches things no cable can.
- [ ] Charge indicator: a row of small emissive bars on the cube. Same trick as
      `RepairPoint`'s status light — a **per-instance** `StandardMaterial3D` per bar, or every
      battery in the ship shows the same charge.
- [ ] **Make it earn its place in the countdown design.** A rope simulation is a lot of code
      for set dressing. The obvious fit: a repair somewhere with no wall socket in reach, so
      the choice becomes *run a cable the long way* or *charge the cube and carry it* — a
      third answer to "is this fix worth the air?", paid in walking rather than in parts.
- [ ] Test: a cable plugged source-to-sink powers the sink and unplugging kills it; the battery
      gains charge on a live socket, loses it under load, and reads empty at zero
