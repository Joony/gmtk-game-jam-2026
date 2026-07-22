# Feature: Game scene (step 3)

**Date:** 2026-07-22
**Status:** Done, verified

## What was done

[scenes/game.tscn](../../scenes/game.tscn) + [scripts/game.gd](../../scripts/game.gd), replacing the
placeholder label scene created during step 2.

- 40×40 flat floor (StaticBody3D + BoxShape3D + BoxMesh), top surface at y=0
- `DirectionalLight3D` with shadows, plus a `WorldEnvironment` (dark background, low blue ambient)
- Three crates as movement landmarks — they make motion legible in screenshots and give the
  step 8 carry system something to bump into later
- `PlayerSpawn` marker at (0, 1, 4); `game.gd` moves the player onto it in `_ready`
- Player instanced from [scenes/player.tscn](../../scenes/player.tscn) (step 4)
- `game.gd` captures the mouse on entry via `capture_mouse()`. Step 5 hands cursor ownership to
  the pause menu, which will call back into this.

## Dev convenience — booting straight into the game

No debug flag needed; Godot takes a scene path directly, skipping the 11s intro:

```
godot --path . scenes/game.tscn
```

Verified: boots with no `[SceneManager]` transition logged, meaning it went straight to the game
scene rather than through intro → menu.

## How it was verified

Covered by [tests/smoke_player.gd](../../tests/smoke_player.gd) — see
[player-controller.md](player-controller.md) for the full list. Scene-specific checks:

- player starts exactly on the spawn marker in XZ, and near it in Y
- player settles on the floor and does not fall through it
- scene renders correctly (PNG capture inspected: floor, crates, shadows, player's own shadow)
