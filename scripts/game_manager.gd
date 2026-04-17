extends Node

## Game Manager
##
## Handles game state transitions and player spawning.
## Add this as an autoload singleton.

const PlayerScene = preload("res://scenes/player/player.tscn")
const TaserPickupScene = preload("res://scenes/weapons/taser/taser_pickup.tscn")
const BatonPickupScene = preload("res://scenes/weapons/baton/baton.tscn")
const GAME_LEVEL = "res://scenes/levels/main.tscn"
const LOBBY_SCENE_PATH = "res://scenes/lobby/lobby_room.tscn"
const SecurityCamerasScene = preload("res://scenes/levels/cams/security_cameras.tscn")
const TASER_SPAWN_POS = Vector3(-19.66497, 0.45656508, 16.686378)
const BATON01_SPAWN_POS = Vector3(-19.932, 0.0, 21.235)
const BATON02_SPAWN_POS = Vector3(-19.932, 0.0, 23.177)

const BATON_SPAWN_CHANCE = 0.75

var _initial_weapon_data: Array = []	# Stores lists of [item_id, global_position] for each weapon spawn

@export var spawn_points: Array[Vector3] = [
	Vector3(0, 1, 0),
	Vector3(3, 1, 0),
	Vector3(-3, 1, 0),
	Vector3(0, 1, 3),
]

var imposter_count: int = 1

const PLAYER_COLORS: Array[Color] = [
	Color.GREEN,
	Color.DODGER_BLUE,
	Color.ORANGE_RED,
	Color.GOLD,
]

var players_container: Node3D = null
var hud_instance: Control = null  # hold reference to local HUD
var world_env: WorldEnvironment = null # For changing the environment lighting
# Destination progress
const time_to_dest: float = 600

var destination_progress: float = 0.0
var destination_distance: float = time_to_dest
var base_progress_speed: float = 1.0
var progress_speed_modifier: float = 1.0
const PROGRESS_SYNC_RATE: float = 1.0
var _progress_sync_timer: float = 0.0
var true_destination_progress: float = 0

# Arrival countdown
var arrival_time: float = 0.0  # absolute Unix timestamp
var timer_active: bool = false
var timer_phase_one: float = 30.0  # default 5-minute countdown
var timer_phase_two: float = time_to_dest

# Ship integrity
var max_ship_integrity: float = 100.0
var ship_integrity: float = 50.0

# Game State (0: Start, 1: Phase 1, 2: Phase 2, 3: GameOver)
var game_state: int = 1
const GAME_STATE_GAME_OVER: int = 3

# Sabotage state
var active_sabotages: Dictionary = {}  # sabotage_type -> remaining duration
const SABOTAGE_DURATION: float = 20.0
const SABOTAGE_COOLDOWN: float = 30.0
const SABOTAGE_INTEGRITY_DRAIN: float = 15.0

# Lights out effect
var _original_ambient_light_energy: float = 1.0
var _lights_out_flicker_tween: Tween = null
var _lights_out_dim_tween: Tween = null
const LIGHTS_OUT_FLICKER_DURATION: float = 2.0
const LIGHTS_OUT_DIM_DURATION: float = 3.0

# End screen
var _end_screen_layer: CanvasLayer = null
var _end_screen: Control = null
var _local_player_is_impostor: bool = false

func _ready():
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.game_over_received.connect(_on_game_over)
	NetworkManager.play_again_received.connect(_on_play_again)
	NetworkManager.timer_sync_received.connect(_on_timer_sync_received)
	LobbyManager.player_left.connect(_on_player_left)
	NetworkManager.ship_integrity_update_received.connect(_on_ship_integrity_update_received)
	NetworkManager.sabotage_received.connect(_on_sabotage_received)
	UIState.ship_durability_changed.emit(ship_integrity)


func _process(delta):
	# Sabotage timers run on all clients
	_update_sabotages(delta)

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
		_broadcast_timer_sync()
		UIState.system_alert.emit("Successful hyperjump achieved, all systems nominal. Avoid contact with the the warp. Risk of data corruption: Low")
	if game_state == 2:
		destination_progress += base_progress_speed * progress_speed_modifier * delta
		true_destination_progress = destination_progress / destination_distance 
		true_destination_progress = clampf(true_destination_progress * 100, 0.0, 100.0)

		_progress_sync_timer += delta
		if _progress_sync_timer >= PROGRESS_SYNC_RATE:
			_progress_sync_timer = 0.0
			NetworkManager.send_progress_update(true_destination_progress, progress_speed_modifier)
			NetworkManager.progress_update_received.emit(true_destination_progress, progress_speed_modifier)

# ============ SABOTAGE ============

func _on_sabotage_received(sabotage_type: String) -> void:
	if sabotage_type == "drain_integrity":
		# Instant effect: drop ship integrity
		adjust_ship_integrity(-SABOTAGE_INTEGRITY_DRAIN)
		UIState.sabotage_triggered.emit(sabotage_type)
		UIState.system_alert.emit("WARNING: Ship integrity compromised! Hull breach detected!")
	elif sabotage_type in ["lights_out", "disable_comms", "anonymous"]:
		# Timed effect
		active_sabotages[sabotage_type] = SABOTAGE_DURATION
		UIState.sabotage_triggered.emit(sabotage_type)
		if sabotage_type == "lights_out":
			_start_lights_out_effect()
			UIState.system_alert.emit("WARNING: Electrical failure! Emergency lighting only!")
		elif sabotage_type == "disable_comms":
			UIState.system_alert.emit("WARNING: Communications array offline! Directives unavailable!")
		elif sabotage_type == "anonymous":
			UIState.system_alert.emit("WARNING: IFF and audio systems compromised! Crew identity unknown!")

func _update_sabotages(delta: float) -> void:
	var to_remove: Array[String] = []
	for sabotage_type in active_sabotages:
		active_sabotages[sabotage_type] -= delta
		if active_sabotages[sabotage_type] <= 0.0:
			to_remove.append(sabotage_type)
	for sabotage_type in to_remove:
		active_sabotages.erase(sabotage_type)
		if sabotage_type == "lights_out":
			_restore_lights()
		UIState.sabotage_ended.emit(sabotage_type)

func is_sabotage_active(sabotage_type: String) -> bool:
	return active_sabotages.has(sabotage_type)

func _start_lights_out_effect() -> void:
	if not world_env or not world_env.environment:
		return
	
	# Kill any existing tweens
	if _lights_out_dim_tween:
		_lights_out_dim_tween.kill()
	
	var env = world_env.environment
	
	# Dim the lights
	_lights_out_dim_tween = create_tween()
	_lights_out_dim_tween.set_trans(Tween.TRANS_CUBIC)
	_lights_out_dim_tween.tween_property(env, "ambient_light_energy", 0.0, LIGHTS_OUT_DIM_DURATION)

func _restore_lights() -> void:
	if not world_env or not world_env.environment:
		return
	
	# Kill any existing tweens
	if _lights_out_dim_tween:
		_lights_out_dim_tween.kill()
	
	var env = world_env.environment
	
	# Smoothly restore to original energy
	var restore_tween = create_tween()
	restore_tween.set_trans(Tween.TRANS_CUBIC)
	restore_tween.tween_property(env, "ambient_light_energy", _original_ambient_light_energy, 1.0)

func adjust_progress_speed(amount: float):
	progress_speed_modifier += amount

func _broadcast_timer_sync():
	NetworkManager.send_timer_sync(arrival_time, progress_speed_modifier)
	UIState.timer_synced.emit(arrival_time, progress_speed_modifier)

func _on_timer_sync_received(server_arrival_time: float, speed: float):
	arrival_time = server_arrival_time
	progress_speed_modifier = speed
	UIState.timer_synced.emit(server_arrival_time, speed)
	
func adjust_ship_integrity(amount: float) -> void:
	ship_integrity = clampf(ship_integrity + amount, 0.0, max_ship_integrity)
	UIState.ship_durability_changed.emit(ship_integrity)
	if LobbyManager.is_host():
		NetworkManager.send_ship_integrity_update(ship_integrity)
		
func _on_ship_integrity_update_received(sender_steam_id: int, integrity: float) -> void:
	ship_integrity = clampf(integrity, 0.0, max_ship_integrity)
	UIState.ship_durability_changed.emit(ship_integrity)
	
func _reset_ship_integrity() -> void:
	ship_integrity = 50
	max_ship_integrity = 100
	UIState.ship_durability_changed.emit(ship_integrity)
	if LobbyManager.is_host():
		NetworkManager.send_ship_integrity_update(ship_integrity)

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
	if destination_progress >= destination_distance:
		_trigger_game_over(false)
		return

	# Condition 4: Ship integrity hits 0 -> Impostor wins
	if ship_integrity <= 0.0:
		_trigger_game_over(true)
		return

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
		play_again_btn.text = "Back To Lobby"
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
	_on_play_again()
	
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

	# Reset ALL game state
	game_state = 1
	destination_progress = 0.0
	progress_speed_modifier = 1.0
	_progress_sync_timer = 0.0
	timer_active = false
	active_sabotages.clear()
	ship_integrity = 50.0
	_local_player_is_impostor = false

	# Clear buffered role so stale impostor status doesn't carry over
	NetworkManager.pending_role_received = false
	NetworkManager.pending_role_impostor = false

	# Reset imposter count to default
	imposter_count = 1

	# Stop voice recording
	VoiceManager.stop()

	# Re-capture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Re-open the lobby so new players can join again
	if LobbyManager.lobby_id != 0:
		Steam.setLobbyJoinable(LobbyManager.lobby_id, true)

	# Go back to lobby room
	get_tree().call_deferred("change_scene_to_file", LOBBY_SCENE_PATH)

func _respawn_taser_pickup():
	# The taser pickup calls queue_free() when picked up, so re-instantiate it on play again
	var parent = get_tree().current_scene.get_node_or_null("UpperDeck")
	if parent == null:
		parent = get_tree().current_scene
	var taser = TaserPickupScene.instantiate()
	taser.position = TASER_SPAWN_POS
	parent.add_child(taser)

func _reset_weapon_pickups():
	var parent = get_tree().current_scene.get_node_or_null("MainTestScene")
	if parent == null:
		parent = get_tree().current_scene
	
	var existing_pickups = get_tree().get_nodes_in_group("pickup")
	for pickup in existing_pickups:
		if pickup.item_id.begins_with("baton") or pickup.item_id.begins_with("taser"):
			pickup.queue_free()
	
	for weapon in _initial_weapon_data:
		var should_spawn = true
		
		if weapon.id.begins_with("baton"):
			if randf() > BATON_SPAWN_CHANCE:
				should_spawn = false
				
		if should_spawn:
			var new_weapon = null
			if weapon.id.begins_with("taser"):
				new_weapon = TaserPickupScene.instantiate()
			elif weapon.id.begins_with("baton"):
				new_weapon = BatonPickupScene.instantiate()
			
			if new_weapon:
				new_weapon.item_id = weapon.id
				new_weapon.transform = weapon.transform
				parent.add_child(new_weapon)
				NetworkManager.send_item_dropped(weapon.id, weapon.transform)
	

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
	# Prevent new players from joining while the game is in progress
	if LobbyManager.lobby_id != 0:
		Steam.setLobbyJoinable(LobbyManager.lobby_id, false)
	destination_progress = 0.0
	progress_speed_modifier = 1.0
	_progress_sync_timer = 0.0
	_reset_ship_integrity()
	_load_game_level()


func _load_game_level():
	# Change to the game level scene
	get_tree().change_scene_to_file(GAME_LEVEL)
	# Wait for scene to load, then spawn players
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Get reference to WorldEnvironment
	world_env = get_tree().current_scene.find_child("WorldEnvironment", true, false)
	if world_env and world_env.environment:
		_original_ambient_light_energy = world_env.environment.ambient_light_energy
	
	if LobbyManager.is_host():
		_capture_initial_weapon_states()
		_reset_weapon_pickups()
	
	_spawn_all_players()
	_spawn_local_hud()
	_spawn_security_cameras()
	if LobbyManager.is_host():
		# emit initial timer now that HUD exists
		var now = Time.get_unix_time_from_system()
		arrival_time = now + timer_phase_one
		timer_active = true
		_broadcast_timer_sync()

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
		#player.reset_inventory()
		players_container.add_child(player)

		# Assign a unique color to each player
		var color = PLAYER_COLORS[(spawn_index - 1) % PLAYER_COLORS.size()]
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		var model = player.get_node("PlayerModel")
		for child in model.get_children():
			if child is MeshInstance3D:
				child.material_override = mat
				break

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

func _spawn_security_cameras():
	var cams = SecurityCamerasScene.instantiate()
	get_tree().current_scene.add_child(cams)

func _capture_initial_weapon_states():
	_initial_weapon_data.clear()
	var starting_pickups = get_tree().get_nodes_in_group("pickup")
	
	for p in starting_pickups:
		if not p.item_id.contains("Healthpack") and p.item_id != "":
			_initial_weapon_data.append({
				"id": p.item_id,
				"transform" : p.global_transform
			})
	print("Weapon state captured: ", _initial_weapon_data.size(), " weapons found")

func _assign_roles():
	# Shuffle members and pick impostor(s) based on imposter_count setting
	var members = LobbyManager.lobby_members.duplicate()
	members.shuffle()
	var actual_count = mini(imposter_count, members.size() - 1)
	actual_count = maxi(actual_count, 1)

	# Collect impostor steam IDs first
	var impostor_ids: Array = []
	for i in range(actual_count):
		impostor_ids.append(members[i].steam_id)

	var my_steam_id = Steam.getSteamID()

	for i in range(members.size()):
		var member_steam_id = members[i].steam_id
		var is_impostor = (i < actual_count)

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
			# Send role to remote player privately, include impostor list
			NetworkManager.send_role_assignment(member_steam_id, is_impostor, impostor_ids)

	print("Impostors assigned: ", actual_count)

func _give_impostor_taser_after_reveal(impostor_steam_id: int):
	await get_tree().create_timer(30.0).timeout
	var impostor_player = NetworkManager.get_player(impostor_steam_id)
	if impostor_player:
		impostor_player.give_taser()
	# Broadcast to all clients so they show the taser on the impostor
	NetworkManager.send_p2p_packet(0, {"type": NetworkManager.PacketType.ITEM_PICKUP, "item_id": "taser_impostor", "picker": impostor_steam_id}, Steam.P2P_SEND_RELIABLE, 0)

func _on_player_left(steam_id: int):
	VoiceManager.remove_player_voice(steam_id)
	var player = NetworkManager.get_player(steam_id)
	if player:
		NetworkManager.unregister_player(steam_id)
		player.queue_free()
		print("Removed player: ", steam_id)

func despawn_all_players():
	if players_container:
		for player in players_container.get_children():
			player.queue_free()
		players_container.queue_free()
		players_container = null
		NetworkManager.players_in_game.clear()
