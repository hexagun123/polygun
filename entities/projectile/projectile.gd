extends Node2D

class_name Projectile

const WORLD_LAYER_MASK: int = 1

@export var speed: float = 1200.0
@export var lifetime: float = 1.3
@export var radius: float = 6.0
@export var color: Color = Color(1.0, 0.9, 0.25)

var direction: Vector2 = Vector2.RIGHT
var age: float = 0.0


func _ready() -> void:
	var body := Polygon2D.new()
	var points := PackedVector2Array()
	points.append(Vector2(radius, 0.0))
	points.append(Vector2(-radius * 0.6, radius * 0.6))
	points.append(Vector2(-radius * 0.6, -radius * 0.6))
	body.polygon = points
	body.color = color
	add_child(body)

	var outline := Line2D.new()
	var outline_points: PackedVector2Array = points.duplicate()
	outline_points.append(points[0])
	outline.points = outline_points
	outline.width = 1.0
	outline.default_color = color.lightened(0.4)
	add_child(outline)


func launch(origin: Vector2, launch_direction: Vector2) -> void:
	global_position = origin
	if launch_direction.length_squared() > 0.0:
		direction = launch_direction.normalized()
	else:
		direction = Vector2.RIGHT
	rotation = direction.angle()
	age = 0.0


func _physics_process(delta: float) -> void:
	var motion: Vector2 = direction * speed * delta

	# Raycast instead of an area so fast shots can't tunnel through the
	# segment-based arena walls. The player is on layer 2 and is ignored.
	var query := PhysicsRayQueryParameters2D.create(
		global_position, global_position + motion, WORLD_LAYER_MASK
	)
	query.collide_with_areas = false
	# A shot fired point-blank starts inside the enemy's shape. Without this the
	# ray ignores that body and the hit is lost.
	query.hit_from_inside = true
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit["position"]
		var collider: Variant = hit.get("collider")
		if collider != null and collider.has_method(&"take_damage"):
			collider.call(&"take_damage", 1, direction)
		queue_free()
		return

	global_position += motion
	age += delta
	if age >= lifetime:
		queue_free()
