class_name Spitter
extends Enemy

## Keeps its distance and fires slow, executable projectiles. This is the main
## source of combo fuel during ordinary waves.

const EnemyProjectileScript = preload("res://entities/projectile/enemy_projectile.gd")

enum State { READY, TELEGRAPH }

const PREFERRED_MIN: float = 320.0
const PREFERRED_MAX: float = 420.0
const FIRE_INTERVAL: float = 1.6
const TELEGRAPH_TIME: float = 0.35
const STRAFE_SCALE: float = 0.6

var _state: int = State.READY
var _timer: float = 0.0
var _fire_timer: float = FIRE_INTERVAL * 0.5
var _base_outline_width: float = 1.0
var _base_outline_color: Color = Color.WHITE


func _init() -> void:
	super()
	sides = 4
	radius = 18.0
	color = Color(1.0, 0.6, 0.9)
	max_health = 3
	speed = 120.0


func _ready() -> void:
	super._ready()
	_base_outline_width = outline.width
	_base_outline_color = outline.default_color


func _get_desired_velocity(delta: float, player: Node2D) -> Vector2:
	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()
	if distance <= 0.001:
		return Vector2.ZERO

	var to_dir: Vector2 = to_player / distance

	if _state == State.TELEGRAPH:
		_timer -= delta
		var t: float = 1.0 - maxf(_timer, 0.0) / TELEGRAPH_TIME
		outline.width = _base_outline_width + 3.0 * t
		outline.default_color = _base_outline_color.lerp(Color.WHITE, t)
		if _timer <= 0.0:
			_fire(to_dir)
			_end_telegraph()
		return Vector2.ZERO

	_fire_timer -= delta
	if _fire_timer <= 0.0 and distance <= PREFERRED_MAX * 1.25:
		_state = State.TELEGRAPH
		_timer = TELEGRAPH_TIME
		return Vector2.ZERO

	# Hold the band: back off when crowded, close in when out of range.
	if distance < PREFERRED_MIN:
		return -to_dir * speed
	if distance > PREFERRED_MAX:
		return to_dir * speed
	return to_dir.orthogonal() * speed * STRAFE_SCALE


func _end_telegraph() -> void:
	_state = State.READY
	_fire_timer = FIRE_INTERVAL
	outline.width = _base_outline_width
	outline.default_color = _base_outline_color


func _fire(direction: Vector2) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return

	var shot := EnemyProjectileScript.new()
	shot.launch(direction)
	parent.add_child(shot)
	shot.global_position = global_position + direction * (radius + 8.0)
