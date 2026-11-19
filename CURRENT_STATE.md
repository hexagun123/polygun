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
3. Aim with the mouse. Press LMB to dash instantly toward the cursor; hold LMB to wind the *next* dash (preview line grows; movement is never slowed). The wind is spent by the dash.
4. The dash lasts 0.1 s and wind maps distance 180–420 px, so distance sets speed (1800–4200 px/s) and damage (2–4). It passes through enemies, damages each one once per dash along the travelled segment, and stops early on walls. I-frames cover the dash + 0.05 s.
5. A dash that crosses an enemy and ends within 1.5 × its radius of its centre **executes** it: ×3 damage and +1 combo. Ending the dash inside the enemy costs the player 1 HP instead. The combo breaks on any dash that executes nothing, after 1 s without an execute, or when the player takes a hit.
6. Bosses execute at 2 × radius, and a boss execute resets the combo — unless the hit lands inside the tighter perfect band (1.1 × radius) or kills it.
7. Every combo point slows the world logarithmically (`1 - 0.15·ln(1+combo)`) while the player keeps acting in real time. A hit taken **breaks the combo instead of dealing damage**, and the break also destroys hostile projectiles and cancels attacks.
8. Enemies flash white, get knocked back, and burst into shards when killed.
9. Touching an enemy costs 1 HP, the boss costs 2 (player has 5). At 0 HP the run ends in game over.
10. Clearing waves 1–3 (3 / 5 / 7 enemies, 2 s between waves) spawns the placeholder boss. Killing it wins the run.
11. 0.8 s after a win or loss the tree pauses and the HUD shows an overlay; press `R` to restart from wave 1.

## Controls

| Action | Binding |
| --- | --- |
| Move | WASD or arrow keys (`move_left/right/up/down`) |
| Aim | Mouse position (player faces cursor every physics frame) |
| Dash | Press LMB to dash; hold to wind the next dash (`dash`) |
| Restart | `R` (`restart`) — only on the win/lose overlay |

No pause menu or controller/touch input.

## Systems

### `entities/polygon/polygon.gd` — `Polygon` base
- `CharacterBody2D` that builds visuals at runtime: `Polygon2D` fill, `Line2D` outline, `CollisionPolygon2D`.
- Exports: `sides` (3–64), `radius`, `color`, `outline_width`. Vertices start at +X so `look_at()` aims the front at the target.
- Built once in `_ready()`; runtime export changes do not rebuild geometry.

### `entities/player/player.gd` — `Player` (extends `Polygon`)
- Triangle, radius 24, green; collision layer 2, mask 1. Group `&"player"`. Signals: `health_changed(current, maximum)`, `died`.
- Speed 300 px/s, mouse-facing aim (aim stays free while winding).
- Dash state machine: `READY` / `DASHING` (no charge state; pressing always dashes).
  - Wind: holding LMB fills `_wind` 0→1 over 0.9 s. It persists after release and is spent by the dash, so tap = 180 px and a held wind = up to 420 px. Movement is never slowed while winding.
  - Dash lasts 0.1 s; distance = 180→420 px, speed = distance / 0.1 (1800→4200 px/s), damage = 2→4.
  - Preview `Line2D` shows the stored wind distance; outline widens/brightens with wind; rising tone while holding.
  - Moves with `move_and_slide`, ends early on wall contact. Enemies get temporary collision exceptions so the player passes through them.
  - Hits are resolved geometrically as the dash travels, then **classified once when the dash ends**: ending inside the body (`d ≤ body_ratio·radius`) costs the player 1 HP (bypassing dash i-frames); crossing the body and ending within `execute_ratio·radius` executes for ×3 damage; everything else takes a normal hit.
  - Execution builds the combo (`+1`), which breaks on a non-executing dash, after 1 s without an execute, or when the player takes a hit. Emits `combo_changed(combo)`.
  - Combo = bullet time and shield: `Engine.time_scale = 1 - 0.15·ln(1+combo)` through `TimeControl`, while every player timer and its movement are compensated by `1 / bullet_time_factor`, so only the world slows. Any hit taken while combo > 0 is absorbed by the chain (no HP loss) and clears hostile projectiles via the `&"hostile_projectiles"` group hook.
  - Feel: hit-stop through `TimeControl.freeze` (hit 0.035 s, kill 0.060 s, hurt 0.050 s, halved in bullet time), trauma-based camera shake (`camera.offset`, trauma², 10 px max), zoom punch (`camera.zoom` lerped back to exactly 1.0), dash ghosts every 40 px (cap 8), floating damage numbers, and hurt knockback away from `from_position` plus a `hurt` signal for the HUD flash.
  - Aim and dash direction subtract `camera.offset` (`_aim_point()`) so shake never skews them.
  - I-frames for dash duration + 0.05 s; 0.12 s cooldown after dash ends. Noise whoosh on dash start.
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
- Execution data (exported, ratio-based): `execute_ratio` 1.5, `body_ratio` 1.0, `perfect_ratio` 0 (disabled), `execute_damage_scale` 3, `execute_breaks_combo` false.
- On death: emits `died`, spawns `DeathBurst`, plays impact through a temporary sibling player, then frees.

### `entities/enemy/boss.gd` — `Boss` (extends `Enemy`)
- Hexagon, radius 48, magenta, outline 3; HP 20, contact damage 2, speed 90 px/s, `knockback_scale` 0.35.
- Execution: `execute_ratio` 2.0 (48–96 px), `perfect_ratio` 1.1 (48–52.8 px, keeps the combo), `execute_breaks_combo` true.
- State machine in `_get_desired_velocity()`: `CHASE` (90 px/s) → `WINDUP` (0.45 s, telegraphed) → `CHARGE` (600 px/s, locked direction, 0.4 s, ends early on wall) → `RECOVER` (0.7 s). Triggers within 500 px after cooldown (1.0 s initial, 2.5 s after).
- Telegraphs via outline width/color and `body.scale` only; `body.color` stays for hit flash.

### `world/wave_director.gd` — `WaveDirector`
- Group `&"director"`. Signals: `wave_changed(wave, total)`, `boss_spawned(boss)`, `run_finished(victory)`.
- Waves of 3 / 5 / 7 enemies spawned at once on a 450–700 px ring around the player (evenly spaced + jitter), clamped to ±1400 with ≥320 px clearance fallback. 2 s intermission between waves.
- After wave 3 spawns boss ~650 px from player. Tracks alive enemies via `died`.
- Player `died` → defeat; boss `died` → victory. Emits `run_finished` then pauses the tree after 0.8 s.

### `ui/hud.gd` — `Hud` (CanvasLayer)
- Built in code; `process_mode = ALWAYS`, `layer = 10`, last in scene.
- HP pips (per `max_health`), `WAVE n / 3` label, `COMBO n` counter top-right (hidden at zero), boss bar driven by boss `health_changed`.
- Hurt flash: full-screen red `ColorRect` on a `CanvasLayer` at layer 9 (below the HUD), faded in real time from the player's `hurt` signal.
- End overlay (`VICTORY` / `GAME OVER` + "Press R to restart"). `R` unpauses and reloads the scene.
- Binds via groups (`&"player"`, `&"director"`) deferred; seeds initial wave from director state.

### `entities/fx/time_control.gd` — `TimeControl`
- Static single writer of `Engine.time_scale`: `bullet_time_factor * hitstop_factor`.
- `set_bullet_time`, `set_hitstop`, `reset()`. Static state survives scene reloads, so `reset()` is called by the director's `_begin()` and by the HUD on win/lose and `R` restart.
- `freeze(tree, seconds)` is real-time (ignores `time_scale`), extends overlapping freezes via a token, and restores the hit-stop factor to 1.0.

### `entities/fx/dash_ghost.gd` — `DashGhost`
- `Node2D` that draws a copy of the player's polygon at a fixed alpha and fades over 0.18 s in real time. Callers `configure()` then `add_child()`; joined to `&"dash_ghosts"` so the player can cap the count.

### `entities/fx/damage_number.gd` — `DamageNumber`
- Floating `Label` parented to the current scene (survives the enemy being freed), rises 46 px and fades over 0.5 s in real time.

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
| Dash | wind 0→1 over 0.9 s (spent on dash), distance 180–420, duration 0.1 s → speed 1800–4200, damage 2–4, cooldown 0.12 s, i-frames dash+0.05 s |
| Feel | input buffer 0.2 s, momentum carry 18 % (decay 2800), camera look-ahead 45 px walk / 90 px cap, smoothing 10 → 55 |
| Hit-stop | hit 0.035 s, kill 0.060 s, hurt 0.050 s (halved in bullet time), freeze factor 0.05 |
| Shake / zoom | trauma² decay 2.2/s, 10 px max offset; zoom punch 0.96, settles to 1.0 |
| FX | dash ghost every 40 px (cap 8, 0.18 s), damage number 0.5 s / 46 px rise |
| Enemy | radius 20, speed 140, HP 3, contact 1, knockback 260/900, execute 1.5·s, body 1.0·s |
| Waves | 3/5/7, ring 450–700, clamp ±1400, clearance 320, intermission 2 s |
| Boss | hexagon r48, HP 20, contact 2, speed 90, charge 600; windup 0.45, charge 0.4, recover 0.7, cooldown 2.5 s (1.0 initial), trigger 500 px, knockback ×0.35, execute 2.0·s, perfect 1.1·s |
| Combo | 1 s window, execute damage ×3, boss execute resets the chain |
| Bullet time | `1 - 0.15·ln(1+combo)`: 0.896 at combo 1, 0.792 at 3, 0.64 at 10 |
| End | overlay on end, pause after 0.8 s |

## Not implemented (gaps relevant to the plan)

- No combo damage multiplier (position is the reward instead).
- No feel polish beyond the core effects: no reticle, charge tiers, combo pop, bullet-time tint or audio layering (Stage 8).
- No rebalance pass (Stage 7), upgrades/inheritance, currency, level/arena pool, or score.
- No pause menu; `R` only on win/lose overlay.
- One enemy type + placeholder boss; dash-only attack (`projectile.gd` unreferenced), no hostile projectiles.
- No mobile/touch controls despite mobile renderer.
- No pickups. `Polygon` visuals not rebuildable at runtime.
- No tests/CI; verification is manual in-editor (headless smoke harnesses used previously and removed).
