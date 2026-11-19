class_name Boss
extends Enemy

## Level boss. Two attacks: a telegraphed charge, and a volley of slow
## projectiles that double as execute fuel. Below half HP it enters phase 2:
## the volley becomes a full ring and the charge comes back faster.

const EnemyProjectileScript = preload("res://entities/projectile/enemy_projectile.gd")

enum State { CHASE, WINDUP, CHARGE, RECOVER, VOLLEY_WINDUP }

const CHARGE_SPEED: float = 600.0
const CHARGE_TIME: float = 0.4
const WINDUP_TIME: float = 0.45
const RECOVER_TIME: float = 0.7
const COOLDOWN: float = 2.5
const TRIGGER_RANGE: float = 500.0
const BOSS_COLOR: Color = Color(0.68, 0.2, 0.9)

const VOLLEY_WINDUP_TIME: float = 0.5
const VOLLEY_COOLDOWN: float = 6.0
const VOLLEY_COOLDOWN_P2: float = 4.5
const VOLLEY_FAN_COUNT: int = 6
const VOLLEY_FAN_SPREAD: float = 1.75
const VOLLEY_RING_COUNT: int = 10
const VOLLEY_PROJECTILE_SPEED: float = 240.0
const PHASE2_COOLDOWN: float = 1.8

var _state: State = State.CHASE
var _timer: float = 0.0
var _cooldown: float = 1.0
var _volley_timer: float = VOLLEY_COOLDOWN * 0.6
var _phase2: bool = false
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
	max_health = 36
	contact_damage = 2
	speed = 90.0
	knockback_scale = 0.35
	execute_ratio = 2.0
	perfect_ratio = 1.1
	body_ratio = 0.6
	execute_breaks_combo = true


func _ready() -> void:
	super._ready()
	# Cache the base visuals so telegraphs never touch body.color (hit flash).
	_base_outline_width = outline.width
	_base_outline_color = outline.default_color
	_base_scale = body.scale


func _on_damaged(hit_direction: Vector2) -> void:
	super._on_damaged(hit_direction)
	if _phase2 or health > max_health / 2:
		return
	_phase2 = true
	_cooldown = minf(_cooldown, 0.4)
	_volley_timer = minf(_volley_timer, 1.5)


func _get_desired_velocity(delta: float, player: Node2D) -> Vector2:
	var to_player: Vector2 = player.global_position - global_position
	_cooldown = maxf(_cooldown - delta, 0.0)
	_volley_timer = maxf(_volley_timer - delta, 0.0)

	match _state:
		State.CHASE:
			if _volley_timer <= 0.0:
				_enter(State.VOLLEY_WINDUP)
				return Vector2.ZERO
			if _cooldown <= 0.0 and to_player.length_squared() <= TRIGGER_RANGE * TRIGGER_RANGE:
				_enter(State.WINDUP)
			if to_player.length_squared() <= 0.001:
				return Vector2.ZERO
			return to_player.normalized() * speed

		State.VOLLEY_WINDUP:
			_timer -= delta
			var t: float = 1.0 - maxf(_timer, 0.0) / VOLLEY_WINDUP_TIME
			var pulse: float = 0.5 - 0.5 * cos(t * TAU * 4.0)
			outline.width = _base_outline_width + 5.0 * pulse
			outline.default_color = _base_outline_color.lerp(Color(0.4, 1.0, 1.0), pulse)
			if _timer <= 0.0:
				_spawn_volley(player)
				_volley_timer = VOLLEY_COOLDOWN_P2 if _phase2 else VOLLEY_COOLDOWN
				_enter(State.CHASE)
			return Vector2.ZERO

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
				_cooldown = PHASE2_COOLDOWN if _phase2 else COOLDOWN
				_enter(State.CHASE)
			return Vector2.ZERO

	return Vector2.ZERO


func _spawn_volley(player: Node2D) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return

	if _phase2:
		for i in VOLLEY_RING_COUNT:
			_spawn_shot(parent, Vector2.from_angle(TAU * float(i) / float(VOLLEY_RING_COUNT)))
		return

	var base_dir: Vector2 = player.global_position - global_position
	if base_dir.length_squared() <= 0.001:
		base_dir = Vector2.RIGHT
	base_dir = base_dir.normalized()

	for i in VOLLEY_FAN_COUNT:
		var offset: float = 0.0
		if VOLLEY_FAN_COUNT > 1:
			offset = lerpf(-VOLLEY_FAN_SPREAD * 0.5, VOLLEY_FAN_SPREAD * 0.5, float(i) / float(VOLLEY_FAN_COUNT - 1))
		_spawn_shot(parent, base_dir.rotated(offset))


func _spawn_shot(parent: Node, direction: Vector2) -> void:
	var shot := EnemyProjectileScript.new()
	shot.speed = VOLLEY_PROJECTILE_SPEED
	shot.launch(direction)
	parent.add_child(shot)
	shot.global_position = global_position + direction * (radius + 10.0)


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
		State.VOLLEY_WINDUP:
			_timer = VOLLEY_WINDUP_TIME
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
