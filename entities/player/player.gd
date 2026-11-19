class_name Player
extends Polygon

signal health_changed(current: int, maximum: int)
signal died

const SfxScript = preload("res://audio/sfx.gd")

const HIT_FLASH_TIME: float = 0.12
const CHARGE_PREVIEW_COLOR: Color = Color(0.55, 1.0, 0.75)

## A press made while dashing / cooling down is remembered this long so the
## input is never silently dropped.
const DASH_BUFFER_TIME: float = 0.2
## The camera leads the player along its movement direction, which is what
## makes a 1900+ px/s dash read as fast instead of as lag.
const CAMERA_LOOK_AHEAD: float = 90.0
const CAMERA_LOOK_AHEAD_PER_SPEED: float = 0.15
const CAMERA_LOOK_SMOOTHING: float = 10.0
const CAMERA_BASE_SMOOTHING: float = 10.0
const CAMERA_DASH_SMOOTHING: float = 55.0

enum DashState {
	READY,
	CHARGING,
	DASHING,
}

@export var speed: float = 300.0
@export var camera_bounds_half_size: Vector2 = Vector2(1536.0, 1536.0)
@export var max_health: int = 5
@export var damage_cooldown: float = 0.7

@export_group("Dash")
@export var dash_charge_time: float = 1.0
@export var dash_min_distance: float = 150.0
@export var dash_max_distance: float = 520.0
@export var dash_min_speed: float = 1200.0
@export var dash_max_speed: float = 1900.0
@export var dash_min_damage: int = 2
@export var dash_max_damage: int = 3
@export var dash_cooldown: float = 0.25
@export var dash_charge_move_scale: float = 0.35
@export var dash_invulnerability_after: float = 0.05
## Fraction of the dash speed kept when the dash ends, so landing slides
## instead of hitting an invisible brake.
@export var dash_momentum_carry: float = 0.18
@export var momentum_decay: float = 2800.0

const DASH_HIT_RADIUS_BONUS: float = 4.0

var camera: Camera2D = Camera2D.new()
var health: int = 5
var charge_audio: AudioStreamPlayer
var dash_audio: AudioStreamPlayer

var _base_color: Color = Color.WHITE
var _base_outline_width: float = 1.0
var _base_outline_color: Color = Color.WHITE
var _invulnerability_timer: float = 0.0
var _flash_timer: float = 0.0
var _dead: bool = false

var _dash_state: int = DashState.READY
var _charge_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _dash_direction: Vector2 = Vector2.RIGHT
var _dash_speed: float = 0.0
var _dash_damage: int = 1
var _dash_time_left: float = 0.0
var _dash_hit_ids: Dictionary = {}
var _dash_buffer: float = 0.0
var _momentum: Vector2 = Vector2.ZERO
var _dash_exceptions: Array[Node] = []
var _dash_shape: CircleShape2D
var _dash_query: PhysicsShapeQueryParameters2D
var _charge_preview: Line2D


func _ready() -> void:
	add_to_group(&"player")

	# Projectiles and dash queries scan layer 1 (world) only; keep the player
	# out of that layer.
	collision_layer = 2

	health = max_health
	_base_color = color

	# camera settings
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = CAMERA_BASE_SMOOTHING
	add_child(camera)
	camera.make_current()
	_update_camera_limits()

	super._ready()

	_base_outline_width = outline.width
	_base_outline_color = outline.default_color

	_charge_preview = Line2D.new()
	_charge_preview.points = PackedVector2Array([Vector2(radius + 4.0, 0.0), Vector2(radius + 4.0, 0.0)])
	_charge_preview.width = 2.0
	_charge_preview.default_color = CHARGE_PREVIEW_COLOR
	_charge_preview.visible = false
	add_child(_charge_preview)

	_dash_shape = CircleShape2D.new()
	_dash_shape.radius = radius + DASH_HIT_RADIUS_BONUS
	_dash_query = PhysicsShapeQueryParameters2D.new()
	_dash_query.shape = _dash_shape
	_dash_query.collision_mask = 1
	_dash_query.collide_with_areas = false
	_dash_query.collide_with_bodies = true

	charge_audio = AudioStreamPlayer.new()
	charge_audio.stream = SfxScript.cached_tone(220.0, 440.0, 1.5, 7000.0)
	add_child(charge_audio)

	dash_audio = AudioStreamPlayer.new()
	dash_audio.stream = SfxScript.cached_noise(0.15, 14000.0)
	add_child(dash_audio)

	health_changed.emit(health, max_health)


func _update_camera_limits() -> void:
	# Limits apply to the visible rectangle, so the arena bounds can be used
	# directly. Offsetting them by half the viewport locks the camera at the
	# center whenever the window is wider than the arena.
	camera.limit_left = int(-camera_bounds_half_size.x)
	camera.limit_right = int(camera_bounds_half_size.x)
	camera.limit_top = int(-camera_bounds_half_size.y)
	camera.limit_bottom = int(camera_bounds_half_size.y)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_invulnerability_timer = maxf(_invulnerability_timer - delta, 0.0)
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	_dash_buffer = maxf(_dash_buffer - delta, 0.0)
	if Input.is_action_just_pressed(&"dash"):
		_dash_buffer = DASH_BUFFER_TIME
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		if _flash_timer <= 0.0 and body != null:
			body.color = _base_color

	# Rotate to face mouse. Aim stays free while charging.
	look_at(get_global_mouse_position())

	if _dash_state == DashState.DASHING:
		_update_dash(delta)
		_update_camera(delta)
		return

	var move_input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")

	if _dash_state == DashState.CHARGING:
		velocity = move_input * speed * dash_charge_move_scale + _momentum
		move_and_slide()
		_update_momentum(delta)
		_update_charge(delta)
		_update_camera(delta)
		return

	velocity = move_input * speed + _momentum
	move_and_slide()
	_update_momentum(delta)

	if _dash_state == DashState.READY and _cooldown_timer <= 0.0 and _dash_buffer > 0.0:
		_dash_buffer = 0.0
		_start_charge()

	_update_camera(delta)


func _update_momentum(delta: float) -> void:
	_momentum = _momentum.move_toward(Vector2.ZERO, momentum_decay * delta)


func _update_camera(delta: float) -> void:
	var look_ahead: Vector2 = velocity * CAMERA_LOOK_AHEAD_PER_SPEED
	if look_ahead.length_squared() > CAMERA_LOOK_AHEAD * CAMERA_LOOK_AHEAD:
		look_ahead = look_ahead.normalized() * CAMERA_LOOK_AHEAD

	# Frame-rate independent smoothing toward the lead position.
	camera.position = camera.position.lerp(look_ahead, 1.0 - exp(-CAMERA_LOOK_SMOOTHING * delta))

	# Glue the camera to the player during a dash so it cannot fall behind.
	var dash_ratio: float = clampf(velocity.length() / maxf(dash_min_speed, 1.0), 0.0, 1.0)
	camera.position_smoothing_speed = lerpf(CAMERA_BASE_SMOOTHING, CAMERA_DASH_SMOOTHING, dash_ratio)


func _charge_ratio() -> float:
	return clampf(_charge_timer / maxf(dash_charge_time, 0.001), 0.0, 1.0)


func _start_charge() -> void:
	_dash_state = DashState.CHARGING
	_charge_timer = 0.0
	_charge_preview.visible = true
	_update_charge_visuals()
	if charge_audio != null:
		charge_audio.pitch_scale = 0.7
		charge_audio.play()


func _update_charge(delta: float) -> void:
	_charge_timer = minf(_charge_timer + delta, dash_charge_time)
	_update_charge_visuals()

	if charge_audio != null:
		charge_audio.pitch_scale = lerpf(0.7, 1.9, _charge_ratio())

	if Input.is_action_just_released(&"dash") or not Input.is_action_pressed(&"dash"):
		_start_dash()


func _update_charge_visuals() -> void:
	var ratio: float = _charge_ratio()

	var distance: float = lerpf(dash_min_distance, dash_max_distance, ratio)
	_charge_preview.set_point_position(1, Vector2(distance, 0.0))
	_charge_preview.default_color = Color(
		CHARGE_PREVIEW_COLOR.r,
		CHARGE_PREVIEW_COLOR.g,
		CHARGE_PREVIEW_COLOR.b,
		lerpf(0.35, 0.85, ratio)
	)

	if outline != null:
		outline.width = _base_outline_width + 4.0 * ratio
		outline.default_color = _base_outline_color.lerp(Color.WHITE, ratio)


func _reset_charge_visuals() -> void:
	if _charge_preview != null:
		_charge_preview.visible = false
	if outline != null:
		outline.width = _base_outline_width
		outline.default_color = _base_outline_color


func _start_dash() -> void:
	var ratio: float = _charge_ratio()

	var distance: float = lerpf(dash_min_distance, dash_max_distance, ratio)
	_dash_speed = lerpf(dash_min_speed, dash_max_speed, ratio)
	_dash_damage = roundi(lerpf(float(dash_min_damage), float(dash_max_damage), ratio))

	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 0.0001:
		_dash_direction = to_mouse.normalized()
	else:
		_dash_direction = Vector2.RIGHT.rotated(rotation)

	_dash_time_left = maxf(distance / _dash_speed, 0.001)
	_dash_state = DashState.DASHING
	_dash_hit_ids.clear()

	# Enemies share layer 1 with the walls. Ignore them physically during the
	# dash so the player passes through and damages them instead of stopping.
	_dash_exceptions.clear()
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		if enemy is PhysicsBody2D:
			add_collision_exception_with(enemy as PhysicsBody2D)
			_dash_exceptions.append(enemy)

	_invulnerability_timer = maxf(_invulnerability_timer, _dash_time_left + dash_invulnerability_after)

	_reset_charge_visuals()
	if charge_audio != null:
		charge_audio.stop()
	if dash_audio != null:
		dash_audio.stop()
		dash_audio.pitch_scale = SfxScript.varied_pitch()
		dash_audio.play()


func _update_dash(delta: float) -> void:
	velocity = _dash_direction * _dash_speed
	move_and_slide()
	_damage_enemies_in_dash()

	# Enemies have collision exceptions during the dash, so any slide hit is a
	# wall: end the dash early on contact.
	if get_slide_collision_count() > 0:
		_end_dash()
		return

	_dash_time_left -= delta
	if _dash_time_left <= 0.0:
		_end_dash()


func _damage_enemies_in_dash() -> void:
	if _dash_query == null:
		return
	_dash_query.transform = Transform2D(0.0, global_position)

	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(_dash_query, 16)
	for hit in hits:
		var collider: Variant = hit.get("collider")
		if not (collider is Enemy):
			continue
		var collider_node: Enemy = collider as Enemy
		if not collider_node.has_method(&"take_damage"):
			continue
		var instance_id: int = collider_node.get_instance_id()
		if _dash_hit_ids.has(instance_id):
			continue
		_dash_hit_ids[instance_id] = true
		collider_node.call(&"take_damage", _dash_damage, _dash_direction)


func _end_dash() -> void:
	_release_dash_exceptions()
	_dash_state = DashState.READY
	_cooldown_timer = dash_cooldown
	# Keep part of the dash speed instead of stopping dead.
	_momentum = _dash_direction * _dash_speed * dash_momentum_carry
	velocity = _momentum


func _cancel_dash() -> void:
	_release_dash_exceptions()
	_dash_state = DashState.READY
	_charge_timer = 0.0
	_cooldown_timer = 0.0
	_momentum = Vector2.ZERO
	velocity = Vector2.ZERO
	_reset_charge_visuals()
	if charge_audio != null:
		charge_audio.stop()


func _release_dash_exceptions() -> void:
	for enemy in _dash_exceptions:
		if is_instance_valid(enemy) and enemy is PhysicsBody2D:
			remove_collision_exception_with(enemy)
	_dash_exceptions.clear()


func take_damage(amount: int, from_position: Vector2) -> void:
	if _dead or _invulnerability_timer > 0.0 or amount <= 0:
		return

	health -= amount
	_invulnerability_timer = damage_cooldown
	_flash_timer = HIT_FLASH_TIME
	if body != null:
		body.color = Color(1.0, 0.25, 0.25)
	health_changed.emit(maxi(health, 0), max_health)

	if health <= 0:
		_die()


func _die() -> void:
	if _dead:
		return

	_dead = true
	health = 0
	_cancel_dash()
	velocity = Vector2.ZERO
	if body != null:
		body.color = Color(0.35, 0.45, 0.35)
	if outline != null:
		outline.default_color = Color(0.5, 0.6, 0.5)
	died.emit()
