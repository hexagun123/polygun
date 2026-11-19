class_name Tank
extends Enemy

## Slow, heavy, and hard to shove. Survives one execute (9 HP vs 6 damage), so
## it acts as a combo anchor while you deal with everything around it.


func _init() -> void:
	super()
	sides = 6
	radius = 34.0
	color = Color(0.95, 0.55, 0.2)
	outline_width = 2.0
	max_health = 9
	contact_damage = 2
	speed = 70.0
	knockback_scale = 0.2
