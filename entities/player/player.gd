class_name Player
extends Polygon

const ProjectileScript = preload("res://entities/projectile/projectile.gd")
const SfxScript = preload("res://audio/sfx.gd")

@export var speed: float = 300.0
@export var camera_bounds_half_size: Vector2 = Vector2(1536.0, 1536.0)
@export var fire_cooldown: float = 0.12
@export var muzzle_offset: float = 30.0
@export var max_health: int = 3
@export var damage_cooldown: float = 0.7

const HIT_FLASH_TIME: float = 0.12

var camera: Camera2D = Camera2D.new()
var fire_timer: float = 0.0
var fire_audio: AudioStreamPlayer
var health: int = 3
var _base_color: Color = Color.WHITE
var _invulnerability_timer: float = 0.0
var _flash_timer: float = 0.0

func _ready() -> void:
	add_to_group(&"player")

	# Projectiles scan layer 1 (world) only; keep the player out of that layer.
	collision_layer = 2

	health = max_health
	_base_color = color

	# camera settings
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10.0
	add_child(camera)
	camera.make_current()
	_update_camera_limits()
	
	super._ready()

	fire_audio = AudioStreamPlayer.new()
	fire_audio.stream = SfxScript.make_tone(1100.0, 500.0, 0.08, 12000.0)
	add_child(fire_audio)


func _update_camera_limits() -> void:
	# Limits apply to the visible rectangle, so the arena bounds can be used
	# directly. Offsetting them by half the viewport locks the camera at the
	# center whenever the window is wider than the arena.
	camera.limit_left = int(-camera_bounds_half_size.x)
	camera.limit_right = int(camera_bounds_half_size.x)
	camera.limit_top = int(-camera_bounds_half_size.y)
	camera.limit_bottom = int(camera_bounds_half_size.y)


func _physics_process(delta: float) -> void:
	_invulnerability_timer = maxf(_invulnerability_timer - delta, 0.0)
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		if _flash_timer <= 0.0 and body != null:
			body.color = _base_color

	# Rotate to face mouse
	look_at(get_global_mouse_position())

	# Movement
	var move_input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = move_input * speed
	move_and_slide()

	fire_timer = maxf(fire_timer - delta, 0.0)
	if Input.is_action_pressed(&"fire") and fire_timer <= 0.0:
		_fire()
		fire_timer = fire_cooldown


func _fire() -> void:
	var direction: Vector2 = get_global_mouse_position() - global_position
	if direction.length_squared() <= 0.0:
		return
	direction = direction.normalized()
	var origin: Vector2 = global_position + direction * muzzle_offset
	var projectile = ProjectileScript.new()
	get_tree().current_scene.add_child(projectile)
	projectile.launch(origin, direction)
	fire_audio.stop()
	fire_audio.play()


func take_damage(amount: int, from_position: Vector2) -> void:
	if _invulnerability_timer > 0.0 or amount <= 0:
		return

	health -= amount
	_invulnerability_timer = damage_cooldown
	_flash_timer = HIT_FLASH_TIME
	if body != null:
		body.color = Color(1.0, 0.25, 0.25)

	if health <= 0:
		_respawn()


func _respawn() -> void:
	health = max_health
	global_position = Vector2.ZERO
	_invulnerability_timer = damage_cooldown
