extends Control

@onready var host_btn = $HostButton
@onready var join_btn = $JoinButton
@onready var code_input = $CodeInput
@onready var status_label = $StatusLabel
@onready var player_list = $PlayerList
@onready var code_label = $CodeLabel
@onready var copy_btn = $CopyButton
@onready var start_btn = $StartButton

var current_code: String = ""

func _ready():
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	copy_btn.pressed.connect(_on_copy_pressed)
	start_btn.pressed.connect(_on_start_pressed)

	LobbyManager.lobby_created.connect(_on_lobby_created)
	LobbyManager.lobby_joined.connect(_on_lobby_joined)
	LobbyManager.player_joined.connect(_on_player_update)
	LobbyManager.player_left.connect(_on_player_update)
	NetworkManager.game_started.connect(_on_game_started)

	status_label.text = "Not in lobby"
	code_label.text = ""
	copy_btn.visible = false
	start_btn.visible = false

func _on_host_pressed():
	status_label.text = "Creating lobby..."
	LobbyManager.create_lobby(4)

func _on_lobby_created(lobby_id: int):
	current_code = str(lobby_id)
	code_label.text = "Code: " + current_code
	copy_btn.visible = true
	start_btn.visible = true  # Show start button for host
	status_label.text = "Lobby created!"
	_refresh_players()

func _on_copy_pressed():
	DisplayServer.clipboard_set(current_code)
	status_label.text = "Code copied!"

func _on_join_pressed():
	var code = code_input.text.strip_edges()
	if code.is_empty():
		status_label.text = "Enter a lobby code"
		return
	status_label.text = "Joining..."
	LobbyManager.join_lobby(int(code))

func _on_lobby_joined(_lobby_id: int):
	status_label.text = "Joined lobby!"
	_refresh_players()

func _on_player_update(_steam_id: int):
	_refresh_players()

func _refresh_players():
	player_list.clear()
	for member in LobbyManager.lobby_members:
		var prefix = "[HOST] " if member.steam_id == LobbyManager.get_host_steam_id() else ""
		player_list.add_item(prefix + member.name)

func _on_start_pressed():
	status_label.text = "Starting game..."
	GameManager.start_game()

func _on_game_started():
	# Scene will change, this UI will be removed
	status_label.text = "Loading game..."
