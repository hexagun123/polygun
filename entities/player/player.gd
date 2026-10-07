class_name Player
extends Polygon

@export var speed := 300.0


var camera := Camera2D.new()

func _ready() -> void:
	sides = 3
	radius = 24.0
	color = Color.GREEN
	
	# camera settings
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)
	
	super._ready()
	
	
func _physics_process(_delta: float) -> void:
	# Rotate to face mouse
	look_at(get_global_mouse_position())

	# Movement
	var move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = move_input * speed
	move_and_slide()
