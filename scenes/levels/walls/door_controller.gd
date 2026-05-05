@tool
extends StaticBody3D
## Control script for the door, handles locking and unlocking.

# Export variables
## Whether the door is locked or not.
@export var is_locked: bool = false:
	set(value):
		is_locked = value
		if door:
			door.is_locked = value

# Initialize child nodes
@onready var door: Node3D = $Door

func _ready() -> void:
	# Sync the inner Door node once at startup so the setter doesn't have to
	# fire every frame to keep them aligned.
	if door:
		door.is_locked = is_locked
