class_name DamageNumber
extends Node2D

## A short-lived floating number. Lives under the current scene, not the enemy,
## so it survives the enemy being freed by the same hit.

const TimeControlScript = preload("res://entities/fx/time_control.gd")

const LIFETIME: float = 0.5
const RISE: float = 46.0

var _label: Label
var _start: Vector2 = Vector2.ZERO
var _life: float = LIFETIME


func configure(amount: int, color: Color, at: Vector2) -> void:
	_start = at
	var label := Label.new()
	label.text = str(amount)
	label.size = Vector2(48.0, 26.0)
	label.position = Vector2(-24.0, -30.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", ThemeDB.fallback_font)
	label.add_theme_font_size_override(&"font_size", 22)
	label.add_theme_color_override(&"font_color", color)
	add_child(label)
	_label = label


func _process(delta: float) -> void:
	var dt: float = delta / maxf(TimeControlScript.bullet_time_factor, 0.001)
	_life -= dt
	if _life <= 0.0:
		queue_free()
		return

	var t: float = 1.0 - _life / LIFETIME
	global_position = _start + Vector2(0.0, -RISE * t)
	_label.modulate.a = 1.0 - t * t
