extends StaticBody3D

@export var elevator: AnimatableBody3D

func activate() -> void:
	print("DoorButton activate() called!")
	
	if elevator == null:
		push_warning("DoorButton: elevator reference not set!")
		return
	
	elevator.open_doors_manually()
