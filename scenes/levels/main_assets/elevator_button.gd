extends StaticBody3D

@export var elevator: AnimatableBody3D
@onready var sound_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

func _ready() -> void:
	pass

func activate() -> void:
	print("ElevatorButton activate() called!")
	
	if elevator == null:
		push_warning("ElevatorButton: elevator reference not set!")
		return
	
	sound_player.play()
	elevator.activate()
