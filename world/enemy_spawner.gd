class_name EnemySpawner
extends Node2D

const EnemyScript = preload("res://entities/enemy/enemy.gd")

const MIN_SPAWN_DISTANCE: float = 260.0

@export var count: int = 3
@export var spawn_radius: float = 700.0


func _ready() -> void:
	_spawn_enemies()


func _spawn_enemies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Spawn as our own children: the arena may still be setting up its other
	# children while this node's _ready() runs.
	var max_distance: float = maxf(spawn_radius, MIN_SPAWN_DISTANCE)
	for i in range(count):
		# Even sectors with jitter keep the spawn ring readable and spread out.
		var base_angle: float = TAU * float(i) / float(maxi(count, 1))
		var angle: float = base_angle + rng.randf_range(-0.35, 0.35)
		var distance: float = rng.randf_range(MIN_SPAWN_DISTANCE, max_distance)

		var enemy := EnemyScript.new()
		add_child(enemy)
		enemy.global_position = global_position + Vector2.from_angle(angle) * distance
