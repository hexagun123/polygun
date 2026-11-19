class_name WaveDirector
extends Node2D

signal wave_changed(wave: int, total: int)
signal level_changed(level: int, total: int)
signal boss_spawned(boss: Boss)
signal level_cleared(level: int)
signal run_finished(victory: bool)

enum State {
	IDLE,
	FIGHTING,
	INTERMISSION,
	BOSS,
	FINISHED,
}

const ENEMY_SCRIPTS: Dictionary = {
	&"chaser": preload("res://entities/enemy/enemy.gd"),
	&"spitter": preload("res://entities/enemy/spitter.gd"),
	&"lunger": preload("res://entities/enemy/lunger.gd"),
	&"tank": preload("res://entities/enemy/tank.gd"),
}

## One level for now. Each entry is a wave: a list of {role, count} groups.
const WAVES: Array = [
	[
		{"role": &"chaser", "count": 4},
	],
	[
		{"role": &"chaser", "count": 3},
		{"role": &"spitter", "count": 2},
	],
	[
		{"role": &"chaser", "count": 3},
		{"role": &"spitter", "count": 2},
		{"role": &"lunger", "count": 1},
		{"role": &"tank", "count": 1},
	],
]

const INTERMISSION_TIME: float = 0.8
const SPAWN_MIN_DISTANCE: float = 300.0
const SPAWN_MAX_DISTANCE: float = 560.0
const ARENA_LIMIT: float = 1400.0
const BOSS_SPAWN_DISTANCE: float = 520.0
const MIN_SPAWN_CLEARANCE: float = 240.0
const END_DELAY: float = 0.8

var state: State = State.IDLE
var level: int = 1
var total_levels: int = 1
var wave: int = 0
var total_waves: int = WAVES.size()

var _alive: int = 0
var _boss: Boss = null
var _rng := RandomNumberGenerator.new()
var _intermission_timer: Timer
var _end_timer: Timer


func _ready() -> void:
	add_to_group(&"director")
	_rng.randomize()

	_intermission_timer = Timer.new()
	_intermission_timer.one_shot = true
	_intermission_timer.timeout.connect(_on_intermission_timeout)
	add_child(_intermission_timer)

	_end_timer = Timer.new()
	_end_timer.one_shot = true
	_end_timer.timeout.connect(_on_end_timeout)
	add_child(_end_timer)

	# The player is a sibling earlier in the scene, but deferring keeps this
	# working even if the tree order changes.
	call_deferred(&"_begin")


func _begin() -> void:
	TimeControl.reset()
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_signal(&"died"):
		player.died.connect(_on_player_died)
	level_changed.emit(level, total_levels)
	_start_wave(1)


func _start_wave(index: int) -> void:
	wave = clampi(index, 1, total_waves)
	state = State.FIGHTING
	_alive = 0
	_clear_hostile_projectiles()
	wave_changed.emit(wave, total_waves)
	_spawn_wave(WAVES[wave - 1])


func _spawn_wave(composition: Array) -> void:
	var origin: Vector2 = _player_position()

	var total: int = 0
	for entry: Dictionary in composition:
		total += int(entry["count"])

	var index: int = 0
	for entry: Dictionary in composition:
		var script: Script = ENEMY_SCRIPTS[entry["role"]]
		for i in int(entry["count"]):
			# Even sectors with jitter spread the ring without stacking enemies.
			var angle: float = TAU * float(index) / float(maxi(total, 1)) + _rng.randf_range(-0.3, 0.3)
			var distance: float = _rng.randf_range(SPAWN_MIN_DISTANCE, SPAWN_MAX_DISTANCE)
			var position: Vector2 = _ring_position(origin, angle, distance)

			var enemy: Enemy = script.new()
			add_child(enemy)
			enemy.global_position = position
			_alive += 1
			enemy.died.connect(_on_enemy_died)
			index += 1


func _on_enemy_died(_enemy: Executable) -> void:
	if state != State.FIGHTING:
		return

	_alive = maxi(_alive - 1, 0)
	if _alive == 0:
		state = State.INTERMISSION
		_intermission_timer.start(INTERMISSION_TIME)


func _on_intermission_timeout() -> void:
	if state != State.INTERMISSION:
		return

	if wave >= total_waves:
		_spawn_boss()
	else:
		_start_wave(wave + 1)


func _spawn_boss() -> void:
	state = State.BOSS
	_clear_hostile_projectiles()
	var origin: Vector2 = _player_position()
	var angle: float = _rng.randf_range(0.0, TAU)
	var position: Vector2 = _ring_position(origin, angle, BOSS_SPAWN_DISTANCE)

	_boss = load("res://entities/enemy/boss.gd").new()
	add_child(_boss)
	_boss.global_position = position
	_boss.died.connect(_on_boss_died)
	boss_spawned.emit(_boss)


func _on_boss_died(_boss_node: Executable) -> void:
	if state != State.BOSS:
		return
	# One level today: clear it and end the run. Extra levels become another
	# WAVES entry and a level advance here.
	level_cleared.emit(level)
	_finish(true)


func _on_player_died() -> void:
	_finish(false)


func _finish(victory: bool) -> void:
	if state == State.FINISHED:
		return

	state = State.FINISHED
	run_finished.emit(victory)
	_end_timer.start(END_DELAY)


func _on_end_timeout() -> void:
	# Freeze the arena; the HUD runs with PROCESS_MODE_ALWAYS and owns restart.
	get_tree().paused = true


func _clear_hostile_projectiles() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"hostile_projectiles"):
		if is_instance_valid(node):
			node.queue_free()


func _player_position() -> Vector2:
	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if player != null and is_instance_valid(player):
		return player.global_position
	return Vector2.ZERO


func _clamp_to_arena(position: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, -ARENA_LIMIT, ARENA_LIMIT),
		clampf(position.y, -ARENA_LIMIT, ARENA_LIMIT)
	)


## Ring spawn clamped to the arena, with an inward fallback for corner cases
## so enemies never land on top of the player.
func _ring_position(origin: Vector2, angle: float, distance: float) -> Vector2:
	var position: Vector2 = _clamp_to_arena(origin + Vector2.from_angle(angle) * distance)
	if position.distance_to(origin) >= MIN_SPAWN_CLEARANCE:
		return position

	var inward: Vector2 = -origin
	if inward.length_squared() < 1.0:
		inward = Vector2.UP
	return _clamp_to_arena(origin + inward.normalized() * distance)
