extends Control

@export var crosshair_size: int = 18
@export var thickness: int = 2
@export var color: Color = Color(1, 1, 1, 0.55)

func _draw() -> void:
	var center = Vector2.ZERO
	var half = crosshair_size / 2

	# Horizontal line
	draw_rect(Rect2(center.x - half, center.y - thickness / 2.0, crosshair_size, thickness), color)
	# Vertical line
	draw_rect(Rect2(center.x - thickness / 2.0, center.y - half, thickness, crosshair_size), color)
