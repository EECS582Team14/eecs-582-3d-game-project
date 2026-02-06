extends Control

@onready var host_btn = $HostButton
@onready var status_label = $StatusLabel
@onready var player_list = $PlayerList
@onready var start_btn = $StartButton
@onready var refresh_btn = $RefreshButton
@onready var lobby_list = $LobbyList

var available_lobbies: Array = []

func _ready():
	host_btn.pressed.connect(_on_host_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	start_btn.pressed.connect(_on_start_pressed)
	lobby_list.item_activated.connect(_on_lobby_selected)

	LobbyManager.lobby_created.connect(_on_lobby_created)
	LobbyManager.lobby_joined.connect(_on_lobby_joined)
	LobbyManager.player_joined.connect(_on_player_update)
	LobbyManager.player_left.connect(_on_player_update)
	LobbyManager.lobby_list_received.connect(_on_lobby_list_received)
	NetworkManager.game_started.connect(_on_game_started)

	status_label.text = "Not in lobby"
	start_btn.visible = false

	# Auto-search for lobbies on startup
	_on_refresh_pressed()

# ============ HOST ============

func _on_host_pressed():
	status_label.text = "Creating lobby..."
	LobbyManager.create_lobby(4)

func _on_lobby_created(_lobby_id: int):
	start_btn.visible = true
	status_label.text = "Lobby created! Waiting for players..."
	_refresh_players()

# ============ BROWSE / JOIN ============

func _on_refresh_pressed():
	status_label.text = "Searching for lobbies..."
	lobby_list.clear()
	LobbyManager.find_lobbies()

func _on_lobby_list_received(lobbies: Array):
	available_lobbies = lobbies
	lobby_list.clear()

	if lobbies.is_empty():
		status_label.text = "No lobbies found. Host one or refresh."
		return

	for lobby in lobbies:
		var text = "%s  (%d/%d)" % [lobby.name, lobby.player_count, lobby.max_players]
		lobby_list.add_item(text)

	status_label.text = "Found %d lobby(s). Double-click to join." % lobbies.size()

func _on_lobby_selected(index: int):
	if index < 0 or index >= available_lobbies.size():
		return
	var lobby = available_lobbies[index]
	status_label.text = "Joining %s..." % lobby.name
	LobbyManager.join_lobby(lobby.id)

# ============ JOINED ============

func _on_lobby_joined(_lobby_id: int):
	status_label.text = "Joined lobby!"
	lobby_list.visible = false
	refresh_btn.visible = false
	host_btn.visible = false
	# Show start button if we're the host
	start_btn.visible = LobbyManager.is_host()
	_refresh_players()

func _on_player_update(_steam_id: int):
	_refresh_players()

func _refresh_players():
	player_list.clear()
	for member in LobbyManager.lobby_members:
		var prefix = "[HOST] " if member.steam_id == LobbyManager.get_host_steam_id() else ""
		player_list.add_item(prefix + member.name)

# ============ GAME START ============

func _on_start_pressed():
	status_label.text = "Starting game..."
	GameManager.start_game()

func _on_game_started():
	status_label.text = "Loading game..."
