# TODO — GMTK Game Jam 2026

Godot 4.7 project. Core flow: Intro → Main Menu → Game ⇄ Pause Menu.

## Project structure — done ([log](docs/features/project-structure.md))

- [x] Create folder layout: `scenes/`, `scripts/`, `ui/`, `assets/`
- [x] Add input map action `pause` bound to Esc (physical keycode, in `project.godot`)
- [x] Set the main scene in Project Settings (stub `scenes/intro.tscn` for now — replaced by the Intro feature)

## Scene loading system (do this first — everything else uses it)

- [ ] `SceneManager` autoload (`scripts/scene_manager.gd`)
  - [ ] `change_scene(path)` — swaps the current scene
  - [ ] Fade-out / fade-in transition (CanvasLayer + ColorRect, tween alpha)
  - [ ] Optional: `ResourceLoader.load_threaded_request` for async loading if scenes get heavy
- [ ] Register autoload in Project Settings → Globals

## Intro

- [ ] `scenes/intro.tscn` — splash screen (logo / jam title)
- [ ] Auto-advance to main menu after ~2s timer
- [ ] Skip on any key press / mouse click
- [ ] Fade in/out via SceneManager transition

## Main menu

- [ ] `scenes/main_menu.tscn` — Control-based UI
  - [ ] Title label
  - [ ] **Play** button → `SceneManager.change_scene("res://scenes/game.tscn")`
  - [ ] **Options** button (stub for now — volume slider later if time allows)
  - [ ] **Quit** button → `get_tree().quit()` (hide on web export — `OS.has_feature("web")`)
- [ ] Keyboard/gamepad navigation: set initial focus with `grab_focus()`

## In-game pause menu

- [ ] `ui/pause_menu.tscn` — CanvasLayer, hidden by default
  - [ ] Esc toggles it: pause with `get_tree().paused = true`
  - [ ] Set pause menu's `process_mode` to `Always` so it works while paused
  - [ ] **Resume** button (also Esc again)
  - [ ] **Quit to Menu** button → unpause, then `SceneManager.change_scene` to main menu
  - [ ] Dim background (semi-transparent ColorRect)
- [ ] Make sure Esc is ignored during intro/main menu

## Game scene (placeholder)

- [ ] `scenes/game.tscn` — minimal playable stub so the full loop is testable
- [ ] Instance the pause menu (or add it via the game scene root)

## Verify the loop

- [ ] Intro → auto/skip → Main Menu → Play → Game → Esc → Quit to Menu → Play again (no leaks/errors)
- [ ] Quit button exits cleanly

## Later / jam-day

- [ ] Hook up jam theme once announced
- [ ] Audio: menu music, button click SFX (AudioController pattern from 2025 project)
- [ ] Options menu: master volume slider
- [ ] Web export preset for itch.io
