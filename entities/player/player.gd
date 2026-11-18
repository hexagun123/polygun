class_name Player
extends Polygon

@export var speed: float = 300.0
@export var camera_bounds_half_size: Vector2 = Vector2(1536.0, 1536.0)


var camera: Camera2D = Camera2D.new()

func _ready() -> void:
	# camera settings
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10.0
	add_child(camera)
	camera.make_current()
	_update_camera_limits()
	
	super._ready()


func _update_camera_limits() -> void:
	# Limits apply to the visible rectangle, so the arena bounds can be used
	# directly. Offsetting them by half the viewport locks the camera at the
	# center whenever the window is wider than the arena.
	camera.limit_left = int(-camera_bounds_half_size.x)
	camera.limit_right = int(camera_bounds_half_size.x)
	camera.limit_top = int(-camera_bounds_half_size.y)
	camera.limit_bottom = int(camera_bounds_half_size.y)


func _physics_process(_delta: float) -> void:
	# Rotate to face mouse
	look_at(get_global_mouse_position())

	# Movement
	var move_input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = move_input * speed
	move_and_slide()
