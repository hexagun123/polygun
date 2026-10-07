extends CharacterBody2D

class_name Polygon

@export_category("Polygon settings")
@export var sides := 3
@export var radius := 3.0
@export var color := Color.WHITE
@export var outline_width := 1.0
@export var outline_color := color.lightened(0.4)

var body : Polygon2D
var outline : Line2D
var collision_box : CollisionPolygon2D

func _ready() -> void:
	_setup()
	_update()
	
func _setup() -> void:
	body = Polygon2D.new()
	body.color = color
	add_child(body)
	
	outline = Line2D.new()
	outline.width = outline_width
	outline.default_color = outline_color
	add_child(outline)
	
	collision_box = CollisionPolygon2D.new()
	add_child(collision_box)
	
	
func _update() -> void:
	var points = PackedVector2Array()
	
	for i in range(sides):
		var angle = (i * (TAU / sides)) - (PI / 2.0)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	
	# Apply to visual fill & physics
	body.polygon = points
	collision_box.polygon = points

	# Apply to outline (add first point again to close the loop)
	var outline_points = points.duplicate()
	outline_points.append(points[0])
	outline.points = outline_points
