# polyguns — current functionality (as of 2026-11-19)

Snapshot of what the game actually does today, written as planning input. Complements `PLAN.md` (which holds the intended roadmap).

## How to run

- Godot 4.7 project, main scene `uid://cjmff0wlmncdk` = `world/testing_arena.tscn`.
- Renderer: `gl_compatibility` (desktop + mobile).
- No build/test/lint scripts, no autoloads. Verification = open project and run the main scene.

## Core loop (playable today)

1. You spawn at the arena centre as a green triangle.
2. The wave director starts wave 1: three red pentagons spawn 450–700 px around you and chase you.
3. Aim with the mouse. Hold LMB to charge a dash (movement slows to 35 %, a preview line grows), release to dash toward the cursor.
4. The dash passes through enemies, damages each one once per dash, and stops early on walls. I-frames cover the dash.
5. Enemies flash white, get knocked back, and burst into shards when killed.
6. Touching an enemy costs 1 HP, a boss costs 2 (player has 5). At 0 HP the run ends in game over.
7. Clearing waves 1–3 (3 / 5 / 7 enemies, 2 s between waves) spawns the placeholder boss. Killing it wins the run.
8. After a win or loss the arena pauses and the HUD shows an overlay; press `R` to restart from wave 1.

## Controls

| Action | Binding |
| --- | --- |
| Move | WASD or arrow keys (`move_left/right/up/down`, physical keycodes) |
| Aim | Mouse position (player rotates to face cursor every physics frame) |
| Dash | Hold LMB to charge, release to dash (`dash`, mouse button 1) |
| Restart | `R` (`restart`, physical keycode 82) — only on the win/lose overlay |

No pause menu or controller/touch input.

## Systems

### `entities/polygon/polygon.gd` — `Polygon` base
- `CharacterBody2D` that builds its own visuals at runtime: `Polygon2D` fill, `Line2D` outline (lightened 40 %), and `CollisionPolygon2D`.
- Exports: `sides` (3–64), `radius`, `color`, `outline_width`.
- Vertices start at +X, so `look_at()` aims that first vertex (a corner) at the target.
- Rebuild only happens in `_ready()`; changing exports at runtime does not refresh geometry.

### `entities/player/player.gd` — `Player` (extends `Polygon`)
- Triangle, radius 24, green; collision layer 2 (so world bodies ignore the player unless they mask it), default mask 1.
- Signals: `health_changed(current, maximum)`, `died`.
- Speed 300 px/s, mouse-facing aim (aim stays free while charging).
- Dash state machine: `READY`, `CHARGING`, `DASHING`.
  - Hold LMB (`dash`): charge up to 1.0 s; movement drops to 35 % speed; a preview `Line2D` grows toward the cursor and the outline widens/brightens.
  - Release: dash toward the cursor. Charge 0 → 1 maps distance 150 → 520 px, speed 1200 → 1900 px/s, damage 2 → 3.
  - Dash moves with `move_and_slide` and ends early on wall contact. Enemies are given collision exceptions for the dash so the player passes through them.
  - A circle shape query (layer 1, player radius + 4) damages each enemy once per dash via an instance-id hit set.
  - I-frames cover the whole dash plus 0.05 s; 0.25 s cooldown starts when the dash ends.
  - Generated charge tone (pitch rises with charge) and noise whoosh on release.
- Camera2D with smoothing (speed 10) clamped to ±1536 px (matches arena half-size).
- Health 5; `take_damage(amount, from_position)`:
  - 0.7 s invulnerability window, red flash for 0.12 s; emits `health_changed`.
  - At 0 HP: sets `_dead`, cancels the dash, dims the body/outline, early-returns from `_physics_process` and emits `died`. The wave director turns that into game over. No auto-respawn.

### `entities/projectile/projectile.gd` — `Projectile` (legacy, unreferenced)
- Plain `Node2D`, manually drawn as a small triangle + outline; not a physics body.
- Speed 1200 px/s, lifetime 1.3 s, radius 6, yellow.
- Moves by raycast (`intersect_ray`) against layer 1 with `hit_from_inside`, so it cannot tunnel through walls or point-blank enemies.
- On hit: snap to impact point, call `take_damage(1, direction)` if the collider has it, then free. Damage is hard-coded to 1; no pierce.
- Hits the first layer-1 body only — walls, enemies. Player is layer 2 and is skipped.
- Kept on disk for a possible future gun; nothing preloads or spawns it now.

### `entities/enemy/enemy.gd` — `Enemy` (extends `Polygon`)
- Pentagon, radius 20, red; collision layer 1 / mask 1; joins group `&"enemies"`.
- Signals: `died(enemy)`, `health_changed(current, maximum)`.
- Speed 140 px/s, chases the first node in group `&"player"`, faces it while `face_target` is true.
- Movement is a hook: base `_physics_process` calls `_get_desired_velocity(delta, player)` (default: chase at `speed`); subclasses override only that hook. `face_target = false` freezes facing during charges.
- Contact damage is a distance check (`enemy.radius + player.radius`), not a physics hit: 1 damage.
- Health 3. On hit: white flash 0.08 s, knockback impulse 260 px/s × `knockback_scale` (1.0 by default) decaying at 900 px/s², noise SFX, `health_changed`.
- On death: emits `died`, spawns a `DeathBurst` at its position, plays the impact through a temporary sibling `AudioStreamPlayer` (so the sound survives `queue_free`), then frees itself.

### `entities/enemy/boss.gd` — `Boss` (extends `Enemy`)
- Hexagon, radius 48, magenta, outline width 3; HP 20, contact damage 2, chase speed 90 px/s, knockback scale 0.35.
- State machine driven from `_get_desired_velocity()` only:
  - `CHASE` at 90 px/s. After a cooldown (1.0 s on spawn, then ~2.5 s), if the player is within 500 px → `WINDUP`.
  - `WINDUP` 0.45 s stationary, faces the player, then locks a charge direction.
  - `CHARGE` ~600 px/s in the locked direction for 0.4 s; ends early on wall contact (`get_slide_collision_count()`); `face_target` is off so it cannot turn.
  - `RECOVER` 0.7 s stationary, then back to chase with a fresh cooldown.
- Telegraphs with outline width/colour and the visual `body.scale` only; `body.color` stays reserved for the white hit flash.

### `world/wave_director.gd` — `WaveDirector`
- Group `&"director"`; signals `wave_changed(wave, total)`, `boss_spawned(boss)`, `run_finished(victory)`.
- Spawns waves of 3 / 5 / 7 enemies at once on a 450–700 px ring around the player, evenly spaced with angle jitter; positions are clamped to ±1400, with an inward fallback that keeps at least 320 px clearance so nothing lands on the player.
- Waits 2 s between waves. Clearing wave 3 spawns the boss 650 px from the player.
- Tracks alive enemies via their `died` signal; a player `died` ends the run in defeat, boss `died` ends it in victory.
- After either end, emits `run_finished` and pauses the tree 0.8 s later (so the death burst/overlay can show).

### `ui/hud.gd` — `Hud` (CanvasLayer)
- Built entirely in code; `process_mode = ALWAYS`, `layer = 10`. Last node in the arena scene.
- HP pips (one per `max_health`, green fill), centred `WAVE n / 3` label, boss bar with name + red fill driven by boss `health_changed`.
- End overlay (`VICTORY` / `GAME OVER` + `Press R to restart`). `R` unpauses (`get_tree().paused = false`) and calls `reload_current_scene()`.
- Binds via groups (`&"player"`, `&"director"`) deferred, and seeds the initial wave label from the director's state.

### `entities/fx/death_burst.gd` — `DeathBurst`
- 10 `Line2D` shards flying outward at ~320 px/s, decelerating, fading over 0.35 s, then freed.

### `world/testing_arena.gd` — `ArenaGrid` (named `Node2D` in the scene)
- Draws the arena at `z_index = -100`: 3072 × 3072 dark background, 64 px grid lines, bright cyan 4 px border.
- Builds a hollow perimeter `StaticBody2D` from a `CollisionPolygon2D` in `BUILD_SEGMENTS` mode (default layer 1) — four walls, no floor.
- `arena_size` / `cell_size` / colours are exports with setters that redraw (and rebuild walls for size). Runtime resizing is supported in code, but nothing calls it.

### `world/enemy_spawner.gd` — removed
- Superseded by `WaveDirector` in Stage B (the one-shot startup spawner was deleted).

### `audio/sfx.gd` — `Sfx`
- Generates 16-bit mono WAVs at 22050 Hz at runtime; no audio assets on disk.
- `make_tone(start_freq, end_freq, duration, volume)` — used for the charge tone (220 → 440 Hz, 1.5 s; pitch-scaled while charging).
- `make_noise(duration, volume)` — used for enemy hits (0.06 s) and the dash whoosh (0.15 s).
- Volume is the raw int16 amplitude scale (e.g. 12000 ≈ 0.37 full scale).

## Arena / scene layout

```
TestingArena (Node2D)
├── Player          (player.tscn instance, at origin)
├── Node2D          (ArenaGrid script: background, grid, border, walls)
├── WaveDirector    (waves 3/5/7, intermission, boss, win/lose)
└── HUD             (code-built CanvasLayer, last so it can bind groups)
```

## Numbers to tune

| Thing | Value |
| --- | --- |
| Arena | 3072 × 3072, 64 px grid, centred on origin |
| Player | radius 24, speed 300, HP 5, i-frames 0.7 s |
| Dash | charge 1.0 s, distance 150–520 px, speed 1200–1900 px/s, damage 2–3 |
| Dash safety | 0.25 s cooldown, i-frames dash + 0.05 s, hit query radius 28 |
| Charging | movement ×0.35, preview length = dash distance |
| Enemy | radius 20, speed 140, HP 3, contact damage 1 |
| Knockback | 260 px/s impulse, 900 px/s² decay, ×`knockback_scale` |
| Waves | 3 / 5 / 7 enemies, ring 450–700 px, clamp ±1400, 320 px clearance, 2 s intermission |
| Boss | radius 48, HP 20, contact damage 2, speed 90, charge 600 px/s |
| Boss timing | 1 s initial cooldown, then 2.5 s cooldown, 0.45 s windup, 0.4 s charge, 0.7 s recover, 500 px trigger |
| End of run | overlay immediately, tree paused after 0.8 s |
| Camera | smoothing 10, limits ±1536 |

## Not implemented (gaps relevant to the plan)

- No combo, damage multiplier, or bullet time (Stage C/D).
- No upgrades, inheritance, progression, currency, level/arena pool, or score.
- No pause menu; `R` restart only appears after a win/lose.
- One enemy type (melee chaser) plus the placeholder boss; dash is the only attack (the gun is removed, `projectile.gd` is unreferenced).
- No screen shake, particles (only line shards), hit-stop, or damage numbers.
- No mobile/touch controls despite the mobile renderer setting.
- No health pickup or any pickup system.
- `Polygon` visuals are built once in `_ready()`; runtime stat/visual changes need a rebuild path.
- Player `take_damage`'s `from_position` argument is unused (no directional feedback).
- No tests/CI; only manual in-editor verification (a temporary headless harness verified Stage B and was removed).
