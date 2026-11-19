# polyguns — current functionality (as of 2026-11-19)

Snapshot of what the game actually does today, written as planning input. Complements `PLAN.md` (which holds the intended roadmap).

## How to run

- Godot 4.7 project, main scene `uid://cjmff0wlmncdk` = `world/testing_arena.tscn`.
- Renderer: `gl_compatibility` (desktop + mobile).
- No build/test/lint scripts, no autoloads. Verification = open project and run the main scene.

## Core loop (playable today)

1. You spawn at the arena centre as a green triangle.
2. Three red pentagons spawn 260–700 px around you and chase you.
3. Aim with the mouse. Hold LMB to charge a dash (movement slows to 35 %, a preview line grows), release to dash toward the cursor.
4. The dash passes through enemies, damages each one once per dash, and stops early on walls. I-frames cover the dash.
5. Enemies flash white, get knocked back, and burst into shards when killed.
6. Touching an enemy costs 1 HP (player has 3). At 0 HP you instantly respawn at the centre with full HP.
7. Killing all enemies leaves an empty arena — nothing spawns or ends the run.

## Controls

| Action | Binding |
| --- | --- |
| Move | WASD or arrow keys (`move_left/right/up/down`, physical keycodes) |
| Aim | Mouse position (player rotates to face cursor every physics frame) |
| Dash | Hold LMB to charge, release to dash (`dash`, mouse button 1) |

No pause, restart, or controller/touch input.

## Systems

### `entities/polygon/polygon.gd` — `Polygon` base
- `CharacterBody2D` that builds its own visuals at runtime: `Polygon2D` fill, `Line2D` outline (lightened 40 %), and `CollisionPolygon2D`.
- Exports: `sides` (3–64), `radius`, `color`, `outline_width`.
- Vertices start at +X so `look_at()` points the flat "front" at the target.
- Rebuild only happens in `_ready()`; changing exports at runtime does not refresh geometry.

### `entities/player/player.gd` — `Player` (extends `Polygon`)
- Triangle, radius 24, green; collision layer 2 (so world bodies ignore the player unless they mask it), default mask 1.
- Speed 300 px/s, mouse-facing aim (aim stays free while charging).
- Dash state machine: `READY`, `CHARGING`, `DASHING`.
  - Hold LMB (`dash`): charge up to 1.0 s; movement drops to 35 % speed; a preview `Line2D` grows toward the cursor and the outline widens/brightens.
  - Release: dash toward the cursor. Charge 0 → 1 maps distance 150 → 520 px, speed 1200 → 1900 px/s, damage 2 → 3.
  - Dash moves with `move_and_slide` and ends early on wall contact. Enemies are given collision exceptions for the dash so the player passes through them.
  - A circle shape query (layer 1, player radius + 4) damages each enemy once per dash via an instance-id hit set.
  - I-frames cover the whole dash plus 0.05 s; 0.25 s cooldown starts when the dash ends.
  - Generated charge tone (pitch rises with charge) and noise whoosh on release.
- Camera2D with smoothing (speed 10) clamped to ±1536 px (matches arena half-size).
- Health 3; `take_damage(amount, from_position)`:
  - 0.7 s invulnerability window, red flash for 0.12 s.
  - On 0 HP: cancel any dash/charge, full heal, teleport to `(0, 0)`, 0.7 s i-frames. No death screen, score loss, or run reset.

### `entities/projectile/projectile.gd` — `Projectile` (legacy, unreferenced)
- Plain `Node2D`, manually drawn as a small triangle + outline; not a physics body.
- Speed 1200 px/s, lifetime 1.3 s, radius 6, yellow.
- Moves by raycast (`intersect_ray`) against layer 1 with `hit_from_inside`, so it cannot tunnel through walls or point-blank enemies.
- On hit: snap to impact point, call `take_damage(1, direction)` if the collider has it, then free. Damage is hard-coded to 1; no pierce.
- Hits the first layer-1 body only — walls, enemies. Player is layer 2 and is skipped.
- Kept on disk for a possible future gun; nothing preloads or spawns it now.

### `entities/enemy/enemy.gd` — `Enemy` (extends `Polygon`)
- Pentagon, radius 20, red; collision layer 1 / mask 1; joins group `&"enemies"`.
- Speed 140 px/s, chases the first node in group `&"player"`, always faces it.
- Contact damage is a distance check (`enemy.radius + player.radius`), not a physics hit: 1 damage.
- Health 3. On hit: white flash 0.08 s, knockback impulse 260 px/s decaying at 900 px/s², noise SFX.
- On death: spawns a `DeathBurst` at its position, plays the impact through a temporary sibling player node (so the sound survives `queue_free`), then frees itself.

### `entities/fx/death_burst.gd` — `DeathBurst`
- 10 `Line2D` shards flying outward at ~320 px/s, decelerating, fading over 0.35 s, then freed.

### `world/testing_arena.gd` — `ArenaGrid` (named `Node2D` in the scene)
- Draws the arena at `z_index = -100`: 3072 × 3072 dark background, 64 px grid lines, bright cyan 4 px border.
- Builds a hollow perimeter `StaticBody2D` from a `CollisionPolygon2D` in `BUILD_SEGMENTS` mode (default layer 1) — four walls, no floor.
- `arena_size` / `cell_size` / colours are exports with setters that redraw (and rebuild walls for size). Runtime resizing is supported in code, but nothing calls it.

### `world/enemy_spawner.gd` — `EnemySpawner`
- On `_ready()`, spawns `count` (3) enemies as its own children, evenly spaced around a ring with ±0.35 rad jitter, at 260–700 px from the spawner.
- Spawner sits at the scene origin; no respawn, no waves, no difficulty scaling.
- `MIN_SPAWN_DISTANCE` is a constant, `count` and `spawn_radius` are exports.

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
└── EnemySpawner    (spawns 3 enemies at startup)
```

## Numbers to tune

| Thing | Value |
| --- | --- |
| Arena | 3072 × 3072, 64 px grid, centred on origin |
| Player | radius 24, speed 300, HP 3, i-frames 0.7 s |
| Dash | charge 1.0 s, distance 150–520 px, speed 1200–1900 px/s, damage 2–3 |
| Dash safety | 0.25 s cooldown, i-frames dash + 0.05 s, hit query radius 28 |
| Charging | movement ×0.35, preview length = dash distance |
| Enemy | radius 20, speed 140, HP 3, contact damage 1 |
| Knockback | 260 px/s impulse, 900 px/s² decay |
| Spawning | 3 enemies, ring 260–700 px, one-shot at startup |
| Camera | smoothing 10, limits ±1536 |

## Not implemented (gaps relevant to the plan)

- No HUD: health, score, wave or enemy count are invisible.
- No waves, wave director, boss, or level/arena pool; enemies spawn once and never again.
- No upgrades, inheritance, progression, currency, or run structure.
- No game over / restart / pause; death silently teleports you to the centre.
- One enemy type (melee chaser); dash is the only attack (the gun is removed, `projectile.gd` is unreferenced).
- No screen shake, particles (only line shards), hit-stop, or damage numbers.
- No mobile/touch controls despite the mobile renderer setting.
- No health pickup or any pickup system.
- `Polygon` visuals are built once in `_ready()`; runtime stat/visual changes need a rebuild path.
- Player `take_damage`'s `from_position` argument is unused (no directional feedback).
- No tests/CI; only manual in-editor verification.
