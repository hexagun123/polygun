extends CharacterBody2D

class_name Polygon

@export_category("Polygon settings")
@export_range(3, 64, 1) var sides: int = 3
@export var radius: float = 3.0
@export var color: Color = Color.WHITE
@export var outline_width: float = 1.0

var body : Polygon2D
var outline : Line2D
var collision_box : CollisionPolygon2D

func _ready() -> void:
	_setup()
	_update()
	
func _setup() -> void:
	body = Polygon2D.new()
	add_child(body)
	
	outline = Line2D.new()
	add_child(outline)
	
	collision_box = CollisionPolygon2D.new()
	add_child(collision_box)
	
	
func _update() -> void:
	if sides < 3:
		push_error("Polygon.sides must be at least 3.")
		return

	body.color = color
	outline.width = outline_width
	outline.default_color = color.lightened(0.4)

	var points := PackedVector2Array()
	
	for i in range(sides):
		# Start at +X so look_at() points the polygon's front at the target.
		var angle: float = i * (TAU / sides)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	
	# Apply to visual fill & physics
	body.polygon = points
	collision_box.polygon = points

	# Apply to outline (add first point again to close the loop)
	var outline_points: PackedVector2Array = points.duplicate()
	outline_points.append(points[0])
	outline.points = outline_points
