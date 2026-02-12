extends Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var intro = preload("res://scenes/intro_Text.tscn").instantiate()
	add_child(intro)
	
	var directives = preload("res://scenes/directive_Text.tscn").instantiate()
	add_child(directives)
	print("Directives Loaded")
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
