# polyguns — feature plan (updated 2026-11-19)

## Status / constraints

- Current work is tracked in `CURRENT_STATE.md`; this file holds the roadmap and the finalized dash plan.
- Repo instructions (`AGENTS.md`): concise responses; change mode uses sub-agents except for small fixes; Godot 4.x GDScript only; ask the user to make risky `uid://` changes in the Godot editor; verify broken paths and type errors after features.
- No build/test/lint/CI scripts. Verification means opening the project in Godot and running the main scene.
- Main scene: `uid://cjmff0wlmncdk` = `world/testing_arena.tscn`. Renderer is `gl_compatibility`. No autoloads; `autoload/` and `ui/` are empty placeholders.
- Input actions exist in `project.godot` (`move_left/right/up/down`, `dash` = LMB).
- Scripts have `.gd.uid` sidecars. Preserve UIDs; have the user change UID-sensitive data in the editor.

## Progress — 2026-11-19

Shooting milestone is implemented:

- Mouse aim + hold-to-fire (`fire` = LMB), `Projectile` moved by raycast so it can't tunnel through arena walls; generated shot tone.
- `Enemy` chaser (5-sided, 3 HP, layer 1) chases the `&"player"` group and deals contact damage.
- Hit feedback: white flash, generated noise impact, directional knockback; death shard burst via `DeathBurst`.
- Minimal player health: 3 HP, 0.7 s damage cooldown, red flash, respawn at origin.
- `EnemySpawner` in `testing_arena.tscn` spawns 3 enemies at 260–700 px from origin.
- Generated audio moved to `audio/sfx.gd` (`Sfx.make_tone`, `Sfx.make_noise`).
- Verified with headless Godot 4.7.2: project runs clean, and a smoke harness confirmed projectile damage, enemy death + burst, and player invulnerability. Still run the main scene once to tune feel.

Dash core (Stage A) is implemented:

- LMB is now `dash`: hold to charge (movement ×0.35, growing preview + outline), release to dash toward the cursor; distance/speed/damage scale with charge, 0.25 s cooldown, i-frames for the dash + 0.05 s.
- The dash passes through enemies (temporary collision exceptions) and damages each one once per dash via a circle shape query; walls end the dash early.
- Generated charge tone + release whoosh; tap still gives the minimum dash.
- Gun code removed from `player.gd`; `projectile.gd` kept on disk unreferenced. `Enemy` now joins `&"enemies"` for the dash collision exceptions.
- Verified with a headless Godot 4.7.2 smoke harness: damage once per dash, pass-through, wall stop, i-frames, charge slow/preview, no projectiles. Still run the main scene once to tune feel.

Stage B (wave slice) is implemented:
- `WaveDirector` (`world/wave_director.gd`) runs waves of 3 / 5 / 7 enemies on a 450–700 px ring around the player (clamped to ±1400, 2 s intermission), then spawns the boss; player death = game over, boss death = victory, and the tree pauses 0.8 s after either end.
- Placeholder `Boss` (`entities/enemy/boss.gd`) chases → winds up → charges → recovers, telegraphing via outline/scale.
- Player HP is 5 and now emits `health_changed` / `died` instead of respawning.
- `Enemy` gained `died`, `health_changed`, `knockback_scale`, `face_target` and the `_get_desired_velocity()` hook.
- Code-built HUD (`ui/hud.gd`) with HP pips, wave counter, boss bar and win/lose overlay; `R` restarts.
- Verified with a temporary headless Godot 4.7.2 harness: waves 3/5/7 spawn and advance, boss stats/state machine (windup → 600 px/s charge → recover), victory, game over, pause and `R` restart; the real scene also ran clean headless. Still run the main scene once to tune feel.

Next step: Stage C — combo, then Stage D — bullet time.

## Finalized plan — dash combat (2026-11-19)

Decisions:

- Dash is the main attack; the gun is removed for now (`projectile.gd` kept on disk, unreferenced).
- Holding to charge slows movement to 35%; tap = minimum dash.
- Bullet time slows the world but not the player.
- Dash core ships before the wave slice; combo and bullet time come after.

### Stage A — dash core — ✅ completed (2026-11-19)

Charge → dash:

- [x] Hold LMB (`dash` action) to charge over 1.0 s; release to dash toward the cursor.
- [x] Distance 150 → 520 px, speed 1200 → 1900 px/s, damage 2 → 3.
- [x] 0.25 s cooldown after the dash ends; i-frames during the dash + ~0.05 s.
- [x] Movement at 35% speed while charging; aim stays free.

Movement and damage:

- [x] `move_and_slide` at dash velocity; end the dash early on wall contact.
- [x] Per physics frame, a circle shape query (layer 1, player radius + 4) damages each enemy once per dash via a hit set.
- [x] Contact damage ignored during i-frames.

Readability:

- [x] Charge preview `Line2D` from the player toward the cursor, length = dash distance.
- [x] Outline width/colour grows with charge (set `outline.width` / `default_color` directly).
- [x] SFX (rising `pitch_scale` on a generated tone, noise whoosh on release).
- [ ] Optional dash trail (`entities/fx/dash_trail.gd` not added).

Gun removal:

- [x] Remove `ProjectileScript`, fire cooldown/muzzle/audio and `_fire()` from `player.gd`.
- [x] Rename the `fire` input action to `dash` (LMB) in `project.godot`.

Stage A files: `entities/player/player.gd`, `project.godot`, `audio/sfx.gd` (no dash trail).

Acceptance (verified with a temporary headless Godot 4.7.2 harness; game feel still needs a manual run): [x] charge preview grows and movement slows; [x] release dashes; [x] each enemy takes damage once per dash; [x] walls stop the dash; [x] i-frames block contact damage; [x] tap gives a min dash; [x] no projectile spawns; [x] no script errors.

### Stage B — wave slice — ✅ completed (2026-11-19)

- [x] 3 / 5 / 7 enemies per wave, spawned at once on a 450–700 px ring around the player, clamped inside the arena (±1400); 2 s intermission.
- [x] Player HP 5; death = game over; clearing wave 3 spawns the boss; boss death = win.
- [x] Placeholder boss: radius 48, HP 20, contact damage 2, knockback scale 0.35×.
- [x] Boss behaviour: `CHASE` (90 px/s) → `WINDUP` (0.45 s) → `CHARGE` (~600 px/s, locked direction, 0.4 s, ends early on wall) → `RECOVER` (0.7 s), every ~2.5 s when within ~500 px. Telegraphed via outline/scale, not `body.color`.
- [x] `R` restarts (`reload_current_scene()` after setting `paused = false`).
- [x] HUD: HP pips, `Wave n/3`, boss HP bar, win/lose overlay (`process_mode = ALWAYS`).
- [x] Enemy additions: `died` + `health_changed` signals, `&"enemies"` group (already present), knockback resistance, `_get_desired_velocity()` hook; `boss.gd extends Enemy` overrides only that hook for behaviour.
- [x] Wiring via groups (`&"player"`, `&"director"`); HUD last in the scene. `EnemySpawner` removed.

Stage B files: `entities/enemy/enemy.gd`, `entities/enemy/boss.gd`, `entities/player/player.gd`, `world/wave_director.gd`, `ui/hud.gd`, `world/testing_arena.tscn`, `project.godot` (`restart` action).

Acceptance (verified with a temporary headless Godot 4.7.2 harness, then removed; game feel still needs a manual run): [x] waves 1–3 spawn 3/5/7 enemies and advance after 2 s; [x] spawns stay on the ring/clamped; [x] boss spawns after wave 3 with the planned stats; [x] boss windup/charge/recover runs and charges at 600 px/s; [x] boss death = victory overlay + pause; [x] player death = game over overlay + pause; [x] `R` reloads the scene at wave 1; [x] no script errors in the main scene.

### Stage C — combo

- +1 per enemy hit by a dash (once per enemy per dash).
- Resets after 2.5 s without a hit or when the player takes damage.
- Damage multiplier `1 + 0.1 × combo`, capped at 2×.
- HUD combo counter.

### Stage D — bullet time

- Triggers at combo ≥ 3; lasts 3 s; hits refresh; ending resets the combo so it can't chain forever.
- `Engine.time_scale = 0.35`; player compensates with `delta / time_scale` for movement, charge and dash timers.
- Charge rate ×2, damage ×1.5, HUD tint.
- Reset `time_scale` to 1.0 on death, win and scene reload.
- Camera smoothing also slows; boost smoothing temporarily if the player outruns the camera.

### Stage E — rebalance

- Tune enemy/boss HP and timings around dash damage; optionally bring the gun back as a secondary/unlock.

### Verification

- Manual, in Godot: run the main scene, play Stage A against the existing 3 enemies, then the wave slice, then combo/bullet time. No CLI tests exist.

## User's vision

- Fast-paced geometry shooter with nice SFX so it feels entertaining.
- Souls-like fighting arena: different levels, each with roughly 3 waves then a final boss.
- Roguelike variant: spawn a few levels from templates.
- Inherit variant: one player instance always spawned regardless of death, with all upgrades inherited.
- Later clarification: "inherit" means **upgrades only** persist, not a persistent `Player` node/scene.

## Decisions locked in this discussion

- First target: **combat core** (shooting + feedback) before choosing a progression mode.
- Inheritance semantics: **upgrades/stats only** across deaths or runs; no persistent player node.
- "Levels" = **a pool of random waves**; enemies and bosses drawn from a random pool. Reuse the existing arena geometry initially; no new map templates needed yet.
- First playable milestone: **shooting + feedback**.
- SFX: **placeholder/generated** for now.

## Completed milestone: shooting + feedback (superseded by the dash plan)

Outcome in `world/testing_arena.tscn`:

- Player aims with the mouse (already implemented) and fires fast geometric projectiles.
- A basic enemy takes damage and dies.
- Hits produce visible feedback and generated/placeholder sound.
- No waves, bosses, upgrades, or level pools yet.

Original touch points (implemented):

- `entities/player/player.gd` — add fire input/cooldown; preserve `_ready()` order (`sides`, `radius`, `color` before `super._ready()`).
- New projectile scene/script under `entities/`; create in Godot if UID-sensitive.
- New basic enemy scene/script, likely reusing the `Polygon` base for geometry/collision.
- Hit feedback (flash/particles/shake) plus `AudioStreamPlayer` with generated tones.

## Later phases

1. ✅ Dash core — charge/release dash is the main attack; gun removed for now.
2. ✅ Wave slice — 3 waves + placeholder boss (chaser + charge) + HUD + game over/restart.
3. Combo + bullet time — combo scaling, then world-slowing bullet time.
4. Enemy/boss pools; upgrade-only inheritance — stats/unlocks persist across runs; no persistent `Player` node.
5. Polish — better SFX, screen shake/particles; optional authored arena-template pool.

## Resolved questions

- Shooting milestone choices (hold-to-fire, one projectile, chaser enemy, flash + knockback + generated tones) are implemented.
- Remaining design questions are resolved in the finalized dash plan above.

## Handoff

- [x] Stage A implemented with Godot 4.x GDScript and verified headless; play the main scene once to tune feel.
- [x] Stage B implemented and verified headless (waves 3/5/7 → boss → win/lose, HUD, R restart). Play it once to tune enemy/boss numbers.
- Keep `.gd.uid` sidecars; ask the user to make UID-sensitive changes in the editor.
- Next: Stage C (combo), then Stage D (bullet time).
