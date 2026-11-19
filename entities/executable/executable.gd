class_name Executable
extends Polygon

## Anything the dash can hit and execute: enemies, projectiles, later spawns.
## Owns the shared health / flash / execution data so one resolution path in
## the player handles every type.

signal died(executable: Executable)
signal health_changed(current: int, maximum: int)

@export var max_health: int = 3
@export var hit_flash_time: float = 0.08

@export_group("Execution")
## Distance from the dash endpoint to this object's centre, as a multiple of
## radius, within which a dash that crossed the body executes.
@export var execute_ratio: float = 2.0
## Tighter optional band: executing inside it keeps the combo even when
## `execute_breaks_combo` is set (0 disables it).
@export var perfect_ratio: float = 0.0
## Dash ending inside this multiple of radius costs the player a hit.
@export var body_ratio: float = 0.6
@export var execute_damage_scale: int = 3
## Bosses reset the chain when executed, unless the hit is perfect or lethal.
@export var execute_breaks_combo: bool = false
## Absolute execute range for tiny objects (projectiles), where radius alone
## would make the window impossible. 0 = pure ratio.
@export var execute_floor: float = 0.0
## Projectiles execute by how close the dash path passes, not by where it ends.
@export var proximity_execution: bool = false

var health: int = 3

var _base_color: Color = Color.WHITE
var _flash_timer: float = 0.0


func _ready() -> void:
	health = max_health
	super._ready()
	_base_color = color
	health_changed.emit(health, max_health)


func execute_range() -> float:
	return maxf(radius * execute_ratio, execute_floor)


func body_range() -> float:
	return radius * body_ratio


func take_damage(amount: int, hit_direction: Vector2) -> void:
	if amount <= 0 or health <= 0:
		return

	health -= amount
	_flash_timer = hit_flash_time
	if body != null:
		body.color = Color.WHITE

	_on_damaged(hit_direction)
	health_changed.emit(maxi(health, 0), max_health)

	if health <= 0:
		_die()
	else:
		_on_survived_hit()


## Hook for subclasses (knockback and similar).
func _on_damaged(_hit_direction: Vector2) -> void:
	pass


## Hook for feedback that only makes sense when the object survives.
func _on_survived_hit() -> void:
	pass


func _die() -> void:
	health = 0
	died.emit(self)
	queue_free()


func _tick_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	if _flash_timer <= 0.0 and body != null:
		body.color = _base_color
