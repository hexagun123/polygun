# polyguns — next feature plan (saved 2026-11-18)

## Status / constraints

- Another instance is currently fixing bugs; do not overlap until it finishes. Observed state at save time: `M project.godot`, untracked `AGENTS.md`, `.agents/`, `skills-lock.json`; no source-file bug fixes had landed yet.
- Read-only analysis was requested while that instance worked; this plan file is the only artifact created from the discussion.
- Repo instructions (`AGENTS.md`): concise responses; change mode uses sub-agents except for small fixes; Godot 4.x GDScript only; ask the user to make risky `uid://` changes in the Godot editor; verify broken paths and type errors after features.
- No build/test/lint/CI scripts. Verification means opening the project in Godot and running the main scene.
- Main scene: `uid://cjmff0wlmncdk` = `world/testing_arena.tscn`. Renderer is `gl_compatibility`. No autoloads; `autoload/` and `ui/` are empty placeholders.
- `Player` reads `move_left`, `move_right`, `move_up`, `move_down`, but `project.godot` has no `[input]` section. Confirm/add those plus a fire action.
- Scripts have `.gd.uid` sidecars. Preserve UIDs; have the user change UID-sensitive data in the editor.

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

## Immediate milestone: shooting + feedback

Outcome in `world/testing_arena.tscn`:

- Player aims with the mouse (already implemented) and fires fast geometric projectiles.
- A basic enemy takes damage and dies.
- Hits produce visible feedback and generated/placeholder sound.
- No waves, bosses, upgrades, or level pools yet.

Tentative touch points (confirm after the bug-fix instance lands):

- `entities/player/player.gd` — add fire input/cooldown; preserve `_ready()` order (`sides`, `radius`, `color` before `super._ready()`).
- New projectile scene/script under `entities/`; create in Godot if UID-sensitive.
- New basic enemy scene/script, likely reusing the `Polygon` base for geometry/collision.
- Hit feedback (flash/particles/shake) plus `AudioStreamPlayer` with generated tones.
- `project.godot` input actions — coordinate with the bug-fix instance.

## Later phases

1. Enemy/boss pools + wave director — random wave picks; enemies and bosses drawn from pools; same arena.
2. Upgrade-only inheritance — stats/unlocks persist across runs; no persistent `Player` node.
3. Polish — better SFX, screen shake/particles, HUD, tuning.
4. Optional authored arena-template pool only if the user later wants new maps.

## Open questions before implementation

- Fire control: hold-to-fire or click? Projectile speed, lifetime, pierce?
- Enemy baseline: melee chaser, ranged attacker, or both? HP: one-shot or small pool?
- Hit feedback: flash, knockback, particles, screen shake, tones — which ones?
- Placeholder SFX: code-generated tones or tiny imported clips?
- Upgrade modeling: Godot `Resource`s now or deferred?
- First slice scope: one projectile/enemy type or more?

## Handoff

- Re-check `git status` and source files after the other instance finishes; this plan was written before its fixes landed.
- Confirm the open questions, then implement with Godot 4.x GDScript and verify in the editor.
