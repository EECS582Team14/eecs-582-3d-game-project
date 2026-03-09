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
@export var max_health: int = 100
@export var jump_velocity: float = 5.0

@onready var current_health: int = max_health


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

# Animation
var _anim_player: AnimationPlayer = null

# Third-person camera
var _third_person: bool = false
const THIRD_PERSON_DISTANCE: float = 4.0
const THIRD_PERSON_HEIGHT: float = 1.5

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
var _taser_hidden: bool = false

# Dead state (ghost mode)
var is_dead: bool = false

# Interaction
var _looking_at_interactable: Node = null
var _interact_label: Label = null
var _notification_label: Label = null

#Task Designations
var integrity_tasks = ["Armory_task", "Cam_task", "Crew_task", "Fab_task", "Life_task", "Sheilding_task", "Trash_task"]
var TASK_DESCRIPTIONS := {
	"Armory_task": "Secure weapon lockers and verify ammunition counts. (Upper - Armory)",
	"Cam_task": "Realign and calibrate surveillance camera feeds. (Upper - Cams)",
	"Colonial_task": "Inspect colonial artifacts and log preservation status. (Lower - Colonial)",
	"Crew_task": "Update crew manifest and verify ID badge scans. (Upper - Crew Quarters)",
	"Electrical_task": "Reset overloaded breakers and reroute power flow. (Lower - Electrical)",
	"Fab_task": "Fabricate replacement components using the nano‑printer. (Lower - Fabrication Lab)",
	"Human_Resources_task": "File crew performance reports and update duty assignments. (Upper - Human Resources)",
	"Intercom_task": "Test shipwide intercom channels and repair faulty speakers. (Upper - Intercoms)",
	"Life_task": "Check life support filters and balance oxygen levels. (Upper - Life Support)",
	"Lower_Reactor_task": "Calibrate reactor temperature. (Lower - Reactor)",
	"Nav_task": "Align navigation array. (Upper - Nav)",
	"Nexus_task": "Stabilize data uplinks and clear corrupted routing nodes. (Upper - Nexus)",
	"Personal_task": "Sort personal storage items and verify locker security. (Lower - Personal Items)",
	"Shielding_task": "Reinforce hull shielding and patch micro‑fractures. (Upper - Shielding)",
	"Supply_Closet_task": "Restock essential supplies and inventory materials. (Upper - Supply Closet)",
	"Trash_task": "Empty waste bins and compact refuse for disposal. (Lower - Trash)",
	"Upper_Reactor_task": "Balance plasma conduits and tune reactor output. (Upper - Reactor)",
}


# Hold-E task system
var _task_hold_timer: float = 0.0
const TASK_HOLD_DURATION: float = 5.0
var _is_holding_task: bool = false
var _task_progress_bar: ProgressBar = null
var _completed_tasks: Array[String] = []

# Destination progress HUD
var _destination_bar: ProgressBar = null
var _destination_label: Label = null

# Signals
signal health_changed(new_health)

# _ready() calls when the node is added to the scene
func _ready() -> void:
	_target_position = global_position
	_target_rotation_y = rotation.y
	_target_camera_rotation_x = 0.0

	# Find AnimationPlayer inside the FBX model
	var model = $PlayerModel
	for child in model.get_children():
		if child is AnimationPlayer:
			_anim_player = child
			break

	if is_local_player:
		# Capture the mouse cursor for looking around
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_is_mouse_captured = true
		# Make this the active camera
		camera.current = true
		# Hide own model in first-person view
		$PlayerModel.visible = false
		# Connect to receive remote player states
		NetworkManager.player_state_received.connect(_on_player_state_received)
		NetworkManager.health_update_received.connect(_on_health_update_received)
		NetworkManager.role_assigned.connect(_on_role_assigned)
		NetworkManager.item_picked_up.connect(_on_item_picked_up)
		NetworkManager.taser_shot_received.connect(_on_taser_shot_received)
		NetworkManager.taser_hit_received.connect(_on_taser_hit_received)
		NetworkManager.taser_hide_received.connect(_on_taser_hide_received)


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

		# Create destination progress label (top-right)
		_destination_label = Label.new()
		_destination_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_destination_label.anchor_left = 1.0
		_destination_label.anchor_right = 1.0
		_destination_label.anchor_top = 0.0
		_destination_label.anchor_bottom = 0.0
		_destination_label.offset_left = -320
		_destination_label.offset_right = -20
		_destination_label.offset_top = 20
		_destination_label.offset_bottom = 50
		_destination_label.add_theme_font_size_override("font_size", 20)
		_destination_label.text = "Destination: 0%"
		$HUD.add_child(_destination_label)

		# Create destination progress bar (top-right, below label)
		_destination_bar = ProgressBar.new()
		_destination_bar.min_value = 0
		_destination_bar.max_value = 100
		_destination_bar.value = 0
		_destination_bar.show_percentage = false
		_destination_bar.anchor_left = 1.0
		_destination_bar.anchor_right = 1.0
		_destination_bar.anchor_top = 0.0
		_destination_bar.anchor_bottom = 0.0
		_destination_bar.offset_left = -320
		_destination_bar.offset_right = -20
		_destination_bar.offset_top = 52
		_destination_bar.offset_bottom = 76
		# Style the fill with a cyan color
		var fill_style = StyleBoxFlat.new()
		fill_style.bg_color = Color.CYAN
		fill_style.corner_radius_top_left = 3
		fill_style.corner_radius_top_right = 3
		fill_style.corner_radius_bottom_left = 3
		fill_style.corner_radius_bottom_right = 3
		_destination_bar.add_theme_stylebox_override("fill", fill_style)
		# Style the background
		var bg_style = StyleBoxFlat.new()
		bg_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
		bg_style.corner_radius_top_left = 3
		bg_style.corner_radius_top_right = 3
		bg_style.corner_radius_bottom_left = 3
		bg_style.corner_radius_bottom_right = 3
		_destination_bar.add_theme_stylebox_override("background", bg_style)
		$HUD.add_child(_destination_bar)

		# Create task hold progress bar (center screen)
		_task_progress_bar = ProgressBar.new()
		_task_progress_bar.min_value = 0
		_task_progress_bar.max_value = TASK_HOLD_DURATION
		_task_progress_bar.value = 0
		_task_progress_bar.show_percentage = false
		_task_progress_bar.anchor_left = 0.5
		_task_progress_bar.anchor_right = 0.5
		_task_progress_bar.anchor_top = 0.5
		_task_progress_bar.anchor_bottom = 0.5
		_task_progress_bar.offset_left = -100
		_task_progress_bar.offset_right = 100
		_task_progress_bar.offset_top = 40
		_task_progress_bar.offset_bottom = 56
		var task_fill = StyleBoxFlat.new()
		task_fill.bg_color = Color.GREEN
		task_fill.corner_radius_top_left = 3
		task_fill.corner_radius_top_right = 3
		task_fill.corner_radius_bottom_left = 3
		task_fill.corner_radius_bottom_right = 3
		_task_progress_bar.add_theme_stylebox_override("fill", task_fill)
		var task_bg = StyleBoxFlat.new()
		task_bg.bg_color = Color(0.15, 0.15, 0.15, 0.8)
		task_bg.corner_radius_top_left = 3
		task_bg.corner_radius_top_right = 3
		task_bg.corner_radius_bottom_left = 3
		task_bg.corner_radius_bottom_right = 3
		_task_progress_bar.add_theme_stylebox_override("background", task_bg)
		_task_progress_bar.visible = false
		$HUD.add_child(_task_progress_bar)

		# Connect destination progress updates
		NetworkManager.progress_update_received.connect(_on_progress_update_received)

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
	if GameManager.game_state == GameManager.GAME_STATE_GAME_OVER:
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
		elif event.key_label == KEY_H and event.pressed and not is_dead:
			if has_taser and _held_taser:
				_taser_hidden = not _taser_hidden
				_held_taser.visible = not _taser_hidden
				NetworkManager.send_taser_hide(_taser_hidden)
		elif event.key_label == KEY_F and event.pressed:
			NetworkManager.send_emergency_meeting()
		elif event.key_label == KEY_K and event.pressed:
			GameManager.adjust_ship_integrity(-10.0)
		elif event.key_label == KEY_L and event.pressed:
			GameManager.adjust_ship_integrity(10.0)
		elif event.key_label == KEY_F5 and event.pressed:
			_toggle_third_person()

		
	# If the input is a mouse button event
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not _is_mouse_captured:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				_is_mouse_captured = true
			elif has_taser and not is_dead and not _taser_hidden:
				_shoot_taser()

func _process(delta: float) -> void:
	if not is_local_player or not _role_received:
		return
	if GameManager.game_state == GameManager.GAME_STATE_GAME_OVER:
		return

	if _role_timer > 0.0:
		_role_timer -= delta
		_timer_label.text = "Role reveal in: %d" % ceili(_role_timer)
		if _role_timer <= 0.0:
			_timer_label.text = ""
			_reveal_role()

func _physics_process(delta: float) -> void:
	if is_local_player and GameManager.game_state == GameManager.GAME_STATE_GAME_OVER:
		return
	if is_local_player:
		if is_dead:
			_process_ghost_movement(delta)
			move_and_slide()
			_send_network_update(delta)
		else:
			_process_local_movement(delta)
			_apply_gravity(delta)
			if is_on_floor() and Input.is_action_just_pressed("jump"):
				velocity.y = jump_velocity
			move_and_slide()
			_update_walk_animation()
			_send_network_update(delta)
			_update_interaction_look()
			if _taser_cooldown_timer > 0.0:
				_taser_cooldown_timer -= delta
			if Input.is_action_just_pressed("interact") and _looking_at_interactable:
				_try_interact()
			_update_task_hold(delta)
	else:
		_process_remote_movement(delta)

func _update_walk_animation() -> void:
	if not _anim_player:
		return
	var dominated_moving = Vector2(velocity.x, velocity.z).length() > 0.1
	if dominated_moving and not _anim_player.is_playing():
		var anims = _anim_player.get_animation_list()
		if anims.size() > 0:
			_anim_player.play(anims[0])
	elif not dominated_moving and _anim_player.is_playing():
		_anim_player.stop()

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

func _process_ghost_movement(_delta: float) -> void:
	var direction: Vector3 = Vector3.ZERO
	var forward: Vector3 = -transform.basis.z
	var backward: Vector3 = transform.basis.z
	var left: Vector3 = -transform.basis.x
	var right: Vector3 = transform.basis.x

	if Input.is_action_pressed("move_forward"):
		direction += forward
	if Input.is_action_pressed("move_backward"):
		direction += backward
	if Input.is_action_pressed("move_left"):
		direction += left
	if Input.is_action_pressed("move_right"):
		direction += right

	var input_direction = direction.normalized()
	velocity.x = input_direction.x * speed
	velocity.z = input_direction.z * speed

	# Vertical ghost movement: Space to fly up, Shift to fly down
	velocity.y = 0.0
	if Input.is_action_pressed("jump"):
		velocity.y = speed
	if Input.is_key_pressed(KEY_SHIFT):
		velocity.y = -speed

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
		if health <= 0 and not player.is_dead:
			player.is_dead = true
			player.get_node("PlayerModel").visible = false
			if player._held_taser:
				player._held_taser.visible = false

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
		elif collider.is_in_group("task_console"):
			_looking_at_interactable = _find_activatable(collider)
			if _looking_at_interactable:
				var tid = _looking_at_interactable.task_id if _looking_at_interactable.has_method("activate") else ""
				if tid in _completed_tasks:
					_interact_label.text = "Already completed"
					_interact_label.visible = true
				else:
					_interact_label.text = "Hold E to calibrate"
					_interact_label.visible = true
				return

	if _is_holding_task and not _is_looking_at_task_console():
		_cancel_task_hold()
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
	elif _looking_at_interactable.is_in_group("task_console"):
		var tid = _looking_at_interactable.task_id if _looking_at_interactable.has_method("activate") else ""
		if tid not in _completed_tasks:
			_is_holding_task = true
			_task_hold_timer = 0.0
			_task_progress_bar.value = 0
			_task_progress_bar.visible = true
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

func _on_taser_hide_received(sender_steam_id: int, hidden: bool) -> void:
	var player = NetworkManager.get_player(sender_steam_id)
	if player and player != self and player._held_taser:
		player._held_taser.visible = not hidden

func _on_item_picked_up(picker_steam_id: int, item_id: String) -> void:
	if not item_id.begins_with("taser"):
		return
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

func _toggle_third_person() -> void:
	_third_person = not _third_person
	if _third_person:
		camera.position = Vector3(0, THIRD_PERSON_HEIGHT, THIRD_PERSON_DISTANCE)
		$PlayerModel.visible = true
	else:
		camera.position = Vector3(0, 0, 0)
		$PlayerModel.visible = not is_dead

func _enter_dead_state() -> void:
	is_dead = true
	$PlayerModel.visible = false
	if _held_taser:
		_held_taser.visible = false
	$PhysicsCollider.disabled = true
	_interact_label.visible = false

func _on_taser_hit_received(dmg: int) -> void:
	if is_dead:
		return
	current_health -= dmg
	if current_health < 0:
		current_health = 0
	UIState.health_changed.emit(current_health)
	health_changed.emit(current_health)
	NetworkManager.send_health_update(current_health)
	if current_health <= 0:
		_enter_dead_state()

func _on_progress_update_received(progress: float, _speed: float) -> void:
	if _destination_bar:
		_destination_bar.value = progress
	if _destination_label:
		_destination_label.text = "Destination: %d%%" % int(progress)

func _is_looking_at_task_console() -> bool:
	return _looking_at_interactable != null and _looking_at_interactable.is_in_group("task_console")

func _update_task_hold(delta: float) -> void:
	if not _is_holding_task:
		return
	if not Input.is_action_pressed("interact") or not _is_looking_at_task_console():
		_cancel_task_hold()
		return
	_task_hold_timer += delta
	_task_progress_bar.value = _task_hold_timer
	if _task_hold_timer >= TASK_HOLD_DURATION:
		var tid = _looking_at_interactable.task_id
		_complete_task(tid)

func _cancel_task_hold() -> void:
	_is_holding_task = false
	_task_hold_timer = 0.0
	_task_progress_bar.value = 0
	_task_progress_bar.visible = false

func _complete_task(task_id: String) -> void:
	print(task_id)
	_completed_tasks.append(task_id)
	_cancel_task_hold()
	if task_id in integrity_tasks and is_impostor:
		NetworkManager.send_ship_integrity_update(GameManager.ship_integrity - 5)
	elif task_id in integrity_tasks and !is_impostor:
		NetworkManager.send_ship_integrity_update(GameManager.ship_integrity + 5)
	if is_impostor:
		GameManager.adjust_progress_speed(-0.5)
	else:
		GameManager.adjust_progress_speed(0.5)
	# Update directives panel and task description
	var panels = get_tree().get_nodes_in_group("directives_panel")
	var description = TASK_DESCRIPTIONS.get(task_id, task_id) # fallback to task_id if missing

	for panel in panels:
		if panel.has_method("mark_task_completed"):
			panel.mark_task_completed(description)
