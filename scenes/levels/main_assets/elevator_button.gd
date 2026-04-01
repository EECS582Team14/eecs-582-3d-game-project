extends StaticBody3D

@export var elevator: AnimatableBody3D

func activate() -> void:
	print("ElevatorButton activate() called!")
	
	if elevator == null:
		push_warning("ElevatorButton: elevator reference not set!")
		return
	
	elevator.activate()
