extends Node

## Game Manager
##
## Handles game state transitions and player spawning.
## Add this as an autoload singleton.

const PlayerScene = preload("res://scenes/player/player.tscn")
const GAME_LEVEL = "res://scenes/levels/main.tscn"

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

func _ready():
	NetworkManager.game_started.connect(_on_game_started)
	LobbyManager.player_left.connect(_on_player_left)

# Call this when ready to start the game (e.g., from a "Start Game" button)
func start_game():
	if LobbyManager.is_host():
		# Send start to other players, then load level
		# Don't call _load_game_level here - the signal handler will do it
		NetworkManager.send_game_start()
	else:
		print("Only the host can start the game")

func _on_game_started():
	_load_game_level()

func _load_game_level():
	# Change to the game level scene
	get_tree().change_scene_to_file(GAME_LEVEL)
	# Wait for scene to load, then spawn players
	await get_tree().process_frame
	await get_tree().process_frame
	_spawn_all_players()

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

func _assign_roles():
	# Pick one random player as the impostor
	var impostor_index = randi() % LobbyManager.lobby_members.size()
	var my_steam_id = Steam.getSteamID()

	for i in range(LobbyManager.lobby_members.size()):
		var member_steam_id = LobbyManager.lobby_members[i].steam_id
		var is_impostor = (i == impostor_index)

		if member_steam_id == my_steam_id:
			# Host assigns own role directly
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
		NetworkManager.players_in_game.clear()
