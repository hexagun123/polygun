class_name Player
extends Polygon

signal health_changed(current: int, maximum: int)
signal died
signal combo_changed(combo: int)
signal hurt

const SfxScript = preload("res://audio/sfx.gd")
const TimeControlScript = preload("res://entities/fx/time_control.gd")
const DashGhostScript = preload("res://entities/fx/dash_ghost.gd")
const DamageNumberScript = preload("res://entities/fx/damage_number.gd")

const HIT_FLASH_TIME: float = 0.12
const MARKER_IDLE_COLOR: Color = Color(0.55, 1.0, 0.75)
const MARKER_EXECUTE_COLOR: Color = Color(1.0, 0.82, 0.3)
const MARKER_DANGER_COLOR: Color = Color(1.0, 0.3, 0.3)
const MARKER_SIZE: float = 10.0
const MARKER_GAP: float = 4.0

## A release that lands during a dash / cooldown is remembered this long so the
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
## The roof. Distance starts at 0 and eases up to this.
@export var dash_max_distance: float = 520.0
## 0 = linear wind to distance, 1 = the full S-curve (flat at both ends).
@export_range(0.0, 1.0) var wind_curve_strength: float = 1.0
## Time spent holding dash to fill the wind meter and reach max distance.
@export var dash_wind_time: float = 0.9
@export var dash_min_damage: int = 1
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

# Feel (Stage 4).
const HITSTOP_HIT: float = 0.035
const HITSTOP_KILL: float = 0.060
const HITSTOP_HURT: float = 0.050
const SHAKE_MAX_OFFSET: float = 10.0
const SHAKE_DECAY: float = 2.2
const ZOOM_PUNCH: float = 0.96
const GHOST_SPACING: float = 40.0
const MAX_GHOSTS: int = 8
const HURT_KNOCKBACK: float = 420.0
const NORMAL_DAMAGE_COLOR: Color = Color(1.0, 0.95, 0.8)
const EXECUTE_DAMAGE_COLOR: Color = Color(1.0, 0.8, 0.25)

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
var _trauma: float = 0.0
var _zoom_mult: float = 1.0
var _ghost_travel: float = 0.0
var _body_points: PackedVector2Array = PackedVector2Array()
var _dash_buffer: float = 0.0
## 1 / Engine.time_scale, so the player keeps acting in real time.
var _inv_time_scale: float = 1.0
var _momentum: Vector2 = Vector2.ZERO
var _dash_exceptions: Array[Node] = []
## True between dash press and release: wind builds, release fires the dash.
var _winding: bool = false
var _aim_marker: Node2D
var _marker_lines: Array[Line2D] = []


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
	_body_points = body.polygon

	wind_audio = AudioStreamPlayer.new()
	wind_audio.stream = SfxScript.cached_tone(220.0, 440.0, 1.5, 7000.0)
	add_child(wind_audio)

	dash_audio = AudioStreamPlayer.new()
	dash_audio.stream = SfxScript.cached_noise(0.15, 14000.0)
	add_child(dash_audio)

	_build_aim_marker()

	health_changed.emit(health, max_health)


## Endpoint crosshair: shows where the dash will land and turns gold when that
## landing would execute, red when it would end inside a body.
func _build_aim_marker() -> void:
	_aim_marker = Node2D.new()
	_aim_marker.name = "AimMarker"
	_aim_marker.top_level = true
	_aim_marker.z_index = 10
	_aim_marker.visible = false
	add_child(_aim_marker)

	var segments: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-MARKER_SIZE, 0.0), Vector2(-MARKER_GAP, 0.0)]),
		PackedVector2Array([Vector2(MARKER_GAP, 0.0), Vector2(MARKER_SIZE, 0.0)]),
		PackedVector2Array([Vector2(0.0, -MARKER_SIZE), Vector2(0.0, -MARKER_GAP)]),
		PackedVector2Array([Vector2(0.0, MARKER_GAP), Vector2(0.0, MARKER_SIZE)]),
	]
	for segment: PackedVector2Array in segments:
		var line := Line2D.new()
		line.points = segment
		line.width = 2.0
		line.default_color = MARKER_IDLE_COLOR
		_aim_marker.add_child(line)
		_marker_lines.append(line)


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

	# Bullet time slows the world, not the player: undo the global time scale
	# for every timer here and for movement.
	_inv_time_scale = 1.0 / maxf(TimeControlScript.bullet_time_factor, 0.001)
	var dt: float = delta * _inv_time_scale

	_invulnerability_timer = maxf(_invulnerability_timer - dt, 0.0)
	_cooldown_timer = maxf(_cooldown_timer - dt, 0.0)
	_dash_buffer = maxf(_dash_buffer - dt, 0.0)
	if combo > 0:
		_combo_timer = maxf(_combo_timer - dt, 0.0)
		if _combo_timer <= 0.0:
			_break_combo()
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - dt, 0.0)
		if _flash_timer <= 0.0 and body != null:
			body.color = _base_color

	# Rotate to face mouse. Aim stays free while winding. Subtract the shake
	# offset so a shaking camera never skews aim or the dash direction.
	look_at(_aim_point())

	if _dash_state == DashState.DASHING:
		_update_dash(delta, dt)
		return

	_update_wind(dt)

	var move_input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var ground_velocity: Vector2 = move_input * speed + _momentum
	velocity = ground_velocity * _inv_time_scale
	move_and_slide()
	_update_momentum(dt)

	if _cooldown_timer <= 0.0 and _dash_buffer > 0.0:
		_dash_buffer = 0.0
		_start_dash()

	_update_camera(dt, ground_velocity)


## Hold to wind, release to dash. Wind starts at zero on press and is spent by
## the release, so every dash is aimed with a deliberate hold length.
func _update_wind(delta: float) -> void:
	# `just_pressed` is folded in so a press+release inside one physics tick is
	# still seen as a (zero-length) hold rather than being dropped.
	var pressed: bool = Input.is_action_pressed(&"dash") or Input.is_action_just_pressed(&"dash")

	if not _winding and _dash_buffer <= 0.0 and pressed:
		_winding = true
		_wind = 0.0
		if wind_audio != null:
			wind_audio.pitch_scale = 0.7
			wind_audio.play()

	if _winding:
		if pressed:
			_wind = minf(_wind + delta / maxf(dash_wind_time, 0.001), 1.0)
			if wind_audio != null:
				wind_audio.pitch_scale = lerpf(0.7, 1.9, _wind)
		else:
			# Release fires the dash; if the cooldown is still running the
			# release is buffered and fires the moment it ends.
			_winding = false
			_dash_buffer = DASH_BUFFER_TIME
			if wind_audio != null:
				wind_audio.stop()

	_update_wind_visuals()


## Smooth S-curve: 0 at zero wind, 1 at full wind, flat at both ends.
func wind_curve() -> float:
	return _wind - wind_curve_strength * sin(TAU * _wind) / TAU


func dash_distance() -> float:
	return dash_max_distance * wind_curve()


func _update_wind_visuals() -> void:
	var active: bool = _winding or _dash_buffer > 0.0

	if outline != null:
		if active:
			outline.width = _base_outline_width + 4.0 * _wind
			outline.default_color = _base_outline_color.lerp(Color.WHITE, _wind)
		else:
			outline.width = _base_outline_width
			outline.default_color = _base_outline_color

	_update_aim_marker(active)


func _update_aim_marker(active: bool) -> void:
	_aim_marker.visible = active
	if not active:
		return

	var distance: float = dash_distance()
	var origin: Vector2 = global_position
	var endpoint: Vector2 = origin + Vector2.RIGHT.rotated(rotation) * distance
	_aim_marker.global_position = endpoint

	var segment: Vector2 = endpoint - origin
	var segment_len_sq: float = segment.length_squared()
	var danger: bool = false
	var execute: bool = false

	for node: Node in get_tree().get_nodes_in_group(&"executables"):
		var target: Executable = node as Executable
		if target == null or not is_instance_valid(target):
			continue

		var end_distance: float = endpoint.distance_to(target.global_position)
		if not target.proximity_execution and end_distance <= target.body_range():
			danger = true
			continue

		var path_distance: float = _closest_path_distance(target.global_position, origin, segment, segment_len_sq)

		if target.proximity_execution:
			if path_distance <= target.execute_range():
				execute = true
			continue

		if end_distance > target.execute_range():
			continue
		if path_distance <= target.radius:
			execute = true

	var color: Color = MARKER_IDLE_COLOR
	if danger:
		color = MARKER_DANGER_COLOR
	elif execute:
		color = MARKER_EXECUTE_COLOR
	for line in _marker_lines:
		line.default_color = color


func _closest_path_distance(point: Vector2, from: Vector2, segment: Vector2, segment_len_sq: float) -> float:
	var t: float = 0.0
	if segment_len_sq > 0.0001:
		t = clampf((point - from).dot(segment) / segment_len_sq, 0.0, 1.0)
	return (from + segment * t).distance_to(point)


func _reset_wind_visuals() -> void:
	if _aim_marker != null:
		_aim_marker.visible = false
	if outline != null:
		outline.width = _base_outline_width
		outline.default_color = _base_outline_color


func _update_momentum(delta: float) -> void:
	_momentum = _momentum.move_toward(Vector2.ZERO, momentum_decay * delta)


func _update_camera(dt: float, motion: Vector2) -> void:
	var look_ahead: Vector2 = motion * CAMERA_LOOK_AHEAD_PER_SPEED
	if look_ahead.length_squared() > CAMERA_LOOK_AHEAD * CAMERA_LOOK_AHEAD:
		look_ahead = look_ahead.normalized() * CAMERA_LOOK_AHEAD

	# Frame-rate independent smoothing toward the lead position.
	camera.position = camera.position.lerp(look_ahead, 1.0 - exp(-CAMERA_LOOK_SMOOTHING * dt))

	# Glue the camera to the player during a dash so it cannot fall behind.
	var dash_ratio: float = clampf(motion.length() / maxf(speed * 3.0, 1.0), 0.0, 1.0)
	camera.position_smoothing_speed = lerpf(CAMERA_BASE_SMOOTHING, CAMERA_DASH_SMOOTHING, dash_ratio) * _inv_time_scale

	_update_shake(dt)
	_update_zoom(dt)


## Trauma model: trauma² keeps small hits subtle while big ones still read.
func _update_shake(dt: float) -> void:
	_trauma = maxf(_trauma - SHAKE_DECAY * dt, 0.0)
	var shake: float = _trauma * _trauma
	if shake <= 0.0001:
		camera.offset = Vector2.ZERO
		return
	camera.offset = Vector2.from_angle(randf() * TAU) * SHAKE_MAX_OFFSET * shake


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Single multiplier recomputed every frame so it always settles to exactly 1.
func _update_zoom(dt: float) -> void:
	_zoom_mult = lerpf(_zoom_mult, 1.0, 1.0 - exp(-14.0 * dt))
	if absf(_zoom_mult - 1.0) < 0.0005:
		_zoom_mult = 1.0
	camera.zoom = Vector2.ONE * _zoom_mult


func _aim_point() -> Vector2:
	return get_global_mouse_position() - camera.offset


func _freeze(duration: float) -> void:
	# Hit-stop is an accent; in bullet time the world is already slow.
	if TimeControlScript.bullet_time_factor < 0.95:
		duration *= 0.5
	TimeControlScript.freeze(get_tree(), duration)


func _emit_dash_ghosts(distance: float) -> void:
	_ghost_travel += distance
	while _ghost_travel >= GHOST_SPACING:
		_ghost_travel -= GHOST_SPACING
		if get_tree().get_nodes_in_group(&"dash_ghosts").size() >= MAX_GHOSTS:
			break
		var parent: Node = get_parent()
		if parent == null:
			break
		var ghost := DashGhostScript.new()
		ghost.configure(_body_points, _base_color, rotation)
		ghost.z_index = -1
		ghost.add_to_group(&"dash_ghosts")
		parent.add_child(ghost)
		ghost.global_position = global_position


func _start_dash() -> void:
	var ratio: float = wind_curve()
	var distance: float = dash_distance()
	_dash_speed = distance / maxf(dash_duration, 0.001)
	_dash_damage = roundi(lerpf(float(dash_min_damage), float(dash_max_damage), ratio))

	var to_mouse: Vector2 = _aim_point() - global_position
	if to_mouse.length_squared() > 0.0001:
		_dash_direction = to_mouse.normalized()
	else:
		_dash_direction = Vector2.RIGHT.rotated(rotation)

	_dash_remaining = distance
	_dash_state = DashState.DASHING
	_winding = false
	_dash_crossings.clear()
	_dash_executed = false
	_ghost_travel = 0.0

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


func _update_dash(delta: float, dt: float) -> void:
	var from: Vector2 = global_position

	# Step by remaining distance, not by a timer, so the dash lands exactly on
	# its wind distance. A timer overshoots by a whole frame at 4200 px/s,
	# which is wider than the execute bands.
	var step: float = minf(_dash_speed * dt, _dash_remaining)
	velocity = _dash_direction * (step / maxf(delta, 0.0001))
	move_and_slide()
	_dash_remaining -= step
	_emit_dash_ghosts(step)

	# Track how close the travelled segment got to each enemy, so a 4200 px/s
	# dash cannot tunnel past anything and a wall stop stays exact.
	_track_dash_crossings(from, global_position)

	# Enemies have collision exceptions during the dash, so any slide hit is a
	# wall: end the dash early on contact.
	if get_slide_collision_count() > 0 or _dash_remaining <= 0.0001:
		_end_dash()

	_update_camera(dt, _dash_direction * _dash_speed)


func _track_dash_crossings(from: Vector2, to: Vector2) -> void:
	var segment: Vector2 = to - from
	var segment_len_sq: float = segment.length_squared()

	for node: Node in get_tree().get_nodes_in_group(&"executables"):
		var target: Executable = node as Executable
		if target == null or not is_instance_valid(target):
			continue

		var t: float = 0.0
		if segment_len_sq > 0.0001:
			t = clampf((target.global_position - from).dot(segment) / segment_len_sq, 0.0, 1.0)
		var closest: Vector2 = from + segment * t
		var path_distance: float = closest.distance_to(target.global_position)

		var instance_id: int = target.get_instance_id()
		var previous: float = _dash_crossings.get(instance_id, INF)
		if path_distance < previous:
			_dash_crossings[instance_id] = path_distance


## Classifies everything the dash met, using where the dash actually ended.
## Body > execute > normal hit, in that priority.
func _resolve_dash_hits() -> void:
	var end_pos: Vector2 = global_position
	var body_source: Vector2 = Vector2.ZERO
	var body_hit: bool = false
	var hits: int = 0
	var kills: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"executables"):
		var target: Executable = node as Executable
		if target == null or not is_instance_valid(target):
			continue

		var instance_id: int = target.get_instance_id()
		var end_distance: float = end_pos.distance_to(target.global_position)
		var size: float = target.radius

		# Ended inside the body: costs the player a hit and deals no damage.
		if not target.proximity_execution and end_distance <= target.body_range():
			body_hit = true
			body_source = target.global_position
			continue

		var path_distance: float = _dash_crossings.get(instance_id, INF)
		var hit_radius: float = radius + size + DASH_HIT_RADIUS_BONUS
		if path_distance > hit_radius:
			continue

		var executed: bool = false
		if target.proximity_execution:
			# Small movers execute by the path clipping them, not by where the
			# dash happens to end.
			executed = path_distance <= target.execute_range()
		else:
			# Execution needs the path to have gone through the body itself.
			executed = path_distance <= size and end_distance <= target.execute_range()

		if executed:
			if _execute(target, end_distance, size):
				kills += 1
			hits += 1
		else:
			_deal_damage(target, _dash_damage, NORMAL_DAMAGE_COLOR)
			hits += 1
			if target.health <= 0:
				kills += 1

	if hits > 0:
		_freeze(HITSTOP_KILL if kills > 0 else HITSTOP_HIT)
		add_trauma(0.32 if kills > 0 else 0.18)
	if kills > 0:
		_zoom_mult = ZOOM_PUNCH

	if body_hit:
		_take_body_damage(body_source)


## Applies damage and its visual feedback. Returns true if the hit was lethal.
func _execute(target: Executable, end_distance: float, size: float) -> bool:
	var damage: int = _dash_damage * target.execute_damage_scale
	var perfect: bool = target.perfect_ratio > 0.0 and end_distance <= size * target.perfect_ratio

	_deal_damage(target, damage, EXECUTE_DAMAGE_COLOR)
	var killed: bool = target.health <= 0
	_dash_executed = true

	# The boss cashes your chain: a normal execute resets it, a perfect one or
	# a kill keeps it going.
	if target.execute_breaks_combo and not perfect and not killed:
		_break_combo()
	else:
		_add_combo()

	return killed


func _deal_damage(target: Executable, amount: int, color: Color) -> void:
	target.take_damage(amount, _dash_direction)

	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_parent()
	if parent == null:
		return

	var number := DamageNumberScript.new()
	number.configure(amount, color, target.global_position)
	number.z_index = 20
	parent.add_child(number)
	number.global_position = target.global_position


func _add_combo() -> void:
	combo += 1
	_combo_timer = COMBO_WINDOW
	_update_bullet_time()
	combo_changed.emit(combo)


func _break_combo() -> void:
	if combo == 0:
		return
	combo = 0
	_combo_timer = 0.0
	_update_bullet_time()
	combo_changed.emit(0)


## The world slows logarithmically with the chain; the player does not slow,
## because every player timer and movement is compensated by _inv_time_scale.
func _update_bullet_time() -> void:
	var target: float = 1.0
	if combo > 0:
		target = 1.0 - 0.15 * log(1.0 + float(combo))
	TimeControlScript.set_bullet_time(target)


## The combo shield may destroy projectiles and cancel attacks -nothing else.
## Projectiles do not exist yet; this is the hook Stage 5 fills in.
func _clear_hostile_hazards() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"hostile_projectiles"):
		if is_instance_valid(node):
			node.queue_free()


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
	_winding = false
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


func _apply_damage(amount: int, from_position: Vector2) -> void:
	# A live execution chain is a shield: it eats the hit and clears hostile
	# projectiles and attacks, and the chain is what you lose.
	if combo > 0:
		_invulnerability_timer = damage_cooldown
		_flash_timer = HIT_FLASH_TIME
		if body != null:
			body.color = Color(0.8, 1.0, 1.0)
		_clear_hostile_hazards()
		_break_combo()
		_freeze(HITSTOP_HIT)
		add_trauma(0.25)
		return

	health -= amount
	_invulnerability_timer = damage_cooldown
	_flash_timer = HIT_FLASH_TIME
	if body != null:
		body.color = Color(1.0, 0.25, 0.25)
	_break_combo()

	# Knock away from whatever hit us; `from_position` finally earns its keep.
	var away: Vector2 = global_position - from_position
	if away.length_squared() > 0.01:
		_momentum = away.normalized() * HURT_KNOCKBACK

	_freeze(HITSTOP_HURT)
	add_trauma(0.45)
	hurt.emit()
	health_changed.emit(maxi(health, 0), max_health)

	if health <= 0:
		_die()


func _die() -> void:
	if _dead:
		return

	_dead = true
	health = 0
	_break_combo()
	TimeControlScript.reset()
	_cancel_dash()
	velocity = Vector2.ZERO
	if body != null:
		body.color = Color(0.35, 0.45, 0.35)
	if outline != null:
		outline.default_color = Color(0.5, 0.6, 0.5)
	died.emit()
