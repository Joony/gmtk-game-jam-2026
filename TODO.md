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
- [x] **Export + zip automated**: [tools/export_web.sh](tools/export_web.sh) imports, exports,
      verifies the artifacts (Godot exits 0 even on a failed export) and zips with `index.html`
      at the archive root, which is what itch.io wants. It also caught that the `build/web/` in
      the tree was assetless — a 131 KB `.pck` where a good one is ~20 MB — and that `build/`
      being inside the project fed old export PNGs back into the next `.pck` (now blocked by
      `build/.gdignore` + `exclude_filter`)
- [x] **Pointer lock addressed** by the START prompt (step 7a below) — capture now happens inside
      a button `pressed` handler, which is the user gesture browsers require
- [x] **Losing pointer lock mid-game is survivable** ([log](docs/features/mouse-recapture-on-web.md)):
      alt-tab / a click off the canvas / the browser's own Esc used to leave the player walking a
      draining ship with dead mouse look and no way back. A lost cursor now pauses the game with a
      hint, and the Resume *click* is the gesture that buys pointer lock back. Web-only; an
      Esc-resume the browser refuses just pauses straight back
- [x] **Pointer lock confirmed in a normal browser tab** (playtested by hand). It can only ever be
      checked that way: the automated browser pane serves the page with `visibilityState: hidden`,
      which both refuses pointer lock to *any* code (`WrongDocumentError`) **and suspends
      `requestAnimationFrame` — i.e. Godot's main loop**, so the build paints one frame and freezes.
      Serve with `.claude/launch.json` (port 8099) and open a real tab
- [x] **Missing glyphs fixed** ([log](docs/features/font-and-theme.md)): the trial font maps only
      66 codepoints and the Web target has no system fonts to cover the rest, so `:` `%` `!` `[` `]`
      `—` `·` all rendered as boxes. `FontFallback` autoload attaches the engine's built-in font;
      `allow_system_fallback=false` stops desktop from hiding the next one
- [ ] **Swap in the licensed Abolition** (`.woff`/`.woff2` — Godot 4 imports both). Retires the
      trial font's licence risk on a public build and closes most of the glyph gaps
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
- [x] **Ship redrawn from a plan image** (branch `ship-layout`,
      [log](docs/features/ship-layout.md)). Now at **`room_layout_5.png`** — v3 and v4 were
      superseded before either shipped. 4 rooms -> 8 rooms + 5 corridor rects, transcribed
      one-pixel-per-metre (alpha = hull, black = corridor, white = window, grey = door).
      Bridge, kitchen/mess, bathroom, janitor's closet, life support, cryo bay, engine room,
      cargo/docking bay
  - [x] The anchor survived three redraws: the spine corridor lands on `Rect2i(-1, -12, 3, 8)`
        every time, so the cryo bay keeps its forward wall and centreline, and its furnace,
        pods and spare parts keep their coordinates
  - [x] **The bridge is the hub.** The cryo bay has exactly ONE door, so every trip routes
        through the bridge. That makes the walks much longer than the smaller footprint
        suggests — engine 30.8 m -> 63.5 m, cargo 29.9 m -> 67.1 m from the pod
  - [x] `smoke_ship_layout.gd` checks the built ship against the DRAWING, not against
        `ship_layout.gd` — rects, overlaps, doors on shared walls, windows facing hull, full
        reachability, per-room light confinement, and no room on the exterior layer.
        Mutation-tested five ways
  - [x] Lighting fixed under GL Compatibility: per-room culling
        (`LightingController.bind_occupancy`), `max_lights_per_object` 8 -> 32, and one visual
        layer per room so shadowless omnis stop shining through walls. Floor-luminance spread
        across camera yaw: 23-44% -> 1-5%
  - [x] **Furnished** — 60 decor props across 23 models, every scale derived from a measured
        target size rather than eyeballed. Crawlers, crates, barrels and canisters in cargo;
        beds, lockers and a bedside table in cryo; counters, table and vending in the mess;
        pc and terminal on the bridge; silos scaled per room so each meets its own ceiling;
        wall-mounted pipes throughout
  - [x] **Prop scales** — hammer and battery 2x (hammer head yawed 90 degrees so it points
        fore-aft when held), plugs and sockets 1.5x. Four bugs fell out and were each traced
        to a cause: seat constants that must scale with the plug model; socket mount distance
        (~0.095 m from the wall line — past the 0.075 m face, but not coplanar with it, which
        z-fights); the battery's charge bars hardcoding the old cube size; and the plugs being
        the only carryable left on the default collision layer, which Carry's wall sweep uses
  - [ ] **Engine model** — removed from `scenes/game.tscn` pending a replacement. The wrapper
        is still there and ready: instance `scenes/props/engine.tscn` back into the `Decor`
        node and repoint its model. CD_Engine_v3 was pulled because its animation squashes and
        stretches — the exporter baked a rotation into scale keys, which glTF forces when a
        child rotates inside a non-uniformly scaled parent (`Middle` was 1.65 x 0.404 x 0.667).
        The replacement needs UNIFORM scale on the parent objects (they need not be 1). See
        `LoopingModelAnimation` for that and for why the four exported clips must not be merged
  - [x] **Editor preview** — `RoomBuilder`, `ShipLayout`, `Room`, `Doorway` and `SlidingDoor`
        are `@tool`, so the ship's floors, walls, windows, doors and ceilings build in the
        editor viewport instead of only on play. Tick `rebuild` on the Ship node after
        editing a rectangle. The generated nodes are deliberately UNOWNED so Godot never
        serialises them into game.tscn — verified byte-identical across an editor open+quit.
        SlidingDoor's proximity polling is skipped under `is_editor_hint`
  - [ ] **Rebalance oxygen for v5's walks.** Nothing has been retuned since the layout changed
        and every destination roughly doubled in distance. This blocks step 17 too — see 17d,
        which measures the same problem from the supply-run side
  - [ ] **`CD_BridgeTerminals` clips the hull.** The only decor at unscaled 1:1 (the model is
        15 x 1 x 5 units); at 5 m deep it reaches z=-22.42 against a bridge fore wall at
        z=-21, so it passes through the wall and the 13 m forward window. `v2` was pushed but
        is dimensionally identical, and the scene still points at `v1`. Needs a scale on the
        node or a shallower model
  - [ ] Cargo bay airlock — the drawing has no hull door yet
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
- [x] **45° corners on every opening** ([log](docs/features/opening-chamfers.md)) — small
      triangular prisms dropped into each opening's corners, so a window reads as a chamfered
      porthole and a doorway as a chamfered frame. Additive, so the wall-splitting maths is
      untouched. Tinted, because a 45° face under shadowless lighting is otherwise invisible —
      the same lesson `SlidingDoor.BEVEL_TINT` already learned. `opening_chamfer` (default 0.12m)
      sets the leg, clamped so the 1m bathroom portholes can't close into a diamond.
- [x] Doorways too, in a second pass. Three differences, all real: a doorway has two corners not
      four (it reaches the floor), is cut through BOTH neighbours' skins not one, and — the one
      that made doors a follow-up rather than part of the first pass — its panels slide through
      the middle of the wall, so the chamfer is confined to the outer 3cm of each skin where a
      panel can never reach it. Asserted in `smoke_door_bevel`, three more mutations killed.
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
- [x] **The view collapses before the summary** — the run no longer freezes and cuts. The
      camera goes over sideways and sinks toward the floor, the screen wipes to black, and
      only then do the numbers arrive. Roll and drop live on `CameraController`, not on the
      camera node, because its `_process` rewrites the camera's transform every frame; the
      roll goes in the euler Z slot so Godot's YXZ order applies it about the view axis.
      Both shutdowns `_on_run_ended` used to do on frame one had to move — pausing the tree
      freezes the fall, and disabling the player stops the controller performing it.
      `smoke_run_end.gd` measures the camera's WORLD BASIS, since a roll that is written
      but never read looks identical from outside. Mutation-tested

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
- [x] **Video playback confirmed in the web export** (2026-07-26): on a `tools/export_web.sh`
      build, START plays the intro, frames decode and advance, it runs to `finished` and cuts to
      `game.tscn`, which renders in-browser. VideoStreamTheora on Web/Compatibility works.
- [ ] Re-run `tools/export_web.sh` once more against the *final* build immediately before
      submitting, so the uploaded zip matches what's committed.

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

---

## 17. Needs & supply countdowns — SPEC (not yet built)

**Theme fit.** The jam theme is *Countdown* and the ship currently runs three: distance to
arrival, oxygen, and drive %. This turns survival itself into countdowns, and — more
importantly — makes solving one **start** another. That is the stated tone (*The Martian* —
"solutions that create tomorrow's problem") expressed as mechanics rather than flavour text.

### 17a. It is ONE mechanic, six times over — build it once

Every item below is the same shape: *a thing that runs down (or fills up), and a consumable you
fetch to reset it*. Build two components and configure them; do not write six systems.

**BUILT 2026-07-26 — see [docs/features/needs-and-silos.md](docs/features/needs-and-silos.md).**

- [x] `Need` (`scripts/game/need.gd`) — a countdown that runs **only while awake** (the guard
      lives with the caller, which already knows about `in_stasis`), warns at a threshold, and
      fires at zero. `active` is false by default, which is what makes the 17d staggering
      possible. `start()` is idempotent so a second beer cannot silently reset the bladder.
- [x] `Silo` (`scripts/game/silo.gd`) — a fixed container with a 0..1 level. **Supply and waste
      are the same object with one sign flipped**: `use()` drains a supply and FILLS a waste
      tank, `service(can)` does the opposite, and `headroom()` reads the same for both, so the
      HUD, the Need and the tests are written once.
- [x] `Consumable` (`scripts/game/consumable.gd`) — a carryable tagged `o2`/`beer`/`food`/
      `battery`/`empty`. Plus `becomes`, which was not in the original spec and earns its
      place: **air → empty → shit**, so one prop scene covers all four canister models and
      spending a can hands you the next problem as an object.
- [x] One `tests/smoke_needs.gd` covering the whole component set, not six near-identical
      suites — the 17a claim stated as a test. Builds its own fixtures, mutation-tested six
      ways (see the feature doc's table).

### 17b. The six systems

See **17j** — five of these already have recorded voiceover, and it names
mechanics the table below does not (the garage door, oiling the crawlers).

| # | Countdown | Where it is fixed | Consumable | Source | On zero |
|---|---|---|---|---|---|
| 1 | **CO2 → narcosis** | Life support silo | O2 canister | Cargo bay | Narcosis — the one new LETHAL |
| 2 | **Hunger** | Vending machine (mess) | Food item | Vending, restocked from food crates in cargo | Degrade: slower, then collapse |
| 3 | **Thirst** | Beer silo (mess) | Beer canister | Cargo bay | Degrade |
| 4 | **Bladder** | Toilet (bathroom) | — (an action, not an item) | Caused by 3 | Degrade + indignity |
| 5 | **Crap silo** | Toilet silo — FILLS | Empty canister to pump out | Cargo bay | Explosion |
| 6 | **Power/fuel** | Engine | Battery | Cargo bay | Drive stops |

- [ ] **Change the existing O2 SCRUBBER malfunction.** It currently applies
      `speed_penalty = 0.1` + `oxygen_drain_multiplier = 1.6` — i.e. it attacks the drive and
      the oxygen budget. Per this spec it should instead start the CO2 countdown. Keep
      `repair_oxygen_bonus`; drop the drive penalty.

### 17c. The chain is the best idea here — protect it

Drink beer → bladder fills → use the toilet → the crap silo fills → it will explode unless you
carry empty canisters from the cargo bay. **Fixing thirst is what creates the toilet problem,
and using the toilet is what creates the explosion problem.** Nothing else in the game
currently does this. If any part of this spec gets cut for time, cut around this chain, not
through it.

### 17d. THE PROBLEM TO SOLVE FIRST: six needs do not fit in the oxygen budget

Measured, not estimated:

- The cargo bay is **67.1 m** from the pod — the furthest room but one. A round trip is 134 m.
- `Carry` holds exactly **one** item (`carry.gd`, `var _held: RigidBody3D`). One trip, one can.
- At `max_speed = 7.0` that is **~19 s per trip**, ~8% of the 240 s oxygen total. Realistically
  20–25 s with acceleration and door waits.
- **Six supply runs ≈ 115 s ≈ 48% of the entire oxygen budget** — before a single repair, and
  the ship already ships a broken drive regulator at t=0.

Add six needs as specified and the run is unwinnable.

**SETTLED 2026-07-26: stagger + long fuses now, multi-carry as the stretch.** The two chosen
are the two that are pure `RunState` logic — no prop placed, no art — so they can ship under
the scene lock and they are also the two cheapest. Together they cut the six runs to one or two
per run, which fits.

- [x] **Stagger, don't stack** — only 1–2 needs are ever live in a run; which ones is
      randomised, like malfunctions already are. **Chosen.**
- [x] **Long fuses** — each need takes several wakings to become urgent, so one trip services
      it for a long time. **Chosen**, and it composes with stagger rather than competing.
- [ ] **Multi-carry** — a crate or trolley holding 3–4 canisters, so a supply run is one trip
      that services several needs. **The best answer and still worth building**, because it
      turns the cargo bay into a *planning* problem ("what do I need this trip?") instead of a
      treadmill — but it needs a carryable crate placed in the cargo bay, so it is 17i work.
      Deferred, not dropped.
- [ ] **Distribute the sources** — beer in the mess, spare O2 in life support. Folded into the
      17i placement pass; it costs nothing extra once things are being placed anyway.

### 17e. Settled 2026-07-26 — these were the open questions

- [x] **Needs do not tick in stasis.** The pod pauses the body, or a long haul kills you asleep.
      Same rule as oxygen (`stasis_oxygen_rate`). `RunState.in_stasis` exists and
      `stasis_changed` is already emitted, so this is one guard, not a system.
- [x] **Only two of them are lethal: CO2 narcosis and the crap-silo explosion.** Nine countdowns
      × "you died" is a bad ending screen. Hunger, thirst and bladder **degrade** (slower
      movement, narrowed vision, dropped items); power loss stops the drive, which the distance
      countdown already punishes on its own.
- [x] **A need's HUD row appears only once it crosses a threshold.** Oxygen + arrival + drive is
      already three readouts. The HUD grows as things get bad rather than shipping nine dials.
- [x] **The vending machine's "extra hop" does not exist — the objection was miscounted.** Every
      other need is *need → silo in a room → canister from cargo*. Hunger is *need → vending
      machine in the mess → food crate from cargo*. That is the same three steps: **the vending
      machine IS a `Silo` and the food crate IS a `Consumable`.** Nothing about hunger is
      special-cased, which is the point of 17a — and it is why hunger can safely be built last.

### 17f. Assets

- [x] Already present: `CD_Canister_Air/Beer/Shit/Empty`, `CD_Silo_Base_v1`,
      `CD_VendingMachine_v1`, `CD_Crate_v1.1`, `CD_Cake_v1`, `CD_Can_v1`, `CD_Tp_v1`
- [x] **Toilet model** — `CD_Terlet_v1` (2.00 x 2.70 x 3.00 units, no collision)
      arrived 2026-07-25, with `CD_Chair_v1` alongside it
- [ ] **New battery model with charge rings** — rings show charge level. Note `CD_Battery_v1`
      exists and `battery_cube.tscn` already derives its charge bars from its own collision box
      (`_half_extent()`), so a ring-based indicator should follow that pattern rather than
      hardcoding sizes
- [ ] A few of the new batteries placed in the cargo bay
- [ ] Small food crates in the cargo bay

### 17g. Build order

1. [x] `Silo` + `Consumable` — built and proven, 2026-07-26 (17h Phase 1)
2. [x] Decide 17d and 17e — they change the shape of everything after this (done 2026-07-26)
3. [x] `Need` + HUD rows, proven on CO2 (17h Phase 2)
4. [x] Power/fuel — done without the battery model, which is still outstanding (17h Phase 3)
5. [x] The thirst → bladder → toilet → crap chain, as one unit (17c, 17h Phase 4)
6. [x] Hunger + vending restock — done 2026-07-26. The "extra hop" was a miscount (see 17e);
       it needed no new script, no new field and no branch, which is the whole claim of 17a

### 17h. IMPLEMENTATION PLAN (2026-07-25)

**Working constraint:** `scenes/game.tscn` and `scripts/level/ship_layout.gd` are being edited
elsewhere and must not be touched. Everything below is arranged so that no step needs either
file; what genuinely does is parked in 17i.

**The constraint picks the architecture, and it picks a good one.** `RunState.start()` already
finds its systems with `get_tree().get_nodes_in_group(Malfunction.GROUP_MALFUNCTION)` rather
than through exported paths wired in the scene. Needs and silos follow that precedent: they are
declared as DATA and spawned at runtime, the same way the ship's own geometry is authored in
code rather than placed by hand. That means zero scene edits for the logic, and it stays the
right design after the lock lifts.

- [x] **Phase 0 — settle 17d/17e.** Done 2026-07-26; the answers are written into 17d and 17e
      themselves rather than duplicated here. In short: stagger + long fuses, needs pause in
      stasis, only CO2 and the crap silo are lethal, HUD rows appear on a threshold, and the
      vending machine is just another `Silo`. Every one of them is buildable under the lock.
- [x] **Phase 1 — the components.** Done 2026-07-26. All NEW files, nothing existing touched:
      `scripts/game/need.gd`, `scripts/game/silo.gd`, `scripts/game/consumable.gd`
  - [x] `tests/smoke_needs.gd` builds its own fixtures in code rather than leaning on
        `game.tscn` — the technique `smoke_cable_drag.gd` already uses with `_make_plug()`.
        That is what makes Phase 1 verifiable while the scene is locked, and it is also what
        stops the suite breaking the next time a room is furnished
  - [x] It assembles the whole 17c chain (beer → thirst → bladder → toilet → crap tank →
        empties) out of the three components **with no extra script**, which is the evidence
        that Phase 1 is enough to build the rest on
  - [x] Two GDScript traps found and written up in `docs/debugging-gotchas.md`: a lambda
        captures by VALUE (so `int` counters in a test silently never move, and a
        `count == 0` assertion passes vacuously), and an `Interactable` script cannot be cast
        onto a `RigidBody3D` at compile time
  - **Next up is Phase 2**, which needs prop scenes (`scenes/props/canister.tscn` and a silo)
        — those are NOT blocked, only their placement in `game.tscn` is
- [x] **Phase 2 — CO2 end to end, no scene edits.** Done 2026-07-26. `RunState.start()` spawns
      the CO2 `Need` from its `NEEDS` table and finds silos by group, exactly as it already
      does with faults; the HUD builds the row at runtime into the existing `%SystemList`
  - [x] `scenes/props/canister.tscn` — ONE scene that is all four canisters, because a
        canister changes kind IN THE PLAYER'S HANDS and the models therefore have to live on
        the same body. Scale 0.2004, matching the cargo bay's decorative cans
  - [x] `scripts/level/ship_supplies.gd` — `ShipSupplies`, the supply counterpart to
        `ship_layout.gd`. **Adopts** the silo (reads the decor prop's position and puts a
        functional body there, so nothing is duplicated and nothing looks different) and
        **spawns** the canisters (a decor `Node3D` cannot become a `RigidBody3D`)
  - [x] The O2 SCRUBBER's `speed_penalty`/`oxygen_drain_multiplier` are stripped at load by the
        `neutralise` dictionary in `RunState.NEEDS`, so the two effects do not both apply.
        Temporary scaffolding for the `game.tscn` edit in 17i — one dictionary to delete
  - [x] Death by CO2 says so: `Need.fatal_title` reaches the end screen through the run
        summary, so `run_end.gd` never had to learn what a need is
  - [x] `tests/smoke_supplies.gd` against the real scene, mutation-tested nine ways
  - **Two bugs it caught, both pre-existing:** `RunState.start()` cleared `finished` *after*
        spawning, so a restarted run opened with its opening need switched off; and `start()`
        re-connected `broke`/`repaired` unguarded, double-counting patch failures on a second
        call. Both fixed
- [x] **Phase 3 — power/fuel.** Done 2026-07-26. The sixth system, and the only one that runs
      down without the player doing anything
  - [x] `Silo.drain_per_day` — the one silo that empties on its own, on the **ship's** clock.
        That is the point rather than a detail: the pod was the free half of the loop, and now
        stasis burns fuel at 24x. Everything else on the ship has `drain_per_day = 0` and is
        genuinely inert (it emits nothing at all, rather than a change of zero)
  - [x] `Silo.stops_the_drive` — an empty tank is a 100% speed penalty, so it lands on the same
        `min_speed_fraction` floor every other total does. A drive frozen at exactly zero is an
        unwinnable run the player still has to sit through
  - [x] `scenes/props/power_cell.tscn` (Consumable, kind `battery`) and
        `scenes/props/silo.tscn` — a spawnable tank, for rooms with no decor silo to adopt.
        Four cells in the cargo bay, deliberately a separate errand from the air canisters
  - [x] The tank stands **off** the aft wall: every wall in the engine room is already taken by
        a repair panel needing 0.9 m of clear air, which `smoke_navigation` caught the first
        placement stealing from MAIN DRIVE
  - [x] `power_off` is now wired — the recorded line names the battery, so the computer says it
        when the tank runs dry (17j)
  - [x] HUD rows for silos in trouble, sharing the need rows: a tank running low and a body
        clock running down are the same problem to the player, which is *something needs
        fetching*. Shown as a percentage, not a clock — it is not convertible into "can I get
        there and back"
  - [x] `Silo` builds an emissive status lamp, green through amber to red
  - **Not done, and it was my claim to begin with:** driving the silo's glass level from
        `Silo.level`. See 17i — the model has no liquid mesh to drive
- [x] **Phase 4 — the chain** (17c). Done 2026-07-26, as ONE unit, because it is the part worth
      protecting: thirst -> bladder -> toilet -> septic tank -> a bad end
  - [x] Beer silo in the mess (adopts `MessSilo`), `no_beer` wired
  - [x] `scenes/props/toilet.tscn` — the head AND the septic tank as one object, which is what
        17b's single row already said. Everything the player does happens in the same place:
        relieving yourself FILLS it, an empty canister empties it. Two nodes a metre apart
        would mean two prompts for one problem. `shitters_full` wired
  - [x] `Need.starts_after_days` — the staggering (17d) as a SCHEDULE rather than a dice roll,
        matching how malfunctions already stagger off `fire_at_distance`. Thirst arrives six
        days in, so the opening of a run is about the ship rather than about your body
  - [x] Four ways a need comes into play, and between them they are the staggering: a fault
        breaking, a tank filling, a point in the voyage, or **another need being satisfied**
  - [x] `Need.movement_penalty` — the degrade route (17e). An expired need costs walking speed
        until it is dealt with, which in a game whose currency is seconds outside the pod means
        every future trip costs more air. Penalties multiply, so two of them cannot stop you dead
  - [x] The septic countdown is itself a lethal `Need`, started by the tank filling and stopped
        by pumping it down — no new machinery, and it gets `SEPTIC` on the end screen
  - [x] Beer and empty canisters in the cargo bay, deliberately fewer empties than beers
  - [x] `tests/smoke_chain.gd`, its own suite rather than a section of `smoke_supplies` —
        buried in a bigger file this is the thing that would get quietly deleted to make a
        failing suite pass. Mutation-tested six ways
- [x] **Phase 5 — hunger.** Done 2026-07-26, and the point of doing it last is that it needed
      **no new script, no new field and no branch anywhere**. If it had, 17a's "one mechanic
      six times over" would have been wrong
  - [x] The vending machine in the mess becomes a `Silo` (adopts `MessVending`), `ate_food`
        wired — the line is "You ate all the food", so it belongs to the machine running out
  - [x] `scenes/props/food_crate.tscn` — a `Consumable`, half the size of the cargo bay's
        decorative crates so a crate you can pick up reads differently from scenery
  - [x] Adoption now takes the decor prop's ROTATION as well as its position. Every tank sits
        square; the vending machine is turned to face out of its wall, and its collider and
        lamp are described in its own frame
  - [x] Longest fuse of the six and the latest arrival (11 days), so the back half of a voyage
        is where the ship's problems and the body's start landing together
  - [x] **The machine shows its stock**, 2026-07-26. Nine pigeonholes, read from the model's own
        `slot1`..`slot9` empties rather than a computed grid (the rows are not a perfect
        lattice). Starts with one cake, one can and one plant; a purchase takes a RANDOM hole;
        a food crate refills three. `VendingStock` is a view over `Silo.level`, not a second
        tally — the randomness is only in *which* hole, never in *how many*
  - [x] **The lamp is three states with no gradient**, 2026-07-26: red out of order, orange
        empty, green otherwise. The old amber "getting low" tier was the wrong shape for a lamp
        read across a room — at that distance the question is "must I bring something", which
        has a yes and a no. Urgency belongs on the HUD row, which has room for a number
  - [x] **The machine can break**, and it breaks like everything else on the ship: an ordinary
        `Malfunction` with an ordinary `RepairPoint`, so it is a spare part or a hammer bodge,
        a row in the fault list, and the same repair sounds. A bespoke "out of order" flag
        would have been less code and a worse game — a second repair idiom for one prop
    - Fires at a RANDOM point mid-voyage, unlike every other fault. A run should be a sequence
        you can learn the shape of; a vending machine packing up is comic, not structural
    - Costs no drive, so the HUD now omits the drive clause for a fault that has none —
        `(-0% drive)` reads as a broken readout rather than as a fault with no speed cost
    - A bodge holds 9 million miles against 25–33 elsewhere: cheap to patch, back soon, so the
        spare is worth spending on a machine you keep needing
    - Broken blocks `use()` but NOT `service()` — refusing the crate would throw away a trip
        already paid for in air, over a distinction invisible from the cargo bay
  - [x] Counting a silo in ninths turned three latent float bugs real, all fixed with one
        `EPSILON` in `Silo`: `is_exhausted()` never fired (so `ate_food` never played),
        `uses_left()` reported 2 while three items were on the shelf, and — worst — the last
        item could not be bought at all, because a crate's third and a purchase's ninth do not
        compose. The player would have seen an item and a prompt that refused it

### 17i. Blocked on `scenes/game.tscn` — do when the lock lifts

Each of these is a placement or a scene-wiring change. Pull first, re-run the suite, then:

- [ ] **Give the decor silos the `Silo` script directly** and delete the adoption pass in
      `ShipSupplies._adopt_silo()`. Adoption is a good workaround but it is still a workaround:
      it reads a decor node's position by name, so renaming a prop silently loses the silo
      (`smoke_supplies` is what catches that). Applies to the mess and bathroom silos too
  - Seen in the render: **only the adopted silo has collision.** `CD_Silo_Base_v1` ships with
      no collider, so `LifeSilo1` is now solid while `LifeSilo2`/`3` beside it are walk-through.
      Give the prop its own collision rather than leaving it to whoever adopts it
  - **The silo model's glass window has a liquid level painted into it, and it cannot be
      driven.** I said in Phase 2 this would be nearly free; it is not. `CD_Silo_Base_v1` has no
      separate liquid mesh (`Holder_Bottom/Top`, `Pipe_Bottom/Top`, `Plane`, `Silo_001`,
      `Siphon`, `Siphon_Pipe`) and its geometry is offset from its own origin, so a code-built
      mesh would have to be lined up by hand against art that may move. **Ask the modeller for
      a named liquid mesh** whose Y scale can be driven, and `Silo` will drive it. Until then
      `Silo` builds a small emissive lamp instead — green/amber/red — which is readable from
      across a dark room and was the thing that actually mattered
- [ ] **Link the toilet and the bathroom's decorative tank.** The toilet at (-7, 0, -5.7) IS
      the septic silo; `BathroomSilo` at (-3, 0, -6) is a tank it notionally feeds and is still
      pure scenery. Either run a pipe between them or move the tank beside the toilet — as it
      stands the room reads as two unrelated objects
- [ ] Stock the cargo bay properly: beer / empty canisters, food crates, batteries. NOTE the
      four **decorative** canisters at x 26.3–27 are now sat right beside three functional ones
      and look identical — a player will try to pick them up. Replace them with real ones or
      remove them
- [ ] Repoint the O2 SCRUBBER malfunction at the CO2 need — set its `speed_penalty` to 0 and
      `oxygen_drain_multiplier` to 1 in the scene, then delete the `neutralise` dictionary from
      `RunState.NEEDS` that is standing in for it (see Phase 2)
- [ ] Place the multi-carry crate once 17d moves off "stagger"
- [ ] Rehome the `need_oil` line from DRIVE REGULATOR to the cargo-bay crawlers (17j)
- [ ] `CD_BridgeTerminals` still clips the bridge's fore wall and window — same file, so fold
      it into the same pass

### 17j. What the recorded voiceover already tells us

`assets/audio/voiceover/` holds **15 recorded lines**; `audio_controller.gd` registers all 15,
but only 6 are wired to anything. The 9 idle ones are a content spec that predates 17 — and
three of the six systems in 17b already have their audio in the can.

**Already recorded, matches 17b — no new VO needed:**

| line | says | 17b system |
|---|---|---|
| `ate_food` | "You ate all the food. Go restock it." | 2, hunger + vending restock |
| `no_beer` | "There's no more beer left." | 3, thirst |
| `shitters_full` | "The shitter's full." | 5, crap silo |
| `life_support` | "The life support is failing. Go fix it." | 1, CO2 (wired today) |
| `power_off` | "The power's off. Go charge it up again with a battery." | 6, power — and it already names the battery |

**Recorded, and NOT in the spec.** Each is a ready-made problem with its audio done:

- [ ] **`garage_open`** — *"Someone left the goddamn garage door open. Go close it."* This is
      the cargo bay airlock, already an open item. The line turns it from set dressing into a
      hazard with a countdown, and it is the most on-theme of the lot: a door to vacuum
- [ ] **`need_oil`** — *"Them robots in the garage need some oil."* The crawlers now standing
      in the cargo bay are those robots. **It is currently mis-wired to DRIVE REGULATOR in the
      engine room**, which is neither a robot nor in the garage; rehoming it costs nothing and
      the crawlers stop being pure decoration (17i — the fault lives in `game.tscn`)
- [ ] **`pipes_life_support`** — *"One of them pipes down at life support is broken."* A second
      instance of the pipe repair that already exists in the engine room, in a room that now
      exists. Cheapest new content on this list
- [ ] **`alarm_broken`** — *"Hey, the alarm is broken. Uh... wee-woo, wee-woo."* Comedic: the
      computer has to imitate the klaxon itself. A malfunction whose only effect is that you
      stop being told about other malfunctions is a genuinely nasty little idea
- [ ] **`asteroids`** — *"Asteroids incoming. You better shoot them down fast."* A whole action
      mechanic and by far the biggest scope here; `CD_Asteroid_v1.blend` already exists. Not a
      countdown-need — park it unless there is time

**Tone note.** `CD_Intro` establishes the player as the ship's **janitor**, and "the last clone
of you we's got". Every other line is the computer nagging — "go fix it", "go restock it", "go
close it". That is exactly the register section 17 is written in, and it is why a chore list
reads as characterful here rather than as busywork: the joke is that you are the janitor and
the ship is a nag. Keep the needs' HUD copy in that voice.

---

## 18. Opening tutorial — the first fault teaches the loop

Full write-up: [docs/features/opening-tutorial.md](docs/features/opening-tutorial.md).

The run already opens on an active fault. The tutorial is that fault: find it, and the computer
tells you the two ways to fix anything. No separate tutorial mode, no text box — the first
problem IS the lesson. **Settled 2026-07-26: that fault lives on the bridge, with the hammer
beside it** (18b); the trigger and the wiring are built (18a, 18c) and only the placement is
still blocked (18d).

**The cue is arriving in the room, not the fault firing.** Told while still in the pod the
instruction is abstract and unactionable; told on a timer it fires whether the player found the
room or not. Walking in with the thing in front of you is the moment it means something.

`CD_Thingamajig` is exactly the right line for it, and it is already recorded:

> "You're gonna need a spare part to fix that thingamajig there. It should be around here
> somewhere. Or you can use that hammer to patch it temporarily. You'll figure it out."

That one line teaches both repair routes and the hammer, which is the whole of the repair
economy.

### 18a. Built — the trigger mechanism (unblocked, done 2026-07-25)

- [x] `RoomBuilder.room_at(position)` — which room a world point is in, "" for none. Reads the
      same rects the geometry was built from, so it cannot drift when the drawing is redrawn
- [x] `scripts/game/room_voice.gd` — `RoomVoice`. Data-driven `room id -> voice line`, said
      once per room per run. Emits `room_changed` for any crossing and `spoke` for an actual
      utterance. NOT an `Area3D`: the rooms are built at runtime, so there is no editor-time
      box to attach one to, and a hand-placed trigger volume would need re-syncing every redraw
  - [x] A `margin` (0.6m) so loitering in a doorway does not burn the cue — a doorway sits on
        the shared wall line, so without it the room flips every frame
  - [x] Resolves the computer by NODE PATH, not the `Audio` global: a `-s` test script loads
        its dependencies before autoloads register, so a compile-time `Audio` reference breaks
        the moment a suite does `RoomVoice.new()`
- [x] `tests/smoke_room_voice.gd` — builds its own two-room ship rather than loading
      `game.tscn`. Mutation-tested: dropping the once-only guard and zeroing the margin each
      fail it

### 18b. Settled — the first problem happens on the bridge (decided 2026-07-26)

**Decision: the run opens on a fault in the BRIDGE, with the hammer on the floor beside it.**

The bridge is the right room for it and by some distance. It is the hub — the cryo bay has
exactly one door and every trip out of the pod passes through here — so it is the one room the
player cannot fail to find, and it is ~16.5 m from the pod against the engine room's 63.5 m.
The previous opening fault was DRIVE REGULATOR, in the furthest room on the ship, reachable
only by crossing the spine and the whole bridge to get to it.

**The hammer beside it is the SAME hammer, not a second one.** Picking it up there is how you
learn the tool exists, and from then on it lives wherever you last put it down. That preserves
what the janitor's-closet placement was actually for (`hammer.tscn`: the trip is "the price of
having a patch route at all") — the cost just becomes remembering where you left it. A second
hammer would delete that cost outright.

### 18c. Built — the cue is wired and aimed (unblocked, done 2026-07-26)

- [x] `Game._wire_room_voice()` — builds a `RoomVoice` in code (a node is a `game.tscn` edit),
      binds it to `$Ship` and the player, and disables it on `run_ended`
- [x] **The room is NOT named in code.** The cue is looked up from whichever `Malfunction`
      carries `starts_broken`, via `RoomBuilder.room_at()`. That is the whole workaround for
      the scene lock: the tutorial line is already aimed at the engine room today and will
      retarget itself to the bridge the moment the fault below is moved, with no code change
      and no second thing to keep in sync. If nothing starts broken the table is empty, which
      is better than a line said in an arbitrary room
- [x] `tests/smoke_tutorial_cue.gd` — proves the AIM against the real scene (smoke_room_voice
      already proves the trigger): the cue sits on the opening fault's room whatever room that
      is, the cold open and the wake stay silent, walking in says it, and it never repeats.
      Mutation-tested: never building the `RoomVoice`, and nailing the cue to a fixed room id,
      each fail it
- [x] **Whether the fault's own alarm also speaks: it does not, and nothing had to be done.**
      `RunState.start()` calls `break_now()` BEFORE connecting `alarm`, deliberately, so the
      cold open is silent — an opening fault never announces itself. `RoomVoice` is the only
      voice on it, so there was never a second one to suppress
- **Found while testing:** a repair panel is mounted flush on a wall, so the fault's own
      position is a few centimetres inside the room and is correctly NOT "well inside" it by
      `RoomVoice.margin`. The player walks into the room and then up to the panel, so this
      never bites in play — but a test that teleports to the fault's exact position sees no cue
      and looks like a bug in the trigger. `smoke_tutorial_cue` stands in the room's centre

### 18d. Blocked on `scenes/game.tscn` — a mechanical edit list

Everything here is one file and one lock. Nothing else in 18 is waiting on anything.

- [ ] **Make NAV ARRAY the opening fault, on the bridge.** It is the natural bridge system, the
      bridge already has the terminals and the forward window for "drifting off course", and it
      is currently at (-8.83, 1.3, -2) — which is *inside the cryo bay*, on its port wall. A nav
      array in the bedroom is a placement bug regardless of the tutorial
  - Move to `Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, -6.83, 1.3, -17.5)` — the bridge's port
      wall (x = -7, +0.17 clearance, the same offset DRIVE REGULATOR uses), facing +X into the
      room, forward of the port-arm door at z = -14.5 and clear of `BridgePipeA` at z = -13
  - Set `starts_broken = true` on it
  - Set `vo_line = &"thingamajig"` on it, and **remove `starts_broken` from DRIVE REGULATOR**
- [ ] **Move the hammer beside it**, from the janitor's closet (4.5, 0.07, -9.6) to roughly
      (-6.0, 0.07, -17.5) — a metre out from the panel, on the floor, in the same lying-flat
      basis it already has: `Transform3D(1, 0, 0, 0, 0, 1, 0, -1, 0, -6.0, 0.07, -17.5)`
- [ ] **`need_oil` moves to the crawlers.** DRIVE REGULATOR currently says "Them robots in the
      garage need some oil", which per 17j belongs to the cargo-bay crawlers. Give DRIVE
      REGULATOR a line that fits a drive regulator, or none
- [ ] After the edit, re-run `smoke_tutorial_cue` — it should still pass **unchanged**, now
      reporting `bridge` rather than `engine_room`. If it needs editing to pass, the cue stopped
      following the fault and that is the regression it exists to catch

---

## 19. ✅ Ship status map — done ([log](docs/features/ship-status-map.md))

Full spec: [ship-status-map.md](docs/features/ship-status-map.md). A **London Underground diagram
of the ship** as a second page on the nav console, with **pulsating red and orange blobs in the
rooms where something needs doing**.

The HUD fault list says *what* is wrong and has never said *where*. That is the question the
player actually has to answer on waking, because every fault is priced in walking distance and
walking distance is priced in air.

### 19a. The decisions worth not relitigating

- [x] **Second page on the existing console, not a new prop or a HUD overlay.** A prop needs a
      `scenes/game.tscn` edit (locked, see 17i); an overlay would make the information free, and
      this game charges air for information — which is why the nav plot walks you to a console
      instead of opening a menu
- [x] **Colour is reserved for trouble.** The diagram is drawn in the same green ink as the nav
      plot, so the blobs are the only saturated pixels on the page and nothing competes with them
- [x] **RED = FAULT (repair it), ORANGE = WARNING (fetch something)** — the game's only two
      responses to a problem, in the colours the silo lamps and the HUD rows already use
      (`Silo.LAMP_CRIT` / `LAMP_WARN`), and the only two entries in the legend
- [x] **Patched faults are NOT on this map** (decided 2026-07-26). A patch is not somewhere you
      have to go — it is a bill that falls due later, and the HUD fault list already carries it
      with the number that matters. A third symbol dilutes a page that means "walk here now"
- [x] **Pulse RATE encodes urgency, blob SIZE does not.** 0.5–2.2 Hz, the same grammar as the HUD
      air vignette. A constant base radius stops the map lying about magnitude; the *number* of
      blobs in a room is the magnitude
- [x] **A "YOU ARE HERE" arrow points at the player's room**, in green — where you are is not a
      problem. Added 2026-07-26, reversing the spec's "the marker would be a constant": true only
      while the console is the sole place the map is readable, and it is what makes the diagram
      read as a map. `""` hides it, which is a player standing in a doorway
- [x] **The legend only explains marks that are actually on the page.** Colour key with the first
      blob, arrow when there is a player, `ALL SYSTEMS NOMINAL` otherwise — which is what keeps
      "a clean ship has no saturated pixel on it" true rather than rhetorical
- [x] **Topology derived, positions authored.** Edges come from `RoomBuilder.doorways` at runtime;
      only the 13 schematic positions are hand-written. A hand-drawn map drifts from the ship the
      first time a room moves — this way the drift is a test failure

### 19b. Build order

- [x] **Phase 1 — the drawing.** Done 2026-07-26. `scripts/ui/ship_plan.gd` (the plan table + edge
      derivation from `RoomBuilder.doorways`) and `scripts/ui/status_map.gd` (`_draw()`, blobs,
      pulse clock), fed a hard-coded problem list. Nothing existing was touched, so this phase
      could not break the game
- [x] **Phase 2 — wire it up.** Done 2026-07-26. `ComputerTerminal` collects problems from
      `RunState` (`active_malfunctions()`, `pressing_silos()`, `pressing_needs()` located via
      their silo),
      page toggle on `left`/`right` while READING, and the console auto-shows the map whenever
      anything is wrong. Also feeds `StatusMap.set_player_room()` from `Ship.room_at()`, the same
      call `RoomVoice` already makes. No new input action, no `game.tscn` edit

Two phases, and that is the whole feature. **Walking costs on the segments — metres, or seconds
of air — were considered and dropped.** The map answers *where*; the segments stay unlabelled.

### 19c. Verification

- [x] `tests/smoke_status_map.gd` — 331 checks. Every `ShipLayout` room has a node and every node a
      room (the drift guard); 12 doorways → 12 edges and no window mistaken for one; every edge
      horizontal, vertical or exactly 45°; no crossings; the graph is a tree; blobs land on the
      room they name, fan out when a room has several, and hold their order between collections
- [x] **Orientation check** (not in the spec, added during the build): the diagram may straighten
      the ship but may not mirror it. Everything else passes on a swapped HEAD/CLOSET
- [x] **Mutations killed:** room added (coverage), room removed (orphan), node moved off 45°
      (octilinear), the two stubs mirrored (orientation, 7 checks)
- [x] `tests/capture_status_map.gd` — renders at two pulse phases: a clean ship has NO saturated
      pixel anywhere, every trouble pixel belongs to a blob, each blob's core is the right colour,
      and the phases differ inside the blob discs and nowhere else at all
- [x] `tests/smoke_status_console.gd` — 64 checks against the REAL `game.tscn`: every fault and
      every silo as actually placed resolves to a room the diagram can draw (a check nothing else
      in the project makes); breaking/patching/repairing adds and clears the right blob in the
      right room; a pressing need and its own tank merge to ONE blob; the console picks its own
      page and drops a manual override when the player steps away
- [x] **Mutations killed:** the silo dedupe removed (the merge check fails), the auto-page logic
      inverted (six checks fail)
- [x] `tests/capture_status_console.gd` — the real console in the room, photographed. Measured
      RELATIVELY, because a critical fault reddens the whole room: 16.7% of the screen changes on
      a page swap against 2.9% for the same page twice


---

## 20. Three status displays — SPEC (not yet built)

Full spec: [status-displays.md](docs/features/status-displays.md). One display, one job:

| | where | shows | answers |
|---|---|---|---|
| NAV PLOT | the console, cryo bay | `NavChart` | where is the ship going |
| DECK PLAN | the bridge console bank | `StatusMap` | what is wrong with the ship |
| DECK PLAN, compact | the HUD corner | `StatusMap` | which way do I walk, now |

### 20a. Nothing built in step 19 is thrown away

- [ ] The console's two pages, auto-choice and manual flip become **the behaviour of a screen that
      declares both pages**: `@export var pages: Array[Page]`. One page = no flip, no auto-choice,
      and the prompt names it. The current two-page console stays a valid configuration, and
      `smoke_status_console` must keep passing **unchanged**
- [ ] **The bridge display needs no new script.** `computer_terminal.gd` has nothing
      console-specific left in it, so it is that script with `pages = [STATUS]` on an adopted
      decor node. The class name becomes wrong; renaming touches locked `game.tscn` — follow-up

### 20b. The bridge is the right home for the deck plan, and that is the point

- [ ] Today the plan is on a console in the **cryo bay** — the room you are already standing in.
      `ship_layout.gd`: the cryo bay has ONE door, up the spine to the bridge, and every other
      room hangs off the bridge — so **every trip out crosses the bridge**, and the bridge is
      where the direction is actually chosen. On the way back too, which is when you find out
      what else broke
- [ ] **Host it on `CD_BridgeTerminals_v1`, not a new prop.** It is already dressed on the bridge
      at `(0.47, 0, -19.92)`, unscaled 1:1, and the model is **15 x 1 x 5 units** — a waist-height
      bank of consoles running the full width of the bow, centred within 3 cm of the spine's
      centreline. Come through the spine door and its centre panel is what you walk into
- [ ] **Adopt it, the way `ShipSupplies` adopts the decor silos and the vending machine** — read
      the decor node and hang the collider, SubViewport, quad and `ViewPoint` off it. No new
      furniture, no clearance problem, no `game.tscn` edit
- [ ] **Parent the display in the node's LOCAL frame, and that is load-bearing.**
      `CD_BridgeTerminals` still clips the hull and the forward window (step 9 list + 17i, fix is
      a scale or a shallower model). A display parented locally rides along with either — so this
      neither waits on that fix nor breaks when it lands. Assert it: move the host, everything
      moves
- [ ] **The measurement this spec cannot make:** where the chart panel is on the 15 m bank, how
      far proud of it, and whether its face is flat, sloped or upright. Take it from the editor or
      tune it against the capture. **A shallower-model fix would change it** — the one thing local
      parenting does not absorb
- [ ] **If the panel is flat or sloped, lay the map out bow-up.** The reader stands aft of the
      bank (~`(0.5, -16.6)`, facing −Z) because that is the only side there is — so map-up = away
      = −Z = the ship's heading, AND the labels are upright, both for free. If the panel turns out
      **upright**, it reads like the console and ship-alignment simply does not apply
- [ ] **`Game._open_nav_screen()` hardcodes the reading pitch to `0.0`** — invisible while every
      readable thing was a wall CRT, wrong the moment a display is waist height. Take the pitch
      from the marker so `view_transform()` describes the whole pose. `_glide_player_to()`'s `0.0`
      is for the pod and stays

### 20c. The HUD copy

- [ ] **A `compact` flag on `StatusMap`, not a second class** — two would drift. No title, no
      legend, a `PAPER` backing panel (it sits over the lit world), tighter margins, **labels only
      on rooms carrying a blob**, and pixel floors on the label size and the thinnest stroke
- [ ] Bottom-left, 460 × 260 at `(60, -340)`–`(520, -80)`. Scale works out at 70.8 px/unit: blobs
      13.5 px radius, station rings 10.3, player dot 5.3 — and the bridge stubs at **2.3 px**,
      which is the one marginal number and the reason for the floor
- [ ] Visible only with a problem on it, out of the pod, not leaning into a screen, run not ended.
      No toggle key: the readout grows as things go wrong (17e)

### 20d. The honest problem, stated up front

- [ ] **If the HUD map ships, the bridge display becomes set dressing** — anything it tells you,
      the corner of your eye already did. The resolution is an onboarding arc: the bridge is the
      only place the ship's shape is NAMED (every room, the legend, the rooms that are fine), and
      the HUD is stripped to marks. The bridge teaches the map; the HUD uses it
- [ ] If that does not hold up in play, the lever is the HUD: make the corner map appear only once
      the player has read the bridge display once. One boolean

### 20e. Build order — and if time runs out, build the BRIDGE one

- [ ] **Phase 1 — one collector.** `scripts/game/ship_status.gd` takes `collect_problems()` and
      the three urgency statics off `ComputerTerminal`. No visible change
- [ ] **Phase 2 — `pages` as data.** Console set to `[NAV]`. The plan is briefly nowhere, which is
      why Phase 3 follows immediately
- [ ] **Phase 3 — the deck plan on the bridge.** Adopt the bank, measure the panel, fit the quad
      and the `ViewPoint`, fix the reading pitch. Independently shippable, and the one that
      changes where a decision gets made
- [ ] **Phase 4 — compact mode**, measured at HUD size in isolation
- [ ] **Phase 5 — the HUD corner.** Also independently shippable

### 20f. Verification — run the measurements FIRST

- [ ] `tests/smoke_status_displays.gd`: one collector feeding all three, never disagreeing
      (*mutation: give the HUD its own and confirm it fails*); `[NAV]`-only and `[STATUS]`-only
      screens behave; **ship-alignment** (map-up transformed by the quad's basis points along −Z),
      if the panel is flat or sloped; the `ViewPoint` is aft of the bank with a negative, non-zero
      pitch; **the display rides with its host** when the decor node is moved or rescaled; the
      reading position is standable (`smoke_navigation` route); HUD rect intersects none of
      `Oxygen`, `Arrival`, `SystemList`, `StasisPanel`, computed from the real controls
- [ ] `tests/capture_status_displays.gd`: the bank from its own `ViewPoint` — the plan sitting ON
      the panel rather than floating above or sunk into it, upright and in frame. **This is what
      settles the measurement**, so the offset is tuned against it rather than guessed. Plus the
      HUD map at real 1920 × 1080 — blobs above a pixel floor, blobs on different rooms not
      touching, the 2.3 px stubs still drawn, labels only on blobbed rooms. Keep the PNGs
- [ ] **Frame cost**, budget ~0.5 ms/frame. If it disappoints, redraw at **20–30 Hz instead of
      60** across all three — the fastest pulse on the page is 2.2 Hz — before cutting anything

---

## 21. Repair puzzles — the main mechanic (SPEC, not yet built)

These puzzles *are* the game. Everything in 17 is a countdown that sends you for a consumable;
this is the other half — a system breaks, it bleeds the drive, and you choose how to fix it.

**SCOPE: oxygen, and the navigation/engine fails. Nothing else.** The beer silo, the vending
machine and the septic tank stay exactly as they are — still 0..1 levels, still working, still
tested — and are not touched by any of this. Neither is CO2, which gets its own silo later
(21f). Four fails and one canister swap is the whole of section 21.

That is a deliberate narrowing and it decides the build order: **21a → 21b → 21d → 21c → 21e**.
The template first, because the other four items are configurations of it; spare parts before
the battery, because three of the four fails need a part and only one needs a cable.

### 21a. The puzzle template — build it once, configure it four times

Every FAIL has the same shape, and the shape is already most of what `Malfunction` does:

| | |
| --- | --- |
| **initial effect** | what it costs the moment it fires |
| **maximum effect** | where it climbs to if ignored |
| **growth** | it worsens over time, on the ship's clock (so stasis makes it worse) |
| **bodge (hammer)** | **freezes the effect where it stands — never reverses it** — and the fault then recurs **3–4× more often** |
| **spare part** | full fix, effect cleared to zero |
| **indicator** | green normally; **red and FLASHING** when critical |

The bodge rule is the heart of it and worth stating twice: *if the Nav Computer's maximum is
-10%, it starts at -5%, and it has climbed to -7% when you hit it with the hammer, the drive
stays down 7% until a real spare part goes in.* Bodging buys time, not power back.

**Already supported** by `Malfunction`: `speed_penalty` is the maximum, `speed_decay_per_day` the
growth, `speed_decay` the current value — and `repair(false)` already freezes `speed_decay`
without reversing it, which is exactly the rule above. `RepairPoint` already dispatches hammer
vs part off what is in your hands.

**Built 2026-07-26 — the numbers half of the template:**

- [x] **An initial effect.** `Malfunction.initial_speed_penalty`, seeded into `speed_decay` by
      `break_now()` with a `maxf` so a patch giving out never hands speed back.
- [x] **Bodge raises the recurrence rate.** `bodge_recurrence` (default 3.5); the patch holds
      `bodge_distance / bodge_recurrence`. A RATE rather than a second distance, so tuning how
      long a system lasts cannot silently leave its bodge outlasting its proper repair.
- [x] **Ramping is decoupled from severity.** It used to be a CRITICAL-only behaviour, which
      tied two unrelated ideas together — whether the ship-wide red alert trips, and whether
      the cost ramps. The nav computer ramps and is not critical; that was unrepresentable.
      `Malfunction.ramps()` now asks whether the fault HAS a ramp.
- [x] **A spare part can clear a bodge**, which the spec's own wording requires ("the drive
      loses 7% until you fix it with a real spare part") and which was NOT possible: a patched
      fault is inactive, `repair()` refused to act on it, and the panel stopped being a ray
      target. So a bodge meant losing that speed for good. Now a patched panel stays
      interactable, names the number it is holding you down by, and takes a part — but not
      another hammer. You cannot bodge a bodge.

**Built 2026-07-26 — the presentation half:**

- [x] **`IndicatorLight`** (`scripts/game/indicator_light.gd`), one light used by everything.
      `RepairPoint` and `Silo` each had their own emissive-quad routine and a third was about
      to appear for the engine and the nav computer. Mounts on the model's `Indicator` empty
      when there is one, falls back to the panel prop's `StatusLight` mesh, and builds a quad
      only if there is neither. Scale-compensated at every step, so it comes out metre-sized on
      a prop dressed at 0.25 or 0.6.
      (Named `IndicatorLight`, not `StatusIndicator` — Godot 4.7 already has one of those.)
- [x] **Flashing on critical**, at 2 Hz on a sine, dipping to 25% rather than to black — a
      light that goes fully out reads as a dead lamp on the half-cycle you glance at it.
      Colour says which of three states; the flash says now-versus-eventually.
- [x] **A MODEL can be the repair point.** `RepairPoint.setup()` mirrors `Silo.setup()`, so the
      script can be attached to a dressed-in prop at runtime — `Interactor` walks UP from
      whatever the ray hits, so the model's own collider resolves to it. The `RepairPanel` prop
      is now the fallback for systems with no geometry of their own.
- [x] `tests/smoke_indicator.gd` — short on purpose, covering only the two failures that are
      SILENT: an adopted model with no `setup()` never offers a prompt, and an indicator sized
      in local units comes out quarter-size but still lights up. Colours and flashing are
      visible the moment you look at the thing, so they are not tested.

### 21b. The four drive FAILs

| # | System | Where | Repair | Initial | Max |
|---|---|---|---|---|---|
| 1 | **Nav Computer** | Bridge — the `Computer`, at (0.43, 0, -20.50) | part or bodge | -5% | -10% |
| 2 | **Drive Regulator** | Engine room | part or bodge | -5% | -20% |
| 3 | **Drive Coupler** | Engine room | part or bodge | -5% | -20% |
| 4 | **Engine Core Depleted** | Engine room — the Engine | **a charged battery plugged in** | -100% | -100% |

- [ ] **The Nav Computer starts broken**, and is the run's opening fault. It replaces NAV ARRAY,
      which currently sits unrepaired in the CRYO BAY with no panel at all — the one failing
      assertion in `smoke_run_state` right now (`every malfunction is fixable`)
- [ ] Its repair point is the bridge **computer itself**, with the indicator added to it — not a
      panel bolted beside it
- [ ] **The computer already has an interaction, and the two must not fight.** Normally it is
      "lean in and read the map" (`ComputerTerminal.interact()` → `opened` → NavScreen). When
      the fault is critical the **map goes dark** and the same prop becomes a repair point:
      hammer to bodge, spare part to fix
  - So the prop needs ONE interactable that switches role on the fault's state, not two
      competing ones — the same shape `Silo` already uses, where being broken takes the
      ordinary use out of service and puts the repair in its place
  - Decide what "read the map" does while it is broken: refuse with a reason (consistent with
      the silos) rather than going silent, which reads as a prop the player misjudged
- [ ] "Drive Coupler" replaces the current MAIN DRIVE ("injector coupling failed")

### 21c. Engine Core — the battery puzzle

Not a consumable and not a silo: **a cable carrying power from a battery into the drive.**

- [x] **ENGINE CORE** as a `Malfunction` on the engine model: -100% initial and maximum, so it
      stops the ship outright rather than slowing it. `RunState.min_speed_fraction` is what
      keeps that survivable — verified dropping to the 0.06 floor and back to 0.95 when fed
- [x] The Engine's `socket` empty gets a `CableSocket` **sink**, parented to the empty so it
      tracks the model, and scale-compensated (the engine is dressed at 0.5)
- [x] The Engine's `Indicator` empty gets the light — red and flashing while depleted
- [x] `PoweredSocket` at (-18.06, 1.15, -1.92) is now a live **source** socket: the bay's
      charging point
- [x] `scenes/props/battery.tscn` — the modelled battery, same `BatteryCube` script and so the
      same charge/drain/flow behaviour and the same emissive bars. Port **on top**, where the
      model's own socket disc is; the cube's was on a side face because a box has no obvious
      top. Replaces the bare model instance already dressed into the engine room
- [x] Reuses `SocketPowerRepair` — the feed-the-inlet route already built for the aux-power
      device — rather than inventing a second way to say the same thing
- [ ] **`PoweredDevice` is now redundant** and still standing in the engine room at
      (-22.8, 0, 2.2). It is the same idea with a grey box instead of the engine. Delete it,
      or repurpose it as a second powered system somewhere that needs one

### 21d. Spare parts

- [x] Three kinds — **Spring, Screw, Gear** — as `scenes/props/spare_{spring,screw,gear}.tscn`,
      in the `spare_parts` group. Sized from the MEASURED model bounds rather than guessed, so
      each collider matches its mesh; added to `tests/diag_prop_bounds.gd`, which reports all
      three at 0.99–1.00
- [x] Placed: two in the **janitor's closet**, two in the **cargo bay**, and one **spring in the
      bridge** beside the nav computer — the tutorial's "it should be around here somewhere",
      now that the opening fault is there (21b). All five settle on the floor in the right room
- [x] The three blue placeholder cylinders in the cryo bay are gone; they were three identical
      untextured parts sat where no fault is
- [x] **Fungible, and staying that way.** Any of the three fixes any part-or-bodge fault, via
      `RepairPoint.required_part_group` matching the group rather than a name. Scarcity is what
      makes "which repairs are worth it" the decision; naming a part per fault would turn that
      into an inventory hunt. `required_part` still exists for a one-off if one is ever wanted

### 21e. The O2 canister — life support becomes a SWAP, not a level

**This is about OXYGEN, the run's own air budget — not about CO2.** CO2 keeps its countdown and
gets a silo of its own once that model exists (21f); nothing here touches it.

- [ ] The silo model carries `Socket` (where the canister attaches) and `Indicator`
- [ ] Oxygen under a minute → fetch a fresh canister, **take the used one out and put the new
      one in**
- [ ] A used canister **switches to the `Canister_Empty` model**. It can be taken out of the
      silo but **never put back in** — an empty is spent, and the swap is one-way
- [ ] An indicator **on the canister** shows used or unused
- [ ] The silo indicator is **green above a minute of oxygen, orange below**
- [ ] `OXYGEN LOW — REPLACE O2 CANISTER` as a **warning** (not a fault) in the HUD, and on the
      **ship map**

### 21f. What this changes in what is already built

Stated plainly, because 21 overlaps section 17 and the overlap has to be resolved deliberately
rather than discovered halfway through.

- [ ] **The life-support silo stops being a 0..1 level**, and becomes a socket holding one
      canister. **Only that one.** The beer silo, the vending machine and the septic tank keep
      their levels and are out of scope — so `Silo` has to support both shapes side by side
      rather than being converted wholesale. A `Socket`-based silo is arguably a different
      class; decide that when 21e is built, not before
- [ ] **CO2 keeps its own countdown and gets its own silo — not yet modelled.** Settled: the
      O2 canister in 21e feeds the run's OXYGEN, and CO2 is a separate system with a separate
      tank that has not been added to the ship yet. So the existing CO2 `Need`, its warning row
      and `CO2 NARCOSIS` all stay exactly as built; nothing there is redundant.
  - The one concrete change: the CO2 need currently names `silo_id = &"life_support"`, because
      that was the only tank going. When the CO2 silo arrives it points at that instead, and
      life support goes back to being purely about oxygen. One field
  - Until then, leave CO2 alone. It works, it is tested, and re-pointing it at a silo that does
      not exist yet would only break it
- [ ] **`power_cell.tscn` and the `power` silo are superseded** by 21c. The fuel-as-consumable
      model goes; `Silo.drain_per_day` and `stops_the_drive` may go with it
- [ ] **Two models changed size on reimport** and their props are now stale:
      `CD_Battery_v1` 8.84 → 2.65 units tall (so `power_cell.tscn`'s 0.0792 scale is wrong), and
      `CD_Canister_Air_v1` 4.68 → 4.49 (so `canister.tscn`'s centring offset is 1.8 cm out —
      within the floor test's tolerance, which is why nothing went red)

### 21g. Measured, so nobody has to re-derive it

Model-space positions of the empties, and what they are in metres at the scale each prop is
dressed at in `game.tscn`. **Re-measure in a RUNNING scene, never by instancing a `.blend`
headlessly** (see `docs/debugging-gotchas.md`) — and reimport first, since several of these
appeared only after the import cache was cleared.

| Prop | Dressed at | Empty | Model units | Metres |
|---|---|---|---|---|
| `CD_Engine_v4.2` | 0.5 | `Indicator` | (0, 5.20, 0.90) | (0, 2.60, 0.45) |
| | | `socket` | (0, 3.50, 2.30) | (0, 1.75, 1.15) |
| `CD_Silo_Base_v1.1` | 0.25 | `Indicator` | (-1.50, 9.00, 0) | (-0.375, 2.25, 0) |
| | | `Socket` | (0, 2.00, 0) | (0, 0.50, 0) |

Sizes in model units: engine 7.76 x 10.00 x 7.76, silo 10.64 x 21.00 x 9.28, battery
2.00 x 2.65 x 2.00, socket 3.75 x 3.75 x 0.50, air canister 2.00 x 4.49 x 2.00,
spring 1.39 x 2.37 x 1.39, screw 1.20 x 1.81 x 1.20, gear 2.81 x 0.63 x 2.95.

Scene nodes this needs: `Computer` (0.43, 0, -20.50), `CD_Engine_v4_2` (-19.5, 0, 4.5),
`PoweredSocket` (-18.06, 1.15, -1.92), silos `CD_Silo_Base_v1_1` (22.5, 0, -16.5) life support,
`_2` (-6.5, 0, -10) bathroom, `_3` (-17.5, 0, -12) mess.

**Note on adoption:** these props bring their own collision, so a functional body standing
*beside* one is invisible to the interaction ray — `Interactor` walks UP from whatever it hits.
`ShipSupplies` now attaches the script to the prop itself. Anything hung off an adopted prop
(indicator, socket, panel) is in that prop's LOCAL space, which is scaled — divide by the host
scale so offsets can stay written in metres.

---

## 22. ✅ Items falling through the deck — done ([log](docs/features/lost-items.md))

Items could be glitched through the floor into the void and lost for good. Fixed with two
independent defences, both proved by mutation.

Neither obvious cause was it, and both are worth not re-guessing:

- **The floor is not too thin.** `tests/diag_floor_escape.gd` slams every prop straight down at
  up to **120 m/s** (`Carry` caps release at 12) and onto five doorway seams: not one loss.
  `continuous_cd` is set on every prop scene and it holds.
- **There is no hole.** `tests/diag_floor_gaps.gd` rains 1157 probes over every walkable square
  metre: none escaped. It does confirm all 12 room-to-room seams are exact zero-overlap butt
  joints and that every doorway stands on one — but nothing falls through them.

The mechanism is **depenetration**: a body already inside the 0.2m slab is resolved to the
nearest face, and past the midplane that is the underside, with nothing below the ship.
Measured threshold ~0.15m for every prop, less for the canister. It gets in there because
`Carry._clamp_to_walls()` sweeps translation but writes the basis straight onto the body, so a
long prop can yaw itself into a corner and `drop()` unfroze it there.

- [x] **`Carry` will not unfreeze an embedded body** — every authored pose checked with
      `test_move(..., recovery_as_collision = true)`, and `drop()` backs up to the last clear
      origin
- [x] **`LostAndFound`** sweeps the `interactables` group each second and returns anything below
      y −0.5 to the room it fell through, or the player's feet if it went through over no room.
      Silent to the player, `push_warning` to the log
- [x] **`tests/smoke_lost_items.gd`**, three mutations killed

Not cosmetic: thirteen spares against roughly forty-seven repairs, and the canisters **are** the
oxygen — one lost under a doorway can make a run unwinnable with no feedback at all.

**The testing gotcha worth keeping:** the first version of the suite passed with the `Carry`
guard deliberately broken, because the net was rescuing the props behind it. The carry section
now switches the net off for its duration. Two defences are only two defences if each is proved
on its own.
