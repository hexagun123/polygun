class_name TimeControl
extends RefCounted

## Single authority for Engine.time_scale.
##
## Bullet time (combo) and hit-stop both want to slow the world; if they each
## wrote Engine.time_scale directly they would overwrite each other and leak a
## stale slow-motion on the way out. Everything multiplies here instead.
## Static state survives a scene reload, so reset() must be called on restart.

static var bullet_time_factor: float = 1.0
static var hitstop_factor: float = 1.0


static func set_bullet_time(factor: float) -> void:
	bullet_time_factor = clampf(factor, 0.02, 1.0)
	_apply()


static func set_hitstop(factor: float) -> void:
	hitstop_factor = clampf(factor, 0.02, 1.0)
	_apply()


static func reset() -> void:
	bullet_time_factor = 1.0
	hitstop_factor = 1.0
	Engine.time_scale = 1.0


static func _apply() -> void:
	Engine.time_scale = bullet_time_factor * hitstop_factor
