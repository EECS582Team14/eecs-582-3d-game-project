extends Control

signal resume_game
signal settings_menu
signal quit_game

var _crosshair: Control = null

func _ready() -> void:
	visible = false
	$CenterContainer/PanelContainer/VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$CenterContainer/PanelContainer/VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$CenterContainer/PanelContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

func set_crosshair(crosshair: Control) -> void:
	_crosshair = crosshair

func show_menu() -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _crosshair:
		_crosshair.visible = false

func hide_menu() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _crosshair:
		_crosshair.visible = true

func _input(event: InputEvent) -> void:
	# Only handle input when pause menu is visible
	if not visible:
		return
	
	# Resume game when Escape is pressed in pause menu
	if event is InputEventKey and event.pressed and event.key_label == KEY_ESCAPE:
		_on_resume_pressed()
		get_viewport().set_input_as_handled()

func _on_resume_pressed() -> void:
	resume_game.emit()

func _on_settings_pressed() -> void:
	settings_menu.emit()

func _on_quit_pressed() -> void:
	quit_game.emit()
