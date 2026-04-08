extends Control

@onready var host_btn = $HostButton
@onready var status_label = $StatusLabel
@onready var player_list = $PlayerList
@onready var start_btn = $StartButton
@onready var refresh_btn = $RefreshButton
@onready var lobby_list = $LobbyList
@onready var leave_lobby = $LeaveLobbyButton
@onready var close_lobby = $CloseLobbyButton

var available_lobbies: Array = []
var dot_blue = preload("res://scenes/lobby/lobby_assets/BlueIcon.png")
var dot_red = preload("res://scenes/lobby/lobby_assets/RedIcon.png")
var dot_purple = preload("res://scenes/lobby/lobby_assets/PurpleIcon.png")
var dot_host = preload("res://scenes/lobby/lobby_assets/HostIcon.png")
var lobby_password: String = ""

func _ready():
	#SAFE SIGNAL CONNECTIONS (prevents duplicates)
	if not host_btn.pressed.is_connected(_on_host_pressed):
		host_btn.pressed.connect(_on_host_pressed)
	if not refresh_btn.pressed.is_connected(_on_refresh_pressed):
		refresh_btn.pressed.connect(_on_refresh_pressed)
	if not start_btn.pressed.is_connected(_on_start_pressed):
		start_btn.pressed.connect(_on_start_pressed)
	if not leave_lobby.pressed.is_connected(_on_leave_lobby_pressed):
		leave_lobby.pressed.connect(_on_leave_lobby_pressed)
	if not close_lobby.pressed.is_connected(_on_close_lobby_pressed):
		close_lobby.pressed.connect(_on_close_lobby_pressed)
	if not lobby_list.item_activated.is_connected(_on_lobby_selected):
		lobby_list.item_activated.connect(_on_lobby_selected)

	if not LobbyManager.lobby_created.is_connected(_on_lobby_created):
		LobbyManager.lobby_created.connect(_on_lobby_created)
	if not LobbyManager.lobby_joined.is_connected(_on_lobby_joined):
		LobbyManager.lobby_joined.connect(_on_lobby_joined)
	if not LobbyManager.player_joined.is_connected(_on_player_update):
		LobbyManager.player_joined.connect(_on_player_update)
	if not LobbyManager.player_left.is_connected(_on_player_update):
		LobbyManager.player_left.connect(_on_player_update)
	if not LobbyManager.lobby_list_received.is_connected(_on_lobby_list_received):
		LobbyManager.lobby_list_received.connect(_on_lobby_list_received)
	if not NetworkManager.game_started.is_connected(_on_game_started):
		NetworkManager.game_started.connect(_on_game_started)
	if not LobbyManager.host_changed.is_connected(_on_host_changed):
		LobbyManager.host_changed.connect(_on_host_changed)
	if not LobbyManager.lobby_join_failed.is_connected(_on_lobby_join_failed):
		LobbyManager.lobby_join_failed.connect(_on_lobby_join_failed)

	#RESET DEFAULT UI
	status_label.text = "Not in lobby"
	start_btn.visible = false
	player_list.visible = false
	leave_lobby.visible = false
	close_lobby.visible = false
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await get_tree().process_frame
	#HANDLE RETURNING FROM GAME
	if LobbyManager.is_in_lobby():
		status_label.text = "Returned to lobby"
		lobby_list.visible = false
		refresh_btn.visible = false
		host_btn.visible = false
		player_list.visible = true

		_update_lobby_buttons()
		_refresh_players()
	else:
		_on_refresh_pressed()

func _on_lobby_join_failed(reason: String):
	status_label.text = "Failed to join lobby: %s" % reason

# ============ HOST ============

func _on_host_changed(_new_host_id):
	_update_lobby_buttons()
	_refresh_players()

	if LobbyManager.is_host():
		status_label.text = "You are now the host."
	else:
		status_label.text = "Host changed."

func _on_host_pressed():
	var popup = AcceptDialog.new()
	popup.title = "Host New Lobby"
	popup.size = Vector2i(300, 150)
	
	var vbox = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "Set a lobby password\n(Leave blank for public):"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "Optional password..."
	line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(line_edit)
	
	popup.add_child(vbox)
	add_child(popup)
	popup.popup_centered()
	
	# Focus the line edit immediately so the user can just start typing
	line_edit.grab_focus()

	# Connect signals
	popup.confirmed.connect(_create_lobby_with_password.bind(line_edit, popup))
	line_edit.text_submitted.connect(func(_text): _create_lobby_with_password(line_edit, popup))
	popup.canceled.connect(popup.queue_free)

func _on_lobby_created(_lobby_id: int):
	start_btn.visible = true
	close_lobby.visible = true
	status_label.text = "Lobby created! Waiting for players..."
	_refresh_players()

func _update_lobby_buttons():
	if LobbyManager.is_host():
		close_lobby.visible = true
		leave_lobby.visible = false
		start_btn.visible = true
		#start_btn.disabled = LobbyManager.lobby_members.size() < 2
	else:
		close_lobby.visible = false
		leave_lobby.visible = true

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
		var icon = dot_purple
		var ratio = float(lobby.player_count) / lobby.max_players
		if ratio >= 0.75:
			icon = dot_blue
		elif ratio > 0:
			icon = dot_red
		lobby_list.add_item(text, icon)

	status_label.text = "Found %d lobby(s). Double-click to join." % lobbies.size()

func _on_lobby_selected(index: int):
	if index < 0 or index >= available_lobbies.size():
		return
	var lobby = available_lobbies[index]
	if lobby.has_password:
		lobby_password = ""  # reset
		_show_password_prompt(lobby)  # call your popup UI
	else:
		status_label.text = "Joining %s..." % lobby.name
		LobbyManager.join_lobby(lobby.id)
		
# ============ PASSWORD ============
func _submit_password(lobby_id: int, entered_password: String):
	status_label.text = "Joining lobby..."
	LobbyManager.join_lobby_with_password(lobby_id, entered_password)
	
func _show_password_prompt(lobby):
	var popup = AcceptDialog.new()
	popup.title = "Join Lobby: %s" % lobby.name
	popup.size = Vector2i(300, 120)
	
	# Container for vertical layout
	var vbox = VBoxContainer.new()
	
	# Add a descriptive label
	var label = Label.new()
	label.text = "Enter a password or leave blank\nfor a public lobby:"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	
	# Add the input field
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "Password..."
	line_edit.secret = true # Masks the password characters
	vbox.add_child(line_edit)
	
	popup.add_child(vbox)
	add_child(popup)
	popup.popup_centered()

	# Handle the 'OK' button or pressing 'Enter' in the LineEdit
	popup.confirmed.connect(_on_password_entered.bind(lobby.id, line_edit, popup))
	line_edit.text_submitted.connect(func(_text): popup.hide(); _on_password_entered(lobby.id, line_edit, popup))
	
	# Cleanup on close
	popup.canceled.connect(popup.queue_free)
	
func _on_password_entered(lobby_id: int, line_edit: LineEdit, popup:AcceptDialog):
	var entered_password = line_edit.text.strip_edges()
	_submit_password(lobby_id, entered_password)
	
	# Close the popup after submitting
	popup.queue_free()
	
func _create_lobby_with_password(line_edit: LineEdit, popup: AcceptDialog):
	lobby_password = line_edit.text.strip_edges()
	status_label.text = "Creating lobby..."
	
	# Transition UI
	player_list.visible = true
	lobby_list.visible = false
	
	LobbyManager.create_lobby(8, lobby_password)
	
	if is_instance_valid(popup):
		popup.queue_free()
	
# ============ JOINED ============	
func _on_lobby_joined(_lobby_id: int):
	status_label.text = "Joined lobby!"
	lobby_list.visible = false
	refresh_btn.visible = false
	host_btn.visible = false
	player_list.visible = true
	_update_lobby_buttons()
	_refresh_players()

func _on_player_update(_steam_id: int):
	_refresh_players()
	_update_lobby_buttons()

func _refresh_players():
	player_list.clear()
	for member in LobbyManager.lobby_members:
		var icon = dot_purple
		if member["steam_id"] == LobbyManager.get_host_steam_id():
			icon = dot_host
		player_list.add_item(member["name"], icon)

# ============ LEAVING ============

func _on_leave_lobby_pressed():
	status_label.text = "Leaving lobby..."
	LobbyManager.leave_lobby()
	player_list.clear()
	player_list.visible = false
	lobby_list.visible = true
	refresh_btn.visible = true
	host_btn.visible = true
	start_btn.visible = false
	close_lobby.visible = false
	leave_lobby.visible = false
	_on_refresh_pressed()

func _on_close_lobby_pressed():
	if not LobbyManager.is_host():
		return
	status_label.text = "Closing lobby..."
	LobbyManager.close_lobby()
	_return_to_start_screen()

func _return_to_start_screen():
	player_list.clear()
	player_list.visible = false
	lobby_list.visible = true
	refresh_btn.visible = true
	host_btn.visible = true
	start_btn.visible = false
	close_lobby.visible = false
	leave_lobby.visible = false
	status_label.text = "Lobby closed."
	_on_refresh_pressed()

# ============ GAME START ============

func _on_start_pressed():
	status_label.text = "Starting game..."
	GameManager.start_game()

func _on_game_started():
	status_label.text = "Loading game..."
