class_name Boss
extends Enemy

## Placeholder boss: chases, telegraphs, then charges in a locked direction.

enum State { CHASE, WINDUP, CHARGE, RECOVER }

const CHARGE_SPEED: float = 600.0
const CHARGE_TIME: float = 0.4
const WINDUP_TIME: float = 0.45
const RECOVER_TIME: float = 0.7
const COOLDOWN: float = 2.5
const TRIGGER_RANGE: float = 500.0
const BOSS_COLOR: Color = Color(0.68, 0.2, 0.9)

var _state: State = State.CHASE
var _timer: float = 0.0
var _cooldown: float = 1.0
var _charge_dir: Vector2 = Vector2.RIGHT
var _base_outline_width: float = 0.0
var _base_outline_color: Color = Color.WHITE
var _base_scale: Vector2 = Vector2.ONE


func _init() -> void:
	super()
	sides = 6
	radius = 48.0
	color = BOSS_COLOR
	outline_width = 3.0
	max_health = 20
	contact_damage = 2
	speed = 90.0
	knockback_scale = 0.35
	execute_ratio = 2.0
	perfect_ratio = 1.1
	execute_breaks_combo = true


func _ready() -> void:
	super._ready()
	# Cache the base visuals so telegraphs never touch body.color (hit flash).
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
			# Grow and flash the outline while winding up.
			_timer -= delta
			var t: float = 1.0 - maxf(_timer, 0.0) / WINDUP_TIME
			var pulse: float = 0.5 - 0.5 * cos(t * TAU * 3.0)
			outline.width = _base_outline_width + 6.0 * pulse
			outline.default_color = _base_outline_color.lerp(Color.WHITE, pulse)
			body.scale = Vector2(_base_scale.x * (1.0 + 0.08 * pulse), _base_scale.y * (1.0 + 0.08 * pulse))
			if _timer <= 0.0:
				if to_player.length_squared() > 0.001:
					_charge_dir = to_player.normalized()
				_enter(State.CHARGE)
			return Vector2.ZERO

		State.CHARGE:
			# The previous move_and_slide() result tells us if we hit a wall.
			_timer -= delta
			if _timer <= 0.0 or get_slide_collision_count() > 0:
				_enter(State.RECOVER)
				return Vector2.ZERO
			# Stretch along the facing axis; the base keeps the rotation locked.
			outline.width = _base_outline_width + 8.0
			outline.default_color = Color.WHITE
			body.scale = Vector2(_base_scale.x * 1.15, _base_scale.y * 0.9)
			return _charge_dir * CHARGE_SPEED

		State.RECOVER:
			_timer -= delta
			if _timer <= 0.0:
				_cooldown = COOLDOWN
				_enter(State.CHASE)
			return Vector2.ZERO

	return Vector2.ZERO


func _enter(next: State) -> void:
	_state = next
	_timer = 0.0
	match next:
		State.WINDUP:
			_timer = WINDUP_TIME
			face_target = true
		State.CHARGE:
			_timer = CHARGE_TIME
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
