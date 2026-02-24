extends Node

## Game Manager
##
## Handles game state transitions and player spawning.
## Add this as an autoload singleton.

const PlayerScene = preload("res://scenes/player/player.tscn")
const TaserPickupScene = preload("res://scenes/weapons/taser/taser_pickup.tscn")
const GAME_LEVEL = "res://scenes/levels/main.tscn"
const TASER_SPAWN_POS = Vector3(-19.66497, 0.45656508, 16.686378)

@export var spawn_points: Array[Vector3] = [
	Vector3(0, 1, 0),
	Vector3(3, 1, 0),
	Vector3(-3, 1, 0),
	Vector3(0, 1, 3),
]

const PLAYER_COLORS: Array[Color] = [
	Color.GREEN,
	Color.DODGER_BLUE,
	Color.ORANGE_RED,
	Color.GOLD,
]

var players_container: Node3D = null
var hud_instance: Control = null  # hold reference to local HUD
# Destination progress
var destination_progress: float = 0.0
var base_progress_speed: float = 1.0
var progress_speed_modifier: float = 1.0
const PROGRESS_SYNC_RATE: float = 1.0
var _progress_sync_timer: float = 0.0

# Arrival countdown
var arrival_time: float = 0.0  # absolute Unix timestamp
var timer_active: bool = false
var timer_phase_one: float = 30.0  # default 5-minute countdown
var timer_phase_two: float = 60.0
# Game State (0: Start, 1: Phase 1, 2: Phase 2, 3: GameOver)
var game_state: int = 1
const GAME_STATE_GAME_OVER: int = 3

# End screen
var _end_screen_layer: CanvasLayer = null
var _end_screen: Control = null
var _local_player_is_impostor: bool = false

func _ready():
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.game_over_received.connect(_on_game_over)
	NetworkManager.play_again_received.connect(_on_play_again)
	LobbyManager.player_left.connect(_on_player_left)

func _process(delta):
	if not LobbyManager.is_host():
		return
	if players_container == null:
		return
	if game_state == GAME_STATE_GAME_OVER:
		return

	# Check win conditions every frame (host only)
	_check_win_conditions()

	var now = Time.get_unix_time_from_system()
	if now > arrival_time and game_state == 1:
		game_state = 2
		arrival_time = now + timer_phase_two
		timer_active = true
		UIState.timer_synced.emit(arrival_time, progress_speed_modifier)
		UIState.system_alert.emit("Successful hyperjump achieved, all systems nominal. Avoid contact with the the warp. Risk of data corruption: Low")
	if game_state == 2:
		destination_progress += base_progress_speed * progress_speed_modifier * delta
		destination_progress = clampf(destination_progress, 0.0, 100.0)

		_progress_sync_timer += delta
		if _progress_sync_timer >= PROGRESS_SYNC_RATE:
			_progress_sync_timer = 0.0
			NetworkManager.send_progress_update(destination_progress, progress_speed_modifier)
			NetworkManager.progress_update_received.emit(destination_progress, progress_speed_modifier)

func adjust_progress_speed(amount: float):
	progress_speed_modifier += amount

# ============ WIN CONDITIONS (host only) ============

func _check_win_conditions():
	var all_crewmates_dead := true
	var impostor_dead := false
	var has_any_player := false
	var crewmate_count := 0

	for player in players_container.get_children():
		if not ("is_impostor" in player and "is_dead" in player):
			continue
		has_any_player = true
		if player.is_impostor:
			if player.is_dead:
				impostor_dead = true
		else:
			crewmate_count += 1
			if not player.is_dead:
				all_crewmates_dead = false

	if not has_any_player:
		return

	# Condition 1: All crewmates dead -> Impostor wins (skip in solo games with no crewmates)
	if crewmate_count > 0 and all_crewmates_dead:
		_trigger_game_over(true)
		return

	# Condition 2: Impostor dead -> Crewmates win
	if impostor_dead:
		_trigger_game_over(false)
		return

	# Condition 3: Destination progress reaches 100% -> Crewmates win
	if destination_progress >= 100.0:
		_trigger_game_over(false)
		return

	# Condition 4: Ship integrity hits 0 -> Impostor wins
	# TODO: Implement ship integrity system.
	# When ship_integrity variable is added, check:
	# if ship_integrity <= 0.0:
	#     _trigger_game_over(true)
	#     return

func _trigger_game_over(impostor_won: bool):
	game_state = GAME_STATE_GAME_OVER
	NetworkManager.send_game_over(impostor_won)

# ============ GAME OVER HANDLING ============

func _on_game_over(impostor_won: bool):
	game_state = GAME_STATE_GAME_OVER
	_local_player_is_impostor = NetworkManager.pending_role_impostor

	# Switch voice chat to non-proximity (everyone hears everyone)
	VoiceManager.disable_proximity()

	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_show_end_screen(impostor_won)

func _show_end_screen(impostor_won: bool):
	if _end_screen_layer != null:
		_end_screen_layer.queue_free()

	_end_screen_layer = CanvasLayer.new()
	_end_screen_layer.layer = 100  # Render above all other UI
	get_tree().current_scene.add_child(_end_screen_layer)

	_end_screen = Control.new()
	_end_screen.name = "EndScreen"
	_end_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.mouse_filter = Control.MOUSE_FILTER_PASS

	# Semi-transparent dark background
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_screen.add_child(bg)

	# Determine if local player's side won
	var local_side_won: bool
	if _local_player_is_impostor:
		local_side_won = impostor_won
	else:
		local_side_won = not impostor_won

	# Result title
	var title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.anchor_left = 0.5
	title_label.anchor_right = 0.5
	title_label.anchor_top = 0.0
	title_label.anchor_bottom = 0.0
	title_label.offset_left = -300
	title_label.offset_right = 300
	title_label.offset_top = 120
	title_label.offset_bottom = 200
	title_label.add_theme_font_size_override("font_size", 72)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if local_side_won:
		title_label.text = "VICTORY"
		title_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		title_label.text = "GAME OVER"
		title_label.add_theme_color_override("font_color", Color.RED)
	_end_screen.add_child(title_label)

	# Subtitle: which side won
	var subtitle = Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_left = 0.5
	subtitle.anchor_right = 0.5
	subtitle.anchor_top = 0.0
	subtitle.anchor_bottom = 0.0
	subtitle.offset_left = -300
	subtitle.offset_right = 300
	subtitle.offset_top = 200
	subtitle.offset_bottom = 250
	subtitle.add_theme_font_size_override("font_size", 28)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if impostor_won:
		subtitle.text = "The Impostor has won."
		subtitle.add_theme_color_override("font_color", Color.ORANGE_RED)
	else:
		subtitle.text = "The Crewmates have won."
		subtitle.add_theme_color_override("font_color", Color.CYAN)
	_end_screen.add_child(subtitle)

	# Host: Play Again button. Non-host: Waiting label.
	if LobbyManager.is_host():
		var play_again_btn = Button.new()
		play_again_btn.text = "Play Again"
		play_again_btn.anchor_left = 0.5
		play_again_btn.anchor_right = 0.5
		play_again_btn.anchor_top = 0.5
		play_again_btn.anchor_bottom = 0.5
		play_again_btn.offset_left = -100
		play_again_btn.offset_right = 100
		play_again_btn.offset_top = 20
		play_again_btn.offset_bottom = 60
		play_again_btn.add_theme_font_size_override("font_size", 24)
		play_again_btn.pressed.connect(_on_play_again_pressed)
		_end_screen.add_child(play_again_btn)
	else:
		var waiting_label = Label.new()
		waiting_label.text = "Waiting for Host..."
		waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		waiting_label.anchor_left = 0.5
		waiting_label.anchor_right = 0.5
		waiting_label.anchor_top = 0.5
		waiting_label.anchor_bottom = 0.5
		waiting_label.offset_left = -200
		waiting_label.offset_right = 200
		waiting_label.offset_top = 20
		waiting_label.offset_bottom = 60
		waiting_label.add_theme_font_size_override("font_size", 24)
		waiting_label.add_theme_color_override("font_color", Color.GRAY)
		_end_screen.add_child(waiting_label)

	_end_screen_layer.add_child(_end_screen)

# ============ PLAY AGAIN ============

func _on_play_again_pressed():
	NetworkManager.send_play_again()

func _on_play_again():
	# Remove end screen
	if _end_screen_layer != null:
		_end_screen_layer.queue_free()
		_end_screen_layer = null
		_end_screen = null

	# Remove existing HUD
	if hud_instance != null:
		hud_instance.queue_free()
		hud_instance = null

	# Despawn all players
	despawn_all_players()

	# Reset game state
	game_state = 1
	destination_progress = 0.0
	progress_speed_modifier = 1.0
	_progress_sync_timer = 0.0
	timer_active = false

	# Clear buffered role
	NetworkManager.pending_role_received = false
	NetworkManager.pending_role_impostor = false

	# Re-capture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Re-spawn players, HUD, and pickups in the same level
	await get_tree().process_frame
	_spawn_all_players()
	_spawn_local_hud()
	_respawn_taser_pickup()

	# Host starts the timer
	if LobbyManager.is_host():
		var now = Time.get_unix_time_from_system()
		arrival_time = now + timer_phase_one
		timer_active = true
		UIState.timer_synced.emit(arrival_time, progress_speed_modifier)

func _respawn_taser_pickup():
	# The taser pickup calls queue_free() when picked up, so re-instantiate it on play again
	var parent = get_tree().current_scene.get_node_or_null("UpperDeck")
	if parent == null:
		parent = get_tree().current_scene
	var taser = TaserPickupScene.instantiate()
	taser.position = TASER_SPAWN_POS
	parent.add_child(taser)

# ============ GAME START ============

# Call this when ready to start the game (e.g., from a "Start Game" button)
func start_game():
	if LobbyManager.is_host():
		# Send start to other players, then load level
		# Don't call _load_game_level here - the signal handler will do it
		NetworkManager.send_game_start()
	else:
		print("Only the host can start the game")

func _on_game_started():
	destination_progress = 0.0
	progress_speed_modifier = 1.0
	_progress_sync_timer = 0.0
	_load_game_level()


func _load_game_level():
	# Change to the game level scene
	get_tree().change_scene_to_file(GAME_LEVEL)
	# Wait for scene to load, then spawn players
	await get_tree().process_frame
	await get_tree().process_frame
	_spawn_all_players()
	_spawn_local_hud()
	if LobbyManager.is_host():
		# emit initial timer now that HUD exists
		var now = Time.get_unix_time_from_system()
		arrival_time = now + timer_phase_one
		timer_active = true
		UIState.timer_synced.emit(arrival_time, progress_speed_modifier)

func _spawn_all_players():
	var current_scene = get_tree().current_scene

	# Remove any existing Player nodes from the scene
	var existing_player = current_scene.get_node_or_null("Player")
	if existing_player:
		existing_player.queue_free()

	# Create a container for players if it doesn't exist
	if players_container == null:
		players_container = Node3D.new()
		players_container.name = "Players"
		current_scene.add_child(players_container)

	var my_steam_id = Steam.getSteamID()
	var spawn_index = 0

	for member in LobbyManager.lobby_members:
		var player_steam_id = member.steam_id
		var is_local = (player_steam_id == my_steam_id)

		# Spawn the player
		var player = PlayerScene.instantiate()

		# Setup BEFORE adding to tree so _ready() has correct values
		player.steam_id = player_steam_id
		player.is_local_player = is_local
		player.name = "Player_" + str(player_steam_id)

		# Set position BEFORE adding to tree to avoid physics glitch
		var spawn_pos = spawn_points[spawn_index % spawn_points.size()]
		player.position = spawn_pos
		spawn_index += 1

		players_container.add_child(player)

		# Assign a unique color to each player
		var color = PLAYER_COLORS[(spawn_index - 1) % PLAYER_COLORS.size()]
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		player.get_node("CapsuleMesh").material_override = mat

		# Register with NetworkManager
		NetworkManager.register_player(player_steam_id, player)

		# Set up voice playback for remote players (proximity audio)
		if not is_local:
			VoiceManager.setup_player_voice(player_steam_id, player)

		print("Spawned player: ", member.name, " (local: ", is_local, ")")

	# Start always-on voice recording after all players are spawned
	VoiceManager.start()

	# Host assigns roles — one random impostor
	if LobbyManager.is_host():
		_assign_roles()

func _spawn_local_hud():
	if hud_instance != null:
		hud_instance.queue_free()  # remove old HUD if it exists

	# Load HUD scene
	var hud_scene = preload("res://scenes/HUD/HUD.tscn")
	hud_instance = hud_scene.instantiate()

	# Add it to the root of the scene tree
	get_tree().current_scene.add_child(hud_instance)

	# Make sure it's visible and top-level
	hud_instance.owner = get_tree().current_scene


func _assign_roles():
	# Pick one random player as the impostor
	var impostor_index = randi() % LobbyManager.lobby_members.size()
	var my_steam_id = Steam.getSteamID()

	for i in range(LobbyManager.lobby_members.size()):
		var member_steam_id = LobbyManager.lobby_members[i].steam_id
		var is_impostor = (i == impostor_index)

		# Set is_impostor on the player node so the host can check win conditions
		var player_node = NetworkManager.get_player(member_steam_id)
		if player_node:
			player_node.is_impostor = is_impostor

		if member_steam_id == my_steam_id:
			# Host assigns own role directly (also buffer it)
			NetworkManager.pending_role_received = true
			NetworkManager.pending_role_impostor = is_impostor
			NetworkManager.role_assigned.emit(is_impostor)
		else:
			# Send role to remote player privately
			NetworkManager.send_role_assignment(member_steam_id, is_impostor)

	var impostor_name = LobbyManager.lobby_members[impostor_index].name
	print("Impostor assigned: ", impostor_name)

func _on_player_left(steam_id: int):
	VoiceManager.remove_player_voice(steam_id)
	var player = NetworkManager.get_player(steam_id)
	if player:
		NetworkManager.unregister_player(steam_id)
		player.queue_free()
		print("Removed player: ", steam_id)

func despawn_all_players():
	VoiceManager.stop()
	if players_container:
		for player in players_container.get_children():
			player.queue_free()
		players_container.queue_free()
		players_container = null
		NetworkManager.players_in_game.clear()
