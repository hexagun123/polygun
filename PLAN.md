# polyguns — feature plan (updated 2026-11-19)

## Status / constraints

- Current work is tracked in `CURRENT_STATE.md`; this file holds the **locked design** and the staged roadmap.
- Repo instructions (`AGENTS.md`): concise responses; Godot 4.x GDScript only; edit small fixes directly, use sub-agents for non-overlapping multi-file work; ask the user to make `uid://` / `.tscn` changes in the editor; check code quality (paths, types) after features; read `CURRENT_STATE.md` when a feature lands.
- No build/test/lint/CI scripts. Verification = open the project in Godot and run the main scene. Headless Godot 4.7.2 has been used for smoke checks.
- Main scene: `uid://cjmff0wlmncdk` = `world/testing_arena.tscn`. Renderer `gl_compatibility`. No autoloads.
- Scripts have `.gd.uid` sidecars — preserve them.
- Input actions: `move_left/right/up/down`, `dash` (LMB), `restart` (R).

## Progress

Historical and superseded (see git history and `CURRENT_STATE.md` for detail):

- **Shooting milestone** — gun, projectiles, chaser enemy, feedback. The gun was removed; `entities/projectile/projectile.gd` is orphaned.
- **Stage A — dash core** — charge/release dash, pass-through damage, charge preview, generated SFX.
- **Stage B — wave slice** — 3/5/7 waves, placeholder boss, HUD, game over / victory / `R` restart.

The dash combat design was reworked after playtesting: the old charge-up read as laggy. Everything below replaces the old Stage A/F/C/D plan.

- **Stage 0 — Responsiveness** — ✅ done (headless-verified; camera feel still needs a manual run).
- **Stage 1 — Instant dash + wind** — ✅ done (headless-verified; wind feel still needs a manual run).
- **Stage 2 — Execute + combo** — ✅ done (headless-verified; band feel still needs a manual run).
- **Stage 3 — Bullet time + combo shield** — ✅ done (headless-verified; feel still needs a manual run).
- **Stage 4 — Feel pass (core 6)** — ✅ done (headless-verified; feel still needs a manual run).
- **Tuning pass — wind curve + execution B** — ✅ done (headless-verified).
- **Section — Level one** — ✅ done (headless-verified; needs a playtest).

## Locked design — dash combat v5

Goal: instant response, technique-heavy, fast. The dash is the whole game.

### Dash + wind

- **Hold LMB to wind, release to dash.** Movement is never slowed, and a release during cooldown is buffered so it fires the instant the cooldown ends.
- Wind is *distance*, not a delay. Aim feedback is an endpoint crosshair: it shows where the dash will land, turns gold when that landing would execute, and red when it would end inside a body.
- Fixed dash duration means distance **is** speed; damage rides on speed.
- **No floor.** The dash starts at 0 px and eases to a roof of 520 px along a smooth S-curve, so close-range executes are possible and max wind settles instead of jumping.

```
wind        0 → 1 over 0.9 s, spent by the dash (new hold each time)
curve       f(w) = w - sin(2πw)/(2π)      # zero at both ends, sensitive in the middle
duration    0.1 s fixed
distance    520 · f(w)                     # 0 .. 520 px
speed       distance / 0.1                 # 0 .. 5200 px/s
normal hit  round(1 + 3·f(w))              # 1 .. 4
execute     normal hit × 3                 # 3 .. 12
cooldown    0.12 s, momentum carried through the landing
```

Tuning hooks: `dash_max_distance` (520) and `wind_curve_strength` (1.0; 0 = linear). A future automated-weapon build can flatten the curve without touching mechanics.

### Execution bands

`s` = object radius (centre → edge). Ratios are **variables**, not constants, so future difficulty modes can scale them.

Resolve each object **once per dash**, geometrically (no per-frame sampling, no tunneling at 4200 px/s).

1. **Cross** — the dash segment must pass through the body (perpendicular distance from the object centre to the dash segment ≤ `s`). Otherwise the dash is at best a plain hit.
2. **End distance** — classify by `d` = distance from the dash endpoint to the object centre.

```
ENEMY  (s = 20)          body_ratio 0.6, execute_ratio 2.5
  d ≤ 0.6·s             BODY        self-damage (combo shield absorbs first)
  0.6·s < d ≤ 2.5·s     EXECUTE     combo +1        (12–50 px: 38 px window)
  d > 2.5·s             normal hit

BOSS   (s = 48)          body_ratio 0.6, execute_ratio 2.5, perfect_ratio 1.1
  d ≤ 0.6·s             BODY
  0.6·s < d ≤ 1.1·s     PERFECT     big damage, combo KEPT   (29–53 px)
  1.1·s < d ≤ 2.5·s     EXECUTE     big damage, combo RESETS
  d > 2.5·s             normal hit

PROJECTILE  (s ≈ 6)      proximity_execution, execute_floor 40
  path within 40 px     EXECUTE     combo +1
  any normal hit        destroys it, no combo
```

**Landing assist** (the thing that makes chains possible): on release, if the dash path already crosses an enemy and the raw landing is within 50 px of that enemy's execute band, the distance is nudged so the landing sits at `1.5·s` past its centre. Aim and rough range still decide the hit; a ~20 ms slip in hold length no longer kills the chain. The crosshair uses the assisted distance, so it never lies.

- Any object the dash passes through but does not execute takes a **normal hit** (damage from dash speed).
- **Self-damage** only when the dash *ends* with the player centre inside the object (`d ≤ s`). Passing through mid-dash is free.
- Projectiles are handled by proximity (crossing a tiny moving object is unrealistic). They can still be destroyed by normal hits for no combo.

### Combo + bullet time

- **+1 per execute** (enemy, boss perfect, projectile).
- **Any dash that doesn't execute breaks the combo immediately** (whiff = break).
- **1.5 s without an execute** breaks it.
- **Boss execute resets the combo** unless it is a perfect execute or the boss dies.
- **Taking a hit clears the combo and deals zero HP damage**; the clear also **destroys projectiles and cancels attacks** (only those).
- Normal hits never feed the meter.

Bullet time is derived from combo, not triggered, in two tiers — the first execute pops to a clearly felt slow, then each further point adds a smaller logarithmic step:

```
time_scale = 1.0                              combo 0
           = 0.80                             combo 1
           = 0.80 - 0.10 · ln(combo)          combo ≥ 2   # 3 → 0.69, 5 → 0.64, 10 → 0.57
```

Player unaffected. Losing the combo snaps back to 1.0.

### Data-driven

All objects the dash can hit share `Executable` (`entities/executable/executable.gd`, extends `Polygon`): `radius`, `health`, `take_damage`, `execute_ratio`, `body_ratio`, `perfect_ratio`, `execute_damage_scale`, `execute_breaks_combo`, `execute_floor`, `proximity_execution`. `Enemy` and `EnemyProjectile` extend it, and the player resolves one group (`&"executables"`). Everything stays exported for future difficulty scaling.

## Roadmap

### Stage 0 — Responsiveness (done)

Millisecond-level work that is independent of the design above; these all survive later stages.

- [x] Input buffer (0.2 s) so presses made during cooldown are never eaten.
- [x] Momentum carry on dash end instead of a hard stop (no `velocity = ZERO` brake).
- [x] Camera look-ahead along the movement/dash direction, with speed-boosted smoothing.
- [x] Physics at 120 Hz (`project.godot`).
- [x] Shared cached audio streams + per-play pitch variance (no per-spawn WAV generation).
- [ ] Reticle / OS cursor hiding (deferred to polish if it fights the HUD).

Acceptance: verified headless — a press during cooldown starts a charge once the cooldown ends, dash end carries 217 px/s of momentum on a tap, and the project runs clean at 120 ticks/s. Camera feel still needs a manual run.

### Stage 1 — Instant dash + wind (done)

- [x] Hold to wind, release to dash; wind 0→1 over 0.9 s and is spent by the dash; movement never slowed.
- [x] Fixed 0.1 s duration; distance 0→520 through the S-curve; speed-based damage 1→4.
- [x] Charge state machine replaced by `_wind` + a `_winding` hold + `READY` / `DASHING`.
- [x] Path-based resolution: hits resolve against the segment travelled each physics frame, not per-frame point queries.
- [x] Endpoint crosshair replaces the distance line and previews execution (gold) and body self-damage (red).

Acceptance: verified headless — holding does not dash on its own; the crosshair is visible and gold exactly when the landing executes (confirmed by the enemy dying); the wind is spent by the dash. Still needs a manual run to tune wind/distance feel.

### Stage 2 — Execute + combo

- Ratio bands on `Enemy` (and later `Projectile`), body self-damage at dash end, crossing requirement.
- Combo meter, whiff break, 1 s expiry, boss perfect band, HUD combo counter.
- Keep the temporary collision exceptions and i-frames for the dash itself (body damage is a separate check, not a physics hit).

Acceptance: crossing + ending in the band executes; ending outside the band is a normal hit; ending inside costs HP (or combo); the boss perfect band keeps the combo; whiff breaks it.

### Stage 2 — Execute + combo (done)

- [x] Ratio bands on `Enemy` (`execute_ratio`, `perfect_ratio`, `body_ratio`, `execute_damage_scale`, `execute_breaks_combo`).
- [x] Body self-damage when the dash ends inside an enemy (bypasses the dash's i-frames).
- [x] Combo meter (+1 per execute), whiff break, 1 s expiry, boss perfect band, boss reset on a normal execute.
- [x] HUD `COMBO n` counter.
- [x] Hit resolution moved to dash end; per-frame path tracking only records closest approach.

Acceptance: verified headless — execute kills a 3 HP enemy and adds combo; a non-executing dash breaks it; ending inside costs 1 HP and clears the combo; the boss perfect band keeps the combo while a normal boss execute resets it (6 damage each). Still needs a manual run.

### Stage 3 — Bullet time

- `TimeControl` authority (single writer of `Engine.time_scale`): combo slow + hit-stop factors.
- Player compensates with `delta / bullet_time_factor` only.
- Combo shield: a hit clears the combo, deals no damage, destroys projectiles and cancels attacks.
- Reset to 1.0 on death, win, restart and scene load.

### Stage 3 — Bullet time (done)

- [x] `TimeControl` authority owns `Engine.time_scale` (bullet time × hit-stop, hit-stop reserved for Stage 4).
- [x] Combo-derived logarithmic slow, player compensated with `1 / bullet_time_factor` for timers and movement.
- [x] Combo shield: a hit clears the combo, deals no damage, destroys hostile projectiles and cancels attacks.
- [x] Reset to 1.0 on death, win, `R` restart and director `_begin()`.

Acceptance: verified headless — combo 1/3 produce 0.896/0.792 time scale; the player still crosses 150 px in 0.5 s real time at 0.79; a hit with a combo costs no HP but clears the chain; without a combo the same hit costs 1 HP. Still needs a manual run.

### Stage 4 — Feel-lite (core 6) (done)

- [x] Hit-stop through `TimeControl` (hit 0.035 s, kill 0.060 s, hurt 0.050 s), halved in bullet time.
- [x] Screen shake: trauma model on the camera `offset`, real-time decay, aim corrected for the shake.
- [x] Dash ghosts every 40 px, capped at 8, faded in real time.
- [x] Floating damage numbers parented to the scene, normal vs execute colours.
- [x] Zoom punch on kill, always settling to exactly 1.0.
- [x] Hurt feedback: knockback away from `from_position`, red full-screen flash below the HUD, shake + hit-stop.

Acceptance: verified headless — time scale dipped to 0.04 on a kill then restored; zoom hit 0.964 and returned to 1.0; ghosts capped at 4 for a tap dash and faded; damage numbers spawned and cleared; shake settled to zero; hurt fired the signal, cost 1 HP and knocked away; death reset time to 1.0. Still needs a manual run.

### Tuning pass — wind curve + execution B (done)

- [x] Remove `dash_min_distance`; distance = `dash_max_distance · (w - sin(2πw)/(2π))` with `wind_curve_strength` export.
- [x] Damage scales with the curve: `round(1 + 3·f(w))`.
- [x] `body_ratio` 0.6 for enemy and boss; `execute_ratio` 2.5; boss `perfect_ratio` stays 1.1.
- [x] Landing assist: nudge the landing into the band when it is within 50 px and the path crosses the body.
- [x] Combo window 1.0 → 1.5 s.
- [x] Two-tier bullet time: 0.80 at combo 1, then `0.80 - 0.10·ln(combo)`.
- [x] Aim marker, `_start_dash` and damage all read the same curve + assist helper.

Acceptance: verified headless — 0/260/520 px at zero/half/full wind, a 59 px near-miss is assisted to a 30 px execute, a 25 px landing executes, first execute snaps the world to 0.80, combo 3 reaches 0.69, and the marker agrees with the outcome.

### Section — Level one (done)

One arena, one fully tuned level, no upgrades or progression. The level table exists so a second level is data-only later.

1. **`entities/executable/executable.gd`** — `class_name Executable extends Polygon` with health, flash, `take_damage`, `died` / `health_changed`, `execute_range()` / `body_range()`, the ratio exports, `execute_floor` and `proximity_execution`. `Enemy extends Executable`; the player resolves group `&"executables"`.
2. **Projectile** — `EnemyProjectile extends Executable`: r 6, HP 1, speed 260, damage 1, lifetime 3 s, no collision layer, joins `&"hostile_projectiles"` + `&"executables"`, executes by proximity within 40 px.
3. **Cast** — Spitter (r18, HP 3, holds 320–420 px, 0.35 s telegraph, fires every 1.6 s), Lunger (r22, HP 4, windup → 520 px/s lunge → recover), Tank (r34, HP 9, knockback ×0.2, contact 2).
4. **Boss** — HP 36; fan volley every ~6 s (0.5 s telegraph, 5–7 projectiles at 240 px/s) alongside the charge; phase 2 at ≤50 % HP turns the volley into a full ring and shortens the charge cooldown.
5. **Level shape** — waves 4 chasers / 3 chasers + 2 spitters / 3 chasers + 2 spitters + 1 lunger + 1 tank; all at once, ring 300–560 px, intermission 0.8 s.
6. **Flow** — boss death → clear → victory (one level). Director gains a `level` index and a `LEVEL n` HUD line.

Acceptance: verified headless — spitters fire executable projectiles, a dash executes one by proximity, all three roles spawn in their waves, the boss volleys 6 in phase 1 and 10 in phase 2, the level table spawns the planned counts, and the main scene runs clean. Needs a playtest.

### Stage 6 — Secondary damage

- A second, non-dash damage source (roguelike auto-fire: orbiting fireballs etc.).
- **Must not feed the combo**, or the meter is free.

### Stage 7 — Pacing + rebalance

- Pacing (intermission, spawn ring) now ships with the level section.
- Enemy/boss HP and timings around the new damage numbers.

### Stage 8 — Polish

- Audio layering, reticle, charge tiers, speed lines, combo HUD pop, bullet-time tint.
- Optional arena template pool.

## Verification

- Manual: run the main scene in Godot and play the dash loop. No CLI tests exist.
- Headless checks for script errors are acceptable for regressions, but game feel must be played.

## User's vision

- Fast-paced geometry game with good SFX/FX — *instantly* responsive, not "fast on paper".
- Souls-like arena: ~3 waves then a boss per level.
- Roguelike variant: levels from templates; inherit variant: upgrades persist across runs (upgrades only, no persistent player node).
- Placeholder/generated SFX until art direction exists.

## Decisions locked in this discussion

- **Dash model B**: hold = wind, release = dash; movement is never slowed (revised after playtesting — press-to-dash felt wrong).
- **Fixed 0.1 s dash duration**; wind changes distance, so distance sets speed and damage.
- **Execution is positional**: cross the object, then end within `ratio × radius`.
- **Regular enemies are executables**; the boss is a harder, more forgiving band (2.5·s) with a 1.1·s perfect band that keeps the combo.
- **Landing assist** nudges the landing into the execute band when the path already crosses the enemy, so hold precision stops gating chains.
- **Bosses are combo batteries**: their projectiles/spawns are executables; executing the boss body resets the combo.
- **Combo = execution chain only**; normal hits give damage but no meter.
- **Combo expiry**: any non-executing dash, 1.5 s without an execute, or taking a hit (which absorbs the damage instead).
- **Bullet time is combo-derived**, two-tier: 0.80 at combo 1, then `0.80 - 0.10·ln(combo)`; player unaffected.
- **Projectiles**: proximity execute with a floor; normal hits destroy them for no combo.
- **Everything ratio-based and exported**, ready for future difficulty modes.
- A second auto-fire damage source is planned, and it must not build combo.

## Handoff

- Design is locked; implementation starts at Stage 0.
- Keep `.gd.uid` sidecars; ask the user to make UID-sensitive editor changes.
- After each stage: update `CURRENT_STATE.md` and commit.
