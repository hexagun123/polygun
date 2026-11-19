class_name Enemy
extends Polygon

signal died(enemy: Enemy)
signal health_changed(current: int, maximum: int)

const SfxScript = preload("res://audio/sfx.gd")
const DeathBurstScript = preload("res://entities/fx/death_burst.gd")

const KNOCKBACK_DECAY: float = 900.0
const BODY_COLOR: Color = Color(1.0, 0.35, 0.3)

@export var speed: float = 140.0
@export var max_health: int = 3
@export var contact_damage: int = 1
@export var knockback_force: float = 260.0
@export var knockback_scale: float = 1.0
@export var hit_flash_time: float = 0.08

## When false the enemy keeps its current facing (used while charging).
var face_target: bool = true

var health: int = 3
var hit_audio: AudioStreamPlayer
var _base_color: Color = Color.WHITE
var _knockback: Vector2 = Vector2.ZERO
var _flash_timer: float = 0.0


func _init() -> void:
	# Code-created enemies need sane visual defaults (Polygon's are tiny).
	sides = 5
	radius = 20.0
	color = BODY_COLOR


func _ready() -> void:
	# Walls, other enemies and projectiles live on layer 1.
	collision_layer = 1
	collision_mask = 1
	add_to_group(&"enemies")

	health = max_health
	super._ready()

	_base_color = color
	hit_audio = AudioStreamPlayer.new()
	hit_audio.stream = SfxScript.make_noise(0.06, 9000.0)
	add_child(hit_audio)

	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		if _flash_timer <= 0.0 and body != null:
			body.color = _base_color

	var player := _get_player()
	var desired_velocity: Vector2 = Vector2.ZERO
	if player != null:
		desired_velocity = _get_desired_velocity(delta, player)
		if face_target:
			var to_player: Vector2 = player.global_position - global_position
			if to_player.length_squared() > 0.001:
				look_at(player.global_position)
		_try_contact_damage(player)

	velocity = desired_velocity + _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	move_and_slide()


## Movement hook. The boss overrides this to run its attack state machine.
func _get_desired_velocity(_delta: float, player: Node2D) -> Vector2:
	var to_player: Vector2 = player.global_position - global_position
	if to_player.length_squared() <= 0.001:
		return Vector2.ZERO
	return to_player.normalized() * speed


func take_damage(amount: int, hit_direction: Vector2) -> void:
	if amount <= 0 or health <= 0:
		return

	health -= amount
	_flash_timer = hit_flash_time
	if body != null:
		body.color = Color.WHITE

	if hit_direction.length_squared() > 0.0:
		_knockback = hit_direction.normalized() * knockback_force * knockback_scale

	health_changed.emit(maxi(health, 0), max_health)

	if health <= 0:
		_die()
	elif hit_audio != null:
		hit_audio.stop()
		hit_audio.play()


func _die() -> void:
	# Wave bookkeeping listens to this before the node is freed.
	health = 0
	died.emit(self)

	var burst := DeathBurstScript.new()
	burst.color = _base_color.lightened(0.15)
	var burst_parent: Node = get_parent()
	if burst_parent == null:
		burst_parent = get_tree().current_scene
	if burst_parent != null:
		burst_parent.add_child(burst)
		burst.global_position = global_position

		# The enemy is about to be freed, which would cut off its own hit
		# sound; play the killing blow through a short-lived sibling instead.
		if hit_audio != null:
			var impact := AudioStreamPlayer.new()
			impact.stream = hit_audio.stream
			burst_parent.add_child(impact)
			impact.finished.connect(impact.queue_free)
			impact.play()

	queue_free()


func _get_player() -> Node2D:
	var node: Node = get_tree().get_first_node_in_group(&"player")
	if node is Node2D and is_instance_valid(node):
		return node as Node2D
	return null


func _try_contact_damage(player: Node2D) -> void:
	var player_radius: float = radius
	if player is Polygon:
		player_radius = (player as Polygon).radius
	var touch_distance: float = radius + player_radius

	if global_position.distance_squared_to(player.global_position) > touch_distance * touch_distance:
		return

	if player.has_method(&"take_damage"):
		player.call(&"take_damage", contact_damage, global_position)
