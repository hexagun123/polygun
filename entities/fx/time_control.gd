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

const HITSTOP_FACTOR: float = 0.05

static var _freeze_until_msec: int = 0
static var _freeze_token: int = 0


static func set_bullet_time(factor: float) -> void:
	bullet_time_factor = clampf(factor, 0.02, 1.0)
	_apply()


static func set_hitstop(factor: float) -> void:
	hitstop_factor = clampf(factor, 0.02, 1.0)
	_apply()


static func reset() -> void:
	bullet_time_factor = 1.0
	hitstop_factor = 1.0
	_freeze_until_msec = 0
	_freeze_token += 1
	Engine.time_scale = 1.0


## Freeze the world for a few real-time milliseconds. Overlapping calls extend
## the freeze; a newer freeze invalidates the restore of the older timer.
static func freeze(tree: SceneTree, seconds: float) -> void:
	if tree == null or seconds <= 0.0:
		return

	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	if until <= _freeze_until_msec:
		return

	_freeze_until_msec = until
	_freeze_token += 1
	set_hitstop(HITSTOP_FACTOR)
	tree.create_timer(seconds, true, false, true).timeout.connect(_finish_freeze.bind(_freeze_token))


static func _finish_freeze(token: int) -> void:
	if token != _freeze_token:
		return
	_freeze_until_msec = 0
	set_hitstop(1.0)


static func _apply() -> void:
	Engine.time_scale = bullet_time_factor * hitstop_factor
