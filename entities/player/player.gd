class_name Player
extends Polygon

signal health_changed(current: int, maximum: int)
signal died
signal combo_changed(combo: int)

const SfxScript = preload("res://audio/sfx.gd")

const HIT_FLASH_TIME: float = 0.12
const WIND_PREVIEW_COLOR: Color = Color(0.55, 1.0, 0.75)

## A press made while dashing / cooling down is remembered this long so the
## input is never silently dropped.
const DASH_BUFFER_TIME: float = 0.2
## The camera leads the player along its movement direction, which is what
## makes a 4000 px/s dash read as fast instead of as lag.
const CAMERA_LOOK_AHEAD: float = 90.0
const CAMERA_LOOK_AHEAD_PER_SPEED: float = 0.15
const CAMERA_LOOK_SMOOTHING: float = 10.0
const CAMERA_BASE_SMOOTHING: float = 10.0
const CAMERA_DASH_SMOOTHING: float = 55.0

enum DashState {
	READY,
	DASHING,
}

@export var speed: float = 300.0
@export var camera_bounds_half_size: Vector2 = Vector2(1536.0, 1536.0)
@export var max_health: int = 5
@export var damage_cooldown: float = 0.7

@export_group("Dash")
## Every dash lasts exactly this long, so wind (distance) is what sets speed.
@export var dash_duration: float = 0.1
@export var dash_min_distance: float = 180.0
@export var dash_max_distance: float = 420.0
## Time spent holding dash to fill the wind meter and reach max distance.
@export var dash_wind_time: float = 0.9
@export var dash_min_damage: int = 2
@export var dash_max_damage: int = 4
@export var dash_cooldown: float = 0.12
@export var dash_invulnerability_after: float = 0.05
## Fraction of the dash speed kept when the dash ends, so landing slides
## instead of hitting an invisible brake.
@export var dash_momentum_carry: float = 0.18
@export var momentum_decay: float = 2800.0

const DASH_HIT_RADIUS_BONUS: float = 4.0
## Seconds an execution chain survives without a new execution.
const COMBO_WINDOW: float = 1.0

var camera: Camera2D = Camera2D.new()
var health: int = 5
var combo: int = 0
var wind_audio: AudioStreamPlayer
var dash_audio: AudioStreamPlayer

var _base_color: Color = Color.WHITE
var _base_outline_width: float = 1.0
var _base_outline_color: Color = Color.WHITE
var _invulnerability_timer: float = 0.0
var _flash_timer: float = 0.0
var _dead: bool = false

var _dash_state: int = DashState.READY
## 0 = minimum dash, 1 = full distance. Built while holding, spent on dash.
var _wind: float = 0.0
var _cooldown_timer: float = 0.0
var _dash_direction: Vector2 = Vector2.RIGHT
var _dash_speed: float = 0.0
var _dash_damage: int = 1
## Exact distance still to travel in this dash (never overshoots a frame).
var _dash_remaining: float = 0.0
## Enemy instance id -> closest distance from the dash path to its centre.
var _dash_crossings: Dictionary = {}
var _dash_executed: bool = false
var _combo_timer: float = 0.0
var _dash_buffer: float = 0.0
var _momentum: Vector2 = Vector2.ZERO
var _dash_exceptions: Array[Node] = []
var _wind_preview: Line2D


func _ready() -> void:
	add_to_group(&"player")

	# Enemies and walls live on layer 1; keep the player out of that layer.
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

	_wind_preview = Line2D.new()
	_wind_preview.points = PackedVector2Array([Vector2(radius + 4.0, 0.0), Vector2(radius + 4.0, 0.0)])
	_wind_preview.width = 2.0
	_wind_preview.default_color = WIND_PREVIEW_COLOR
	_wind_preview.visible = false
	add_child(_wind_preview)

	wind_audio = AudioStreamPlayer.new()
	wind_audio.stream = SfxScript.cached_tone(220.0, 440.0, 1.5, 7000.0)
	add_child(wind_audio)

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
	if combo > 0:
		_combo_timer = maxf(_combo_timer - delta, 0.0)
		if _combo_timer <= 0.0:
			_break_combo()
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		if _flash_timer <= 0.0 and body != null:
			body.color = _base_color

	# Rotate to face mouse. Aim stays free while winding.
	look_at(get_global_mouse_position())

	if _dash_state == DashState.DASHING:
		_update_dash(delta)
		_update_camera(delta)
		return

	_update_wind(delta)

	var move_input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = move_input * speed + _momentum
	move_and_slide()
	_update_momentum(delta)

	if _cooldown_timer <= 0.0 and _dash_buffer > 0.0:
		_dash_buffer = 0.0
		_start_dash()

	_update_camera(delta)


## Wind builds only while holding; it persists after release and is spent by
## the dash. Tap = minimum distance, hold before the next press = farther.
func _update_wind(delta: float) -> void:
	if Input.is_action_pressed(&"dash"):
		var was_empty: bool = _wind <= 0.0
		_wind = minf(_wind + delta / maxf(dash_wind_time, 0.001), 1.0)
		if wind_audio != null:
			if was_empty:
				wind_audio.play()
			wind_audio.pitch_scale = lerpf(0.7, 1.9, _wind)
	elif wind_audio != null and wind_audio.playing:
		wind_audio.stop()

	_update_wind_visuals()


func _update_wind_visuals() -> void:
	var visible_now: bool = _wind > 0.01
	_wind_preview.visible = visible_now

	if not visible_now:
		if outline != null:
			outline.width = _base_outline_width
			outline.default_color = _base_outline_color
		return

	var distance: float = lerpf(dash_min_distance, dash_max_distance, _wind)
	_wind_preview.set_point_position(1, Vector2(distance, 0.0))
	_wind_preview.default_color = Color(
		WIND_PREVIEW_COLOR.r,
		WIND_PREVIEW_COLOR.g,
		WIND_PREVIEW_COLOR.b,
		lerpf(0.35, 0.9, _wind)
	)

	if outline != null:
		outline.width = _base_outline_width + 4.0 * _wind
		outline.default_color = _base_outline_color.lerp(Color.WHITE, _wind)


func _reset_wind_visuals() -> void:
	if _wind_preview != null:
		_wind_preview.visible = false
	if outline != null:
		outline.width = _base_outline_width
		outline.default_color = _base_outline_color


func _update_momentum(delta: float) -> void:
	_momentum = _momentum.move_toward(Vector2.ZERO, momentum_decay * delta)


func _update_camera(delta: float) -> void:
	var look_ahead: Vector2 = velocity * CAMERA_LOOK_AHEAD_PER_SPEED
	if look_ahead.length_squared() > CAMERA_LOOK_AHEAD * CAMERA_LOOK_AHEAD:
		look_ahead = look_ahead.normalized() * CAMERA_LOOK_AHEAD

	# Frame-rate independent smoothing toward the lead position.
	camera.position = camera.position.lerp(look_ahead, 1.0 - exp(-CAMERA_LOOK_SMOOTHING * delta))

	# Glue the camera to the player during a dash so it cannot fall behind.
	var dash_ratio: float = clampf(velocity.length() / maxf(speed * 3.0, 1.0), 0.0, 1.0)
	camera.position_smoothing_speed = lerpf(CAMERA_BASE_SMOOTHING, CAMERA_DASH_SMOOTHING, dash_ratio)


func _start_dash() -> void:
	var ratio: float = _wind
	var distance: float = lerpf(dash_min_distance, dash_max_distance, ratio)
	_dash_speed = distance / maxf(dash_duration, 0.001)
	_dash_damage = roundi(lerpf(float(dash_min_damage), float(dash_max_damage), ratio))

	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 0.0001:
		_dash_direction = to_mouse.normalized()
	else:
		_dash_direction = Vector2.RIGHT.rotated(rotation)

	_dash_remaining = distance
	_dash_state = DashState.DASHING
	_dash_crossings.clear()
	_dash_executed = false

	# The wind is spent on this dash; holding again loads the next one.
	_wind = 0.0

	# Enemies share layer 1 with the walls. Ignore them physically during the
	# dash so the player passes through and damages them instead of stopping.
	_dash_exceptions.clear()
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		if enemy is PhysicsBody2D:
			add_collision_exception_with(enemy as PhysicsBody2D)
			_dash_exceptions.append(enemy)

	_invulnerability_timer = maxf(_invulnerability_timer, dash_duration + dash_invulnerability_after)

	_reset_wind_visuals()
	if wind_audio != null:
		wind_audio.stop()
	if dash_audio != null:
		dash_audio.stop()
		dash_audio.pitch_scale = SfxScript.varied_pitch()
		dash_audio.play()


func _update_dash(delta: float) -> void:
	var from: Vector2 = global_position

	# Step by remaining distance, not by a timer, so the dash lands exactly on
	# its wind distance. A timer overshoots by a whole frame at 4200 px/s,
	# which is wider than the execute bands.
	var step: float = minf(_dash_speed * delta, _dash_remaining)
	velocity = _dash_direction * (step / maxf(delta, 0.0001))
	move_and_slide()
	_dash_remaining -= step

	# Track how close the travelled segment got to each enemy, so a 4200 px/s
	# dash cannot tunnel past anything and a wall stop stays exact.
	_track_dash_crossings(from, global_position)

	# Enemies have collision exceptions during the dash, so any slide hit is a
	# wall: end the dash early on contact.
	if get_slide_collision_count() > 0:
		_end_dash()
		return

	if _dash_remaining <= 0.0001:
		_end_dash()


func _track_dash_crossings(from: Vector2, to: Vector2) -> void:
	var segment: Vector2 = to - from
	var segment_len_sq: float = segment.length_squared()

	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy: Enemy = node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue

		var t: float = 0.0
		if segment_len_sq > 0.0001:
			t = clampf((enemy.global_position - from).dot(segment) / segment_len_sq, 0.0, 1.0)
		var closest: Vector2 = from + segment * t
		var path_distance: float = closest.distance_to(enemy.global_position)

		var instance_id: int = enemy.get_instance_id()
		var previous: float = _dash_crossings.get(instance_id, INF)
		if path_distance < previous:
			_dash_crossings[instance_id] = path_distance


## Classifies everything the dash met, using where the dash actually ended.
## Body > execute > normal hit, in that priority.
func _resolve_dash_hits() -> void:
	var end_pos: Vector2 = global_position
	var body_source: Vector2 = Vector2.ZERO
	var body_hit: bool = false

	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy: Enemy = node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue

		var instance_id: int = enemy.get_instance_id()
		var end_distance: float = end_pos.distance_to(enemy.global_position)
		var size: float = enemy.radius

		# Ended inside the body: costs the player a hit and deals no damage.
		if end_distance <= size * enemy.body_ratio:
			body_hit = true
			body_source = enemy.global_position
			continue

		var path_distance: float = _dash_crossings.get(instance_id, INF)
		var hit_radius: float = radius + size + DASH_HIT_RADIUS_BONUS
		if path_distance > hit_radius:
			continue

		# Execution needs the path to have gone through the body itself.
		if path_distance <= size and end_distance <= size * enemy.execute_ratio:
			_execute(enemy, end_distance, size)
		else:
			enemy.take_damage(_dash_damage, _dash_direction)

	if body_hit:
		_take_body_damage(body_source)


func _execute(enemy: Enemy, end_distance: float, size: float) -> void:
	var damage: int = _dash_damage * enemy.execute_damage_scale
	var perfect: bool = enemy.perfect_ratio > 0.0 and end_distance <= size * enemy.perfect_ratio

	enemy.take_damage(damage, _dash_direction)
	var killed: bool = enemy.health <= 0
	_dash_executed = true

	# The boss cashes your chain: a normal execute resets it, a perfect one or
	# a kill keeps it going.
	if enemy.execute_breaks_combo and not perfect and not killed:
		_break_combo()
	else:
		_add_combo()


func _add_combo() -> void:
	combo += 1
	_combo_timer = COMBO_WINDOW
	combo_changed.emit(combo)


func _break_combo() -> void:
	if combo == 0:
		return
	combo = 0
	_combo_timer = 0.0
	combo_changed.emit(0)


func _end_dash() -> void:
	_resolve_dash_hits()
	_release_dash_exceptions()

	if _dead:
		return

	_dash_state = DashState.READY
	_cooldown_timer = dash_cooldown
	# Keep part of the dash speed instead of stopping dead.
	_momentum = _dash_direction * _dash_speed * dash_momentum_carry
	velocity = _momentum

	# A dash that executes nothing drops the chain.
	if not _dash_executed:
		_break_combo()


func _cancel_dash() -> void:
	_release_dash_exceptions()
	_dash_state = DashState.READY
	_wind = 0.0
	_cooldown_timer = 0.0
	_momentum = Vector2.ZERO
	velocity = Vector2.ZERO
	_reset_wind_visuals()
	if wind_audio != null:
		wind_audio.stop()


func _release_dash_exceptions() -> void:
	for enemy in _dash_exceptions:
		if is_instance_valid(enemy) and enemy is PhysicsBody2D:
			remove_collision_exception_with(enemy)
	_dash_exceptions.clear()


func take_damage(amount: int, from_position: Vector2) -> void:
	if _dead or _invulnerability_timer > 0.0 or amount <= 0:
		return
	_apply_damage(amount, from_position)


## Ending a dash inside an enemy must hurt even though the dash grants
## i-frames, so this deliberately bypasses them.
func _take_body_damage(from_position: Vector2) -> void:
	if _dead:
		return
	_apply_damage(1, from_position)


func _apply_damage(amount: int, _from_position: Vector2) -> void:
	health -= amount
	_invulnerability_timer = damage_cooldown
	_flash_timer = HIT_FLASH_TIME
	if body != null:
		body.color = Color(1.0, 0.25, 0.25)
	_break_combo()
	health_changed.emit(maxi(health, 0), max_health)

	if health <= 0:
		_die()


func _die() -> void:
	if _dead:
		return

	_dead = true
	health = 0
	_break_combo()
	_cancel_dash()
	velocity = Vector2.ZERO
	if body != null:
		body.color = Color(0.35, 0.45, 0.35)
	if outline != null:
		outline.default_color = Color(0.5, 0.6, 0.5)
	died.emit()
