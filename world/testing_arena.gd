class_name ArenaGrid
extends Node2D

@export var arena_size: Vector2 = Vector2(3000, 3000)
@export var cell_size: float = 64.0
@export var bg_color: Color = Color(0.03, 0.03, 0.06)          # Void color
@export var grid_color: Color = Color(0.12, 0.14, 0.22, 0.5)     # Subtle neon lines
@export var border_color: Color = Color(0.2, 0.8, 1.0)           # Bright arena edge

func _ready() -> void:
	# Force this to render behind everything else in the game
	z_index = -100
	
	# Build the physical walls automatically
	_create_arena_walls()

func _draw() -> void:
	var half_size = arena_size / 2.0
	var top_left = -half_size
	
	# 1. Fill the background
	draw_rect(Rect2(top_left, arena_size), bg_color, true)

	# 2. Draw vertical grid lines
	var x = top_left.x
	while x <= half_size.x:
		draw_line(Vector2(x, top_left.y), Vector2(x, half_size.y), grid_color, 1.0)
		x += cell_size

	# 3. Draw horizontal grid lines
	var y = top_left.y
	while y <= half_size.y:
		draw_line(Vector2(top_left.x, y), Vector2(half_size.x, y), grid_color, 1.0)
		y += cell_size

	# 4. Draw bright arena border outline (unfilled rectangle, width = 4.0)
	draw_rect(Rect2(top_left, arena_size), border_color, false, 4.0)

func _create_arena_walls() -> void:
	var half_size = arena_size / 2.0
	
	var static_body = StaticBody2D.new()
	var collision_shape = CollisionPolygon2D.new()
	
	# Build mode SEGMENTS makes a hollow perimeter so the player stays INSIDE
	collision_shape.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	
	# 4 corners of the arena (closing the loop back at the first corner)
	collision_shape.polygon = PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
		Vector2(-half_size.x, -half_size.y)
	])
	
	static_body.add_child(collision_shape)
	add_child(static_body)
