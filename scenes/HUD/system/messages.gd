extends Control

@onready var text_label = $Panel/MarginContainer/MainText
@onready var panel = $Panel
var full_text = "You are an autonomous maintenance unit. Prepare the ship for hyperjump. Press 'Z' to view current directives."
var typing_speed = 0.02
var current_index = 0
var typing = true
var is_impostor: bool = false

func _ready():
	text_label.text = ""
	type_text()
	UIState.system_alert.connect(_new_message)
	NetworkManager.emergency_meeting_called.connect(_on_emergency_meeting)
	# Check if role was already assigned
	if NetworkManager.pending_role_received:
		_on_role_assigned(NetworkManager.pending_role_impostor)
	NetworkManager.role_assigned.connect(_on_role_assigned)
func _on_emergency_meeting():
	_new_message("An emergency has been reported. All maintenance units are to report to the Nexus immediately.")

func _on_role_assigned(impostor: bool) -> void:
	is_impostor = impostor
	if is_impostor:
		# Wait for the role reveal delay before changing the panel color
		var local_player = NetworkManager.get_player(Steam.getSteamID())
		var delay = local_player.ROLE_REVEAL_DELAY if local_player else 30.0
		await get_tree().create_timer(delay).timeout
		var style = panel.get_theme_stylebox("panel").duplicate()
		style.bg_color = Color(0.84, 0, 0, 0.5)
		style.border_color = Color(0.78, 0.3, 0.3, 1)
		panel.add_theme_stylebox_override("panel", style)

func reset(text):
	text_label.text = ""
	current_index = 0
	full_text = text
	typing = true
	panel.visible = true

func _new_message(text):
	reset(text)
	type_text()
	
func type_text():
	while current_index < full_text.length():
		if !typing:
			return
		text_label.text += full_text[current_index]
		current_index += 1
		await get_tree().create_timer(typing_speed).timeout

	typing = false

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if typing:
			typing = false
			text_label.text = full_text
		else:
			panel.visible = false # removes textbox after finished
