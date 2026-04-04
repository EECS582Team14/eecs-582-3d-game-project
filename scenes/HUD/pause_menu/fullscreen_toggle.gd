extends ColorRect

#Child nodes
@onready var button: Button = $"./HorizontalContainer/FullscreenToggle"

func _ready() -> void:
    button.pressed.connect(_toggle_fullscreen)
    _update_button_label()

func _toggle_fullscreen() -> void:
    var current_mode = DisplayServer.window_get_mode()
    
    if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    else:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
    
    _update_button_label()

func _update_button_label() -> void:
    if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
        button.text = "Windowed"
    else:
        button.text = "Fullscreen"