# AGENTS.md

## Responses

- Keep the response to the point and concise - unless the user asks otherwise

## Planning mode

- always ask clarifying questions
- never assume designs, tech stack or features

## change / edit mode

- edit directly only for small fixes, otherwise use sub-agents as much as possible
- don't over engineer code that is not nessesary.
- upon completing a fix or a feature, check the diff and ask the user for whether to commit or not
- Use Godot 4.x GDScript only
- if something is risky to change, such as possible breaks in "uid://", ask the user to change it in the godot editor
- try to limit the access to godot editor itself as it is really slow
- always check for code quality, including broken path and type errors after completing features

## git

- ensure commit messages are concise but enough to convey the change

## Project shape

- Godot 4.x 2D game (working `project.godot` targets 4.7); main scene is `uid://cjmff0wlmncdk` = `world/testing_arena.tscn`.
- No build, test, lint, or CI scripts exist. Verification means opening the project in Godot and running the main scene; don't invent CLI commands.
- Renderer is `gl_compatibility` on both desktop and mobile; treat that as intentional.
- No autoloads are configured. `autoload/` and `ui/` are empty placeholders.

## Ownership

- `entities/polygon/`: reusable procedural `Polygon` base (`CharacterBody2D`) driven by `sides`, `radius`, `color`.
- `entities/player/`: `Player` subclass, movement and smoothed `Camera2D`.
- `world/`: main arena scene, grid drawing and static walls.
