class_name DeathBurst
extends Node2D

const LIFETIME: float = 0.35
const SHARD_COUNT: int = 10
const SHARD_SPEED: float = 320.0

@export var color: Color = Color(1.0, 0.35, 0.3)

var _shards: Array[Line2D] = []
var _velocities: Array[Vector2] = []
var _age: float = 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in range(SHARD_COUNT):
		var angle: float = rng.randf_range(0.0, TAU)
		var length: float = rng.randf_range(5.0, 14.0)
		var direction: Vector2 = Vector2.from_angle(angle)

		var shard := Line2D.new()
		shard.points = PackedVector2Array([Vector2.ZERO, direction * length])
		shard.width = 2.0
		shard.default_color = color
		add_child(shard)

		_shards.append(shard)
		_velocities.append(direction * rng.randf_range(0.6, 1.0) * SHARD_SPEED)


func _process(delta: float) -> void:
	_age += delta
	var fade: float = 1.0 - clampf(_age / LIFETIME, 0.0, 1.0)

	for i in range(_shards.size()):
		_shards[i].position += _velocities[i] * delta
		_velocities[i] = _velocities[i].move_toward(Vector2.ZERO, SHARD_SPEED * 2.0 * delta)
		_shards[i].modulate.a = fade

	if _age >= LIFETIME:
		queue_free()
