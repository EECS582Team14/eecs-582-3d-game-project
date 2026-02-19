extends CharacterBody3D
## Player Control Script
##
## This script handles player movement, camera control, and input handling.
## Supports multiplayer via Steam P2P networking.

# Export variables
## Controls the movement speed of the player
@export var speed: float = 7.0
## Controls the mouse sensitivity for looking around
@export var mouse_sensitivity: float = 0.3
## How fast remote players interpolate to their target position
@export var interpolation_speed: float = 15.0
## Initial Player health
@export var max_health: int = 200
@export var jump_velocity: float = 5.0

@onready var current_health: int = max_health

@onready var health_bar = $HUD/ProgressBar

# Load child nodes
@onready var camera: Camera3D = $PlayerCamera
@onready var weapon_holder: Node3D = $PlayerCamera/WeaponHolder

# Weapon scenes
var _taser_scene: PackedScene = preload("res://scenes/weapons/taser/heavy_assault_rifle.glb")
var _held_taser: Node3D = null
var _projectile_script = preload("res://scenes/weapons/taser/taser_projectile.gd")

# Taser shooting
const TASER_COOLDOWN: float = 0.5
var _taser_cooldown_timer: float = 0.0

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

# Role assignment
var is_impostor: bool = false
var _role_received: bool = false
var _role_timer: float = 0.0
const ROLE_REVEAL_DELAY: float = 30.0
var _role_label: Label = null
var _timer_label: Label = null

# Inventory
var has_taser: bool = false

# Interaction
var _looking_at_interactable: Node = null
var _interact_label: Label = null
var _notification_label: Label = null

# Signals
signal health_changed(new_health)

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
		NetworkManager.health_update_received.connect(_on_health_update_received)
		NetworkManager.role_assigned.connect(_on_role_assigned)
		NetworkManager.item_picked_up.connect(_on_item_picked_up)
		NetworkManager.taser_shot_received.connect(_on_taser_shot_received)
		NetworkManager.taser_hit_received.connect(_on_taser_hit_received)

		health_bar.max_value = max_health
		health_bar.value = current_health

		# Create timer label (top center)
		_timer_label = Label.new()
		_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_timer_label.anchor_left = 0.5
		_timer_label.anchor_right = 0.5
		_timer_label.anchor_top = 0.0
		_timer_label.anchor_bottom = 0.0
		_timer_label.offset_left = -150
		_timer_label.offset_right = 150
		_timer_label.offset_top = 20
		_timer_label.offset_bottom = 60
		_timer_label.add_theme_font_size_override("font_size", 28)
		_timer_label.text = ""
		$HUD.add_child(_timer_label)

		# Create role label (center of screen, hidden until reveal)
		_role_label = Label.new()
		_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_role_label.anchor_left = 0.5
		_role_label.anchor_right = 0.5
		_role_label.anchor_top = 0.5
		_role_label.anchor_bottom = 0.5
		_role_label.offset_left = -200
		_role_label.offset_right = 200
		_role_label.offset_top = -30
		_role_label.offset_bottom = 30
		_role_label.add_theme_font_size_override("font_size", 48)
		_role_label.text = ""
		_role_label.visible = false
		$HUD.add_child(_role_label)

		# Create interaction prompt label (bottom center)
		_interact_label = Label.new()
		_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_interact_label.anchor_left = 0.5
		_interact_label.anchor_right = 0.5
		_interact_label.anchor_top = 1.0
		_interact_label.anchor_bottom = 1.0
		_interact_label.offset_left = -200
		_interact_label.offset_right = 200
		_interact_label.offset_top = -80
		_interact_label.offset_bottom = -40
		_interact_label.add_theme_font_size_override("font_size", 24)
		_interact_label.text = ""
		_interact_label.visible = false
		$HUD.add_child(_interact_label)

		# Create notification label (upper center, below timer)
		_notification_label = Label.new()
		_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_notification_label.anchor_left = 0.5
		_notification_label.anchor_right = 0.5
		_notification_label.anchor_top = 0.0
		_notification_label.anchor_bottom = 0.0
		_notification_label.offset_left = -200
		_notification_label.offset_right = 200
		_notification_label.offset_top = 70
		_notification_label.offset_bottom = 110
		_notification_label.add_theme_font_size_override("font_size", 32)
		_notification_label.add_theme_color_override("font_color", Color.YELLOW)
		_notification_label.text = ""
		_notification_label.visible = false
		$HUD.add_child(_notification_label)

		# Check if role was already assigned before we loaded
		if NetworkManager.pending_role_received:
			_on_role_assigned(NetworkManager.pending_role_impostor)
		
	else:
		# Remote player - disable camera, input, and HUD
		camera.current = false
		set_process_input(false)
		$HUD.visible = false

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
		elif event.key_label == KEY_H and event.pressed:
			current_health -= 10
			health_bar.value = current_health
			NetworkManager.send_health_update(current_health)
		
	# If the input is a mouse button event
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not _is_mouse_captured:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				_is_mouse_captured = true
			elif has_taser:
				_shoot_taser()

func _process(delta: float) -> void:
	if not is_local_player or not _role_received:
		return

	if _role_timer > 0.0:
		_role_timer -= delta
		_timer_label.text = "Role reveal in: %d" % ceili(_role_timer)
		if _role_timer <= 0.0:
			_timer_label.text = ""
			_reveal_role()

func _physics_process(delta: float) -> void:
	if is_local_player:
		_process_local_movement(delta)
		_apply_gravity(delta)
		if is_on_floor() and Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
		move_and_slide()
		_send_network_update(delta)
		_update_interaction_look()
		if _taser_cooldown_timer > 0.0:
			_taser_cooldown_timer -= delta
		if Input.is_action_just_pressed("interact") and _looking_at_interactable:
			_try_interact()
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

	# Only set horizontal velocity — preserve velocity.y for gravity and jumping
	velocity.x = input_direction.x * speed
	velocity.z = input_direction.z * speed

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

func _on_role_assigned(impostor: bool) -> void:
	is_impostor = impostor
	_role_received = true
	_role_timer = ROLE_REVEAL_DELAY

func _reveal_role() -> void:
	if is_impostor:
		_role_label.text = "IMPOSTOR"
		_role_label.add_theme_color_override("font_color", Color.RED)
	else:
		_role_label.text = "CREWMATE"
		_role_label.add_theme_color_override("font_color", Color.CYAN)
	_role_label.visible = true

	# Hide the role text after 5 seconds
	await get_tree().create_timer(5.0).timeout
	_role_label.visible = false

func _on_health_update_received(sender_steam_id: int, health: int) -> void:
	var player = NetworkManager.get_player(sender_steam_id)
	if player and player != self:
		player.current_health = health

# Apply gravity for local player
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

# Setup function called when spawning the player
func setup(player_steam_id: int, local: bool) -> void:
	steam_id = player_steam_id
	is_local_player = local
	name = "Player_" + str(steam_id)

func _update_interaction_look() -> void:
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * 3.0)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)

	_looking_at_interactable = null
	if result:
		var collider = result.collider
		if collider.is_in_group("pickup"):
			_looking_at_interactable = _find_activatable(collider)
			if _looking_at_interactable:
				_interact_label.text = "Press E to pick up"
				_interact_label.visible = true
				return
		elif collider.is_in_group("elevator_button"):
			_looking_at_interactable = _find_activatable(collider)
			if _looking_at_interactable:
				_interact_label.text = "Press E to interact"
				_interact_label.visible = true
				return

	_interact_label.visible = false

func _find_activatable(node: Node) -> Node:
	while node != null:
		if node.has_method("activate"):
			return node
		node = node.get_parent()
	return null

func _try_interact() -> void:
	if not _looking_at_interactable:
		return
	if _looking_at_interactable.is_in_group("pickup"):
		_looking_at_interactable.activate(steam_id)
	else:
		_looking_at_interactable.activate()

func give_taser() -> void:
	if has_taser:
		return
	has_taser = true
	_attach_taser_model()
	if is_local_player:
		_notification_label.text = "Taser Acquired!"
		_notification_label.visible = true
		await get_tree().create_timer(3.0).timeout
		_notification_label.visible = false

func _attach_taser_model() -> void:
	if _held_taser:
		return
	_held_taser = _taser_scene.instantiate()
	_held_taser.scale = Vector3(0.5, 0.5, 0.5)
	_held_taser.rotation_degrees.y = 90.0
	weapon_holder.add_child(_held_taser)

func _on_item_picked_up(picker_steam_id: int, _item_id: String) -> void:
	var player = NetworkManager.get_player(picker_steam_id)
	if player and player != self and player.has_method("give_taser"):
		player.give_taser()

func _shoot_taser() -> void:
	if _taser_cooldown_timer > 0.0:
		return
	_taser_cooldown_timer = TASER_COOLDOWN
	var origin = camera.global_position
	var direction = -camera.global_transform.basis.z
	_spawn_projectile(origin, direction, steam_id)
	NetworkManager.send_taser_shot(origin, direction)

func _spawn_projectile(origin: Vector3, direction: Vector3, shooter_id: int) -> void:
	var projectile = Area3D.new()
	projectile.set_script(_projectile_script)
	projectile.setup(origin, direction, shooter_id)
	get_tree().root.add_child(projectile)

func _on_taser_shot_received(sender_steam_id: int, origin: Vector3, direction: Vector3) -> void:
	if sender_steam_id == steam_id:
		return
	_spawn_projectile(origin, direction, sender_steam_id)

func _on_taser_hit_received(dmg: int) -> void:
	current_health -= dmg
	if current_health < 0:
		current_health = 0
	health_bar.value = current_health
	health_changed.emit(current_health)
	NetworkManager.send_health_update(current_health)
