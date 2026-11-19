class_name EnemyProjectile
extends Executable

## Slow hostile shot. Executable by proximity during a dash (combo fuel), and
## destroyed by a normal dash hit for no combo.

@export var speed: float = 260.0
@export var damage: int = 1
@export var lifetime: float = 3.0

var _direction: Vector2 = Vector2.RIGHT
var _life: float = 3.0


func _init() -> void:
	sides = 3
	radius = 6.0
	color = Color(1.0, 0.55, 0.85)
	max_health = 1
	hit_flash_time = 0.06
	execute_ratio = 1.0
	body_ratio = 0.0
	proximity_execution = true
	execute_floor = 40.0
	execute_damage_scale = 1


func launch(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		_direction = direction.normalized()
	rotation = _direction.angle()


func _ready() -> void:
	# Purely a visual/queries object: it must never block the player.
	collision_layer = 0
	collision_mask = 0
	add_to_group(&"executables")
	add_to_group(&"hostile_projectiles")

	super._ready()
	_life = lifetime


func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return

	_tick_flash(delta)

	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null or not is_instance_valid(player) or not (player is Polygon):
		return

	var player_radius: float = (player as Polygon).radius
	var touch: float = radius + player_radius
	if global_position.distance_squared_to((player as Node2D).global_position) > touch * touch:
		return

	# Only fizzle on a hit that actually landed; during dash i-frames the shot
	# survives so the dash can execute it instead.
	var landed: Variant = player.call(&"take_damage", damage, global_position)
	if landed == true:
		queue_free()
