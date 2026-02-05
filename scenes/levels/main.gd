extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var result = Steam.steamInitEx()
	print(result)
	if result.status == 0:  # 0 means success in steamInitEx
		print("Hello, ", Steam.getPersonaName())
	else:
		print("Failed: ", result.verbal)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	Steam.run_callbacks()
