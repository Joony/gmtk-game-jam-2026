# Development log — GMTK Game Jam 2026

Overview of implemented features. Each entry links to a detailed per-feature log in `features/`.

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
