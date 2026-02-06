extends CharacterBody3D
## Player Control Script
##
## This script handles player movement, camera control, and input handling.
## Supports multiplayer via Steam P2P networking.

# Export variables
## Controls the movement speed of the player
@export var speed: float = 5.0
## Controls the mouse sensitivity for looking around
@export var mouse_sensitivity: float = 0.3
## How fast remote players interpolate to their target position
@export var interpolation_speed: float = 15.0

# Load child nodes
@onready var camera: Camera3D = $PlayerCamera

# Multiplayer variables
var steam_id: int = 0
var is_local_player: bool = true

# Network sync variables (for remote players)
var _target_position: Vector3
var _target_rotation_y: float
var _target_camera_rotation_x: float

# Internal variables
var _is_mouse_captured: bool
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Network update rate
const NETWORK_UPDATE_RATE: float = 1.0 / 30.0  # 30 updates per second
var _network_update_timer: float = 0.0


# _ready() calls when the node is added to the scene
func _ready() -> void:
	_target_position = global_position
	_target_rotation_y = rotation.y
	_target_camera_rotation_x = 0.0

	if is_local_player:
		# Capture the mouse cursor for looking around
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_is_mouse_captured = true
		# Make this the active camera
		camera.current = true
		# Connect to receive remote player states
		NetworkManager.player_state_received.connect(_on_player_state_received)
	else:
		# Remote player - disable camera and input
		camera.current = false
		set_process_input(false)

# _input() handles input events
func _input(event: InputEvent) -> void:
	# Only process input for local player
	if not is_local_player:
		return

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

func _physics_process(delta: float) -> void:
	if is_local_player:
		_process_local_movement(delta)
		_apply_gravity(delta)
		move_and_slide()
		_send_network_update(delta)
	else:
		_process_remote_movement(delta)

func _process_local_movement(_delta: float) -> void:
	# Initialize the direction vector
	var direction: Vector3 = Vector3.ZERO

	# Initialize the basis for movement directions
	var forward: Vector3 = -transform.basis.z
	var backward: Vector3 = transform.basis.z
	var left: Vector3 = -transform.basis.x
	var right: Vector3 = transform.basis.x

	# Check for input and adjust the direction vector accordingly
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
	velocity = input_direction * speed

func _process_remote_movement(delta: float) -> void:
	# Interpolate position smoothly
	global_position = global_position.lerp(_target_position, interpolation_speed * delta)

	# Interpolate rotation
	rotation.y = lerp_angle(rotation.y, _target_rotation_y, interpolation_speed * delta)

	# Interpolate camera rotation
	var cam_rot = camera.rotation_degrees
	cam_rot.x = lerp(cam_rot.x, _target_camera_rotation_x, interpolation_speed * delta)
	camera.rotation_degrees = cam_rot

func _send_network_update(delta: float) -> void:
	_network_update_timer += delta
	if _network_update_timer >= NETWORK_UPDATE_RATE:
		_network_update_timer = 0.0
		NetworkManager.send_player_state(
			global_position,
			rotation.y,
			camera.rotation_degrees.x
		)

func _on_player_state_received(sender_steam_id: int, state: Dictionary) -> void:
	# Find the player node for this sender and update their target state
	var player = NetworkManager.get_player(sender_steam_id)
	if player and player != self:
		player._target_position = state.position
		player._target_rotation_y = state.rotation_y
		player._target_camera_rotation_x = state.camera_rotation_x

# Apply gravity for local player
func _apply_gravity(_delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity
	else:
		velocity.y = 0

# Setup function called when spawning the player
func setup(player_steam_id: int, local: bool) -> void:
	steam_id = player_steam_id
	is_local_player = local
	name = "Player_" + str(steam_id)
