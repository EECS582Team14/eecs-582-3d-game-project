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
@export var can_move = true
@onready var current_health: int = max_health
@onready var nametag = $Label3D

# Load child nodes
@onready var camera: Camera3D = $PlayerCamera
@onready var weapon_holder: Node3D = $PlayerCamera/WeaponHolder
@onready var flashlight: SpotLight3D = $PlayerCamera/PlayerFlashlight
@onready var directives_panel = get_tree().get_first_node_in_group("directives_panel")

# Sound effects
@onready var steps_sound: AudioStreamPlayer3D = $StepsSound
@onready var denied_sound: AudioStreamPlayer = $AccessDenied
@onready var taser_pickup_sound: AudioStreamPlayer3D = $TaserPickup
@onready var taser_shot_sound: AudioStreamPlayer3D = $TaserShot
@onready var baton_pickup_sound: AudioStreamPlayer3D = $BatonPickup
@onready var baton_use_sound: AudioStreamPlayer3D = $BatonUse
@onready var anomaly_detected: AudioStreamPlayer = $AnomalyDetected
@onready var emergency_measures_activated: AudioStreamPlayer = $EmergencyMeasuresActivated
@onready var hostiles_detected: AudioStreamPlayer = $HostilesDetected
@onready var rebooting_systems: AudioStreamPlayer = $RebootingSystems
@onready var structural_integrity_compromised: AudioStreamPlayer = $StructuralIntegrityCompromised
@onready var systems_operational: AudioStreamPlayer = $SystemsOperational
@onready var warning_malfunction: AudioStreamPlayer = $WarningMalfunction
@onready var welcome_operator: AudioStreamPlayer = $WelcomeOperator

# Weapon scenes
var _taser_scene: PackedScene = preload("res://scenes/weapons/taser/gun_model.glb") #preload("res://scenes/weapons/taser/heavy_assault_rifle.glb")
var _held_taser: Node3D = null
var _projectile_script = preload("res://scenes/weapons/taser/taser_projectile.gd")
var _baton_scene: PackedScene = preload("res://scenes/weapons/baton/stun_baton.glb")
var _held_baton: Node3D = null
# Weapon drop scenes
var _taser_pickup_scene: PackedScene = preload("res://scenes/weapons/taser/taser_pickup.tscn")
var _baton_pickup_scene: PackedScene = preload("res://scenes/weapons/baton/baton.tscn")

#Hiding
var _hiding_in = null

# Extra animation scenes
var _dying_scene: PackedScene = preload("res://scenes/player/Dying.fbx")
var _strafe_left_scene: PackedScene = preload("res://scenes/player/left_strafe_walk.fbx")
var _idle_scene: PackedScene = preload("res://scenes/player/Idle.fbx")
var _punch_scene: PackedScene = preload("res://scenes/player/hook_punch.fbx")
var _jumping_scene: PackedScene = preload("res://scenes/player/jumping.fbx")
var _shoot_rifle_scene: PackedScene = preload("res://scenes/player/Shoot Rifle.fbx")
var _rifle_walk_back_scene: PackedScene = preload("res://scenes/player/Backwards Rifle Walk.fbx")
var _rifle_strafe_scene: PackedScene = preload("res://scenes/player/Strafe.fbx")
var _rifle_strafe_mirror_scene: PackedScene = preload("res://scenes/player/Strafe_mirror.fbx")
var _flair_scene: PackedScene = preload("res://scenes/player/Flair.fbx")
var _crouch_walk_scene: PackedScene = preload("res://scenes/player/Crouched Walking.fbx")
var _crouch_idle_scene: PackedScene = preload("res://scenes/player/Crouching Idle.fbx")
var _crouch_taser_idle_scene: PackedScene = preload("res://scenes/player/idle_crouch_taser.fbx")
var _crouch_taser_walk_scene: PackedScene = preload("res://scenes/player/crouch_run_taser.fbx")
var _crouch_taser_strafe_right_scene: PackedScene = preload("res://scenes/player/strafe_right_crouch_taser.fbx")
var _crouch_taser_strafe_left_scene: PackedScene = preload("res://scenes/player/strafe_left_crouch_taser.fbx")
var _baton_idle_scene: PackedScene = preload("res://scenes/player/Sword And Shield Idle.fbx")
var _baton_run_scene: PackedScene = preload("res://scenes/player/Sword And Shield Run.fbx")
var _baton_slash_scene: PackedScene = preload("res://scenes/player/Sword And Shield Slash.fbx")
var _baton_strafe_right_scene: PackedScene = preload("res://scenes/player/Sword And Shield Strafe.fbx")
var _baton_strafe_left_scene: PackedScene = preload("res://scenes/player/Sword And Shield Strafe (1).fbx")
var _rifle_idle_scene: PackedScene = preload("res://scenes/player/Rifle Aiming Idle.fbx")
var _breakdance_scene: PackedScene = preload("res://scenes/player/Hip Hop Dancing.fbx")
var _thriller_scene: PackedScene = preload("res://scenes/player/Thriller Part 2.fbx")

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
var _is_emoting: bool = false
var _is_crouching: bool = false
const CROUCH_CAMERA_OFFSET: float = -0.45
var _emote_wheel: PanelContainer = null
var _emote_wheel_visible: bool = false
var _emote_music: AudioStreamPlayer3D = null
var _dance_song: AudioStream = preload("res://scenes/player/dance.mp3")

# Emote definitions: name -> scene
var _emote_scenes: Dictionary = {}
var _emote_names: Array[String] = ["Flair", "Breakdance", "Thriller"]

# Third-person camera
var _third_person: bool = false
var _first_person_camera_pos: Vector3
const THIRD_PERSON_DISTANCE: float = 4.0
const THIRD_PERSON_HEIGHT: float = 1.5

# Network update rate
const NETWORK_UPDATE_RATE: float = 1.0 / 30.0  # 30 updates per second
var _network_update_timer: float = 0.0
# Interaction raycast throttle — 15 Hz feels indistinguishable from per-frame
# for "Press E" prompts and saves an aggressive raycast every physics tick.
const INTERACTION_RAYCAST_RATE: float = 1.0 / 15.0
var _interaction_raycast_timer: float = 0.0
# Idle-suppression: skip packets when nothing changed beyond these thresholds.
# A heartbeat is forced every NETWORK_HEARTBEAT_RATE seconds so late joiners
# (and any dropped unreliable packets) still resync.
const NETWORK_POS_EPSILON: float = 0.01           # meters
const NETWORK_ROT_EPSILON: float = 0.00873        # ~0.5 degrees, in radians
const NETWORK_CAM_EPSILON: float = 0.5            # degrees (camera_rotation_x is in degrees)
const NETWORK_HEARTBEAT_RATE: float = 1.0
var _last_sent_position: Vector3 = Vector3.INF
var _last_sent_rotation_y: float = INF
var _last_sent_camera_x: float = INF
var _last_sent_moving: bool = false
var _last_sent_moving_back: bool = false
var _heartbeat_timer: float = 0.0

# Role assignment
var is_impostor: bool = false
var _role_received: bool = false
var _role_timer: float = 0.0
const ROLE_REVEAL_DELAY: float = 30.0  # TODO: restore to 30.0
var _role_label: Label = null
var _allies_label: Label = null
var _timer_label: Label = null

# Sabotage system (impostor only)
var _sabotage_layer: CanvasLayer = null
var _sabotage_panel: PanelContainer = null
var _sabotage_menu_open: bool = false
var _sabotage_cooldown: float = 0.0
var _last_sabotage: String = ""
var _sabotage_buttons: Dictionary = {}  # sabotage_type -> Button
const SABOTAGE_COOLDOWN_TIME: float = 30.0
var _sabotage_hint_label: Label = null
var _sabotage_cooldown_label: Label = null
var _lights_out_overlay: ColorRect = null

# Possession system
var _is_possessing: bool = false          # Impostor: currently controlling someone
var _possess_target_id: int = 0           # Impostor: steam_id of possessed player
var _possess_timer: float = 0.0
const POSSESS_DURATION: float = 10.0
var _possess_overlay: Control = null       # Red vignette border for impostor
var _is_possessed: bool = false            # Target: being controlled by impostor
var _possess_move_dir: Vector3 = Vector3.ZERO
var _possess_rot_y: float = 0.0
var _possess_cam_x: float = 0.0
var _possessed_overlay: Control = null     # Glitch overlay for target
var _player_select_layer: CanvasLayer = null
var _door_map_layer: CanvasLayer = null
var _locked_doors: Dictionary = {}  # door_id -> true
const DOOR_LOCK_DURATION: float = 15.0
const MAX_DOOR_LOCKS: int = 2
var _door_locks_used: int = 0

# Inventory
var has_taser: bool = false
var _taser_hidden: bool = false
var has_baton: bool = false
var _baton_hidden: bool = false



# Dead state (ghost mode)
var is_dead: bool = false

# Interaction
var _looking_at_interactable: Node = null
var _looking_at_corpse: Node = null
var _interact_label: Label = null
var _notification_label: Label = null
var _holding_button: bool = false
var _last_held_button = null

# Minigame system
var _minigame_active: bool = false
var _minigame_instance: Control = null
var _simon_says_scene: PackedScene = preload("res://scenes/tasks/simon_says_minigame.tscn")
var _wiring_scene: PackedScene = preload("res://scenes/tasks/wiring_minigame.tscn")
var _reactor_temp_scene: PackedScene = preload("res://scenes/tasks/reactor_temp_minigame.tscn")
var _breaker_scene: PackedScene = preload("res://scenes/tasks/breaker_minigame.tscn")
var _targetNumber_scene: PackedScene = preload("res://scenes/tasks/targetNumber_minigame.tscn")
var _sorting_scene: PackedScene = preload("res://scenes/tasks/sorting_minigame.tscn")
var _signal_scene: PackedScene = preload("res://scenes/tasks/signal_minigame.tscn")
var _path_scene: PackedScene = preload("res://scenes/tasks/path_minigame.tscn")
var _download_scene: PackedScene = preload("res://scenes/tasks/download_minigame.tscn")

#Task Designations
var integrity_tasks = ["Crew_task", "Fab_task", "Life_task", "Sheilding_task", "Trash_task", "Lower_Reactor_task", "Electrical_task"]
var TASK_DESCRIPTIONS := {
	"Colonial_task": "Log preservation status. (Lower - Colonial)",
	"Crew_task": "Verify ID badge scans. (Upper - Crew Quarters)",
	"Electrical_task": "Reroute power flow. (Lower - Electrical)",
	"Fab_task": "Fabricate replacement components. (Lower - Fabrication Lab)",
	"Human_Resources_task": "File crew reports. (Upper - Human Resources)",
	"Life_task": "Balance oxygen levels. (Upper - Life Support)",
	"Lower_Reactor_task": "Calibrate reactor temperature. (Lower - Reactor)",
	"Nav_task": "Align navigation array. (Upper - Nav)",
	"Nexus_task": "Stabilize data uplinks. (Upper - Nexus)",
	"Personal_task": "Sort storage items. (Lower - Personal Items)",
	"Shielding_task": "Reinforce hull shielding. (Upper - Shielding)",
	"Supply_task": "Sort supply inventory. (Lower - Ship Supplies)",
	"Supply_Closet_task": "Restock supplies. (Upper - Supply Closet)",
	"Trash_task": "Empty waste bins. (Lower - Trash)",
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

# Taser cooldown HUD
var _taser_timer_circle: TextureProgressBar = null

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
		# If Steam hasn't cached this player's name yet, request it and listen for updates
		if nametag.text == "":
			Steam.requestUserInformation(steam_id, true)
			LobbyManager.member_names_updated.connect(_update_nametag)
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
		_import_animation(_shoot_rifle_scene, "shoot_rifle", true)
		_import_animation(_rifle_walk_back_scene, "rifle_walk_back", true)
		_import_animation(_rifle_strafe_scene, "rifle_strafe", true)
		_import_animation(_rifle_strafe_mirror_scene, "rifle_strafe_mirror", true)
		_import_animation(_flair_scene, "flair", true)
		_import_animation(_crouch_walk_scene, "crouch_walk", true)
		_import_animation(_crouch_idle_scene, "crouch_idle", true)
		_import_animation(_crouch_taser_idle_scene, "crouch_taser_idle", true)
		_import_animation(_crouch_taser_walk_scene, "crouch_taser_walk", true)
		_import_animation(_crouch_taser_strafe_right_scene, "crouch_taser_strafe_right", true)
		_import_animation(_crouch_taser_strafe_left_scene, "crouch_taser_strafe_left", true)
		_import_animation(_baton_idle_scene, "baton_idle", true)
		_import_animation(_baton_run_scene, "baton_run", true)
		_import_animation(_baton_slash_scene, "baton_slash", true)
		_import_animation(_baton_strafe_right_scene, "baton_strafe_right", true)
		_import_animation(_baton_strafe_left_scene, "baton_strafe_left", true)
		_import_animation(_rifle_idle_scene, "rifle_idle", true)
		_import_animation(_breakdance_scene, "breakdance", true)
		_import_animation(_thriller_scene, "thriller", true)

		# Debug: print all animations in the library
		if main_lib:
			print("Animations loaded: ", main_lib.get_animation_list())

		# Set walk, strafe, and idle to loop (dying, punch, jumping should not loop)
		_set_anim_looping("walk", true)
		_set_anim_looping("strafe_left", true)
		_set_anim_looping("idle", true)
		_set_anim_looping("shoot_rifle", true)
		_set_anim_looping("crouch_walk", true)
		_set_anim_looping("crouch_idle", true)
		_set_anim_looping("crouch_taser_idle", true)
		_set_anim_looping("crouch_taser_walk", true)
		_set_anim_looping("crouch_taser_strafe_right", true)
		_set_anim_looping("crouch_taser_strafe_left", true)
		_set_anim_looping("baton_idle", true)
		_set_anim_looping("baton_run", true)
		_set_anim_looping("baton_strafe_right", true)
		_set_anim_looping("baton_strafe_left", true)
		_set_anim_looping("rifle_idle", true)
		_set_anim_looping("rifle_walk_back", true)
		_set_anim_looping("rifle_strafe", true)
		_set_anim_looping("rifle_strafe_mirror", true)

	NetworkManager.punch_received.connect(_on_punch_received)
	NetworkManager.baton_swing_received.connect(_on_baton_swing_received)

	if is_local_player:
		# Capture the mouse cursor for looking around
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_is_mouse_captured = true
		# Make this the active camera
		camera.current = true
		# Show own model in first-person view
		$PlayerModel.visible = true
		# Real-time shadowed lights are very expensive in Forward+. The
		# flashlight still illuminates the scene, just without casting shadows.
		# Saves a full shadow pass per frame.
		if flashlight:
			flashlight.shadow_enabled = false
		# Connect to receive remote player states
		NetworkManager.player_state_received.connect(_on_player_state_received)
		NetworkManager.health_update_received.connect(_on_health_update_received)
		NetworkManager.role_assigned.connect(_on_role_assigned)
		NetworkManager.item_picked_up.connect(_on_item_picked_up)
		NetworkManager.taser_shot_received.connect(_on_taser_shot_received)
		NetworkManager.taser_hit_received.connect(_on_taser_hit_received)
		NetworkManager.taser_hide_received.connect(_on_taser_hide_received)
		NetworkManager.item_dropped_received.connect(_on_item_dropped_received)
		NetworkManager.taser_dead.connect(_on_taser_dead)
		NetworkManager.emote_received.connect(_on_emote_received)
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

		# Create allies label (below role label, shows fellow impostors)
		_allies_label = Label.new()
		_allies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_allies_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_allies_label.anchor_left = 0.5
		_allies_label.anchor_right = 0.5
		_allies_label.anchor_top = 0.5
		_allies_label.anchor_bottom = 0.5
		_allies_label.offset_left = -300
		_allies_label.offset_right = 300
		_allies_label.offset_top = 35
		_allies_label.offset_bottom = 75
		_allies_label.add_theme_font_size_override("font_size", 22)
		_allies_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		_allies_label.text = ""
		_allies_label.visible = false
		$HUD.add_child(_allies_label)

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

		# Taser cooldown bar
		_taser_timer_circle = TextureProgressBar.new()
		_taser_timer_circle.min_value = 0
		_taser_timer_circle.max_value = TASER_COOLDOWN
		_taser_timer_circle.step = 0.01
		_taser_timer_circle.visible = false
		_taser_timer_circle.set_anchors_preset(Control.PRESET_CENTER)
		_taser_timer_circle.offset_left = -32
		_taser_timer_circle.offset_right = 32
		_taser_timer_circle.offset_top = -32
		_taser_timer_circle.offset_bottom = 32
		_taser_timer_circle.scale = Vector2(0.5, 0.5)
		_taser_timer_circle.pivot_offset = Vector2(32, 32)
		_taser_timer_circle.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		_taser_timer_circle.texture_progress = preload("res://scenes/HUD/taser_cooldown/vecteezy_minimalist-white-circle-border_60512381.png")
		_taser_timer_circle.tint_progress = Color.DARK_RED
		_taser_timer_circle.texture_under = _taser_timer_circle.texture_progress
		_taser_timer_circle.tint_under = Color(0.1, 0.1, 0.1, 0.5)
		$HUD.add_child(_taser_timer_circle)

		# Connect destination progress updates
		NetworkManager.progress_update_received.connect(_on_progress_update_received)

		# Connect sabotage effects (for crewmate visual effects)
		UIState.sabotage_triggered.connect(_on_sabotage_triggered)
		UIState.sabotage_ended.connect(_on_sabotage_ended)

		# Connect possession signals
		NetworkManager.possess_start_received.connect(_on_possess_start)
		NetworkManager.possess_move_received.connect(_on_possess_move)
		NetworkManager.possess_end_received.connect(_on_possess_end)
		NetworkManager.possess_action_received.connect(_on_possess_action)

		# Create sabotage hint label (bottom-left, above health bar)
		_sabotage_hint_label = Label.new()
		_sabotage_hint_label.text = "Press Q to Sabotage"
		_sabotage_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_sabotage_hint_label.anchor_left = 0.0
		_sabotage_hint_label.anchor_right = 0.0
		_sabotage_hint_label.anchor_top = 1.0
		_sabotage_hint_label.anchor_bottom = 1.0
		_sabotage_hint_label.offset_left = 70
		_sabotage_hint_label.offset_right = 330
		_sabotage_hint_label.offset_top = -230
		_sabotage_hint_label.offset_bottom = -200
		_sabotage_hint_label.add_theme_font_size_override("font_size", 22)
		_sabotage_hint_label.add_theme_color_override("font_color", Color.RED)
		_sabotage_hint_label.visible = false
		$HUD.add_child(_sabotage_hint_label)

		# Create sabotage cooldown label (above hint)
		_sabotage_cooldown_label = Label.new()
		_sabotage_cooldown_label.text = ""
		_sabotage_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_sabotage_cooldown_label.anchor_left = 0.0
		_sabotage_cooldown_label.anchor_right = 0.0
		_sabotage_cooldown_label.anchor_top = 1.0
		_sabotage_cooldown_label.anchor_bottom = 1.0
		_sabotage_cooldown_label.offset_left = 70
		_sabotage_cooldown_label.offset_right = 330
		_sabotage_cooldown_label.offset_top = -255
		_sabotage_cooldown_label.offset_bottom = -230
		_sabotage_cooldown_label.add_theme_font_size_override("font_size", 18)
		_sabotage_cooldown_label.add_theme_color_override("font_color", Color.ORANGE)
		_sabotage_cooldown_label.visible = false
		$HUD.add_child(_sabotage_cooldown_label)

		# Create sabotage selection panel (hidden by default)
		_create_sabotage_panel()

		# Check if role was already assigned before we loaded
		if NetworkManager.pending_role_received:
			_on_role_assigned(NetworkManager.pending_role_impostor)
		
	else:
		# Remote player - disable camera, input, and HUD
		camera.current = false
		set_process_input(false)
		$HUD.visible = false
		# Kill the shadowed SpotLight3D entirely on remote players.
		# Each shadowed light is one extra shadow map per frame; with 6 players
		# that's 5 unnecessary shadow maps for everyone.
		if flashlight:
			flashlight.shadow_enabled = false
			flashlight.visible = false
		# Local-only audio/UI nodes — leave them in the tree but stop them
		# from polling/processing. Footsteps in particular check is_on_floor()
		# which is meaningless on a remote-controlled CharacterBody3D anyway.
		if steps_sound:
			steps_sound.stop()

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
			get_viewport().set_input_as_handled()
			return
		if _is_paused:
			_on_resume_game()
			get_viewport().set_input_as_handled()
			return
		elif _is_mouse_captured:
			_is_paused = true
			_is_mouse_captured = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_pause_menu.show_menu()
			get_viewport().set_input_as_handled()
			return

	# Allow closing player select menu
	if _player_select_layer:
		if event is InputEventKey and (event.key_label == KEY_Q or event.key_label == KEY_ESCAPE) and event.pressed:
			_close_player_select()
			get_viewport().set_input_as_handled()
		return

	# Allow closing door map
	if _door_map_layer:
		if event is InputEventKey and (event.key_label == KEY_Q or event.key_label == KEY_ESCAPE) and event.pressed:
			_close_door_map()
			get_viewport().set_input_as_handled()
		return

	# Allow Q to close sabotage menu even while it's open
	if _sabotage_menu_open:
		if event is InputEventKey and event.key_label == KEY_Q and event.pressed:
			_close_sabotage_menu()
			get_viewport().set_input_as_handled()
		return

	# When paused or in minigame, don't process game input so UI buttons can receive clicks
	if _is_paused or _minigame_active:
		return

	# While possessing, handle mouse look + forward actions to the target
	if _is_possessing:
		if event is InputEventMouseMotion and _is_mouse_captured:
			_possess_rot_y += deg_to_rad(-event.relative.x * mouse_sensitivity)
			_possess_cam_x = clamp(_possess_cam_x - event.relative.y * mouse_sensitivity, -90, 90)
		# Forward action keys to the possessed player
		if event is InputEventKey and event.pressed:
			if event.key_label == KEY_SPACE or Input.is_action_just_pressed("jump"):
				NetworkManager.send_possess_action(_possess_target_id, "jump")
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			NetworkManager.send_possess_action(_possess_target_id, "attack")
		return

	# While being possessed, block normal input
	if _is_possessed:
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
			_try_report_body()
		elif event.key_label == KEY_K and event.pressed:
			GameManager.adjust_ship_integrity(-10.0)
		elif event.key_label == KEY_L and event.pressed:
			GameManager.adjust_ship_integrity(10.0)
		elif event.key_label == KEY_Q and event.pressed and not is_dead:
			if is_impostor and _role_timer <= 0.0:
				_toggle_sabotage_menu()
		elif event.keycode == KEY_CTRL and event.pressed and not is_dead:
			_is_crouching = not _is_crouching
			_current_anim_state = ""  # Force animation update
			if not _is_crouching:
				$PlayerModel.position.y = 0.0  # Snap model back up immediately
			if is_local_player and not _third_person:
				if _is_crouching:
					$PlayerModel.visible = false
				else:
					$PlayerModel.visible = not has_taser
		elif event.key_label == KEY_B and event.pressed and not is_dead:
			_toggle_emote_wheel()
		elif _emote_wheel_visible and event.pressed:
			if event.key_label == KEY_1 and _emote_names.size() >= 1:
				_on_emote_selected(_emote_names[0].to_lower())
			elif event.key_label == KEY_2 and _emote_names.size() >= 2:
				_on_emote_selected(_emote_names[1].to_lower())
			elif event.key_label == KEY_3 and _emote_names.size() >= 3:
				_on_emote_selected(_emote_names[2].to_lower())
			elif event.key_label == KEY_4:
				_close_emote_wheel()
		elif event.key_label == KEY_F5 and event.pressed:
			_toggle_third_person()
		elif event.key_label == KEY_PERIOD and event.pressed and not is_dead:
			_enter_dead_state()  # Debug: kill player


	# If the input is a mouse button event
	if event is InputEventMouseButton:
		if _minigame_active:
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Don't re-capture mouse if a UI overlay is consuming input (e.g. lobby settings)
			if not _is_mouse_captured and Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				_is_mouse_captured = true
			elif not _is_mouse_captured:
				pass  # UI is open, ignore click
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

func _on_baton_swing_received(sender_steam_id: int) -> void:
	if sender_steam_id != steam_id:
		return
	if not _anim_player:
		return
	_is_swinging = true
	var slash_name = "baton_slash" if _anim_player.has_animation(_anim("baton_slash")) else "punch"
	_current_anim_state = slash_name
	_anim_player.play(_anim(slash_name), ANIM_BLEND)
	_anim_player.speed_scale = 1.0
	await _anim_player.animation_finished
	_is_swinging = false
	_current_anim_state = ""

func _punch_hit_check() -> void:
	if not GameManager.players_container:
		return
	var punch_dir = -global_transform.basis.z
	var range_sq = PUNCH_RANGE * PUNCH_RANGE
	# dot(punch_dir, normalized(to_player)) > PUNCH_ANGLE  is equivalent to
	# dot(punch_dir, to_player) > 0 AND dot^2 > PUNCH_ANGLE^2 * dist_sq.
	# Avoids the sqrt in length()/normalized().
	var angle_sq = PUNCH_ANGLE * PUNCH_ANGLE
	for player in GameManager.players_container.get_children():
		if player == self or not player is CharacterBody3D:
			continue
		if player.is_dead:
			continue
		var to_player = player.global_position - global_position
		var dist_sq = to_player.length_squared()
		if dist_sq > range_sq or dist_sq <= 0.0:
			continue
		var dot = punch_dir.dot(to_player)
		if dot > 0.0 and dot * dot > angle_sq * dist_sq:
			NetworkManager.send_taser_hit(player.steam_id, PUNCH_DAMAGE)
			break

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
	if _role_timer <= 0.0 and _role_label and not _role_label.visible and _role_label.text == "":
		_timer_label.text = ""
		_reveal_role()

	# Sabotage cooldown tick
	if is_impostor and _sabotage_cooldown > 0.0:
		_sabotage_cooldown -= delta
		if _sabotage_cooldown_label:
			_sabotage_cooldown_label.text = "Sabotage cooldown: %ds" % ceili(_sabotage_cooldown)
			_sabotage_cooldown_label.visible = true
		if _sabotage_cooldown <= 0.0:
			_sabotage_cooldown = 0.0
			if _sabotage_cooldown_label:
				_sabotage_cooldown_label.visible = false

	# Possession timer tick (impostor side)
	if _is_possessing:
		_possess_timer -= delta
		if _possess_timer <= 0.0:
			_end_possession()

func _physics_process(delta: float) -> void:
	if is_local_player and GameManager.game_state == GameManager.GAME_STATE_GAME_OVER:
		return
	if is_local_player and _is_paused:
		return
	if is_local_player and _sabotage_menu_open:
		return
	if is_local_player and _door_map_layer:
		return
	if is_local_player and _minigame_active:
		return
	
	# Footsteps (local player only — is_on_floor is unreliable on remote-driven
	# CharacterBody3Ds since we don't run move_and_slide for them)
	if is_local_player:
		if velocity.x != 0 and is_on_floor() and not _is_crouching:
			if !steps_sound.playing:
				steps_sound.play()
		elif steps_sound.playing:
			steps_sound.stop()
		
	if is_local_player:
		# If being possessed, apply remote movement instead of local input
		if _is_possessed and not is_dead:
			_process_possessed_movement(delta)
			_apply_gravity(delta)
			move_and_slide()
			_update_walk_animation()
			_send_network_update(delta)
			return

		# If possessing someone, send our input to the target instead
		if _is_possessing and not is_dead:
			_process_possessing(delta)
			_send_network_update(delta)
			return

		if is_dead:
			_process_ghost_movement(delta)
			move_and_slide()
			_send_network_update(delta)
		else:
			_update_crouch_state()
			_process_local_movement(delta)
			_apply_gravity(delta)
			if is_on_floor() and Input.is_action_just_pressed("jump") and not _is_crouching:
				velocity.y = jump_velocity
				_play_jump()
			if _is_jumping and is_on_floor() and velocity.y <= 0:
				_is_jumping = false
				_current_anim_state = ""  # Reset so next frame picks correct animation
			move_and_slide()
			_update_walk_animation()
			_send_network_update(delta)
			_interaction_raycast_timer += delta
			if _interaction_raycast_timer >= INTERACTION_RAYCAST_RATE:
				_interaction_raycast_timer = 0.0
				_update_interaction_look()
			if _taser_cooldown_timer > 0.0:
				_taser_cooldown_timer -= delta
				_taser_timer_circle.value = TASER_COOLDOWN - _taser_cooldown_timer
				_taser_timer_circle.visible = (has_taser and not _taser_hidden)
			else:
				_taser_timer_circle.visible = false
			if Input.is_action_just_pressed("interact") and _looking_at_interactable:
				_try_interact()
			_update_task_hold(delta)
			_update_button_hold()
	else:
		_process_remote_movement(delta)

# Static across all PlayerController instances. The first player to spawn
# pays the FBX instantiation cost; subsequent players reuse the cached
# Animation resource, which AnimationPlayer plays just fine when shared.
# This cuts ~24 full scene instantiations per extra player at game start.
static var _anim_cache: Dictionary = {}

func _import_animation(scene: PackedScene, anim_name: String, strip_root_position: bool = false) -> void:
	var main_lib_names = _anim_player.get_animation_library_list()
	var main_lib: AnimationLibrary = null
	if main_lib_names.size() > 0:
		main_lib = _anim_player.get_animation_library(main_lib_names[0])
	if not main_lib or main_lib.has_animation(anim_name):
		return

	# Fast path: animation already extracted by an earlier player instance.
	if _anim_cache.has(anim_name):
		main_lib.add_animation(anim_name, _anim_cache[anim_name])
		return

	# Slow path: extract from the FBX scene and cache it.
	var temp = scene.instantiate()
	for child in temp.get_children():
		if child is AnimationPlayer:
			var lib_names = child.get_animation_library_list()
			for lib_name in lib_names:
				var lib = child.get_animation_library(lib_name)
				if lib:
					var anim_list = lib.get_animation_list()
					if anim_list.size() > 0:
						var anim = lib.get_animation(anim_list[0])
						if strip_root_position:
							for i in range(anim.get_track_count() - 1, -1, -1):
								var path = str(anim.track_get_path(i))
								if "Hips" in path and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
									anim.remove_track(i)
						_anim_cache[anim_name] = anim
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
	if not _anim_player or _is_punching or _is_jumping or _is_swinging or _is_emoting:
		return
	var is_moving = Vector2(velocity.x, velocity.z).length() > 0.1

	# When crouching with taser, use taser-specific crouch animations
	if _is_crouching and has_taser and not _taser_hidden:
		if is_moving:
			var forward = -transform.basis.z
			var right = transform.basis.x
			var move_dir = Vector3(velocity.x, 0, velocity.z).normalized()
			var dot = forward.dot(move_dir)
			var side_dot = right.dot(move_dir)
			var has_sideways = abs(side_dot) > 0.3

			if has_sideways:
				if side_dot < 0:
					if _current_anim_state != "crouch_taser_strafe_left":
						_current_anim_state = "crouch_taser_strafe_left"
						_reset_model_mirror()
						_anim_player.play(_anim("crouch_taser_strafe_left"), ANIM_BLEND)
						_anim_player.speed_scale = 1.0
				else:
					if _current_anim_state != "crouch_taser_strafe_right":
						_current_anim_state = "crouch_taser_strafe_right"
						_reset_model_mirror()
						_anim_player.play(_anim("crouch_taser_strafe_right"), ANIM_BLEND)
						_anim_player.speed_scale = 1.0
			else:
				if _current_anim_state != "crouch_taser_walk":
					_current_anim_state = "crouch_taser_walk"
					_reset_model_mirror()
					_anim_player.play(_anim("crouch_taser_walk"), ANIM_BLEND)
					_anim_player.speed_scale = 1.5
			if not _anim_player.is_playing():
				_anim_player.play(_anim_player.current_animation, ANIM_BLEND)
		else:
			if _current_anim_state != "crouch_taser_idle":
				_current_anim_state = "crouch_taser_idle"
				_reset_model_mirror()
				_set_model_diagonal_rotation(0.0)
				_anim_player.play(_anim("crouch_taser_idle"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
		_set_model_diagonal_rotation(0.0)
		return

	# When crouching without taser, use regular crouch animations
	if _is_crouching and _anim_player.has_animation(_anim("crouch_walk")):
		if is_moving:
			if _current_anim_state != "crouch_walk":
				_current_anim_state = "crouch_walk"
				_reset_model_mirror()
				_anim_player.play(_anim("crouch_walk"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
			if not _anim_player.is_playing():
				_anim_player.play(_anim("crouch_walk"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
		else:
			if _current_anim_state != "crouch_idle":
				_current_anim_state = "crouch_idle"
				_reset_model_mirror()
				_set_model_diagonal_rotation(0.0)
				_anim_player.play(_anim("crouch_idle"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
		return

	# When holding taser, use rifle animations for all movement
	if has_taser and not _taser_hidden and _anim_player.has_animation(_anim("shoot_rifle")):
		if is_moving:
			var forward = -transform.basis.z
			var right = transform.basis.x
			var move_dir = Vector3(velocity.x, 0, velocity.z).normalized()
			var dot = forward.dot(move_dir)
			var side_dot = right.dot(move_dir)
			var going_backward = dot < -0.1 and abs(side_dot) < 0.3
			var has_sideways = abs(side_dot) > 0.3

			if has_sideways:
				# Any sideways component (pure strafe or diagonal) uses strafe animation
				_reset_model_mirror()
				if side_dot < 0:
					if _current_anim_state != "rifle_strafe_left":
						_current_anim_state = "rifle_strafe_left"
						_anim_player.play(_anim("rifle_strafe_mirror"), ANIM_BLEND)
						_anim_player.speed_scale = 1.0
				else:
					if _current_anim_state != "rifle_strafe_right":
						_current_anim_state = "rifle_strafe_right"
						_anim_player.play(_anim("rifle_strafe"), ANIM_BLEND)
						_anim_player.speed_scale = 1.0
			elif going_backward:
				if _current_anim_state != "rifle_walk_back":
					_current_anim_state = "rifle_walk_back"
					_reset_model_mirror()
					_anim_player.play(_anim("rifle_walk_back"), ANIM_BLEND)
					_anim_player.speed_scale = 1.5
			else:
				if _current_anim_state != "shoot_rifle_move":
					_current_anim_state = "shoot_rifle_move"
					_reset_model_mirror()
					_anim_player.play(_anim("shoot_rifle"), ANIM_BLEND)
					_anim_player.speed_scale = 1.5
			# Ensure animation is playing (in case it was paused from idle)
			if not _anim_player.is_playing():
				_anim_player.play(_anim_player.current_animation, ANIM_BLEND)
		else:
			_reset_model_mirror()
			if _current_anim_state != "rifle_idle":
				_current_anim_state = "rifle_idle"
				_anim_player.play(_anim("rifle_idle"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
		# Keep model facing forward when holding taser so aim matches shot direction
		_set_model_diagonal_rotation(0.0)
		return

	# When holding baton (and not crouching), use sword/shield animations
	if has_baton and not _baton_hidden and _anim_player.has_animation(_anim("baton_run")):
		if is_moving:
			var right = transform.basis.x
			var move_dir = Vector3(velocity.x, 0, velocity.z).normalized()
			var side_dot = right.dot(move_dir)
			var has_sideways = abs(side_dot) > 0.3

			if has_sideways:
				_reset_model_mirror()
				if side_dot < 0:
					if _current_anim_state != "baton_strafe_left":
						_current_anim_state = "baton_strafe_left"
						_anim_player.play(_anim("baton_strafe_left"), ANIM_BLEND)
						_anim_player.speed_scale = 1.0
				else:
					if _current_anim_state != "baton_strafe_right":
						_current_anim_state = "baton_strafe_right"
						_anim_player.play(_anim("baton_strafe_right"), ANIM_BLEND)
						_anim_player.speed_scale = 1.0
			else:
				if _current_anim_state != "baton_run":
					_current_anim_state = "baton_run"
					_reset_model_mirror()
					_anim_player.play(_anim("baton_run"), ANIM_BLEND)
					_anim_player.speed_scale = 1.5
			if not _anim_player.is_playing():
				_anim_player.play(_anim_player.current_animation, ANIM_BLEND)
		else:
			_reset_model_mirror()
			if _current_anim_state != "baton_idle":
				_current_anim_state = "baton_idle"
				_anim_player.play(_anim("baton_idle"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
		_set_model_diagonal_rotation(0.0)
		return

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
	# A dead remote player is ghost-flying and still broadcasting PLAYER_STATE.
	# Without this guard, each incoming state packet would replay walk/idle,
	# interrupting the dying animation. Since walk/idle loop, animation_finished
	# never fires, _enter_dead_state's await hangs, and _spawn_corpse + the
	# PlayerModel hide never run — so the dying player stays visible as a ghost.
	if is_dead:
		return
	if _is_punching or _is_swinging or _is_emoting:
		return
	# Remote players holding taser use shoot_rifle animation
	if has_taser and not _taser_hidden and _anim_player.has_animation(_anim("shoot_rifle")):
		if moving:
			if _current_anim_state != "shoot_rifle_move":
				_current_anim_state = "shoot_rifle_move"
				_anim_player.play(_anim("shoot_rifle"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
			if not _anim_player.is_playing():
				_anim_player.play(_anim("shoot_rifle"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
		else:
			if _current_anim_state != "rifle_idle":
				_current_anim_state = "rifle_idle"
				_anim_player.play(_anim("rifle_idle"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
		return
	# Remote players holding baton use sword/shield animations
	if has_baton and not _baton_hidden and _anim_player.has_animation(_anim("baton_run")):
		if moving:
			if _current_anim_state != "baton_run":
				_current_anim_state = "baton_run"
				_anim_player.play(_anim("baton_run"), ANIM_BLEND)
				_anim_player.speed_scale = 1.5
			if not _anim_player.is_playing():
				_anim_player.play(_anim("baton_run"), ANIM_BLEND)
		else:
			if _current_anim_state != "baton_idle":
				_current_anim_state = "baton_idle"
				_anim_player.play(_anim("baton_idle"), ANIM_BLEND)
				_anim_player.speed_scale = 1.0
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
	if Input.is_action_pressed("move_forward") and can_move:
		direction += forward
	if Input.is_action_pressed("move_backward") and can_move:
		direction += backward
	if Input.is_action_pressed("move_left") and can_move:
		direction += left
	if Input.is_action_pressed("move_right") and can_move:
		direction += right

	# Normalize the direction vector to ensure consistent speed in all directions
	var input_direction = direction.normalized()

	# Slow down movement while punching, swinging, or crouching
	var move_speed = speed
	if _is_punching:
		move_speed = speed * 0.3
	elif _is_crouching:
		move_speed = speed * 0.5
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
	# Skip the lerp work entirely once we're effectively at the target. Saves
	# 3 lerps + a transform write per remote player per physics frame when
	# they're standing still — common case.
	var pos_delta_sq = global_position.distance_squared_to(_target_position)
	var rot_delta = absf(wrapf(rotation.y - _target_rotation_y, -PI, PI))
	var cam_delta = absf(camera.rotation_degrees.x - _target_camera_rotation_x)
	if pos_delta_sq < 0.0001 and rot_delta < 0.001 and cam_delta < 0.05:
		return

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
	_heartbeat_timer += delta
	if _network_update_timer < NETWORK_UPDATE_RATE:
		return
	_network_update_timer = 0.0

	var moving = Vector2(velocity.x, velocity.z).length() > 0.1
	var forward = -transform.basis.z
	var move_dir = Vector3(velocity.x, 0, velocity.z).normalized()
	var moving_backward = moving and forward.dot(move_dir) < -0.1
	var cam_x = camera.rotation_degrees.x

	# Skip the broadcast if nothing meaningful changed since the last send.
	# At ~6 players this cuts ~150 packets/sec when everyone is idle.
	var changed := (
		_heartbeat_timer >= NETWORK_HEARTBEAT_RATE
		or moving != _last_sent_moving
		or moving_backward != _last_sent_moving_back
		or _last_sent_position.distance_squared_to(global_position) > NETWORK_POS_EPSILON * NETWORK_POS_EPSILON
		or absf(wrapf(rotation.y - _last_sent_rotation_y, -PI, PI)) > NETWORK_ROT_EPSILON
		or absf(cam_x - _last_sent_camera_x) > NETWORK_CAM_EPSILON
	)
	if not changed:
		return

	_last_sent_position = global_position
	_last_sent_rotation_y = rotation.y
	_last_sent_camera_x = cam_x
	_last_sent_moving = moving
	_last_sent_moving_back = moving_backward
	_heartbeat_timer = 0.0

	NetworkManager.send_player_state(
		global_position,
		rotation.y,
		cam_x,
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
	welcome_operator.play()
	is_impostor = impostor
	_role_received = true
	_role_timer = ROLE_REVEAL_DELAY

func _reveal_role() -> void:
	hostiles_detected.play()
	if is_impostor:
		_role_label.text = "IMPOSTOR"
		_role_label.add_theme_color_override("font_color", Color.RED)

		# Show fellow impostors if there are any (unless anonymous impostors is on)
		if _allies_label and GameManager.players_container and not GameManager.anonymous_impostors:
			var ally_names: Array[String] = []
			for player in GameManager.players_container.get_children():
				if player == self:
					continue
				if "is_impostor" in player and player.is_impostor:
					ally_names.append(Steam.getFriendPersonaName(player.steam_id))
			if ally_names.size() > 0:
				_allies_label.text = "Fellow Impostors: " + ", ".join(ally_names)
				_allies_label.visible = true
	else:
		_role_label.text = "CREWMATE"
		_role_label.add_theme_color_override("font_color", Color.CYAN)
	_role_label.visible = true

	# Show sabotage hint for impostor
	if is_impostor and _sabotage_hint_label:
		_sabotage_hint_label.visible = true

	# Hide the role text after 5 seconds
	await get_tree().create_timer(5.0).timeout
	_role_label.visible = false
	if _allies_label:
		_allies_label.visible = false

func _update_nametag() -> void:
	var resolved_name = Steam.getFriendPersonaName(steam_id)
	if resolved_name != "":
		nametag.text = resolved_name
		# Disconnect once we have the name
		if LobbyManager.member_names_updated.is_connected(_update_nametag):
			LobbyManager.member_names_updated.disconnect(_update_nametag)

func _on_health_update_received(sender_steam_id: int, health: int) -> void:
	var player = NetworkManager.get_player(sender_steam_id)
	if player and player != self:
		player.current_health = health
		if health <= 0 and not player.is_dead:
			player._enter_dead_state()

# Apply gravity for local player
func _apply_gravity(delta: float) -> void:
	if not is_on_floor() and can_move:
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

# Setup function called when spawning the player
func setup(player_steam_id: int, local: bool) -> void:
	steam_id = player_steam_id
	is_local_player = local
	name = "Player_" + str(steam_id)

func _update_interaction_look() -> void:
	if _hiding_in:
		_looking_at_interactable = _hiding_in
		_interact_label.text = "Press E to leave hiding"
		_interact_label.visible = true
		return
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * 3.0)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)

	_looking_at_interactable = null
	_looking_at_corpse = null
	if result:
		var collider = result.collider
		if collider.is_in_group("corpse"):
			_looking_at_corpse = _find_corpse_root(collider)
			if _looking_at_corpse:
				_interact_label.text = "Press F to report body"
				_interact_label.visible = true
				return
		if collider.is_in_group("pickup"):
			_looking_at_interactable = _find_activatable(collider)
			if _looking_at_interactable:
				_interact_label.text = "Press E to pick up"
				_interact_label.visible = true
				return
		elif collider.is_in_group("elevator_button"):
			_looking_at_interactable = _find_activatable(collider)
			if _looking_at_interactable:
				_interact_label.text = "Press E to change floors"
				_interact_label.visible = true
				return
		elif collider.is_in_group("elevator_call_button"):
			_looking_at_interactable = _find_activatable(collider)
			if _looking_at_interactable:
				_interact_label.text = "Press E to call elevator"
				_interact_label.visible = true
				return
		elif collider.is_in_group("elevator_door_button"):
			_looking_at_interactable = _find_activatable(collider)
			if _looking_at_interactable:
				_interact_label.text = "Press E to open doors"
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
		elif collider.is_in_group("hideable"):
			_looking_at_interactable = _find_activatable(collider)
			if _looking_at_interactable:
				_interact_label.text = "Press E to hide"
				_interact_label.visible = true
				return
		elif collider.is_in_group("lobby_console"):
			_looking_at_interactable = _find_activatable(collider)
			if _looking_at_interactable:
				if _looking_at_interactable.has_method("get_prompt_text"):
					_interact_label.text = _looking_at_interactable.get_prompt_text()
				else:
					_interact_label.text = "Press E to interact"
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

func _find_corpse_root(node: Node) -> Node:
	while node != null:
		if node.is_in_group("corpse") and node.has_meta("victim_name"):
			return node
		node = node.get_parent()
	return null

func _try_report_body() -> void:
	if is_dead:
		return
	if not _looking_at_corpse or not is_instance_valid(_looking_at_corpse):
		return
	var victim_name: String = _looking_at_corpse.get_meta("victim_name", "")
	if victim_name == "":
		return
	if _looking_at_corpse.has_meta("reported") and _looking_at_corpse.get_meta("reported"):
		return
	_looking_at_corpse.set_meta("reported", true)
	NetworkManager.send_body_reported(victim_name)

func _try_interact() -> void:
	if not _looking_at_interactable:
		return
	# Block task interaction during comms disable (crewmates only)
	if not is_impostor and GameManager.is_sabotage_active("disable_comms") and _looking_at_interactable.is_in_group("task_console"):
		if _notification_label:
			_notification_label.text = "Comms offline - cannot access tasks!"
			_notification_label.visible = true
			get_tree().create_timer(2.0).timeout.connect(func(): _notification_label.visible = false)
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
		_last_held_button = _looking_at_interactable
		_looking_at_interactable.activate()
		
	elif _looking_at_interactable.is_in_group("hideable"):
		_looking_at_interactable.activate(self)
	else:
		_looking_at_interactable.activate()

func give_taser() -> void:
	#if is_local_player:
	drop_current_weapon()
	has_taser = true
	_attach_taser_model()
	taser_pickup_sound.play()
	if is_local_player and not _third_person:
		$PlayerModel.visible = false
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
	#if is_local_player:
	drop_current_weapon()
	has_baton = true
	baton_uses = current_uses
	_attach_baton_model()
	baton_pickup_sound.play()
	if is_local_player:
		_notification_label.text = "Baton Acquired (Power Level: %s%%)!" % (baton_uses * 100 / MAX_BATON_USES)
		_notification_label.visible = true
		await get_tree().create_timer(3.0).timeout
		_notification_label.visible = false

func _attach_baton_model() -> void:
	if _held_baton:
		return
	_held_baton = _baton_scene.instantiate()

	var hand_attach := _get_or_create_hand_attachment()
	if hand_attach:
		# Bone is inside PlayerModel (scale 65) inside player root (scale 1.1),
		# so divide visible scale through to compensate
		_held_baton.scale = Vector3(0.008, 0.008, 0.008)
		_held_baton.rotation_degrees = Vector3(0, 0, 0)
		_held_baton.position = Vector3(0, 0, 0)
		hand_attach.add_child(_held_baton)
	else:
		# Fallback: camera-relative (only visible in first-person)
		_held_baton.scale = Vector3(0.5, 0.5, 0.5)
		_held_baton.rotation_degrees.y = 90.0
		weapon_holder.add_child(_held_baton)

func _get_or_create_hand_attachment() -> BoneAttachment3D:
	var skel := _find_skeleton($PlayerModel)
	if not skel:
		return null
	var existing := skel.get_node_or_null("BatonHandAttach")
	if existing and existing is BoneAttachment3D:
		return existing
	var bone_idx := -1
	for bone_name in ["mixamorig_RightHand", "mixamorig:RightHand", "RightHand", "mixamorig_RightHandIndex1"]:
		bone_idx = skel.find_bone(bone_name)
		if bone_idx != -1:
			break
	if bone_idx == -1:
		return null
	var attach := BoneAttachment3D.new()
	attach.name = "BatonHandAttach"
	attach.bone_idx = bone_idx
	skel.add_child(attach)
	return attach

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null


func _on_taser_dead(steam_id):
	var player = NetworkManager.get_player(steam_id)
	if player and player != self and player._held_baton:
		player.drop_current_weapon()
		
	
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
		if is_local_player and not _third_person:
			$PlayerModel.visible = true
	elif has_baton:
		pickup_to_spawn = _baton_pickup_scene
		has_baton = false
		if _held_baton:
			_held_baton.queue_free()
			_held_baton = null
			
	if is_local_player and pickup_to_spawn:
		var pickup = pickup_to_spawn.instantiate()
		var drop_origin = global_position + Vector3(0, 1.0, 0)
		var drop_direction = -global_transform.basis.z * 1.5
		var target_pos = drop_origin + drop_direction
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(target_pos, target_pos + Vector3.DOWN * 2.0)
		query.exclude = [self]
		var result = space_state.intersect_ray(query)
		var final_transform = Transform3D()
		if result:
			final_transform.origin = result.position
			final_transform = final_transform.looking_at(result.position + global_transform.basis.z, result.normal)
		else:
			final_transform.origin = global_position
			final_transform.basis = global_transform.basis
		final_transform = final_transform.rotated_local(Vector3.FORWARD, deg_to_rad(90))
		pickup.global_transform = final_transform
		pickup.item_id = player_weapon_id
		pickup.add_to_group("pickup")
		if "current_uses" in pickup:
			pickup.current_uses = uses
		get_tree().current_scene.add_child(pickup)
		NetworkManager.send_item_dropped(saved_id, pickup.global_transform, uses)
		player_weapon_id = ""

func _on_item_dropped_received(item_id: String, xform: Transform3D, uses: int) -> void:
	# The signal sends a Transform3D (network_manager.gd builds one with both
	# position and rotation). Earlier this handler declared Vector3 here,
	# causing every weapon respawn / drop to fail with a type-conversion
	# error and skipping spawn of the pickup on remote clients.
	var scene_to_spawn: PackedScene = null
	if item_id.begins_with("taser"):
		scene_to_spawn = _taser_pickup_scene
	elif item_id.begins_with("baton"):
		scene_to_spawn = _baton_pickup_scene
	if scene_to_spawn:
		_spawn_pickup_in_world(item_id, scene_to_spawn, xform.origin, uses)
		
func _spawn_pickup_in_world(id: String, scene: PackedScene, pos: Vector3, uses: int) -> void:
	var pickup = scene.instantiate()
	pickup.global_position = pos
	pickup.item_id = id
	if "current_uses" in pickup:
		pickup.current_uses = uses
	pickup.add_to_group("pickup")
	get_tree().current_scene.add_child(pickup)
	print(id, pickup.item_id)

func _on_item_picked_up(picker_steam_id: int, item_id: String) -> void:
	var player = NetworkManager.get_player(picker_steam_id)
	if not player:
		return
	if player == self:
		player_weapon_id = item_id
		return
	# A stale weapon model on the picker (e.g. from a previous round, or from
	# them swapping weapons) makes _attach_*_model early-return, leaving the
	# picker visibly empty-handed on remote clients. Drop whatever they were
	# holding before attaching the new pickup.
	if "drop_current_weapon" in player:
		player.drop_current_weapon()
	if item_id.begins_with("taser") and player.has_method("give_taser"):
		player.give_taser()
	elif item_id.begins_with("baton") and player.has_method("give_baton"):
		player.give_baton()

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
	taser_shot_sound.play()
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
	baton_use_sound.play()
	var slash_name = "baton_slash" if _anim_player.has_animation(_anim("baton_slash")) else "punch"
	_current_anim_state = slash_name
	_anim_player.play(_anim(slash_name), 0.2)
	_anim_player.speed_scale = 1.0
	NetworkManager.send_baton_swing()
	
	await get_tree().create_timer(0.2).timeout
	_baton_hit_check()
	
	await _anim_player.animation_finished
	_is_swinging = false
	_current_anim_state = ""

	
func _baton_hit_check() -> void:
	var swing_dir = -global_transform.basis.z
	var range_sq = BATON_RANGE * BATON_RANGE
	# 0.5 is the cone-cosine threshold; squared so we can avoid normalize().
	const ANGLE_SQ := 0.25
	for player in GameManager.players_container.get_children():
		if player == self or not player is CharacterBody3D or player.is_dead:
			continue
		var to_player = player.global_position - global_position
		var dist_sq = to_player.length_squared()
		if dist_sq > range_sq or dist_sq <= 0.0:
			continue
		var dot = swing_dir.dot(to_player)
		if dot > 0.0 and dot * dot > ANGLE_SQ * dist_sq:
			baton_uses -= 1
			_update_baton_status()
			NetworkManager.send_taser_hit(player.steam_id, BATON_DAMAGE)
			break

func _update_baton_status() -> void:
	var player = self
	if is_local_player:
		_notification_label.text = "Baton Power Remaining: %s%%" % (baton_uses * 100 / MAX_BATON_USES)
		_notification_label.visible = true
		
	if baton_uses <= 0:
		drop_current_weapon()
		NetworkManager.send_taser_dead(player.steam_id)
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
		$PlayerModel.visible = not has_taser
		weapon_holder.visible = true

## Explicitly reset all per-round state to a fresh "alive" baseline.
## Called by GameManager._spawn_all_players_progressively after each player
## spawns into a new round, to defend against:
##   1. Stale damage/death packets from a previous round that get processed
##      during round 2's first frame and would otherwise immediately mark a
##      freshly-spawned player dead.
##   2. Anything else (signal handlers, lingering references) that could
##      leave a fresh node in a non-default state.
## Cheap to call on a fresh node — the values are already correct, this just
## guarantees them.
func reset_round_state() -> void:
	is_dead = false
	current_health = max_health
	_is_possessed = false
	_is_possessing = false
	_possess_target_id = 0
	_possess_timer = 0.0
	_possess_move_dir = Vector3.ZERO
	_possess_rot_y = 0.0
	_possess_cam_x = 0.0
	has_taser = false
	has_baton = false
	baton_uses = 0
	_taser_hidden = false
	_baton_hidden = false
	if _held_taser and is_instance_valid(_held_taser):
		_held_taser.queue_free()
	_held_taser = null
	if _held_baton and is_instance_valid(_held_baton):
		_held_baton.queue_free()
	_held_baton = null
	# Restore visibility / collision in case _enter_dead_state ran on this
	# node before reset (shouldn't happen on a fresh instance, but cheap to
	# be explicit).
	if has_node("PlayerModel"):
		$PlayerModel.visible = true
	if nametag and is_instance_valid(nametag):
		nametag.visible = true
	if has_node("PhysicsCollider"):
		$PhysicsCollider.disabled = false
	if _interact_label and is_instance_valid(_interact_label):
		_interact_label.visible = false

## Maximum time to display the dying animation before forcibly hiding the
## live model and spawning the corpse. We used to await animation_finished,
## but if anything interrupts the animation (e.g. a remote PLAYER_STATE
## packet replaying a walk loop) the await never resumes, leaving the dying
## player visible as a "ghost" forever.
const DYING_ANIMATION_DURATION: float = 2.0

func _enter_dead_state() -> void:
	# Idempotent — guards against double-trigger from overlapping HEALTH_UPDATE
	# packets, retransmits, or simultaneous damage sources.
	if is_dead:
		return
	is_dead = true

	drop_current_weapon()

	if _anim_player and _anim_player.has_animation(_anim("dying")):
		$PlayerModel.visible = true
		_anim_player.play(_anim("dying"), ANIM_BLEND)
		_anim_player.speed_scale = 1.0

	# Fixed-duration delay rather than animation_finished. Reliable even if
	# something else replays a different animation on this AnimationPlayer
	# while the dying animation would have been playing.
	await get_tree().create_timer(DYING_ANIMATION_DURATION).timeout

	# Bail safely if this node was freed during the await (e.g. play_again
	# despawn, scene change).
	if not is_instance_valid(self):
		return

	_spawn_corpse()
	if has_node("PlayerModel"):
		$PlayerModel.visible = false
	if nametag and is_instance_valid(nametag):
		nametag.visible = false
	if _held_taser and is_instance_valid(_held_taser):
		_held_taser.visible = false
	if _held_baton and is_instance_valid(_held_baton):
		_held_baton.visible = false
	if has_node("PhysicsCollider"):
		$PhysicsCollider.disabled = true
	if _interact_label and is_instance_valid(_interact_label):
		_interact_label.visible = false

func _spawn_corpse() -> void:
	var model := $PlayerModel as Node3D
	if not model:
		return
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	var corpse_model := model.duplicate() as Node3D
	if not corpse_model:
		return

	var corpse_root := StaticBody3D.new()
	corpse_root.name = "Corpse_%d" % steam_id
	corpse_root.add_to_group("corpse")
	corpse_root.set_meta("victim_name", String(nametag.text) if nametag else "")
	corpse_root.set_meta("reported", false)
	scene_root.add_child(corpse_root)
	corpse_root.global_transform = Transform3D(Basis.IDENTITY, global_position)

	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 1.6
	collider.shape = capsule
	# Lay the capsule flat along the ground so a prone body is hittable from above.
	collider.transform = Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(90)), Vector3(0, 0.4, 0))
	corpse_root.add_child(collider)

	corpse_root.add_child(corpse_model)
	corpse_model.global_transform = model.global_transform
	corpse_model.visible = true
	var corpse_anim: AnimationPlayer = null
	for child in corpse_model.get_children():
		if child is AnimationPlayer:
			corpse_anim = child
			break
	if corpse_anim and corpse_anim.has_animation(_anim("dying")):
		var dying_anim := corpse_anim.get_animation(_anim("dying"))
		corpse_anim.play(_anim("dying"))
		if dying_anim:
			corpse_anim.seek(dying_anim.length, true)
		corpse_anim.pause()
	if nametag:
		var corpse_nametag := nametag.duplicate() as Node3D
		if corpse_nametag:
			corpse_root.add_child(corpse_nametag)
			corpse_nametag.global_transform = nametag.global_transform
			corpse_nametag.visible = true

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
		if not _can_start_task(tid):
			_cancel_task_hold()
			return
		if _can_player_complete_task(tid):
			_complete_task(tid)
		else:
			_cancel_task_hold()

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
	elif _last_held_button and _last_held_button.has_method("deactivate"):
		_last_held_button.deactivate()
		_last_held_button = null
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
			panel.mark_task_completed(task_id)

func _can_player_complete_task(task_id: String) -> bool:
	var panels = get_tree().get_nodes_in_group("directives_panel")

	for panel in panels:
		if panel.has_method("can_complete_task"):
			return panel.can_complete_task(task_id)

	return false
	
func _can_start_task(task_id: String) -> bool:
	var panels = get_tree().get_nodes_in_group("directives_panel")

	for panel in panels:
		if panel.has_method("can_complete_task"):
			return panel.can_complete_task(task_id)

	return false

# --- Task Minigames ---
func _show_ui_message(msg: String) -> void:
	for panel in get_tree().get_nodes_in_group("directives_panel"):
		if panel.has_method("show_message"):
			panel.show_message(msg)
			
func _open_minigame(task_id: String, minigame_type: String) -> void:
	if _minigame_active:
		return
	if not _can_start_task(task_id):
		denied_sound.play()
		print("Task not assigned — blocking minigame")
		_show_ui_message("Task not assigned")
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
		"targetNumber":
			_minigame_instance = _targetNumber_scene.instantiate()
		"sorting":
			_minigame_instance = _sorting_scene.instantiate()
		"signal":
			_minigame_instance = _signal_scene.instantiate()
		"path":
			_minigame_instance = _path_scene.instantiate()
		"download":
			_minigame_instance = _download_scene.instantiate()
		_:
			_minigame_instance = _simon_says_scene.instantiate()

	layer.add_child(_minigame_instance)

	_minigame_instance.minigame_completed.connect(_on_minigame_completed.bind(task_id))
	_minigame_instance.minigame_cancelled.connect(_on_minigame_cancelled)

	_minigame_instance.start_game()

func _on_minigame_completed(task_id: String) -> void:
	_close_minigame()
	if _can_player_complete_task(task_id):
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

# --- Sabotage System (Impostor only) ---

func _create_sabotage_panel() -> void:
	# Use a CanvasLayer so the panel renders above everything and receives input
	_sabotage_layer = CanvasLayer.new()
	_sabotage_layer.layer = 90
	add_child(_sabotage_layer)

	# Full-screen Control to catch input
	var root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_STOP
	_sabotage_layer.add_child(root_control)

	_sabotage_panel = PanelContainer.new()
	_sabotage_panel.anchor_left = 0.5
	_sabotage_panel.anchor_right = 0.5
	_sabotage_panel.anchor_top = 0.5
	_sabotage_panel.anchor_bottom = 0.5
	_sabotage_panel.offset_left = -160
	_sabotage_panel.offset_right = 160
	_sabotage_panel.offset_top = -120
	_sabotage_panel.offset_bottom = 120

	# Dark red background style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.02, 0.02, 0.92)
	style.border_color = Color(0.8, 0.1, 0.1, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_sabotage_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_sabotage_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "-- SABOTAGE --"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.RED)
	vbox.add_child(title)

	# Sabotage buttons
	var btn_lights = Button.new()
	btn_lights.text = "Lights Out"
	btn_lights.add_theme_font_size_override("font_size", 18)
	btn_lights.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_lights.pressed.connect(_on_sabotage_selected.bind("lights_out"))
	vbox.add_child(btn_lights)
	_sabotage_buttons["lights_out"] = btn_lights

	var btn_drain = Button.new()
	btn_drain.text = "Drain Integrity"
	btn_drain.add_theme_font_size_override("font_size", 18)
	btn_drain.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_drain.pressed.connect(_on_sabotage_selected.bind("drain_integrity"))
	vbox.add_child(btn_drain)
	_sabotage_buttons["drain_integrity"] = btn_drain

	var btn_comms = Button.new()
	btn_comms.text = "Disable Comms"
	btn_comms.add_theme_font_size_override("font_size", 18)
	btn_comms.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_comms.pressed.connect(_on_sabotage_selected.bind("disable_comms"))
	vbox.add_child(btn_comms)
	_sabotage_buttons["disable_comms"] = btn_comms

	var btn_possess = Button.new()
	btn_possess.text = "Possess Player"
	btn_possess.add_theme_font_size_override("font_size", 18)
	btn_possess.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_possess.pressed.connect(_on_possess_selected)
	vbox.add_child(btn_possess)
	_sabotage_buttons["possess"] = btn_possess

	var btn_anon = Button.new()
	btn_anon.text = "Anonymous Mode"
	btn_anon.add_theme_font_size_override("font_size", 18)
	btn_anon.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_anon.pressed.connect(_on_sabotage_selected.bind("anonymous"))
	vbox.add_child(btn_anon)
	_sabotage_buttons["anonymous"] = btn_anon

	var btn_doors = Button.new()
	btn_doors.text = "Lock Doors"
	btn_doors.add_theme_font_size_override("font_size", 18)
	btn_doors.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_doors.pressed.connect(_on_lock_doors_selected)
	vbox.add_child(btn_doors)
	_sabotage_buttons["lock_doors"] = btn_doors

	# Cancel label
	var cancel = Label.new()
	cancel.text = "Press Q to cancel"
	cancel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel.add_theme_font_size_override("font_size", 14)
	cancel.add_theme_color_override("font_color", Color.GRAY)
	vbox.add_child(cancel)

	root_control.add_child(_sabotage_panel)
	_sabotage_layer.visible = false

func _toggle_sabotage_menu() -> void:
	if _sabotage_menu_open:
		_close_sabotage_menu()
	else:
		_open_sabotage_menu()

func _open_sabotage_menu() -> void:
	if _sabotage_cooldown > 0.0:
		_notification_label.text = "Sabotage on cooldown: %ds" % ceili(_sabotage_cooldown)
		_notification_label.visible = true
		await get_tree().create_timer(2.0).timeout
		_notification_label.visible = false
		return
	# Disable the last-used sabotage, enable all others
	for sab_type in _sabotage_buttons:
		_sabotage_buttons[sab_type].disabled = (sab_type == _last_sabotage)
	_sabotage_menu_open = true
	_sabotage_layer.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_is_mouse_captured = false
	# Hide crosshair
	if GameManager.hud_instance:
		var crosshair = GameManager.hud_instance.get_node_or_null("Crosshair")
		if crosshair:
			crosshair.visible = false

func _close_sabotage_menu() -> void:
	_sabotage_menu_open = false
	_sabotage_layer.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_is_mouse_captured = true
	# Restore crosshair
	if GameManager.hud_instance:
		var crosshair = GameManager.hud_instance.get_node_or_null("Crosshair")
		if crosshair:
			crosshair.visible = true

func _on_sabotage_selected(sabotage_type: String) -> void:
	_close_sabotage_menu()
	_sabotage_cooldown = SABOTAGE_COOLDOWN_TIME
	_last_sabotage = sabotage_type
	NetworkManager.send_sabotage(sabotage_type)

func _on_sabotage_triggered(sabotage_type: String) -> void:
	if not is_local_player:
		return
	if sabotage_type == "lights_out":
		emergency_measures_activated.play()
		flashlight.visible = true
		flashlight.light_color = Color.GREEN
	elif sabotage_type == "drain_integrity":
		structural_integrity_compromised.play()
	elif sabotage_type == "disable_comms":
		rebooting_systems.play()
	elif sabotage_type == "anonymous":
		warning_malfunction.play()
		_mask_all_nametags()

func _on_sabotage_ended(sabotage_type: String) -> void:
	if not is_local_player:
		return
	systems_operational.play()
	if sabotage_type == "lights_out":
		flashlight.visible = false
	elif sabotage_type == "anonymous":
		_restore_all_nametags()

func _show_lights_out() -> void:
	if _lights_out_overlay:
		return
	_lights_out_overlay = ColorRect.new()
	_lights_out_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lights_out_overlay.color = Color(0, 0, 0, 0.85)
	_lights_out_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_lights_out_overlay)

func _hide_lights_out() -> void:
	if _lights_out_overlay:
		_lights_out_overlay.queue_free()
		_lights_out_overlay = null

func _mask_all_nametags() -> void:
	if not GameManager.players_container:
		return
	for player in GameManager.players_container.get_children():
		if player == self:
			continue
		if player.has_node("Label3D"):
			var tag = player.get_node("Label3D")
			tag.set_meta("real_name", tag.text)
			tag.text = "???"
			tag.modulate = Color(1, 0.3, 0.3, 1)

func _restore_all_nametags() -> void:
	if not GameManager.players_container:
		return
	for player in GameManager.players_container.get_children():
		if player == self:
			continue
		if player.has_node("Label3D"):
			var tag = player.get_node("Label3D")
			if tag.has_meta("real_name"):
				tag.text = tag.get_meta("real_name")
			tag.modulate = Color(1, 1, 1, 1)

# --- Possession System ---

func _on_possess_selected() -> void:
	_close_sabotage_menu()
	_show_player_select()

func _show_player_select() -> void:
	# Build a list of alive crewmates to possess
	if not GameManager.players_container:
		return

	_player_select_layer = CanvasLayer.new()
	_player_select_layer.layer = 91
	add_child(_player_select_layer)

	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_player_select_layer.add_child(root)

	# Semi-transparent backdrop
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -150
	panel.offset_right = 150
	panel.offset_top = -120
	panel.offset_bottom = 120
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.0, 0.0, 0.95)
	style.border_color = Color(0.8, 0.1, 0.1, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "-- SELECT TARGET --"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.RED)
	vbox.add_child(title)

	var found_targets := false
	for player in GameManager.players_container.get_children():
		if player == self or not ("is_impostor" in player) or player.is_impostor:
			continue
		if player.is_dead:
			continue
		# Skip players already being possessed by another impostor
		if NetworkManager.possessed_players.has(player.steam_id):
			continue
		found_targets = true
		var btn = Button.new()
		btn.text = Steam.getFriendPersonaName(player.steam_id)
		btn.add_theme_font_size_override("font_size", 18)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_target_chosen.bind(player.steam_id))
		vbox.add_child(btn)

	if not found_targets:
		var no_targets = Label.new()
		no_targets.text = "No valid targets"
		no_targets.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_targets.add_theme_font_size_override("font_size", 16)
		no_targets.add_theme_color_override("font_color", Color.GRAY)
		vbox.add_child(no_targets)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	cancel_btn.pressed.connect(_close_player_select)
	vbox.add_child(cancel_btn)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_is_mouse_captured = false

func _close_player_select() -> void:
	if _player_select_layer:
		_player_select_layer.queue_free()
		_player_select_layer = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_is_mouse_captured = true

func _on_target_chosen(target_steam_id: int) -> void:
	_close_player_select()
	_sabotage_cooldown = SABOTAGE_COOLDOWN_TIME
	_last_sabotage = "possess"
	_start_possession(target_steam_id)

# --- Impostor side: possessing ---

func _start_possession(target_steam_id: int) -> void:
	_is_possessing = true
	_possess_target_id = target_steam_id
	_possess_timer = POSSESS_DURATION

	# Initialize our tracked rotation from the target's current state
	var target_player = NetworkManager.get_player(target_steam_id)
	if target_player:
		anomaly_detected.play()
		_possess_rot_y = target_player.rotation.y
		_possess_cam_x = target_player.camera.rotation_degrees.x

	# Tell the target they are possessed
	NetworkManager.send_possess_start(target_steam_id)

	# Create red vignette border overlay
	_possess_overlay = Control.new()
	_possess_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_possess_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_possess_overlay)

	var border_thickness := 6
	# Top border
	var top = ColorRect.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = border_thickness
	top.color = Color(1, 0, 0, 0.8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possess_overlay.add_child(top)
	# Bottom border
	var bottom = ColorRect.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -border_thickness
	bottom.color = Color(1, 0, 0, 0.8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possess_overlay.add_child(bottom)
	# Left border
	var left = ColorRect.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = border_thickness
	left.color = Color(1, 0, 0, 0.8)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possess_overlay.add_child(left)
	# Right border
	var right = ColorRect.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -border_thickness
	right.color = Color(1, 0, 0, 0.8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possess_overlay.add_child(right)

	# Subtle red tint
	var tint = ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(1, 0, 0, 0.08)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possess_overlay.add_child(tint)

	# "POSSESSING" label with timer
	var lbl = Label.new()
	lbl.name = "PossessTimer"
	lbl.text = "POSSESSING - %.0fs" % _possess_timer
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.5
	lbl.anchor_right = 0.5
	lbl.anchor_top = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_left = -200
	lbl.offset_right = 200
	lbl.offset_top = 12
	lbl.offset_bottom = 42
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color.RED)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possess_overlay.add_child(lbl)

func _end_possession() -> void:
	if not _is_possessing:
		return
	_is_possessing = false

	# Tell target they are free
	NetworkManager.send_possess_end(_possess_target_id)
	_possess_target_id = 0

	# Remove overlay
	if _possess_overlay:
		_possess_overlay.queue_free()
		_possess_overlay = null

	# Restore camera back to first-person on our own body
	camera.set_as_top_level(false)
	camera.position = _first_person_camera_pos
	camera.rotation_degrees = Vector3.ZERO

	# Make sure mouse is captured and input works
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_is_mouse_captured = true

func _process_possessing(delta: float) -> void:
	# Update the timer label
	if _possess_overlay:
		var lbl = _possess_overlay.get_node_or_null("PossessTimer")
		if lbl:
			lbl.text = "POSSESSING - %.0fs" % maxf(_possess_timer, 0)

	var target_player = NetworkManager.get_player(_possess_target_id)
	if not target_player:
		_end_possession()
		return

	# Make camera top-level so it's not affected by our body position
	if not camera.is_set_as_top_level():
		camera.set_as_top_level(true)

	# Position camera at the target's eye level (same as first-person camera offset)
	var cam_basis = Basis(Vector3.UP, _possess_rot_y)
	camera.global_position = target_player.global_position + Vector3(0, 1.0, 0) + cam_basis * Vector3(0, 0, -0.3)
	camera.global_rotation = Vector3(deg_to_rad(_possess_cam_x), _possess_rot_y, 0)

	# Gather movement input relative to our tracked rotation (not the remote player's)
	var direction = Vector3.ZERO
	var forward = -cam_basis.z
	var backward = cam_basis.z
	var left = -cam_basis.x
	var right = cam_basis.x

	if Input.is_action_pressed("move_forward"):
		direction += forward
	if Input.is_action_pressed("move_backward"):
		direction += backward
	if Input.is_action_pressed("move_left"):
		direction += left
	if Input.is_action_pressed("move_right"):
		direction += right

	direction = direction.normalized()

	# Send movement + our rotation to the target
	NetworkManager.send_possess_move(
		_possess_target_id,
		direction,
		_possess_rot_y,
		_possess_cam_x
	)

	# Don't move our own body - just stand still
	velocity = Vector3.ZERO

# --- Target side: being possessed ---

func _force_close_all_ui() -> void:
	# Close pause menu
	if _is_paused:
		_on_resume_game()
	# Close active minigame
	if _minigame_active:
		_close_minigame()
	# Cancel task hold
	if _is_holding_task:
		_cancel_task_hold()
	# Close emote wheel
	if _emote_wheel_visible:
		_close_emote_wheel()
	# Close sabotage menu (impostors can't be possessed, but just in case)
	if _sabotage_menu_open:
		_close_sabotage_menu()
	# Ensure mouse is captured and input works
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_is_mouse_captured = true

func _on_possess_start(impostor_steam_id: int, target_steam_id: int) -> void:
	if not is_local_player or target_steam_id != steam_id:
		return

	# Force-close any open menus/tasks so the impostor can control us
	_force_close_all_ui()

	_is_possessed = true

	# Show "SYSTEM COMPROMISED" overlay
	_possessed_overlay = Control.new()
	_possessed_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_possessed_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_possessed_overlay)

	# Glitchy orange/yellow border
	var border_thickness := 5
	var border_color := Color(1.0, 0.4, 0.0, 0.75)
	var t = ColorRect.new()
	t.set_anchors_preset(Control.PRESET_TOP_WIDE)
	t.offset_bottom = border_thickness
	t.color = border_color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possessed_overlay.add_child(t)
	var b = ColorRect.new()
	b.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	b.offset_top = -border_thickness
	b.color = border_color
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possessed_overlay.add_child(b)
	var l = ColorRect.new()
	l.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	l.offset_right = border_thickness
	l.color = border_color
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possessed_overlay.add_child(l)
	var r = ColorRect.new()
	r.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	r.offset_left = -border_thickness
	r.color = border_color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possessed_overlay.add_child(r)

	# Warning text
	var warning = Label.new()
	warning.text = "SYSTEM COMPROMISED\nCONTROLS OVERRIDDEN"
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning.anchor_left = 0.5
	warning.anchor_right = 0.5
	warning.anchor_top = 0.0
	warning.anchor_bottom = 0.0
	warning.offset_left = -250
	warning.offset_right = 250
	warning.offset_top = 60
	warning.offset_bottom = 130
	warning.add_theme_font_size_override("font_size", 28)
	warning.add_theme_color_override("font_color", Color(1.0, 0.3, 0.0, 1.0))
	warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possessed_overlay.add_child(warning)

	# Subtle orange tint
	var tint = ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(1, 0.3, 0, 0.06)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_possessed_overlay.add_child(tint)

func _on_possess_move(_target_steam_id: int, move_dir: Vector3, rot_y: float, cam_rot_x: float) -> void:
	if not is_local_player or not _is_possessed:
		return
	_possess_move_dir = move_dir
	# Apply rotation from the impostor
	rotation.y = rot_y
	camera.rotation_degrees.x = cam_rot_x

func _on_possess_action(_target_steam_id: int, action: String) -> void:
	if not is_local_player or not _is_possessed:
		return
	match action:
		"jump":
			if is_on_floor():
				velocity.y = jump_velocity
				_play_jump()
		"attack":
			if has_taser and not _taser_hidden:
				_shoot_taser()
			elif has_baton and not _baton_hidden and not _is_swinging:
				if baton_uses > 0:
					_swing_baton()
			elif not _is_punching:
				_play_punch()

func _on_possess_end(target_steam_id: int) -> void:
	if not is_local_player or target_steam_id != steam_id:
		return
	_is_possessed = false
	_possess_move_dir = Vector3.ZERO

	if _possessed_overlay:
		_possessed_overlay.queue_free()
		_possessed_overlay = null

func _process_possessed_movement(delta: float) -> void:
	# Apply the movement direction sent by the impostor
	velocity.x = _possess_move_dir.x * speed
	velocity.z = _possess_move_dir.z * speed
	# Apply gravity so jumping works
	if not is_on_floor():
		velocity.y -= gravity * delta
	if _is_jumping and is_on_floor() and velocity.y <= 0:
		_is_jumping = false
		_current_anim_state = ""

# --- Lock Doors Sabotage ---

# Door data: display name -> { path patterns to match, map position }
# Positions are approximate on a 600x400 schematic map
const UPPER_DOORS = {
	"Nexus North": {"pattern": "NorthNexusDoor", "x": 300, "y": 60},
	"Nexus South": {"pattern": "SouthNexusDoor", "x": 300, "y": 180},
	"Nav Bridge": {"pattern": "NavDoor", "x": 300, "y": 30},
	"Cams": {"pattern": "CamsDoor", "x": 250, "y": 120},
	"Intercom": {"pattern": "IntercomDoor", "x": 350, "y": 120},
	"NW Reactor": {"pattern": "NorthwestReactorDoor", "x": 120, "y": 60},
	"NE Reactor": {"pattern": "NortheastReactorDoor", "x": 480, "y": 60},
	"Armory East": {"pattern": "EastDoor", "x": 480, "y": 260},
	"Shielding": {"pattern": "ShieldingDoor", "x": 520, "y": 100},
	"Supply Closet": {"pattern": "SupplyDoor", "x": 520, "y": 160},
	"Crew Quarters": {"pattern": "CrewDoor", "x": 520, "y": 260},
}

const LOWER_DOORS = {
	"NW Reactor": {"pattern": "NorthwestReactorDoor", "x": 120, "y": 60},
	"NE Reactor": {"pattern": "NortheastReactorDoor", "x": 480, "y": 60},
	"Electrical": {"pattern": "NorthwestElectricalDoor", "x": 300, "y": 60},
	"Trash": {"pattern": "SouthwestTrashDoor", "x": 300, "y": 180},
	"Colonial Supplies": {"pattern": "EastCSDoor", "x": 420, "y": 100},
	"Ship Supplies": {"pattern": "EastSSDoor", "x": 420, "y": 160},
	"Personal Items": {"pattern": "EastPIDoor", "x": 420, "y": 220},
	"Fab Lab": {"pattern": "SouthFabDoor", "x": 300, "y": 280},
	"Elevator Control": {"pattern": "ElevatorControlDoor", "x": 420, "y": 340},
}

func _on_lock_doors_selected() -> void:
	_close_sabotage_menu()
	_door_locks_used = 0
	_show_door_map()

func _show_door_map() -> void:
	_door_map_layer = CanvasLayer.new()
	_door_map_layer.layer = 91
	add_child(_door_map_layer)

	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_door_map_layer.add_child(root)

	# Dark backdrop
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.7)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Main container centered
	var container = Control.new()
	container.anchor_left = 0.5
	container.anchor_right = 0.5
	container.anchor_top = 0.5
	container.anchor_bottom = 0.5
	container.offset_left = -350
	container.offset_right = 350
	container.offset_top = -250
	container.offset_bottom = 250
	root.add_child(container)

	# Title
	var title = Label.new()
	title.text = "SHIP MAP - Lock up to %d doors (locks last %ds)" % [MAX_DOOR_LOCKS, int(DOOR_LOCK_DURATION)]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = -30
	title.offset_bottom = 0
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.RED)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(title)

	# Tab buttons for deck switching
	var tab_bar = HBoxContainer.new()
	tab_bar.anchor_left = 0.5
	tab_bar.anchor_right = 0.5
	tab_bar.offset_left = -100
	tab_bar.offset_right = 100
	tab_bar.offset_top = 0
	tab_bar.offset_bottom = 30
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 10)
	container.add_child(tab_bar)

	var upper_btn = Button.new()
	upper_btn.text = "Upper Deck"
	upper_btn.add_theme_font_size_override("font_size", 14)
	upper_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	tab_bar.add_child(upper_btn)

	var lower_btn = Button.new()
	lower_btn.text = "Lower Deck"
	lower_btn.add_theme_font_size_override("font_size", 14)
	lower_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	tab_bar.add_child(lower_btn)

	# Map panel background
	var map_panel = PanelContainer.new()
	map_panel.anchor_left = 0.0
	map_panel.anchor_right = 1.0
	map_panel.offset_top = 35
	map_panel.offset_bottom = 460
	var map_style = StyleBoxFlat.new()
	map_style.bg_color = Color(0.05, 0.05, 0.12, 0.95)
	map_style.border_color = Color(0.3, 0.3, 0.5, 1.0)
	map_style.border_width_left = 2
	map_style.border_width_right = 2
	map_style.border_width_top = 2
	map_style.border_width_bottom = 2
	map_style.corner_radius_top_left = 4
	map_style.corner_radius_top_right = 4
	map_style.corner_radius_bottom_left = 4
	map_style.corner_radius_bottom_right = 4
	map_panel.add_theme_stylebox_override("panel", map_style)
	container.add_child(map_panel)

	var map_content = Control.new()
	map_content.name = "MapContent"
	map_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_panel.add_child(map_content)

	# Populate upper deck by default
	_populate_door_map(map_content, UPPER_DOORS, "UpperDeck")

	# Tab switching
	upper_btn.pressed.connect(func():
		_clear_map_content(map_content)
		_populate_door_map(map_content, UPPER_DOORS, "UpperDeck")
	)
	lower_btn.pressed.connect(func():
		_clear_map_content(map_content)
		_populate_door_map(map_content, LOWER_DOORS, "LowerDeck")
	)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "Close (Q)"
	close_btn.anchor_left = 0.5
	close_btn.anchor_right = 0.5
	close_btn.offset_left = -50
	close_btn.offset_right = 50
	close_btn.offset_top = 465
	close_btn.offset_bottom = 490
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(_close_door_map)
	container.add_child(close_btn)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_is_mouse_captured = false

func _clear_map_content(map_content: Control) -> void:
	for child in map_content.get_children():
		child.queue_free()

func _populate_door_map(map_content: Control, doors: Dictionary, deck_prefix: String) -> void:
	# Find all door script nodes in the scene
	var all_doors: Array = []
	var scene = get_tree().current_scene
	if scene:
		_find_doors_recursive(scene, all_doors)

	for door_name in doors:
		var door_info = doors[door_name]
		var pattern = door_info["pattern"]

		# Find the matching door node path
		var matched_path = ""
		for door_node in all_doors:
			var path_str = str(door_node.get_path())
			if pattern in path_str and deck_prefix in path_str:
				matched_path = path_str
				break

		# If no deck-specific match, try without deck filter
		if matched_path == "":
			for door_node in all_doors:
				var path_str = str(door_node.get_path())
				if pattern in path_str:
					matched_path = path_str
					break

		var btn = Button.new()
		btn.text = door_name
		btn.position = Vector2(door_info["x"] - 55, door_info["y"])
		btn.custom_minimum_size = Vector2(110, 28)
		btn.add_theme_font_size_override("font_size", 12)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP

		# Color based on lock state
		var is_locked = _locked_doors.has(matched_path)
		if is_locked:
			var locked_style = StyleBoxFlat.new()
			locked_style.bg_color = Color(0.6, 0.1, 0.1, 1.0)
			locked_style.corner_radius_top_left = 3
			locked_style.corner_radius_top_right = 3
			locked_style.corner_radius_bottom_left = 3
			locked_style.corner_radius_bottom_right = 3
			btn.add_theme_stylebox_override("normal", locked_style)
			btn.text = door_name + " [LOCKED]"

		if matched_path != "":
			btn.pressed.connect(_on_door_map_toggle.bind(matched_path, btn, door_name))
		else:
			btn.disabled = true
			btn.tooltip_text = "Door not found"

		map_content.add_child(btn)

func _find_doors_recursive(node: Node, result: Array) -> void:
	if node.has_method("_open_door") and node.has_method("_close_door"):
		result.append(node)
	for child in node.get_children():
		_find_doors_recursive(child, result)

func _on_door_map_toggle(door_path: String, btn: Button, door_name: String) -> void:
	if _locked_doors.has(door_path):
		# Unlock (give the lock back)
		_locked_doors.erase(door_path)
		_door_locks_used -= 1
		NetworkManager.send_door_lock(door_path, false)
		btn.text = door_name
		btn.remove_theme_stylebox_override("normal")
	else:
		# Check limit
		if _door_locks_used >= MAX_DOOR_LOCKS:
			return
		# Lock
		_locked_doors[door_path] = true
		_door_locks_used += 1
		NetworkManager.send_door_lock(door_path, true)
		btn.text = door_name + " [LOCKED]"
		var locked_style = StyleBoxFlat.new()
		locked_style.bg_color = Color(0.6, 0.1, 0.1, 1.0)
		locked_style.corner_radius_top_left = 3
		locked_style.corner_radius_top_right = 3
		locked_style.corner_radius_bottom_left = 3
		locked_style.corner_radius_bottom_right = 3
		btn.add_theme_stylebox_override("normal", locked_style)

		# Auto-unlock after duration
		get_tree().create_timer(DOOR_LOCK_DURATION).timeout.connect(
			_auto_unlock_door.bind(door_path)
		)

		# If max locks reached, close map and start cooldown
		if _door_locks_used >= MAX_DOOR_LOCKS:
			_close_door_map()
			_sabotage_cooldown = SABOTAGE_COOLDOWN_TIME
			_last_sabotage = "lock_doors"

func _auto_unlock_door(door_path: String) -> void:
	if _locked_doors.has(door_path):
		_locked_doors.erase(door_path)
		NetworkManager.send_door_lock(door_path, false)

func _close_door_map() -> void:
	if _door_map_layer:
		_door_map_layer.queue_free()
		_door_map_layer = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_is_mouse_captured = true

# ============ CROUCH SYSTEM ============

const CROUCH_MODEL_OFFSET: float = -0.3

func _update_crouch_state() -> void:
	# Smoothly interpolate camera to target crouch height
	var target_y = _first_person_camera_pos.y + CROUCH_CAMERA_OFFSET if _is_crouching else _first_person_camera_pos.y
	if not _third_person:
		camera.position.y = lerp(camera.position.y, target_y, 0.15)
	# Lower the player model when crouching idle so it doesn't float
	var model_target_y = CROUCH_MODEL_OFFSET if (_is_crouching and _current_anim_state in ["crouch_idle", "crouch_taser_idle"]) else 0.0
	$PlayerModel.position.y = lerp($PlayerModel.position.y, model_target_y, 0.15)

# ============ EMOTE SYSTEM ============

func _toggle_emote_wheel() -> void:
	if _is_emoting:
		return
	if _emote_wheel_visible:
		_close_emote_wheel()
		return
	_emote_wheel_visible = true

	# Build the emote wheel UI
	var layer = CanvasLayer.new()
	layer.layer = 90
	layer.name = "EmoteLayer"
	add_child(layer)

	_emote_wheel = PanelContainer.new()
	_emote_wheel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_emote_wheel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_emote_wheel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_emote_wheel.offset_left = -20
	_emote_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	_emote_wheel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var title = Label.new()
	title.text = "Emotes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	for i in range(_emote_names.size()):
		var label = Label.new()
		label.text = "[%d]  %s" % [i + 1, _emote_names[i]]
		label.add_theme_font_size_override("font_size", 18)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(label)

	var dismiss = Label.new()
	dismiss.text = "[4]  Dismiss"
	dismiss.add_theme_font_size_override("font_size", 18)
	dismiss.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	dismiss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dismiss)

	_emote_wheel.add_child(vbox)
	layer.add_child(_emote_wheel)

func _close_emote_wheel() -> void:
	_emote_wheel_visible = false
	var layer = get_node_or_null("EmoteLayer")
	if layer:
		layer.queue_free()
	_emote_wheel = null

func _on_emote_selected(emote_name: String) -> void:
	_close_emote_wheel()
	_play_emote(emote_name)
	NetworkManager.send_emote(emote_name)

func _play_emote(emote_name: String) -> void:
	if not _anim_player or not _anim_player.has_animation(_anim(emote_name)):
		return
	_is_emoting = true
	_current_anim_state = "emote"
	_anim_player.play(_anim(emote_name), ANIM_BLEND)
	_anim_player.speed_scale = 1.0
	# Play dance music as 3D spatial audio so nearby players can hear it
	_start_emote_music()
	# Flair loops 10 times
	if emote_name == "flair":
		for i in range(10):
			await _anim_player.animation_finished
			if i < 9:
				_anim_player.play(_anim("flair"), 0.0)
	else:
		await _anim_player.animation_finished
	_stop_emote_music()
	_is_emoting = false
	_current_anim_state = ""

func _start_emote_music() -> void:
	if not _emote_music:
		_emote_music = AudioStreamPlayer3D.new()
		_emote_music.stream = _dance_song
		_emote_music.unit_size = 5.0
		_emote_music.max_distance = 20.0
		_emote_music.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(_emote_music)
	_emote_music.play()

func _stop_emote_music() -> void:
	if _emote_music and _emote_music.playing:
		_emote_music.stop()

func _on_emote_received(sender_steam_id: int, emote_name: String) -> void:
	if sender_steam_id == steam_id:
		return
	var player = NetworkManager.get_player(sender_steam_id)
	if player:
		player._play_emote(emote_name)
