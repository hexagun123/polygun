# polyguns — current functionality (as of 2026-11-19)

Snapshot of what the game actually does today, written as planning input. Complements `PLAN.md` (roadmap).

## How to run

- Godot 4.7 project, main scene `uid://cjmff0wlmncdk` = `world/testing_arena.tscn`.
- Physics runs at 120 ticks/s (`project.godot` → `physics/common/physics_ticks_per_second`).
- Renderer: `gl_compatibility` (desktop + mobile). No build/test/lint scripts, no autoloads.
- Verification = open project and run the main scene.

## Core loop (playable today)

1. Spawn at arena centre as a green triangle.
2. `WaveDirector` starts wave 1: 3 red pentagons spawn 450–700 px around the player and chase.
3. Aim with the mouse. Hold LMB to charge a dash (movement ×0.35, preview line grows), release to dash toward the cursor.
4. The dash passes through enemies, damages each one once per dash, and stops early on walls. I-frames cover the dash + 0.05 s.
5. Enemies flash white, get knocked back, and burst into shards when killed.
6. Touching an enemy costs 1 HP, the boss costs 2 (player has 5). At 0 HP the run ends in game over.
7. Clearing waves 1–3 (3 / 5 / 7 enemies, 2 s between waves) spawns the placeholder boss. Killing it wins the run.
8. 0.8 s after a win or loss the tree pauses and the HUD shows an overlay; press `R` to restart from wave 1.

## Controls

| Action | Binding |
| --- | --- |
| Move | WASD or arrow keys (`move_left/right/up/down`) |
| Aim | Mouse position (player faces cursor every physics frame) |
| Dash | Hold LMB to charge, release to dash (`dash`) |
| Restart | `R` (`restart`) — only on the win/lose overlay |

No pause menu or controller/touch input.

## Systems

### `entities/polygon/polygon.gd` — `Polygon` base
- `CharacterBody2D` that builds visuals at runtime: `Polygon2D` fill, `Line2D` outline, `CollisionPolygon2D`.
- Exports: `sides` (3–64), `radius`, `color`, `outline_width`. Vertices start at +X so `look_at()` aims the front at the target.
- Built once in `_ready()`; runtime export changes do not rebuild geometry.

### `entities/player/player.gd` — `Player` (extends `Polygon`)
- Triangle, radius 24, green; collision layer 2, mask 1. Group `&"player"`. Signals: `health_changed(current, maximum)`, `died`.
- Speed 300 px/s, mouse-facing aim (aim stays free while charging).
- Dash state machine: `READY` / `CHARGING` / `DASHING`.
  - Charge up to 1.0 s: movement ×0.35, preview `Line2D` grows, outline widens/brightens; rising-pitch tone.
  - Release: dash toward cursor. Charge 0→1 maps distance 150→520 px, speed 1200→1900 px/s, damage 2→3.
  - Moves with `move_and_slide`, ends early on wall contact. Enemies get temporary collision exceptions so the player passes through them.
  - Circle shape query (layer 1, radius 28) damages each enemy once per dash (instance-id set).
  - I-frames for dash duration + 0.05 s; 0.25 s cooldown after dash ends. Noise whoosh on release.
  - Presses made while dashing / cooling down are buffered for 0.2 s instead of being dropped.
  - Dash end keeps 18 % of dash speed as momentum that decays at 2800 px/s², so landing slides instead of stopping dead.
- Camera2D with smoothing (10, boosted to 55 while dashing) clamped to ±1536, plus a movement-direction look-ahead (45 px at walking speed, capped at 90 px).
- HP 5, 0.7 s damage i-frames, red flash 0.12 s. At 0 HP: sets `_dead`, cancels dash, dims body/outline, early-returns from physics and emits `died` (no auto-respawn). `take_damage` ignores `from_position`.

### `entities/enemy/enemy.gd` — `Enemy` (extends `Polygon`)
- Pentagon, radius 20, red; layer 1/mask 1. Group `&"enemies"`. Signals: `died(enemy)`, `health_changed(current, maximum)`.
- Speed 140 px/s, chases group `&"player"`, faces target while `face_target` is true.
- Movement hook: `_get_desired_velocity(delta, player)` (default chase at `speed`); subclasses override only this.
- Contact damage via distance check (`enemy.radius + player.radius`), 1 damage.
- HP 3. On hit: white flash 0.08 s, knockback 260 px/s × `knockback_scale` decaying at 900 px/s², noise SFX.
- On death: emits `died`, spawns `DeathBurst`, plays impact through a temporary sibling player, then frees.

### `entities/enemy/boss.gd` — `Boss` (extends `Enemy`)
- Hexagon, radius 48, magenta, outline 3; HP 20, contact damage 2, speed 90 px/s, `knockback_scale` 0.35.
- State machine in `_get_desired_velocity()`: `CHASE` (90 px/s) → `WINDUP` (0.45 s, telegraphed) → `CHARGE` (600 px/s, locked direction, 0.4 s, ends early on wall) → `RECOVER` (0.7 s). Triggers within 500 px after cooldown (1.0 s initial, 2.5 s after).
- Telegraphs via outline width/color and `body.scale` only; `body.color` stays for hit flash.

### `world/wave_director.gd` — `WaveDirector`
- Group `&"director"`. Signals: `wave_changed(wave, total)`, `boss_spawned(boss)`, `run_finished(victory)`.
- Waves of 3 / 5 / 7 enemies spawned at once on a 450–700 px ring around the player (evenly spaced + jitter), clamped to ±1400 with ≥320 px clearance fallback. 2 s intermission between waves.
- After wave 3 spawns boss ~650 px from player. Tracks alive enemies via `died`.
- Player `died` → defeat; boss `died` → victory. Emits `run_finished` then pauses the tree after 0.8 s.

### `ui/hud.gd` — `Hud` (CanvasLayer)
- Built in code; `process_mode = ALWAYS`, `layer = 10`, last in scene.
- HP pips (per `max_health`), `WAVE n / 3` label, boss bar driven by boss `health_changed`.
- End overlay (`VICTORY` / `GAME OVER` + "Press R to restart"). `R` unpauses and reloads the scene.
- Binds via groups (`&"player"`, `&"director"`) deferred; seeds initial wave from director state.

### `entities/fx/death_burst.gd` — `DeathBurst`
- 10 `Line2D` shards flying outward (~320 px/s), decelerating, fading over 0.35 s, then freed.

### `world/testing_arena.gd` — arena (named `Node2D` in scene)
- Draws arena at `z_index = -100`: 3072×3072 background, 64 px grid, cyan border.
- Hollow perimeter `StaticBody2D` (`CollisionPolygon2D` in `BUILD_SEGMENTS`, layer 1) — four walls, no floor.

### `audio/sfx.gd` — `Sfx`
- Generates 16-bit mono WAVs at 22050 Hz at runtime (no audio assets).
- `make_tone(...)` for charge tone; `make_noise(...)` for enemy hits and dash whoosh. Volume is raw int16 amplitude.
- `cached_tone(...)` / `cached_noise(...)` memoise by parameter key so a sound is generated once per run; `varied_pitch(amount)` returns a random `pitch_scale` so repeated hits do not machine-gun.

### `entities/projectile/projectile.gd` — legacy, unreferenced
- Old raycast bullet kept on disk; nothing preloads or spawns it now.

## Arena / scene layout

```
TestingArena (Node2D)
├── Player          (player.tscn)
├── Node2D          (arena grid/border/walls)
├── WaveDirector    (waves + boss + win/lose)
└── HUD             (CanvasLayer, last)
```

## Numbers to tune

| Thing | Value |
| --- | --- |
| Arena | 3072×3072, 64 px grid, limits ±1536 |
| Player | radius 24, speed 300, HP 5, damage i-frames 0.7 s, physics 120 Hz |
| Dash | charge 1.0 s, distance 150–520, speed 1200–1900, damage 2–3, cooldown 0.25 s, i-frames dash+0.05 s, hit radius 28, move ×0.35 while charging |
| Feel | input buffer 0.2 s, momentum carry 18 % (decay 2800), camera look-ahead 45 px walk / 90 px cap, smoothing 10 → 55 |
| Enemy | radius 20, speed 140, HP 3, contact 1, knockback 260/900 |
| Waves | 3/5/7, ring 450–700, clamp ±1400, clearance 320, intermission 2 s |
| Boss | hexagon r48, HP 20, contact 2, speed 90, charge 600; windup 0.45, charge 0.4, recover 0.7, cooldown 2.5 s (1.0 initial), trigger 500 px, knockback ×0.35 |
| End | overlay on end, pause after 0.8 s |

## Not implemented (gaps relevant to the plan)

- No combo/damage multiplier or bullet time (Stage C/D).
- No feel pass (hit-stop, shake, ghosts, damage numbers, zoom punch, hurt feedback; Stage F).
- No rebalance pass (Stage E), upgrades/inheritance, currency, level/arena pool, or score.
- No pause menu; `R` only on win/lose overlay.
- One enemy type + placeholder boss; dash-only attack (`projectile.gd` unreferenced).
- No screen shake, particles beyond line shards, hit-stop, or damage numbers.
- No mobile/touch controls despite mobile renderer.
- No pickups. `Polygon` visuals not rebuildable at runtime.
- `Player.take_damage` ignores `from_position` (no directional feedback).
- No tests/CI; verification is manual in-editor (headless smoke harnesses used previously and removed).
