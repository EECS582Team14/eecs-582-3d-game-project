extends Control

signal back_to_menu

func _ready() -> void:
	visible = false
	$BackButton.pressed.connect(_on_back_button_pressed)

func _input(event: InputEvent) -> void:
	# Only handle input when settings menu is visible
	if not visible:
		return
	
	# Go back to pause menu when Escape is pressed
	if event is InputEventKey and event.pressed and event.key_label == KEY_ESCAPE:
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


func _on_back_button_pressed():
	back_to_menu.emit()
