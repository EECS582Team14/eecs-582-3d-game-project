@tool
extends StaticBody3D
## Control script for the door, handles locking and unlocking.

# Export variables
## Whether the door is locked or not.
@export var is_locked: bool = false

# Initialize child nodes
@onready var door: Node3D = $Door

func _process(_delta: float) -> void:
	if is_locked:
		door.is_locked = true
	else:
		door.is_locked = false
