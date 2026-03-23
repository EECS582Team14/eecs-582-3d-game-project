extends Control

signal back_to_menu

func _ready() -> void:
    visible = false
    $BackButton.pressed.connect(_on_back_button_pressed)



func _on_back_button_pressed():
    back_to_menu.emit()