extends Node

## Game Manager
##
## Handles game state transitions and player spawning.
## Add this as an autoload singleton.

const PlayerScene = preload("res://scenes/player/player.tscn")
const AIBotScene = preload("res://scenes/player/ai_bot.tscn")
# Sentinel IDs reserved for AI bots. Real Steam IDs are 64-bit numbers in the
# 76561198xxxxxxxxx range, so small ints can't collide.
const AI_BOT_ID_BASE: int = 1
const AI_BOT_MAX_COUNT: int = 4
const TaserPickupScene = preload("res://scenes/weapons/taser/taser_pickup.tscn")
const BatonPickupScene = preload("res://scenes/weapons/baton/baton.tscn")
const GAME_LEVEL = "res://scenes/levels/main.tscn"
const LOBBY_SCENE_PATH = "res://scenes/lobby/lobby_room.tscn"
const SecurityCamerasScene = preload("res://scenes/levels/cams/security_cameras.tscn")
const TASER_SPAWN_POS = Vector3(-19.66497, 0.45656508, 16.686378)
const BATON01_SPAWN_POS = Vector3(-19.932, 0.0, 21.235)
const BATON02_SPAWN_POS = Vector3(-19.932, 0.0, 23.177)

var baton_spawn_chance: float = 0.75

var _initial_weapon_data: Array = []	# Stores lists of [item_id, global_position] for each weapon spawn

@export var spawn_points: Array[Vector3] = [
	Vector3(0, 1, 0),
	Vector3(3, 1, 0),
	Vector3(-3, 1, 0),
	Vector3(0, 1, 3),
]

var imposter_count: int = 1
var anonymous_impostors: bool = false
# AI mode: toggleable via the host's lobby settings. When on, the normal random
# impostor selection is skipped and `ai_bot_count` AI impostors are spawned.
var ai_mode_enabled: bool = false
var ai_bot_count: int = 1

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

# Win conditions only change on death/integrity events, so the per-frame loop
# was wasteful. 2 Hz is plenty responsive for end-of-game detection.
const WIN_CHECK_RATE: float = 0.5
var _win_check_timer: float = 0.0

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
const SURGE_OF_STRENGTH_DURATION: float = 4.0

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

# Loading screen (lives under SceneTree.root so it survives scene changes)
var _loading_screen: CanvasLayer = null
var _loading_progress_bar: ProgressBar = null
var _loading_status_label: Label = null

# Re-entry guard for _on_game_started. The signal can fire from multiple
# sources now: the original P2P GAME_START packet, the host's local emit,
# and the lobby-data fallback poll for clients that missed the packet.
var _game_start_in_progress: bool = false

# F3 perf overlay state
var _perf_overlay_layer: CanvasLayer = null
var _perf_overlay_label: Label = null
var _perf_overlay_visible: bool = false
var _perf_sample_timer: float = 0.0
const _PERF_SAMPLE_INTERVAL: float = 0.25

func _ready():
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.game_over_received.connect(_on_game_over)
	NetworkManager.play_again_received.connect(_on_play_again)
	NetworkManager.timer_sync_received.connect(_on_timer_sync_received)
	LobbyManager.player_left.connect(_on_player_left)
	NetworkManager.ship_integrity_update_received.connect(_on_ship_integrity_update_received)
	NetworkManager.sabotage_received.connect(_on_sabotage_received)
	NetworkManager.bot_spawn_received.connect(_on_bot_spawn_received)
	UIState.ship_durability_changed.emit(ship_integrity)


func _process(delta):
	# Sabotage timers run on all clients
	_update_sabotages(delta)

	# Perf overlay sample (cheap unless visible)
	if _perf_overlay_visible:
		_perf_sample_timer += delta
		if _perf_sample_timer >= _PERF_SAMPLE_INTERVAL:
			_perf_sample_timer = 0.0
			_update_perf_overlay()

	if not LobbyManager.is_host():
		return
	if players_container == null:
		return
	if game_state == GAME_STATE_GAME_OVER:
		return

	# Check win conditions on a timer (host only) — was every frame, now 2 Hz.
	_win_check_timer += delta
	if _win_check_timer >= WIN_CHECK_RATE:
		_win_check_timer = 0.0
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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_toggle_perf_overlay()

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
	elif sabotage_type == "surge_of_strength":
		active_sabotages[sabotage_type] = SURGE_OF_STRENGTH_DURATION
		UIState.sabotage_triggered.emit(sabotage_type)
		UIState.system_alert.emit("WARNING: Anomalous energy surge detected!")

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
	var all_impostors_dead := true
	var has_any_player := false
	var crewmate_count := 0
	var impostor_count := 0

	for player in players_container.get_children():
		if not ("is_impostor" in player and "is_dead" in player):
			continue
		has_any_player = true
		if player.is_impostor:
			impostor_count += 1
			if not player.is_dead:
				all_impostors_dead = false
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

	# Condition 2: All impostors dead -> Crewmates win
	if impostor_count > 0 and all_impostors_dead:
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
	print("_trigger_game_over: impostor_won=%s — broadcasting" % str(impostor_won))
	NetworkManager.send_game_over(impostor_won)
	# Resend twice more on a short delay. send_game_over is RELIABLE so this
	# should normally be redundant, but field reports show the packet
	# occasionally not landing on a client — repeat broadcasts get it through
	# without harm because _on_game_over is idempotent on game_state.
	_resend_game_over(impostor_won)

func _resend_game_over(impostor_won: bool) -> void:
	await get_tree().create_timer(0.5).timeout
	if game_state != GAME_STATE_GAME_OVER:
		return
	NetworkManager.resend_game_over(impostor_won)
	await get_tree().create_timer(1.5).timeout
	if game_state != GAME_STATE_GAME_OVER:
		return
	NetworkManager.resend_game_over(impostor_won)

# ============ GAME OVER HANDLING ============

func _on_game_over(impostor_won: bool):
	# Idempotent — handler may be invoked multiple times if the host
	# retransmits GAME_OVER. Skip the side effects (voice swap, end-screen
	# rebuild) on duplicate calls.
	if game_state == GAME_STATE_GAME_OVER and _end_screen_layer != null:
		print("_on_game_over: already handled, ignoring duplicate")
		return
	print("_on_game_over: impostor_won=%s" % str(impostor_won))
	game_state = GAME_STATE_GAME_OVER
	_local_player_is_impostor = NetworkManager.pending_role_impostor

	# Switch voice chat to non-proximity (everyone hears everyone)
	VoiceManager.disable_proximity()
	VoiceManager.disable_dead_chat()

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
	anonymous_impostors = false
	baton_spawn_chance = 0.75
	# Note: do NOT reset ai_mode_enabled / ai_bot_count — the host chose those
	# in the lobby settings and they should persist across rounds until the
	# host changes them.

	# Stop voice recording
	VoiceManager.stop()

	# Re-capture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Re-open the lobby so new players can join again, and clear the
	# in-progress lobby-data flag so the recovery poll doesn't immediately
	# pull everyone back into another game.
	if LobbyManager.lobby_id != 0:
		Steam.setLobbyJoinable(LobbyManager.lobby_id, true)
		if LobbyManager.is_host():
			Steam.setLobbyData(LobbyManager.lobby_id, "game_state", "lobby")

	# Allow the next round's game-started flow to fire again.
	_game_start_in_progress = false

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
			if randf() > baton_spawn_chance:
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
	# Re-entry guard — multiple sources can fire game_started for the same
	# round (P2P packet, host self-emit, lobby-data fallback). Without this
	# we'd queue multiple _load_game_level coroutines, which is a recipe for
	# scene-change races.
	if _game_start_in_progress:
		print("_on_game_started: already loading, ignoring duplicate")
		return
	_game_start_in_progress = true
	print("_on_game_started: triggering load")

	# Prevent new players from joining while the game is in progress.
	# Also write "in_progress" to lobby data so any client that missed the
	# P2P GAME_START packet can recover by polling lobby state. Lobby data
	# rides on Steam's lobby system, not P2P, so it's far more reliable.
	if LobbyManager.lobby_id != 0:
		Steam.setLobbyJoinable(LobbyManager.lobby_id, false)
		if LobbyManager.is_host():
			Steam.setLobbyData(LobbyManager.lobby_id, "game_state", "in_progress")
	destination_progress = 0.0
	progress_speed_modifier = 1.0
	_progress_sync_timer = 0.0
	_reset_ship_integrity()
	_load_game_level()


func _load_game_level():
	_show_loading_screen("Loading level...")
	# Let the loading screen actually paint before any heavy work hits the main thread.
	await get_tree().process_frame
	await get_tree().process_frame

	# (Removed flush_packet_queue call — was suspected of contributing to a
	# host->client P2P delivery regression. The reset_round_state on each
	# spawned player still defends against stale damage packets.)

	# Synchronous scene change — the threaded variant could silently fail and
	# leave a player stuck on the previous scene while we kept spawning into
	# their old current_scene. Sync is reliable; the per-frame win comes from
	# the progressive player spawn below, not the level load.
	_set_loading_status("Loading level...", 30)
	var change_err: int = get_tree().change_scene_to_file(GAME_LEVEL)
	if change_err != OK:
		push_error("Failed to change scene to game level (err=%d) — aborting game start" % change_err)
		_hide_loading_screen()
		_game_start_in_progress = false
		return

	# Wait for the new scene to be ready before touching it.
	await get_tree().process_frame
	await get_tree().process_frame

	# Sanity check: if we somehow didn't end up on the game level, bail rather
	# than spawning players into the wrong scene (which produced the
	# "third-player stuck in lobby" desync bug).
	var current = get_tree().current_scene
	if current == null or current.scene_file_path != GAME_LEVEL:
		push_error("After change_scene_to_file, current_scene is %s (expected %s)" % [current.scene_file_path if current else "null", GAME_LEVEL])
		_hide_loading_screen()
		_game_start_in_progress = false
		return

	# Get reference to WorldEnvironment
	world_env = current.find_child("WorldEnvironment", true, false)
	if world_env and world_env.environment:
		_original_ambient_light_energy = world_env.environment.ambient_light_energy

	if LobbyManager.is_host():
		_capture_initial_weapon_states()
		_reset_weapon_pickups()

	# Spawn players one at a time with a frame in between, so the (heavy)
	# per-player animation imports don't all stack into one mega-hitch.
	_set_loading_status("Spawning players...", 60)
	await get_tree().process_frame
	await _spawn_all_players_progressively()

	_set_loading_status("Loading HUD...", 90)
	await get_tree().process_frame
	_spawn_local_hud()

	_set_loading_status("Initializing security cameras...", 95)
	await get_tree().process_frame
	_spawn_security_cameras()
	if LobbyManager.is_host():
		# emit initial timer now that HUD exists
		var now = Time.get_unix_time_from_system()
		arrival_time = now + timer_phase_one
		timer_active = true
		_broadcast_timer_sync()

	# Walk the level tree once and disable per-frame processing notifications
	# on every static, scriptless node. With ~16k nodes in the level (mostly
	# walls/floors/decoration), this saves a meaningful chunk of CPU process
	# time per frame. Doesn't affect rendering, physics, or signal handlers —
	# only suppresses _process / _physics_process / _input callbacks (which
	# pure geometry doesn't have anyway).
	_set_loading_status("Optimizing level...", 98)
	await get_tree().process_frame
	_optimize_level_processing(get_tree().current_scene)

	_set_loading_status("Ready!", 100)
	# Hold one extra frame so the first post-load render doesn't show through.
	await get_tree().process_frame
	await get_tree().process_frame
	_hide_loading_screen()

# ============ LOADING SCREEN ============

func _show_loading_screen(initial_text: String = "Loading...") -> void:
	if _loading_screen != null:
		_set_loading_status(initial_text, 0.0)
		return

	_loading_screen = CanvasLayer.new()
	_loading_screen.name = "LoadingScreen"
	_loading_screen.layer = 200  # render above everything

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks while loading
	_loading_screen.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	center.add_child(vbox)

	var title = Label.new()
	title.text = initial_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	vbox.add_child(title)
	_loading_status_label = title

	var bar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(420, 18)
	vbox.add_child(bar)
	_loading_progress_bar = bar

	# Attach to root, NOT current_scene, so the screen survives change_scene_to_*.
	get_tree().root.add_child(_loading_screen)

func _set_loading_status(text: String, progress: float = -1.0) -> void:
	if _loading_status_label and is_instance_valid(_loading_status_label):
		_loading_status_label.text = text
	if _loading_progress_bar and is_instance_valid(_loading_progress_bar) and progress >= 0.0:
		_loading_progress_bar.value = progress

func _hide_loading_screen() -> void:
	if _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
	_loading_screen = null
	_loading_progress_bar = null
	_loading_status_label = null

# ============ LEVEL PROCESSING OPTIMIZER ============

# Names of subtrees we must NEVER touch — they need normal processing.
const _DYNAMIC_SUBTREE_NAMES: Array[String] = [
	"Players",         # player nodes need _physics_process + animations
	"PerfOverlay",     # F3 overlay needs to update
	"LoadingScreen",   # loading screen UI
]

# Walk the scene tree and set process_mode = DISABLED on every node that
# (a) has no script, AND (b) belongs to a static-geometry node class.
# Disabling process_mode skips _process/_physics_process/_input callbacks
# but does NOT affect rendering, collision detection, signals, or AnimationPlayer
# tracks — those are driven by other subsystems.
func _optimize_level_processing(root: Node) -> void:
	if root == null:
		return
	var stats := {"disabled": 0, "kept_script": 0, "kept_dynamic": 0, "visited": 0}
	_optimize_walk(root, stats)
	print("Level optimizer: disabled=%d  kept(script)=%d  kept(dynamic)=%d  visited=%d" % [
		stats.disabled, stats.kept_script, stats.kept_dynamic, stats.visited
	])

func _optimize_walk(node: Node, stats: Dictionary) -> void:
	stats.visited += 1
	# Never recurse into dynamic subtrees — they need processing.
	if node.name in _DYNAMIC_SUBTREE_NAMES:
		return
	# Recurse into children FIRST so we can decide for parent based on what
	# its descendants look like.
	for child in node.get_children():
		_optimize_walk(child, stats)
	# Skip nodes with scripts — they may have logic in _process etc.
	if node.get_script() != null:
		stats.kept_script += 1
		return
	# CRITICAL: do NOT disable any physics-related node. PROCESS_MODE_DISABLED
	# on a CollisionObject3D / CollisionShape3D removes it from the physics
	# simulation, which makes the player fall through floors and walk through
	# walls. Same applies to Area3D, RigidBody3D, etc.
	# Only safe to disable: pure visual nodes (mesh + light) with no children
	# that need processing.
	if node is CollisionObject3D or node is CollisionShape3D or node is Area3D:
		stats.kept_dynamic += 1
		return
	# Limit to genuinely visual-only types.
	if node is MeshInstance3D or node is Light3D or node is BoneAttachment3D:
		node.process_mode = Node.PROCESS_MODE_DISABLED
		stats.disabled += 1

# ============ PERF OVERLAY (F3) ============

func _toggle_perf_overlay() -> void:
	_perf_overlay_visible = not _perf_overlay_visible
	if _perf_overlay_visible:
		if _perf_overlay_layer == null:
			_create_perf_overlay()
		_perf_overlay_layer.visible = true
		_update_perf_overlay()
	elif _perf_overlay_layer:
		_perf_overlay_layer.visible = false

func _create_perf_overlay() -> void:
	_perf_overlay_layer = CanvasLayer.new()
	_perf_overlay_layer.name = "PerfOverlay"
	_perf_overlay_layer.layer = 250  # above loading screen, end screen, etc.

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bg.offset_left = 8
	bg.offset_top = 8
	bg.offset_right = 360
	bg.offset_bottom = 200
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perf_overlay_layer.add_child(bg)

	_perf_overlay_label = Label.new()
	_perf_overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_perf_overlay_label.offset_left = 10
	_perf_overlay_label.offset_top = 6
	_perf_overlay_label.offset_right = -6
	_perf_overlay_label.offset_bottom = -6
	_perf_overlay_label.add_theme_font_size_override("font_size", 13)
	_perf_overlay_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9, 1.0))
	_perf_overlay_label.text = "Sampling..."
	bg.add_child(_perf_overlay_label)

	# Attach to root so it survives scene changes.
	get_tree().root.add_child(_perf_overlay_layer)

func _update_perf_overlay() -> void:
	if _perf_overlay_label == null:
		return
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = (1000.0 / fps) if fps > 0.0 else 0.0
	# Performance monitors return seconds — convert to ms.
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var nav_ms: float = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	var cpu_ms: float = proc_ms + phys_ms + nav_ms
	# "Other" = frame time that isn't accounted for by Process/Physics — this
	# is mostly GPU work + vsync wait. If frame_ms is high but cpu_ms is low,
	# you're GPU-bound (or vsync-locked).
	var other_ms: float = max(0.0, frame_ms - cpu_ms)

	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var vid_mem_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0

	# Bottleneck heuristic: which "side" is eating frame time?
	var verdict := "balanced"
	if frame_ms > 16.7:  # below 60 fps
		if cpu_ms > other_ms * 1.5:
			verdict = "CPU-BOUND"
		elif other_ms > cpu_ms * 1.5:
			verdict = "GPU-BOUND or VSYNC"
		else:
			verdict = "mixed"

	_perf_overlay_label.text = (
		"FPS: %d   frame: %.2f ms   [%s]\n" +
		"  CPU process:  %.2f ms\n" +
		"  CPU physics:  %.2f ms\n" +
		"  CPU nav:      %.2f ms\n" +
		"  Other (GPU+vsync): %.2f ms\n" +
		"\n" +
		"draw calls: %d   prims: %d   objects: %d\n" +
		"nodes in tree: %d   vram: %.1f MB"
	) % [fps, frame_ms, verdict, proc_ms, phys_ms, nav_ms, other_ms,
		 draw_calls, prims, objects, node_count, vid_mem_mb]

# Spawn players one per frame so the per-player FBX animation imports don't
# collapse into a single multi-second hitch. Same end result as
# _spawn_all_players(), just spread across frames.
func _spawn_all_players_progressively() -> void:
	var current_scene = get_tree().current_scene

	# Remove any existing Player nodes from the scene
	var existing_player = current_scene.get_node_or_null("Player")
	if existing_player:
		existing_player.queue_free()

	# Clear any corpse nodes left over from a previous round. The level scene
	# is fresh so this is normally empty, but any node that ended up parented
	# elsewhere (e.g., directly under the SceneTree root) would survive the
	# scene change and confuse win-condition / interaction logic.
	for corpse in get_tree().get_nodes_in_group("corpse"):
		if is_instance_valid(corpse):
			corpse.queue_free()

	if players_container == null:
		players_container = Node3D.new()
		players_container.name = "Players"
		current_scene.add_child(players_container)

	var my_steam_id = Steam.getSteamID()
	var spawn_index = 0
	var total = LobbyManager.lobby_members.size()

	for member in LobbyManager.lobby_members:
		var player_steam_id = member.steam_id
		var is_local = (player_steam_id == my_steam_id)

		var player = PlayerScene.instantiate()
		player.steam_id = player_steam_id
		player.is_local_player = is_local
		player.name = "Player_" + str(player_steam_id)

		var spawn_pos = spawn_points[spawn_index % spawn_points.size()]
		player.position = spawn_pos
		spawn_index += 1
		players_container.add_child(player)

		var color = PLAYER_COLORS[(spawn_index - 1) % PLAYER_COLORS.size()]
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		var model = player.get_node("PlayerModel")
		for child in model.get_children():
			if child is MeshInstance3D:
				child.material_override = mat
				break

		NetworkManager.register_player(player_steam_id, player)

		if not is_local:
			VoiceManager.setup_player_voice(player_steam_id, player)

		# Defensive reset of round-related state (is_dead, possession, weapons,
		# health, visibility). Belt-and-suspenders against stale damage/death
		# packets from a previous round being processed during this frame.
		if player.has_method("reset_round_state"):
			player.reset_round_state()

		print("Spawned player: ", member.name, " (local: ", is_local, ")")

		# Update progress bar and yield so the loading screen repaints
		# between heavy player instantiations.
		var pct = 70.0 + (float(spawn_index) / float(max(total, 1))) * 18.0
		_set_loading_status("Spawning players (%d / %d)..." % [spawn_index, total], pct)
		await get_tree().process_frame

	VoiceManager.start()

	if LobbyManager.is_host():
		_maybe_spawn_ai_bot()
		_assign_roles()

# Two-player special mode: spawn a guaranteed-impostor AI bot so the round has
# a real adversary. Host-only — bot is host-authoritative; clients spawn a
# matching node when they receive BOT_SPAWN.
func _maybe_spawn_ai_bot() -> void:
	if not ai_mode_enabled:
		return
	var count: int = clamp(ai_bot_count, 1, AI_BOT_MAX_COUNT)
	for i in range(count):
		var bot_id: int = AI_BOT_ID_BASE + i
		# Offset each bot's spawn so they don't stack on top of each other.
		var spawn_pos: Vector3 = spawn_points[(2 + i) % spawn_points.size()]
		_spawn_local_ai_bot(bot_id, spawn_pos)
		NetworkManager.send_bot_spawn(bot_id, spawn_pos)
	_bake_bot_navmesh()

# Bake a NavigationRegion3D from the level's static collision geometry so the
# bot's NavigationAgent3D can path around walls and through doorways. Host-only:
# clients don't pathfind (they just lerp the bot to host-broadcast positions).
# Async bake so it doesn't add to load time on the critical path; the bot's
# 10-second initial firing delay covers the bake window.
func _bake_bot_navmesh() -> void:
	var current = get_tree().current_scene
	if current == null:
		return
	if current.get_node_or_null("BotNavRegion") != null:
		return
	var nav_region := NavigationRegion3D.new()
	nav_region.name = "BotNavRegion"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = 1
	nav_mesh.agent_height = 1.8
	# Tight radius so the bot can fit through standard doorways. The player
	# physics box is 0.4 wide, so 0.3 leaves a little slack.
	nav_mesh.agent_radius = 0.3
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 45.0
	nav_mesh.cell_size = 0.2
	nav_mesh.cell_height = 0.2
	nav_region.navigation_mesh = nav_mesh
	current.add_child(nav_region)
	# Threaded bake so the loading screen stays responsive; the bot's 10-second
	# initial firing delay covers the bake window.
	nav_region.bake_navigation_mesh(true)
	print("Bot navmesh: bake started")

func _spawn_local_ai_bot(bot_id: int, spawn_pos: Vector3) -> Node:
	if NetworkManager.get_player(bot_id) != null:
		return NetworkManager.get_player(bot_id)
	var bot = AIBotScene.instantiate()
	bot.steam_id = bot_id
	bot.is_local_player = false
	bot.is_impostor = true
	bot.name = "AIBot_" + str(bot_id)
	bot.position = spawn_pos
	if players_container == null:
		var cur = get_tree().current_scene
		players_container = Node3D.new()
		players_container.name = "Players"
		cur.add_child(players_container)
	players_container.add_child(bot)
	NetworkManager.register_player(bot_id, bot)
	print("Spawned AI bot id=%d at %s" % [bot_id, spawn_pos])
	return bot

func _on_bot_spawn_received(bot_id: int, position: Vector3) -> void:
	# Host already spawned its own bot locally before broadcasting.
	if LobbyManager.is_host():
		return
	if NetworkManager.get_player(bot_id) != null:
		return
	# Ensure we're in the game scene (defensive — BOT_SPAWN can land during
	# the load if a retransmit overlaps).
	if players_container == null:
		await get_tree().process_frame
	_spawn_local_ai_bot(bot_id, position)

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
	# AI mode: every human is a crewmate; the AI bots are the impostors.
	# Skip the normal random-impostor selection entirely.
	if ai_mode_enabled:
		_assign_roles_ai_mode()
		return

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
			# Send role to remote player privately, include impostor list and settings
			NetworkManager.send_role_assignment(member_steam_id, is_impostor, impostor_ids, anonymous_impostors)

	print("Impostors assigned: ", actual_count)

func _assign_roles_ai_mode() -> void:
	var my_steam_id = Steam.getSteamID()
	var count: int = clamp(ai_bot_count, 1, AI_BOT_MAX_COUNT)
	var impostor_ids: Array = []
	for i in range(count):
		impostor_ids.append(AI_BOT_ID_BASE + i)
	for member in LobbyManager.lobby_members:
		var member_steam_id = member.steam_id
		var player_node = NetworkManager.get_player(member_steam_id)
		if player_node:
			player_node.is_impostor = false
		if member_steam_id == my_steam_id:
			NetworkManager.pending_role_received = true
			NetworkManager.pending_role_impostor = false
			NetworkManager.role_assigned.emit(false)
		else:
			NetworkManager.send_role_assignment(member_steam_id, false, impostor_ids, anonymous_impostors)
	print("AI mode: %d bot(s) are the impostors; all humans are crewmates" % count)

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
