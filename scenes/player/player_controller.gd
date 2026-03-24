extends CharacterBody3D
## Player Control Script
##
## This script handles player movement, camera control, and input handling.
## Supports multiplayer via Steam P2P networking.

# Export variables
## Controls the movement speed of the player
@export var speed: float = 4.5
## Controls the mouse sensitivity for looking around
@export var mouse_sensitivity: float = 0.3
## How fast remote players interpolate to their target position
@export var interpolation_speed: float = 15.0
## Initial Player health
@export var max_health: int = 100
@export var jump_velocity: float = 5.0

@onready var current_health: int = max_health
@onready var nametag = $Label3D

# Load child nodes
@onready var camera: Camera3D = $PlayerCamera
@onready var weapon_holder: Node3D = $PlayerCamera/WeaponHolder

# Weapon scenes
var _taser_scene: PackedScene = preload("res://scenes/weapons/taser/gun_model.glb") #preload("res://scenes/weapons/taser/heavy_assault_rifle.glb")
var _held_taser: Node3D = null
var _projectile_script = preload("res://scenes/weapons/taser/taser_projectile.gd")
var _baton_scene: PackedScene = preload("res://scenes/weapons/baton/stun_baton.glb")
var _held_baton: Node3D = null
# Weapon drop scenes
var _taser_pickup_scene: PackedScene = preload("res://scenes/weapons/taser/taser_pickup.tscn")
var _baton_pickup_scene: PackedScene = preload("res://scenes/weapons/baton/baton.tscn")


# Extra animation scenes
var _dying_scene: PackedScene = preload("res://scenes/player/Dying.fbx")
var _strafe_left_scene: PackedScene = preload("res://scenes/player/left_strafe_walk.fbx")
var _idle_scene: PackedScene = preload("res://scenes/player/Idle.fbx")
var _punch_scene: PackedScene = preload("res://scenes/player/hook_punch.fbx")
var _jumping_scene: PackedScene = preload("res://scenes/player/jumping.fbx")

# Taser shooting
const TASER_COOLDOWN: float = 0.5
var _taser_cooldown_timer: float = 0.0

# Baton controls
const BATON_DAMAGE: int = 25
const BATON_RANGE: float = 3.0
const MAX_BATON_USES = 3
# Baton uses
var baton_uses: int = 0

# Weapon id
var player_weapon_id: String = ""

# Multiplayer variables
var steam_id: int = 0
var is_local_player: bool = true

# Network sync variables (for remote players)
var _target_position: Vector3
var _target_rotation_y: float
var _target_camera_rotation_x: float

# Internal variables
var _is_mouse_captured: bool
var _pause_menu: Control = null
var _pause_layer: CanvasLayer = null
var _settings_menu: Control
var _settings_layer: CanvasLayer
var _is_paused: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Animation
var _anim_player: AnimationPlayer = null
var _anim_lib_prefix: String = ""
var _current_anim_state: String = ""
var _is_punching: bool = false
var _is_swinging: bool = false
var _is_jumping: bool = false

# Third-person camera
var _third_person: bool = false
var _first_person_camera_pos: Vector3
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
var has_baton: bool = false
var _baton_hidden: bool = false



# Dead state (ghost mode)
var is_dead: bool = false

# Interaction
var _looking_at_interactable: Node = null
var _interact_label: Label = null
var _notification_label: Label = null
var _holding_button: bool = false

# Minigame system
var _minigame_active: bool = false
var _minigame_instance: Control = null
var _simon_says_scene: PackedScene = preload("res://scenes/tasks/simon_says_minigame.tscn")
var _wiring_scene: PackedScene = preload("res://scenes/tasks/wiring_minigame.tscn")
var _reactor_temp_scene: PackedScene = preload("res://scenes/tasks/reactor_temp_minigame.tscn")
var _breaker_scene: PackedScene = preload("res://scenes/tasks/breaker_minigame.tscn")


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
	_first_person_camera_pos = camera.position
	
	if steam_id != 0:
		nametag.text = Steam.getFriendPersonaName(steam_id)
	else:
		nametag.text = Steam.getPersonaName()
	# Find AnimationPlayer inside the FBX model
	var model = $PlayerModel
	for child in model.get_children():
		if child is AnimationPlayer:
			_anim_player = child
			break

	# Setup animations: clear the default library and rebuild with named animations
	if _anim_player:
		# Find the library prefix (e.g. "mixamo_com/")
		var lib_names = _anim_player.get_animation_library_list()
		var main_lib_name = ""
		if lib_names.size() > 0:
			main_lib_name = lib_names[0]
			if main_lib_name != "":
				_anim_lib_prefix = main_lib_name + "/"

		# Duplicate the library so each player instance has its own copy
		var shared_lib = _anim_player.get_animation_library(main_lib_name)
		var main_lib: AnimationLibrary = null
		if shared_lib:
			main_lib = shared_lib.duplicate()
			_anim_player.remove_animation_library(main_lib_name)
			_anim_player.add_animation_library(main_lib_name, main_lib)
			# Remove all existing animations and re-add the first one as "walk"
			var existing_anims = main_lib.get_animation_list()
			if existing_anims.size() > 0:
				var walk_anim = main_lib.get_animation(existing_anims[0])
				# Clear everything
				for a in existing_anims:
					main_lib.remove_animation(a)
				# Add back as "walk"
				main_lib.add_animation("walk", walk_anim)

		_import_animation(_dying_scene, "dying")
		_import_animation(_strafe_left_scene, "strafe_left")
		_import_animation(_idle_scene, "idle")
		_import_animation(_punch_scene, "punch")
		_import_animation(_jumping_scene, "jumping")

		# Debug: print all animations in the library
		if main_lib:
			print("Animations loaded: ", main_lib.get_animation_list())

		# Set walk, strafe, and idle to loop (dying, punch, jumping should not loop)
		_set_anim_looping("walk", true)
		_set_anim_looping("strafe_left", true)
		_set_anim_looping("idle", true)

	NetworkManager.punch_received.connect(_on_punch_received)

	if is_local_player:
		# Capture the mouse cursor for looking around
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_is_mouse_captured = true
		# Make this the active camera
		camera.current = true
		# Show own model in first-person view
		$PlayerModel.visible = true
		# Connect to receive remote player states
		NetworkManager.player_state_received.connect(_on_player_state_received)
		NetworkManager.health_update_received.connect(_on_health_update_received)
		NetworkManager.role_assigned.connect(_on_role_assigned)
		NetworkManager.item_picked_up.connect(_on_item_picked_up)
		NetworkManager.taser_shot_received.connect(_on_taser_shot_received)
		NetworkManager.taser_hit_received.connect(_on_taser_hit_received)
		NetworkManager.taser_hide_received.connect(_on_taser_hide_received)
		NetworkManager.item_dropped_received.connect(_on_item_dropped_received)

		# Create pause menu on a CanvasLayer so it renders on top and receives input
		_pause_layer = CanvasLayer.new()
		_pause_layer.layer = 100
		_settings_layer = CanvasLayer.new()
		_settings_layer.layer = 100
		add_child(_pause_layer)
		add_child(_settings_layer)
		var pause_menu_scene = preload("res://scenes/HUD/pause_menu/pause_menu.tscn")
		var settings_menu_scene = preload("res://scenes/HUD/pause_menu/settings_menu.tscn")
		_pause_menu = pause_menu_scene.instantiate()
		_settings_menu = settings_menu_scene.instantiate()
		_pause_layer.add_child(_pause_menu)
		_settings_layer.add_child(_settings_menu)
		_pause_menu.resume_game.connect(_on_resume_game)
		_pause_menu.settings_menu.connect(_on_settings)
		_pause_menu.quit_game.connect(_on_quit_game)
		_settings_menu.back_to_menu.connect(_on_back_to_menu)
		if GameManager.hud_instance:
			var crosshair = GameManager.hud_instance.get_node_or_null("Crosshair")
			if crosshair:
				_pause_menu.set_crosshair(crosshair)

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

	# Handle Escape key — minigame cancel takes priority, then pause menu
	if event is InputEventKey and event.key_label == KEY_ESCAPE and event.pressed:
		if _minigame_active:
			_on_minigame_cancelled()
			return
		if _is_paused:
			_on_resume_game()
		elif _is_mouse_captured:
			_is_paused = true
			_is_mouse_captured = false
			_pause_menu.show_menu()
		return

	# When paused or in minigame, don't process game input so UI buttons can receive clicks
	if _is_paused or _minigame_active:
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
		if event.key_label == KEY_H and event.pressed and not is_dead:
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
		elif event.key_label == KEY_PERIOD and event.pressed and not is_dead:
			_enter_dead_state()  # Debug: kill player


	# If the input is a mouse button event
	if event is InputEventMouseButton:
		if _minigame_active:
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not _is_mouse_captured:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				_is_mouse_captured = true
			elif has_taser and not is_dead and not _taser_hidden:
				_shoot_taser()
			elif has_baton and not is_dead and not _baton_hidden and not _is_swinging:
				if baton_uses > 0:
					_swing_baton()
				else:
					_update_baton_status()
			elif not is_dead and not _is_punching:
				_play_punch()

func _play_jump() -> void:
	_is_jumping = true
	_current_anim_state = "jumping"
	_anim_player.play(_anim("jumping"), ANIM_BLEND)
	_anim_player.speed_scale = 1.0

const PUNCH_DAMAGE: int = 10
const PUNCH_RANGE: float = 2.0
const PUNCH_ANGLE: float = 0.5  # dot product threshold (~60 degree cone)

func _play_punch() -> void:
	_is_punching = true
	_current_anim_state = "punch"
	_anim_player.play(_anim("punch"), ANIM_BLEND)
	_anim_player.speed_scale = 2.0
	NetworkManager.send_punch()
	# Deal damage partway through the animation
	await get_tree().create_timer(0.2).timeout
	_punch_hit_check()
	await _anim_player.animation_finished
	_is_punching = false
	_current_anim_state = ""  # Reset so the next frame picks the correct animation

func _on_punch_received(sender_steam_id: int) -> void:
	if sender_steam_id != steam_id:
		return
	if not _anim_player:
		return
	_is_punching = true
	_current_anim_state = "punch"
	_anim_player.play(_anim("punch"), ANIM_BLEND)
	_anim_player.speed_scale = 2.0
	await _anim_player.animation_finished
	_is_punching = false
	_current_anim_state = ""

func _punch_hit_check() -> void:
	if not GameManager.players_container:
		return
	var punch_dir = -global_transform.basis.z
	for player in GameManager.players_container.get_children():
		if player == self or not player is CharacterBody3D:
			continue
		if player.is_dead:
			continue
		var to_player = player.global_position - global_position
		var distance = to_player.length()
		if distance > PUNCH_RANGE:
			continue
		var direction = to_player.normalized()
		if punch_dir.dot(direction) > PUNCH_ANGLE:
			NetworkManager.send_taser_hit(player.steam_id, PUNCH_DAMAGE)

func _on_resume_game() -> void:
	_is_paused = false
	_is_mouse_captured = true
	_pause_menu.hide_menu()

func _on_settings() -> void:
	_pause_menu.hide()
	_settings_menu.show()

func _on_back_to_menu() -> void:
	_settings_menu.hide()
	_pause_menu.show()

func _on_quit_game() -> void:
	# Leave the lobby and return to main menu
	LobbyManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/lobby/lobby_ui.tscn.tscn")

func _process(delta: float) -> void:
	if not is_local_player or not _role_received:
		return
	if GameManager.game_state == GameManager.GAME_STATE_GAME_OVER:
		if _is_paused:
			_is_paused = false
			_pause_menu.visible = false
			_pause_layer.visible = false
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
	if is_local_player and _is_paused:
		return
	if is_local_player and _minigame_active:
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
				_play_jump()
			if _is_jumping and is_on_floor() and velocity.y <= 0:
				_is_jumping = false
				_current_anim_state = ""  # Reset so next frame picks correct animation
			move_and_slide()
			_update_walk_animation()
			_send_network_update(delta)
			_update_interaction_look()
			if _taser_cooldown_timer > 0.0:
				_taser_cooldown_timer -= delta
			if Input.is_action_just_pressed("interact") and _looking_at_interactable:
				_try_interact()
			_update_task_hold(delta)
			_update_button_hold()
	else:
		_process_remote_movement(delta)

func _import_animation(scene: PackedScene, anim_name: String) -> void:
	var temp = scene.instantiate()
	for child in temp.get_children():
		if child is AnimationPlayer:
			# Find the first available animation library (e.g. "mixamo_com")
			var lib_names = child.get_animation_library_list()
			for lib_name in lib_names:
				var lib = child.get_animation_library(lib_name)
				if lib:
					var anim_list = lib.get_animation_list()
					if anim_list.size() > 0:
						var anim = lib.get_animation(anim_list[0])
						var main_lib_names = _anim_player.get_animation_library_list()
						var main_lib = _anim_player.get_animation_library(main_lib_names[0]) if main_lib_names.size() > 0 else null
						if main_lib and not main_lib.has_animation(anim_name):
							main_lib.add_animation(anim_name, anim)
						break
			break
	temp.queue_free()

const ANIM_BLEND: float = 0.2  # crossfade duration between animations

func _anim(anim_name: String) -> String:
	return _anim_lib_prefix + anim_name

func _set_anim_looping(anim_name: String, looping: bool) -> void:
	var anim = _anim_player.get_animation(_anim(anim_name))
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE

func _reset_model_mirror() -> void:
	var model_transform = $PlayerModel.transform
	model_transform.basis.x = Vector3(-65, 0, 0)
	$PlayerModel.transform = model_transform

func _set_model_diagonal_rotation(angle_deg: float) -> void:
	var rad = deg_to_rad(angle_deg)
	var s = sin(rad)
	var c = cos(rad)
	# Rotate around Y while preserving the scale of 65
	$PlayerModel.transform.basis.x = Vector3(-65 * c, 0, -65 * s)
	$PlayerModel.transform.basis.z = Vector3(65 * s, 0, -65 * c)

func _update_walk_animation() -> void:
	if not _anim_player or _is_punching or _is_jumping or _is_swinging:
		return
	var is_moving = Vector2(velocity.x, velocity.z).length() > 0.1
	if is_moving:
		var forward = -transform.basis.z
		var right = transform.basis.x
		var move_dir = Vector3(velocity.x, 0, velocity.z).normalized()
		var dot = forward.dot(move_dir)
		var side_dot = right.dot(move_dir)
		var going_backward = dot < -0.1
		var going_left = side_dot < -0.5 and abs(dot) < 0.5
		var going_right = side_dot > 0.5 and abs(dot) < 0.5
		var strafing = going_left or going_right

		if strafing and _anim_player.has_animation(_anim("strafe_left")):
			# Mirror the model for right strafe (swapped: left uses mirror, right is default)
			var model_transform = $PlayerModel.transform
			if going_left:
				model_transform.basis.x = Vector3(65, 0, 0)
			else:
				model_transform.basis.x = Vector3(-65, 0, 0)
			$PlayerModel.transform = model_transform
			if _current_anim_state != "strafe":
				_current_anim_state = "strafe"
				_anim_player.play(_anim("strafe_left"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
		elif going_backward:
			_reset_model_mirror()
			var diagonal_angle = side_dot * -25.0
			_set_model_diagonal_rotation(diagonal_angle)
			if _current_anim_state != "walk_back":
				_current_anim_state = "walk_back"
				_anim_player.play_backwards(_anim("walk"), ANIM_BLEND)
				_anim_player.speed_scale = 2.0
		else:
			_reset_model_mirror()
			# Rotate model slightly when moving diagonally
			var diagonal_angle = side_dot * 25.0  # up to 25 degrees
			_set_model_diagonal_rotation(diagonal_angle)
			if _current_anim_state != "walk_forward":
				_current_anim_state = "walk_forward"
				_anim_player.play(_anim("walk"), ANIM_BLEND)
				_anim_player.speed_scale = 2.0
	elif not is_moving:
		if _current_anim_state != "idle":
			_current_anim_state = "idle"
			_reset_model_mirror()
			_set_model_diagonal_rotation(0.0)
			_anim_player.play(_anim("idle"), ANIM_BLEND)
			_anim_player.speed_scale = 1.0

func _set_remote_moving(moving: bool, moving_backward: bool = false) -> void:
	if not _anim_player:
		return
	if _is_punching or _is_swinging:
		return
	if moving:
		if moving_backward:
			if _current_anim_state != "walk_back":
				_current_anim_state = "walk_back"
				_anim_player.play_backwards(_anim("walk"), ANIM_BLEND)
				_anim_player.speed_scale = 2.0
		else:
			if _current_anim_state != "walk_forward":
				_current_anim_state = "walk_forward"
				_anim_player.play(_anim("walk"), ANIM_BLEND)
				_anim_player.speed_scale = 2.0
	elif not moving:
		if _current_anim_state != "idle":
			_current_anim_state = "idle"
			_anim_player.play(_anim("idle"), ANIM_BLEND)
			_anim_player.speed_scale = 1.0

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

	# Slow down movement while punching or swinging
	var move_speed = speed * 0.3 if (_is_punching) else speed
	# Only set horizontal velocity — preserve velocity.y for gravity and jumping
	velocity.x = input_direction.x * move_speed
	velocity.z = input_direction.z * move_speed

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
		var moving = Vector2(velocity.x, velocity.z).length() > 0.1
		var forward = -transform.basis.z
		var move_dir = Vector3(velocity.x, 0, velocity.z).normalized()
		var moving_backward = moving and forward.dot(move_dir) < -0.1
		NetworkManager.send_player_state(
			global_position,
			rotation.y,
			camera.rotation_degrees.x,
			moving,
			moving_backward
		)

func _on_player_state_received(sender_steam_id: int, state: Dictionary) -> void:
	# Find the player node for this sender and update their target state
	var player = NetworkManager.get_player(sender_steam_id)
	if player and player != self:
		player._target_position = state.position
		player._target_rotation_y = state.rotation_y
		player._target_camera_rotation_x = state.camera_rotation_x
		player._set_remote_moving(state.get("is_moving", false), state.get("is_moving_backward", false))

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
			if player._held_baton:
				player._held_baton.visible = false

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
				elif _looking_at_interactable.get("is_minigame_task"):
					_interact_label.text = "Press E to calibrate"
					_interact_label.visible = true
				else:
					_interact_label.text = "Hold E to calibrate"
					_interact_label.visible = true
				return
		elif collider.is_in_group("button"):
			_looking_at_interactable = _find_activatable(collider)
			if _looking_at_interactable:
				var button_id = _looking_at_interactable.button_id if _looking_at_interactable.has_method("activate") else ""
				_interact_label.text = "Hold E to press down"
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
			if _looking_at_interactable.get("is_minigame_task"):
				var mg_type = _looking_at_interactable.get("minigame_type")
				_open_minigame(tid, mg_type if mg_type else "simon_says")
			else:
				_is_holding_task = true
				_task_hold_timer = 0.0
				_task_progress_bar.value = 0
				_task_progress_bar.visible = true
	elif _looking_at_interactable.is_in_group("button"):
		_holding_button = true
		_looking_at_interactable.activate()
	else:
		_looking_at_interactable.activate()

func give_taser() -> void:
	drop_current_weapon()
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
	_held_taser.rotation_degrees.y = 180.0
	weapon_holder.add_child(_held_taser)

func _on_taser_hide_received(sender_steam_id: int, hidden: bool) -> void:
	var player = NetworkManager.get_player(sender_steam_id)
	if player and player != self and player._held_taser:
		player._held_taser.visible = not hidden
		
func give_baton(current_uses: int = MAX_BATON_USES) -> void:
	drop_current_weapon()
	has_baton = true
	baton_uses = current_uses
	_attach_baton_model()
	if is_local_player:
		_notification_label.text = "Baton Acquired (Power Level: %s%%)!" % (baton_uses * 100 / MAX_BATON_USES)
		_notification_label.visible = true
		await get_tree().create_timer(3.0).timeout
		_notification_label.visible = false

func _attach_baton_model() -> void:
	if _held_baton:
		return
	_held_baton = _baton_scene.instantiate()
	_held_baton.scale = Vector3(0.5, 0.5, 0.5)
	_held_baton.rotation_degrees.y = 90.0
	weapon_holder.add_child(_held_baton)
	
func _on_baton_hide_received(sender_steam_id: int, hidden: bool) -> void:
	var player = NetworkManager.get_player(sender_steam_id)
	if player and player != self and player._held_baton:
		player._held_baton.visible = not hidden
		
func drop_current_weapon() -> void:	
	var saved_id = player_weapon_id
	var uses = baton_uses
	var pickup_to_spawn: PackedScene = null
	
	if has_taser:
		pickup_to_spawn = _taser_pickup_scene
		has_taser = false
		if _held_taser:
			_held_taser.queue_free()
			_held_taser = null
	elif has_baton:
		pickup_to_spawn = _baton_pickup_scene
		has_baton = false
		if _held_baton:
			_held_baton.queue_free()
			_held_baton = null
			
	if pickup_to_spawn:
		var pickup = pickup_to_spawn.instantiate()
		pickup.scale = Vector3(0.5, 0.5, 0.5)
		pickup.global_position = global_position + (-global_transform.basis.z * 1.5) + Vector3(0, 0.5, 0)
		pickup.item_id = player_weapon_id
		pickup.add_to_group("pickup")
		if "current_uses" in pickup:
			pickup.current_uses = uses
		get_tree().root.add_child(pickup)
		NetworkManager.send_item_dropped(saved_id, pickup.global_position, uses)
		player_weapon_id = ""

func _on_item_dropped_received(item_id: String, pos: Vector3, uses: int) -> void:
	var scene_to_spawn: PackedScene = null
	if item_id.begins_with("taser"):
		scene_to_spawn = _taser_pickup_scene
	elif item_id.begins_with("baton"):
		scene_to_spawn = _baton_pickup_scene
	if scene_to_spawn:
		_spawn_pickup_in_world(item_id, scene_to_spawn, pos, uses)
		
func _spawn_pickup_in_world(id: String, scene: PackedScene, pos: Vector3, uses: int) -> void:
	var pickup = scene.instantiate()
	pickup.global_position = pos
	pickup.item_id = id
	if "current_uses" in pickup:
		pickup.current_uses = uses
	pickup.add_to_group("pickup")
	get_tree().root.add_child(pickup)
	print(id, pickup.item_id)

func _on_item_picked_up(picker_steam_id: int, item_id: String) -> void:
	var player = NetworkManager.get_player(picker_steam_id)
	if player:
		if player != self:
			if item_id.begins_with("taser") and player.has_method("give_taser"):
				player.give_taser()
			elif item_id.begins_with("baton") and player.has_method("give_baton"):
				player.give_baton()
		else:
			player_weapon_id = item_id

func _shoot_taser() -> void:
	if _taser_cooldown_timer > 0.0:
		return
	_taser_cooldown_timer = TASER_COOLDOWN
	var direction = -global_transform.basis.z
	var origin: Vector3
	if _third_person:
		origin = global_position + Vector3(0, _first_person_camera_pos.y, 0) + direction * 0.5
	else:
		origin = camera.global_position
		direction = -camera.global_transform.basis.z
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
	
func _swing_baton() -> void:
	if _is_swinging:
		return
	_is_swinging = true
	_current_anim_state = "punch"
	_anim_player.play(_anim("punch"), 0.2)
	
	await get_tree().create_timer(0.2).timeout
	_baton_hit_check()
	
	await _anim_player.animation_finished
	_is_swinging = false
	_current_anim_state = ""
	
	baton_uses -= 1
	_update_baton_status()
	
func _baton_hit_check() -> void:
	var swing_dir = -global_transform.basis.z
	for player in GameManager.players_container.get_children():
		if player == self or not player is CharacterBody3D or player.is_dead:
			continue
		var to_player = player.global_position - global_position
		if to_player.length() < BATON_RANGE and swing_dir.dot(to_player.normalized()) > 0.5:
			NetworkManager.send_taser_hit(player.steam_id, BATON_DAMAGE)
			break

func _update_baton_status() -> void:
	if is_local_player:
		_notification_label.text = "Baton Power Remaining: %s%%" % (baton_uses * 100 / MAX_BATON_USES)
		_notification_label.visible = true
		
	if baton_uses <= 0:
		drop_current_weapon()
		if is_local_player:
			_notification_label.text = "Baton Out of Power!"
			await get_tree().create_timer(2.0).timeout
			_notification_label.visible = false

func reset_inventory():
	has_taser = false
	has_baton = false
	
	if _held_taser:
		_held_taser.queue_free()
		_held_taser = null
	if _held_baton:
		_held_baton.queue_free()
		_held_baton = null
		
	_taser_hidden = false
	_baton_hidden = false

func _toggle_third_person() -> void:
	_third_person = not _third_person
	if _third_person:
		camera.position = Vector3(0, THIRD_PERSON_HEIGHT, THIRD_PERSON_DISTANCE)
		$PlayerModel.visible = true
		weapon_holder.visible = false
	else:
		camera.position = _first_person_camera_pos
		camera.rotation_degrees.x = 0.0
		$PlayerModel.visible = false
		weapon_holder.visible = true

func _enter_dead_state() -> void:
	is_dead = true
	
	#if is_local_player:
	drop_current_weapon()
	
	if _anim_player and _anim_player.has_animation(_anim("dying")):
		$PlayerModel.visible = true
		_anim_player.play(_anim("dying"), ANIM_BLEND)
		_anim_player.speed_scale = 1.0
		await _anim_player.animation_finished
	$PlayerModel.visible = false
	nametag.visible = false
	if _held_taser:
		_held_taser.visible = false
	if _held_baton:
		_held_baton.visible = false
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

func _looking_at_button() -> bool:
	return _looking_at_interactable != null and _looking_at_interactable.is_in_group("button")

func _update_button_hold() -> void:
	if not _holding_button:
		return
	if not Input.is_action_pressed("interact") or not _looking_at_button():
		cancel_button_hold()

func cancel_button_hold() -> void:
	if _looking_at_interactable and _looking_at_interactable.has_method("deactivate"):
		_looking_at_interactable.deactivate()
	_holding_button = false

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

# --- Task Minigames ---

func _open_minigame(task_id: String, minigame_type: String) -> void:
	if _minigame_active:
		return
	_minigame_active = true

	# Show cursor for clicking buttons
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_is_mouse_captured = false

	# Create a CanvasLayer so the UI renders above the game
	var layer = CanvasLayer.new()
	layer.layer = 50
	layer.name = "MinigameLayer"
	add_child(layer)

	# Pick the right scene based on type
	match minigame_type:
		"wiring":
			_minigame_instance = _wiring_scene.instantiate()
		"reactor_temp":
			_minigame_instance = _reactor_temp_scene.instantiate()
		"breaker":
			_minigame_instance = _breaker_scene.instantiate()
		_:
			_minigame_instance = _simon_says_scene.instantiate()

	layer.add_child(_minigame_instance)

	_minigame_instance.minigame_completed.connect(_on_minigame_completed.bind(task_id))
	_minigame_instance.minigame_cancelled.connect(_on_minigame_cancelled)

	_minigame_instance.start_game()

func _on_minigame_completed(task_id: String) -> void:
	_close_minigame()
	_complete_task(task_id)

func _on_minigame_cancelled() -> void:
	_close_minigame()

func _close_minigame() -> void:
	_minigame_active = false
	if _minigame_instance:
		var layer = _minigame_instance.get_parent()
		layer.queue_free()
		_minigame_instance = null
	# Re-capture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_is_mouse_captured = true
