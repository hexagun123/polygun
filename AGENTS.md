# AGENTS.md

## Responses

- Keep the response to the point and concise - unless the user asks otherwise

## Planning mode

- always ask clarifying questions
- never assume designs, tech stack or features

## change / edit mode

- edit directly for small fixes, assign sub-agents for tasks that have no-overlaps, such as 2 seperate files.
- don't over engineer code that is not nessesary.
- upon completing a fix or a feature, check the diff and ask the user for whether to commit or not
- Read CURRENT_STATE.md after finishing feature or fixing bugs, update if it differs from current game state.
- Use Godot 4.x GDScript only
- if something is risky to change, such as possible breaks in "uid://", ask the user to change it in the godot editor
- Ask the user to open Godot when uid:///.tscn edits or final playtesting require it.
- always check for code quality, including broken path and type errors after completing features

## git

- ensure commit messages are concise but enough to convey the change

## Project shape

- Godot 4.x 2D game (working `project.godot` targets 4.7); main scene is `uid://cjmff0wlmncdk` = `world/testing_arena.tscn`.
- No build, test, lint, or CI scripts exist. Verification means opening the project in Godot and running the main scene; don't invent CLI commands.
- Renderer is `gl_compatibility` on both desktop and mobile; treat that as intentional.
- No autoloads are configured; `autoload/` is an empty placeholder. `ui/` holds the code-built HUD (`ui/hud.gd`).

## Ownership

- `entities/polygon/`: reusable procedural `Polygon` base (`CharacterBody2D`) driven by `sides`, `radius`, `color`.
- `entities/player/`: `Player` subclass, movement and smoothed `Camera2D`.
- `world/`: main arena scene, grid drawing, static walls and the wave director.
- `ui/`: code-built HUD (HP pips, wave counter, boss bar, win/lose overlay).
