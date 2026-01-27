extends CharacterBody3D
## Player Control Script
##
## This script handles player movement, camera control, and input handling.
## Date Created: 2026-27-01
## Date Last Modified: 2026-27-01

# Export variables
# Export variables are modifiable in the Godot editor
## Controls the movement speed of the player
@export var speed: float = 5.0
## Controls the mouse sensitivity for looking around
@export var mouse_sensitivity: float = 0.3

# FUN FACT: Double '##' adds a description to the export variable in the Godot editor.

# Load child nodes
# Camera node for player view
@onready var camera: Camera3D = $PlayerCamera

# Internal variables
# Tracks if the mouse is currently captured
var _is_mouse_captured: bool
# Gravity value for the player
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


# _ready() calls when the node is added to the scene
func _ready() -> void:
	# Capture the mouse cursor for looking around
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_is_mouse_captured = true

# _input() handles input events
func _input(event: InputEvent) -> void:
	# Handle mouse motion events for looking around
	if event is InputEventMouseMotion and _is_mouse_captured:
		# Rotate the player horizontally based on mouse movement
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		# Rotate the camera vertically based on mouse movement
		var camera_rotation: Vector3 = camera.rotation_degrees
		camera_rotation.x = clamp(camera_rotation.x - event.relative.y * mouse_sensitivity, -90, 90)
		camera.rotation_degrees = camera_rotation

	# If the input is a key event
	if event is InputEventKey:
		# If the Escape key is pressed, toggle mouse capture
		if event.key_label == KEY_ESCAPE and event.pressed:
			if _is_mouse_captured:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				_is_mouse_captured = false
		
	# If the input is a mouse button event
	if event is InputEventMouseButton:
		# If the left mouse button is clicked,
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Capture the mouse if it isn't already captured
			if not _is_mouse_captured:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				_is_mouse_captured = true

func _physics_process(_delta: float) -> void:
	_process_movement(_delta)
	_apply_gravity(_delta)
	# Move the player using the calculated velocity
	move_and_slide()

func _process_movement(_delta: float) -> void:
	# Initialize the direction vector
	var direction: Vector3 = Vector3.ZERO

	# Initialize the basis for movement directions
	var forward: Vector3 = -transform.basis.z
	var backward: Vector3 = transform.basis.z
	var left: Vector3 = -transform.basis.x
	var right: Vector3 = transform.basis.x
	# Up can be used for a jump mechanic in the future
	var _up: Vector3 = transform.basis.y

	# Check for input and adjust the direction vector accordingly
	# Input actions are defined in the Input Map in the project settings
	if Input.is_action_pressed("move_forward"):
		direction += forward
	if Input.is_action_pressed("move_backward"):
		direction += backward
	if Input.is_action_pressed("move_left"):
		direction += left
	if Input.is_action_pressed("move_right"):
		direction += right

	# Normalize the direction vector to ensure consistent speed in all directions
	var input_direction = direction.normalized()

	# Calculate the velocity based on input direction and speed
	# velocity is a built-in variable of CharacterBody3D
	velocity = input_direction * speed

# Since we are using a characterbody node, we need to apply gravity manually
func _apply_gravity(_delta: float) -> void:
	# Apply gravity to the player
	if not is_on_floor():
		velocity.y -= gravity
	else:
		velocity.y = 0
