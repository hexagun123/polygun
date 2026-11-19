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

## Locked design — dash combat v5

Goal: instant response, technique-heavy, fast. The dash is the whole game.

### Dash + wind

- **Every LMB press dashes immediately.** Nothing is gated behind a charge, and movement is never slowed.
- Wind is *distance*, not a delay. It builds while LMB is held between dashes and persists, so taps poke and held wind reaches far.
- Fixed dash duration means distance **is** speed; damage rides on speed.

```
wind        0 → 1 over 0.9 s (persists between dashes)
duration    0.1 s fixed
distance    180 → 420 px
speed       1800 → 4200 px/s
normal hit  round(2 + 2·wind)         # 2 .. 4
execute     normal hit × 3            # 6 .. 12
cooldown    0.12 s, momentum carried through the landing
```

Note: partial wind only truly matters because the wind rate is slow (0.9 s). A 10 px execute band at the old 0.4 s rate was ~17 ms of hold precision; at 0.9 s it is ~37 ms.

### Execution bands

`s` = object radius (centre → edge). Ratios are **variables**, not constants, so future difficulty modes can scale them.

Resolve each object **once per dash**, geometrically (no per-frame sampling, no tunneling at 4200 px/s).

1. **Cross** — the dash segment must pass through the body (perpendicular distance from the object centre to the dash segment ≤ `s`). Otherwise the dash is at best a plain hit.
2. **End distance** — classify by `d` = distance from the dash endpoint to the object centre.

```
ENEMY  (s = 20)
  d ≤ s                 BODY        self-damage (combo shield absorbs first)
  s < d ≤ 1.5·s         EXECUTE     combo +1
  d > 1.5·s             normal hit

BOSS   (s = 48)
  d ≤ s                 BODY
  s < d ≤ 1.1·s         PERFECT     big damage, combo KEPT
  1.1·s < d ≤ 2·s       EXECUTE     big damage, combo RESETS
  d > 2·s               normal hit

PROJECTILE  (s ≈ 8)
  proximity during the dash within max(2·s, 56)   EXECUTE   combo +1
  any normal hit                                   destroys it, no combo
```

- Any object the dash passes through but does not execute takes a **normal hit** (damage from dash speed).
- **Self-damage** only when the dash *ends* with the player centre inside the object (`d ≤ s`). Passing through mid-dash is free.
- Projectiles are handled by proximity (crossing a tiny moving object is unrealistic). They can still be destroyed by normal hits for no combo.

### Combo + bullet time

- **+1 per execute** (enemy, boss perfect, projectile).
- **Any dash that doesn't execute breaks the combo immediately** (whiff = break).
- **1 s without an execute** breaks it.
- **Boss execute resets the combo** unless it is a perfect execute or the boss dies.
- **Taking a hit clears the combo and deals zero HP damage**; the clear also **destroys projectiles and cancels attacks** (only those).
- Normal hits never feed the meter.

Bullet time is derived from combo, not triggered:

```
time_scale = 1 - 0.15 · ln(1 + combo)     # 1 → 0.90, 5 → 0.73, 20 → 0.55
```

Logarithmic, no floor, player unaffected. Losing the combo snaps back to 1.0.

### Data-driven

`Enemy.execute_ratio`, `body_ratio`, `perfect_ratio` (boss only), `Projectile.execute_ratio` / `execute_floor`, plus a future global `execution_scale` multiplier for hard modes. Never hard-code the bands again.

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

- [x] Press-to-dash immediately, wind 0→1 over 0.9 s persisting between dashes, movement never slowed.
- [x] Fixed 0.1 s duration; distance 180→420; speed-based damage 2→4.
- [x] Charge state machine replaced by `_wind` + `READY` / `DASHING`.
- [x] Path-based resolution: hits resolve against the segment travelled each physics frame, not per-frame point queries.
- [x] Wind preview line shows the stored distance while held.

Acceptance: verified headless — press dashes instantly at ~1800 px/s with no charge delay; winding keeps full 300 px/s movement; full wind gives 4200 px/s and 4 damage; an enemy on the path takes the hit. Still needs a manual run to tune wind/distance feel.

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

### Stage 5 — Executables

- Enemy/boss projectiles and boss spawns as combo fuel.
- Every boss needs one mechanic that spawns executables.
- Projectile execute range with an absolute floor; normal hits destroy them without combo.

### Stage 6 — Secondary damage

- A second, non-dash damage source (roguelike auto-fire: orbiting fireballs etc.).
- **Must not feed the combo**, or the meter is free.

### Stage 7 — Pacing + rebalance

- Intermission 2.0 → 0.8 s, spawn ring 450–700 → 300–560, enemy speed 140 → 190.
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

- **Dash model B**: press = instant dash; holding winds the *next* dash; movement is never slowed.
- **Fixed 0.1 s dash duration**; wind changes distance, so distance sets speed and damage.
- **Execution is positional**: cross the object, then end within `ratio × radius`.
- **Regular enemies are executables**; the boss is a harder, more forgiving band (2·s) with a 1.1·s perfect band that keeps the combo.
- **Bosses are combo batteries**: their projectiles/spawns are executables; executing the boss body resets the combo.
- **Combo = execution chain only**; normal hits give damage but no meter.
- **Combo expiry**: any non-executing dash, 1 s without an execute, or taking a hit (which absorbs the damage instead).
- **Bullet time is combo-derived**, logarithmic (`1 - 0.15·ln(1+combo)`), player unaffected.
- **Projectiles**: proximity execute with a floor; normal hits destroy them for no combo.
- **Everything ratio-based and exported**, ready for future difficulty modes.
- A second auto-fire damage source is planned, and it must not build combo.

## Handoff

- Design is locked; implementation starts at Stage 0.
- Keep `.gd.uid` sidecars; ask the user to make UID-sensitive editor changes.
- After each stage: update `CURRENT_STATE.md`, show the diff, and ask before committing.
