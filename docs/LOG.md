# Development log — GMTK Game Jam 2026

Overview of implemented features. Each entry links to a detailed per-feature log in `features/`.

> **Hit a weird Godot behaviour?** [`debugging-gotchas.md`](debugging-gotchas.md) collects the
> non-obvious traps this project ran into (row-major `.tscn` bases, the one-frame origin
> flash, silent audio/particle no-ops, headless-test pitfalls) with the workaround for each.

| Date | Feature | Status | Details |
|------|---------|--------|---------|
| 2026-07-22 | Project structure (folders, `pause` input action, main scene) | Done, verified | [project-structure.md](features/project-structure.md) |
| 2026-07-22 | SceneManager autoload (fade transitions, re-entrancy guard) | Done, verified | [scene-manager.md](features/scene-manager.md) |
| 2026-07-22 | Intro: 10→0 red countdown on black, skip button | Done, verified | [intro.md](features/intro.md) |
| 2026-07-22 | Main menu (step 2): title + Play, no Quit | Done, verified | [main-menu.md](features/main-menu.md) |
| 2026-07-22 | Game scene (step 3): floor, light, crates, spawn point | Done, verified | [game-scene.md](features/game-scene.md) |
| 2026-07-22 | Player controller (step 4): FPS movement + camera, ported from Doortal | Done, verified | [player-controller.md](features/player-controller.md) |
| 2026-07-22 | Pause menu (step 5): Esc pauses + releases cursor, Quit to Menu | Done, verified | [pause-menu.md](features/pause-menu.md) |
| 2026-07-22 | Full loop verification (step 6): two round-trips, no leaks | Done, verified | [loop-verification.md](features/loop-verification.md) |
| 2026-07-22 | Web export (step 7): exported, runs in browser | Done — pointer lock unverifiable in automated browser | [web-export.md](features/web-export.md) |
| 2026-07-22 | Font + project-wide UI theme (AbolitionTest) | Done, verified | [font-and-theme.md](features/font-and-theme.md) |
| 2026-07-22 | Intro reworked: two-digit countdown, holds on 01, leads into the game | Done, verified | [intro.md](features/intro.md) |
| 2026-07-22 | START prompt: click-to-begin gate for browser pointer lock | Done, verified | [start-prompt.md](features/start-prompt.md) |
| 2026-07-22 | Interaction & carry (step 8): raycast detection, physics carry, reticle | Done, verified | [interaction-and-carry.md](features/interaction-and-carry.md) |
| 2026-07-22 | Room builder (step 9): rooms, doorway splitting, hand-authored ship | Done, verified | [room-builder.md](features/room-builder.md) |
| 2026-07-23 | Sliding doors: proximity-triggered panels, ported from GMTK 2025 | Done, verified | [sliding-doors.md](features/sliding-doors.md) |
| 2026-07-23 | Flat interior lighting: shadowless omni grid, no directional sun | Done, verified | [flat-lighting.md](features/flat-lighting.md) |
| 2026-07-23 | Script runs no longer capture the real cursor (and two corrected diagnoses) | Done, verified | [mouse-capture-in-tests.md](features/mouse-capture-in-tests.md) |
| 2026-07-23 | Lighting modes (step 10): ship-wide normal/alert, pulsing, data-driven | Done, verified | [lighting-modes.md](features/lighting-modes.md) |
| 2026-07-23 | Window size 1920x1080 (step 9a) with UI scaled to match | Done, verified | [window-size.md](features/window-size.md) |
| 2026-07-23 | Space windows (step 11): wall openings, starfield shader, ship motion | Done, verified | [space-windows.md](features/space-windows.md) |
| 2026-07-23 | Space exterior: backdrop shell, station, nebula band (branch `space-exterior`) | Done, verified | [space-exterior.md](features/space-exterior.md) |
| 2026-07-23 | Countdown loop (step 12): oxygen, distance, stasis pod, malfunctions, repairs, end states | Done, verified | [countdown-loop.md](features/countdown-loop.md) |
| 2026-07-23 | Ship fittings: million-mile/day units, fixed-width readouts, cryo pod ring, vent pipe, nav console | Done, verified | [ship-fittings.md](features/ship-fittings.md) |
| 2026-07-24 | Cables (step 14d, Phase 1): verlet rope ported from Doortal, portals stripped (1868→1280 lines) | Phase 1 done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables (step 14d, Phase 2): CableSocket copied unchanged, full API verified; proximity-release confirmed | Phase 2 done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables (step 14d, Phase 3): CablePlug rebased onto Interactable+Carry — grab/seat/re-grab/breakaway via the real input path | Phase 3 done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables (step 14d, Phase 4): fixed (bolted-in) plugs, power_cable.tscn, engine-room placement, player in cable_ignore | Phase 4 done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables 14d playtest fixes: moved the cable off the wall (forward wall), overstretch now drops from hand / pops from wall with an elastic recoil | Done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables 14d polish: socket flush to wall, CD_Plug_v1 model, breakaway threshold 1.6→1.2 | Done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables (step 14d, Phase 5): battery cube — charges from a source, drains into a sink, per-instance charge bars | Phase 5 done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables 14d playtest fix: plug scaled ~2.3× with collision box matched — model no longer clips walls, rope endpoint stays clear | Done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables 14d playtest fixes: plug-into-battery via look+E (held-aware interaction); cable now exits straight out the plug's back | Done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables 14d playtest fix: a plug seated in a carried battery follows at render rate (no longer lags the cube) | Done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables 14d: merged main's prop models; socket receptacle now uses CD_Socket_v1.1 via a receptacle_scene export | Done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables 14d playtest: fixed wall-socket orientation/placement, plug seats OUTSIDE the socket (standoff), battery uses the socket model | Done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
| 2026-07-24 | Cables 14d (pre-Phase 6): wall sockets (look+E plug-in, source/sink) + a loose two-ended cable, placed in the engine room | Done, verified | [cables-and-battery.md](features/cables-and-battery.md) |
