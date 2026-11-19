class_name Lunger
extends Enemy

## Telegraphs, then commits to a straight lunge. The windup is the execution
## window: sidestep it and dash through while it is overextended.

enum State { CHASE, WINDUP, LUNGE, RECOVER }

const WINDUP_TIME: float = 0.35
const LUNGE_TIME: float = 0.35
const LUNGE_SPEED: float = 520.0
const RECOVER_TIME: float = 0.6
const COOLDOWN: float = 1.2
const TRIGGER_RANGE: float = 420.0

var _state: int = State.CHASE
var _timer: float = 0.0
var _cooldown: float = 0.6
var _lunge_dir: Vector2 = Vector2.RIGHT
var _base_outline_width: float = 1.0
var _base_outline_color: Color = Color.WHITE
var _base_scale: Vector2 = Vector2.ONE


func _init() -> void:
	super()
	sides = 3
	radius = 22.0
	color = Color(1.0, 0.45, 0.2)
	max_health = 4
	speed = 110.0


func _ready() -> void:
	super._ready()
	_base_outline_width = outline.width
	_base_outline_color = outline.default_color
	_base_scale = body.scale


func _get_desired_velocity(delta: float, player: Node2D) -> Vector2:
	var to_player: Vector2 = player.global_position - global_position
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)

	match _state:
		State.CHASE:
			if _cooldown <= 0.0 and to_player.length_squared() <= TRIGGER_RANGE * TRIGGER_RANGE:
				_enter(State.WINDUP)
			if to_player.length_squared() <= 0.001:
				return Vector2.ZERO
			return to_player.normalized() * speed

		State.WINDUP:
			_timer -= delta
			var t: float = 1.0 - maxf(_timer, 0.0) / WINDUP_TIME
			outline.width = _base_outline_width + 3.0 * t
			outline.default_color = _base_outline_color.lerp(Color.WHITE, t)
			body.scale = Vector2(_base_scale.x * (1.0 + 0.12 * t), _base_scale.y * (1.0 + 0.12 * t))
			if _timer <= 0.0:
				if to_player.length_squared() > 0.001:
					_lunge_dir = to_player.normalized()
					look_at(player.global_position)
				_enter(State.LUNGE)
			return Vector2.ZERO

		State.LUNGE:
			_timer -= delta
			# The previous move_and_slide() result tells us if we hit a wall.
			if _timer <= 0.0 or get_slide_collision_count() > 0:
				_enter(State.RECOVER)
				return Vector2.ZERO
			return _lunge_dir * LUNGE_SPEED

		State.RECOVER:
			_timer -= delta
			if _timer <= 0.0:
				_cooldown = COOLDOWN
				_enter(State.CHASE)
			return Vector2.ZERO

	return Vector2.ZERO


func _enter(next: int) -> void:
	_state = next
	_timer = 0.0
	match next:
		State.WINDUP:
			_timer = WINDUP_TIME
			face_target = true
		State.LUNGE:
			_timer = LUNGE_TIME
			face_target = false
		State.RECOVER:
			_timer = RECOVER_TIME
			face_target = true
		State.CHASE:
			face_target = true
	_reset_visuals()


func _reset_visuals() -> void:
	if outline == null or body == null:
		return
	outline.width = _base_outline_width
	outline.default_color = _base_outline_color
	body.scale = _base_scale
