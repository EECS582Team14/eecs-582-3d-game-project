extends StaticBody3D

@export var elevator: AnimatableBody3D
@onready var sound_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

func _ready() -> void:
	pass

func activate() -> void:
	print("DoorButton activate() called!")
	
	if elevator == null:
		push_warning("DoorButton: elevator reference not set!")
		return
	
	sound_player.play()
	elevator.open_doors_manually()
