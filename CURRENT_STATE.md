# polyguns — current functionality (as of 2026-11-19)

Snapshot of what the game actually does today, written as planning input. Complements `PLAN.md` (roadmap).

## How to run

- Godot 4.7 project, main scene `uid://cjmff0wlmncdk` = `world/testing_arena.tscn`.
- Physics runs at 120 ticks/s (`project.godot` → `physics/common/physics_ticks_per_second`).
- Renderer: `gl_compatibility` (desktop + mobile). No build/test/lint scripts, no autoloads.
- Verification = open project and run the main scene.

## Core loop (playable today)

1. Spawn at arena centre as a green triangle.
2. `WaveDirector` starts level 1, wave 1: 4 red pentagons (chasers) spawn 300–560 px around the player and chase.
3. Aim with the mouse. **Hold LMB to wind** — a crosshair shows where the dash will land, turning gold when that landing would execute and red when it would end inside an enemy. Release to dash toward the cursor. Movement is never slowed while winding.
4. The dash lasts 0.1 s. Wind maps distance 0→520 px through a smooth S-curve, so distance sets speed and damage (1–4). It passes through enemies, resolves hits along the travelled segment, and stops early on walls. I-frames cover the dash + 0.05 s.
5. A dash that crosses an enemy and ends within 2.5 × its radius **executes** it: ×3 damage and +1 combo. Ending the dash deep inside the enemy costs the player 1 HP instead. The combo breaks on any dash that executes nothing, after 1.5 s without an execute, or when the player takes a hit. **Landing assist** nudges the dash distance into the execute band when the landing is within 50 px of it and the path crosses the body.
6. Every combo point slows the world: the first execute snaps it to 0.80, then `0.80 - 0.10·ln(combo)` — while the player keeps acting in real time. A hit taken **breaks the combo instead of dealing damage**, and the break also destroys hostile projectiles.
7. Bosses execute at 2 × radius, and a boss execute resets the combo — unless the hit lands inside the tighter perfect band (1.1 × radius) or kills it.
8. Enemies flash white, get knocked back, and burst into shards when killed. Hits freeze time briefly, shake the camera, flash numbers, leave dash ghosts, and punch the zoom.
9. Wave 2 adds 2 spitters; wave 3 adds a lunger and a tank. Clearing wave 3 spawns the boss.
10. The boss chases, charges, and fires telegraphed volleys of slow projectiles that are executable combo fuel. At half HP it enters phase 2: the volley becomes a full ring and the charge returns faster. Killing it wins the level/run.
11. 0.8 s after a win or loss the tree pauses and the HUD shows an overlay; press `R` to restart from wave 1.

## Controls

| Action | Binding |
| --- | --- |
| Move | WASD or arrow keys (`move_left/right/up/down`) |
| Aim | Mouse position (player faces cursor every physics frame) |
| Dash | Hold LMB to wind, release to dash (`dash`) |
| Restart | `R` (`restart`) — only on the win/lose overlay |

No pause menu or controller/touch input.

## Systems

### `entities/polygon/polygon.gd` — `Polygon` base
- `CharacterBody2D` that builds visuals at runtime: `Polygon2D` fill, `Line2D` outline, `CollisionPolygon2D`.
- Exports: `sides` (3–64), `radius`, `color`, `outline_width`. Vertices start at +X so `look_at()` aims the front at the target.
- Built once in `_ready()`; runtime export changes do not rebuild geometry.

### `entities/executable/executable.gd` — `Executable` (extends `Polygon`)
- Shared contract for anything the dash can hit: `max_health`, `health`, `hit_flash_time`, `take_damage(amount, direction)`, `died(executable)` / `health_changed` signals, `_tick_flash(delta)`.
- Execution data (exported): `execute_ratio` 2.5, `perfect_ratio` 0 (disabled), `body_ratio` 0.6, `execute_damage_scale` 3, `execute_breaks_combo` false, `execute_floor` 0, `proximity_execution` false.
- `execute_range()` = `max(radius × execute_ratio, execute_floor)`; `body_range()` = `radius × body_ratio`.
- Hooks: `_on_damaged(direction)` and `_on_survived_hit()`.

### `entities/player/player.gd` — `Player` (extends `Polygon`)
- Triangle, radius 24, green; collision layer 2, mask 1. Group `&"player"`. Signals: `health_changed`, `died`, `combo_changed`, `hurt`.
- Speed 300 px/s, mouse-facing aim (aim stays free while winding, and the shake offset is subtracted so aim never drifts).
- Dash state machine: `READY` / `DASHING`, plus a `_winding` hold.
  - Press LMB → wind starts at 0 and fills over 0.9 s; release → dash, or buffer the release for 0.2 s if the cooldown is running. The wind is spent by the dash.
  - Distance = `dash_max_distance (520) × (w - strength·sin(2πw)/2π)`; `wind_curve_strength` 1.0 (0 = linear). Speed = distance / 0.1. Damage = `round(lerp(1, 4, curve))`.
  - Endpoint crosshair (`AimMarker`, `top_level`) sits where the dash will land: green normally, gold when the landing executes, red when it would end inside an enemy. Outline widens/brightens with wind; rising tone while holding.
  - Moves with `move_and_slide`, ends early on wall contact. Enemies get temporary collision exceptions so the player passes through them.
  - Hits are resolved geometrically as the dash travels, then **classified once at dash end**: body (`d ≤ 0.6·radius`, bypasses i-frames), execute (`d ≤ 2.5·radius` after crossing the body), or a normal hit. Projectiles use proximity instead of the endpoint.
  - Landing assist: on release, if the path crosses an enemy and the raw landing is within 50 px of the ideal `1.5·radius` gap, the distance is nudged into the band. The crosshair uses the assisted distance, so it never lies.
  - I-frames for dash duration + 0.05 s; 0.12 s cooldown; momentum carry 18 % decaying at 2800 px/s².
  - Presses/releases during dash/cooldown are buffered 0.2 s instead of dropped.
- Combo → bullet time and shield: the first execute snaps `Engine.time_scale` to 0.80, then `0.80 - 0.10·ln(combo)` via `TimeControl`; every player timer and movement is multiplied by `1 / bullet_time_factor`, so only the world slows. The combo window is 1.5 s. A hit taken while combo > 0 is absorbed and clears the chain.
- Feel: hit-stop via `TimeControl.freeze` (hit 0.035 s, kill 0.060 s, hurt 0.050 s, halved in bullet time), trauma-based camera shake (10 px), zoom punch to 0.96, dash ghosts every 40 px (cap 8), floating damage numbers, hurt knockback + red flash signal.
- Camera2D: smoothing 10 → 55 while dashing, movement look-ahead (45 px walking, 90 px cap), limits ±1536.
- HP 5, 0.7 s damage i-frames, red flash 0.12 s. `take_damage` returns true only when the hit landed (projectiles use this to decide whether to fizzle).

### `entities/enemy/enemy.gd` — `Enemy` (extends `Executable`)
- Pentagon, radius 20, red; layer 1/mask 1. Groups `&"enemies"` + `&"executables"`. `max_health` 3, contact 1.
- Speed 140 px/s, chases `&"player"`, faces the target while `face_target` is true.
- Movement hook `_get_desired_velocity(delta, player)`; knockback via `_on_damaged`.
- On death: shard burst plus an impact sound through a temporary sibling, then frees.

### `entities/enemy/spitter.gd` — `Spitter` (extends `Enemy`)
- Square, radius 18, pink; HP 3, speed 120.
- Holds a 320–420 px band (backs off when crowded, closes in when far, strafes otherwise).
- Every 1.6 s: 0.35 s outline telegraph → fires an `EnemyProjectile` at 240 px/s. This is the main source of combo fuel in normal waves.

### `entities/enemy/lunger.gd` — `Lunger` (extends `Enemy`)
- Triangle, radius 22, orange; HP 4, speed 110.
- `CHASE` → `WINDUP` (0.35 s, grows/flashes) → `LUNGE` (520 px/s, 0.35 s, facing locked) → `RECOVER` (0.6 s), 1.2 s cooldown, triggers within 420 px.

### `entities/enemy/tank.gd` — `Tank` (extends `Enemy`)
- Hexagon, radius 34, orange; HP 9, contact 2, speed 70, knockback ×0.2, outline 2.
- Survives one execute (6 damage), so it anchors combos rather than dying to them.

### `entities/enemy/boss.gd` — `Boss` (extends `Enemy`)
- Hexagon, radius 48, magenta, outline 3; HP 36, contact 2, speed 90, `knockback_scale` 0.35.
- Execution: `execute_ratio` 2.5, `perfect_ratio` 1.1, `body_ratio` 0.6, `execute_breaks_combo` true.
- Attacks: `CHASE` → `WINDUP` (0.45 s) → `CHARGE` (600 px/s, 0.4 s, ends on wall) → `RECOVER` (0.7 s), 2.5 s cooldown, triggers within 500 px.
- Volley every 6 s: 0.5 s telegraph → 6-projectile fan at 240 px/s. **Phase 2 at ≤ 50 % HP**: the volley becomes a 10-projectile ring and the charge cooldown drops to 1.8 s.

### `entities/projectile/enemy_projectile.gd` — `EnemyProjectile` (extends `Executable`)
- Small triangle, radius 6, HP 1, speed 260, damage 1, lifetime 3 s.
- No collision layers (never blocks the player). Groups `&"executables"` + `&"hostile_projectiles"`.
- Executes by dash proximity within `max(2·s, 40 px)`; a normal hit destroys it without combo. Only fizzles on a hit that actually landed, so dash i-frames don't eat it.

### `world/wave_director.gd` — `WaveDirector`
- Group `&"director"`. Signals: `wave_changed`, `level_changed`, `boss_spawned`, `level_cleared`, `run_finished`.
- One level. Waves are a cast table: 4 chasers / 3 chasers + 2 spitters / 3 chasers + 2 spitters + 1 lunger + 1 tank.
- Spawns all at once on a 300–560 px ring (even sectors + jitter), clamped to ±1400 with ≥240 px clearance fallback. 0.8 s intermission; hostile projectiles are cleared between waves.
- After wave 3 spawns the boss ~520 px from the player. Boss death → `level_cleared` → victory. Player death → defeat.
- Emits `run_finished` then pauses the tree after 0.8 s.

### `ui/hud.gd` — `Hud` (CanvasLayer)
- Built in code; `process_mode = ALWAYS`, `layer = 10`, last in scene.
- HP pips, `LEVEL n · WAVE n / 3` label, `COMBO n` counter top-right (hidden at zero), boss bar driven by boss `health_changed`.
- Hurt flash: full-screen red `ColorRect` on a `CanvasLayer` at layer 9, faded in real time from the player's `hurt` signal.
- End overlay (`VICTORY` / `GAME OVER` + "Press R to restart"). `R` unpauses, resets time, reloads the scene.

### `entities/fx/` — feedback
- `time_control.gd` (`TimeControl`): single writer of `Engine.time_scale` (bullet time × hit-stop), real-time `freeze()` with token-based restore, `reset()` on death, win, restart and director `_begin()`.
- `dash_ghost.gd`: faded player-polygon copies, real-time fade, group `&"dash_ghosts"` for the cap.
- `damage_number.gd`: floating `Label` parented to the current scene, rises 46 px and fades in real time.
- `death_burst.gd`: 10 shards flying outward, decelerating and fading over 0.35 s.

### `world/testing_arena.gd` — arena (named `Node2D` in scene)
- Draws arena at `z_index = -100`: 3072×3072 background, 64 px grid, cyan border.
- Hollow perimeter `StaticBody2D` (four walls, layer 1).

### `audio/sfx.gd` — `Sfx`
- Generates 16-bit mono WAVs at 22050 Hz at runtime.
- `cached_tone` / `cached_noise` memoise by parameter key; `varied_pitch(amount)` randomises per play.
- Charge tone for the wind, noise for dashes, hits and impacts.

### `entities/projectile/projectile.gd` — legacy, unreferenced
- Old player bullet kept on disk; nothing preloads or spawns it.

## Arena / scene layout

```
TestingArena (Node2D)
├── Player          (player.tscn)
├── Node2D          (arena grid/border/walls)
├── WaveDirector    (level table, waves, boss, win/lose)
└── HUD             (CanvasLayer, last)
```

## Numbers to tune

| Thing | Value |
| --- | --- |
| Arena | 3072×3072, 64 px grid, limits ±1536 |
| Player | radius 24, speed 300, HP 5, damage i-frames 0.7 s, physics 120 Hz |
| Dash | wind 0→1 over 0.9 s, distance `520·(w - sin(2πw)/2π)` (0–520), 0.1 s → speed 0–5200, damage 1–4, cooldown 0.12 s, i-frames dash+0.05 s, buffer 0.2 s |
| Bands | body 0.6·s, execute 2.5·s (enemy 12–50 px), boss perfect 1.1·s (29–53 px), projectile floor 40 px, assist ±50 px |
| Combo | 1.5 s window, execute ×3, boss execute resets, bullet time 0.80 then `0.80 - 0.10·ln(combo)` |
| Feel | momentum 18 % (decay 2800), camera lead 45/90 px, hit-stop 0.035/0.060/0.050 s, shake 10 px, zoom 0.96 |
| Enemy | radius 20, speed 140, HP 3, contact 1, knockback 260/900 |
| Spitter | radius 18, speed 120, HP 3, band 320–420, telegraph 0.35 s, fire 1.6 s, shot 240 px/s |
| Lunger | radius 22, speed 110, HP 4, windup 0.35, lunge 520×0.35, recover 0.6, cooldown 1.2, range 420 |
| Tank | radius 34, speed 70, HP 9, contact 2, knockback ×0.2 |
| Waves | 4 / 3+2 / 3+2+1+1, ring 300–560, clamp ±1400, clearance 240, intermission 0.8 s |
| Boss | hexagon r48, HP 36, contact 2, speed 90, charge 600; windup 0.45, charge 0.4, recover 0.7, cooldown 2.5 (1.8 in phase 2), trigger 500 px; volley 6 fan / 10 ring every 6 s (4.5 in phase 2), shot 240 px/s |
| End | overlay on end, pause after 0.8 s |

## Not implemented (gaps relevant to the plan)

- One level only; no progression, upgrades, inheritance, currency, score, or arena pool.
- No pause menu; `R` only on win/lose overlay.
- No secondary damage source (auto-fire) — Stage 6.
- No reticle/cursor hiding, charge tiers, combo pop, bullet-time tint, or audio layering — Stage 8.
- No mobile/touch controls despite mobile renderer.
- No pickups. `Polygon` visuals not rebuildable at runtime.
- No tests/CI; verification is manual in-editor (headless smoke harnesses used and removed).
