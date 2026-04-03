extends HBoxContainer

# Exported variables
@export var action_name: String

# Child nodes
@onready var button: Button = $RemapButton

# State variables
var is_listening: bool = false

func _ready() -> void:
	# Validate that the action exists in the InputMap
	if not InputMap.has_action(action_name):
		push_warning("Action '%s' not found in InputMap" % action_name)
		return
	
	# Connect button pressed signal
	button.pressed.connect(_on_remap_button_pressed)
	
	# Initialize button display with current keybinding
	_update_button_display()


func _input(event: InputEvent) -> void:
	# Only process input when actively listening for a key press
	if not is_listening:
		return
	
	# Only handle keyboard input events
	if not event is InputEventKey:
		return
	
	# Ignore key release events, only process key press
	if not event.pressed:
		return
	
	# Get the physical keycode from the event (Godot 4)
	var key_code = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	
	# Cancel listening if Escape is pressed
	if key_code == KEY_ESCAPE:
		_exit_listening_mode()
		get_viewport().set_input_as_handled()
		return
	
	# Accept the pressed key as the new input event
	var new_event = InputEventKey.new()
	new_event.physical_keycode = key_code
	
	# Clear all existing events for this action
	InputMap.action_erase_events(action_name)
	
	# Add the new event to the action
	InputMap.action_add_event(action_name, new_event)
	
	# Update button display with new keybinding
	_update_button_display()
	
	# Exit listening mode
	_exit_listening_mode()


func _on_remap_button_pressed() -> void:
	"""Toggle listening mode when the remap button is pressed."""
	is_listening = not is_listening
	_update_button_display()
	
	# When entering listening mode, set focus to capture input
	if is_listening:
		button.set_focus_mode(Control.FOCUS_ALL)
		button.grab_focus()


func _update_button_display() -> void:
	"""Update the button text to show current keybinding or prompt for input."""
	if is_listening:
		button.text = "Press any key..."
		button.toggle_mode = false  # Disable toggle mode while listening
	else:
		button.text = _get_current_key_display()
		button.toggle_mode = true  # Re-enable toggle mode
		button.button_pressed = false  # Deselect button


func _get_current_key_display() -> String:
	"""Return a human-readable string of the current keybinding for this action."""
	if not InputMap.has_action(action_name):
		return "[Invalid Action]"
	
	var events = InputMap.action_get_events(action_name)
	
	if events.is_empty():
		return "[No Key Bound]"
	
	# Get the first event (should be an InputEventKey)
	var event = events[0]
	
	if not event is InputEventKey:
		return "[Invalid Event]"
	
	# Get human-readable key name from physical_keycode (Godot 4)
	# Fall back to keycode if physical_keycode is not set
	var key_code = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	var key_name = OS.get_keycode_string(key_code)
	
	return key_name if key_name else "[Unknown Key]"


func _exit_listening_mode() -> void:
	"""Cleanly exit listening mode and reset UI state."""
	is_listening = false
	_update_button_display()