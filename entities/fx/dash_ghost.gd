class_name DashGhost
extends Node2D

## A faded copy of the player left behind during a dash. Purely visual.
## Callers preload this script and drive it through `configure()` + add_child.

const TimeControlScript = preload("res://entities/fx/time_control.gd")

const LIFETIME: float = 0.18
const START_ALPHA: float = 0.35

var _points: PackedVector2Array = PackedVector2Array()
var _color: Color = Color.WHITE
var _life: float = LIFETIME
var _polygon: Polygon2D


func configure(points: PackedVector2Array, source_color: Color, facing: float) -> void:
	_points = points
	_color = source_color
	rotation = facing


func _ready() -> void:
	_polygon = Polygon2D.new()
	_polygon.polygon = _points
	_polygon.color = Color(_color.r, _color.g, _color.b, START_ALPHA)
	add_child(_polygon)


func _process(delta: float) -> void:
	# Real time, so ghost density does not change under bullet time.
	_life -= delta / maxf(TimeControlScript.bullet_time_factor, 0.001)
	if _life <= 0.0:
		queue_free()
		return
	_polygon.color.a = START_ALPHA * (_life / LIFETIME)
