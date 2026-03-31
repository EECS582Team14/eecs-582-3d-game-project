extends StaticBody3D

@export var elevator: AnimatableBody3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func activate() -> void:
	print("ElevatorButton activate() called!")
	
	if elevator == null:
		push_warning("ElevatorButton: elevator reference not set!")
		return
	
	elevator.activate()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
