extends Control

@onready var host_btn = $HostButton
@onready var how_to_play_btn = $HowToPlayButton
@onready var status_label = $StatusLabel
@onready var player_list = $PlayerList
@onready var start_btn = $StartButton
@onready var refresh_btn = $RefreshButton
@onready var lobby_list = $LobbyList
@onready var leave_lobby = $LeaveLobbyButton
@onready var close_lobby = $CloseLobbyButton
@onready var imposter1 = $"PickImposters/1Imposter"
@onready var imposter2 = $"PickImposters/2Imposter"
@onready var imposter3 = $"PickImposters/3Imposter"
@onready var pickImposters = $"PickImposters"
@onready var credits_btn = $CreditsButton
@onready var credits_panel = $CreditsPanel
@onready var close_credits_btn = $"CreditsPanel/CloseCreditsButton"
@onready var credits_text = $"CreditsPanel/CreditsScroll/CreditsText"

var available_lobbies: Array = []
var dot_blue = preload("res://scenes/lobby/lobby_assets/BlueIcon.png")
var dot_red = preload("res://scenes/lobby/lobby_assets/RedIcon.png")
var dot_purple = preload("res://scenes/lobby/lobby_assets/PurpleIcon.png")
var dot_host = preload("res://scenes/lobby/lobby_assets/HostIcon.png")
var lobby_password: String = ""
var imposter_group = ButtonGroup.new()
var imposter_count = 1

const AUTO_REFRESH_INTERVAL: float = 3.0
var _auto_refresh_timer: float = 0.0

func _ready():
	#SAFE SIGNAL CONNECTIONS (prevents duplicates)
	if not host_btn.pressed.is_connected(_on_host_pressed):
		host_btn.pressed.connect(_on_host_pressed)
	if not how_to_play_btn.pressed.is_connected(_on_how_to_play_pressed):
		how_to_play_btn.pressed.connect(_on_how_to_play_pressed)
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
	if not credits_btn.pressed.is_connected(_on_credits_pressed):
		credits_btn.pressed.connect(_on_credits_pressed)
	if not close_credits_btn.pressed.is_connected(_on_close_credits_pressed):
		close_credits_btn.pressed.connect(_on_close_credits_pressed)
	if not credits_text.meta_clicked.is_connected(_on_credits_link_clicked):
		credits_text.meta_clicked.connect(_on_credits_link_clicked)

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
	if not LobbyManager.member_names_updated.is_connected(_on_player_update_names):
		LobbyManager.member_names_updated.connect(_on_player_update_names)
		
	imposter1.button_group = imposter_group
	imposter2.button_group = imposter_group
	imposter3.button_group = imposter_group
	# Default selection
	imposter1.button_pressed = true
	
	imposter1.pressed.connect(_on_imposter_selected)
	imposter2.pressed.connect(_on_imposter_selected)
	imposter3.pressed.connect(_on_imposter_selected)

	#RESET DEFAULT UI
	status_label.text = "Not in lobby"
	start_btn.visible = false
	player_list.visible = false
	leave_lobby.visible = false
	close_lobby.visible = false
	pickImposters.visible = false
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await get_tree().process_frame
	#HANDLE RETURNING FROM GAME
	if LobbyManager.is_in_lobby():
		# Already in a lobby, go straight to physical lobby room
		get_tree().change_scene_to_file("res://scenes/lobby/lobby_room.tscn")
		return
	else:
		_on_refresh_pressed()

func _process(delta):
	# Auto-refresh lobby list while browsing (lobby_list visible and not in a lobby)
	if lobby_list.visible and not LobbyManager.is_in_lobby():
		_auto_refresh_timer += delta
		if _auto_refresh_timer >= AUTO_REFRESH_INTERVAL:
			_auto_refresh_timer = 0.0
			LobbyManager.find_lobbies()

func _on_lobby_join_failed(reason: String):
	status_label.text = "Failed to join lobby: %s" % reason
	
func _on_imposter_selected():
	if not LobbyManager.is_host():
		return  # only host can change this

	for button in imposter_group.get_buttons():
		if button.button_pressed:
			imposter_count = int(button.text)
			print("Imposters set to:", imposter_count)

# ============ HOST ============

func _on_host_changed(_new_host_id):
	_update_lobby_buttons()
	_refresh_players()

	if LobbyManager.is_host():
		status_label.text = "You are now the host."
	else:
		status_label.text = "Host changed."

func _on_how_to_play_pressed():
	get_tree().change_scene_to_file("res://scenes/lobby/how_to_play.tscn")

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
	# Transition to physical lobby room
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/lobby/lobby_room.tscn")

func _update_lobby_buttons():
	if LobbyManager.is_host():
		close_lobby.visible = true
		leave_lobby.visible = false
		start_btn.visible = true
		pickImposters.visible = true
		#start_btn.disabled = LobbyManager.lobby_members.size() < 2
	else:
		close_lobby.visible = false
		leave_lobby.visible = true
		pickImposters.visible = false

# ============ BROWSE / JOIN ============

func _on_refresh_pressed():
	_auto_refresh_timer = 0.0
	status_label.text = "Searching for lobbies..."
	lobby_list.clear()
	LobbyManager.find_lobbies()

func _on_lobby_list_received(lobbies: Array):
	# Remember which lobby was selected so we can restore it after refresh
	var selected_lobby_id: int = -1
	var selected_indices = lobby_list.get_selected_items()
	if selected_indices.size() > 0:
		var sel_idx = selected_indices[0]
		if sel_idx < available_lobbies.size():
			selected_lobby_id = available_lobbies[sel_idx].id

	available_lobbies = lobbies
	lobby_list.clear()

	if lobbies.is_empty():
		status_label.text = "No lobbies found. Host one or refresh."
		return

	var new_selected_index: int = -1
	for i in range(lobbies.size()):
		var lobby = lobbies[i]
		var text = "%s  (%d/%d)" % [lobby.name, lobby.player_count, lobby.max_players]
		var icon = dot_purple
		var ratio = float(lobby.player_count) / lobby.max_players
		if ratio >= 0.75:
			icon = dot_blue
		elif ratio > 0:
			icon = dot_red
		lobby_list.add_item(text, icon)
		if lobby.id == selected_lobby_id:
			new_selected_index = i

	# Restore previous selection
	if new_selected_index >= 0:
		lobby_list.select(new_selected_index)

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
	# Transition to physical lobby room
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/lobby/lobby_room.tscn")

func _on_player_update(_steam_id: int):
	_refresh_players()
	_update_lobby_buttons()

func _on_player_update_names():
	_refresh_players()

func _refresh_players():
	player_list.clear()
	for member in LobbyManager.lobby_members:
		var icon = dot_purple
		if member["steam_id"] == LobbyManager.get_host_steam_id():
			icon = dot_host
		player_list.add_item(member["name"], icon)
	update_imposter_options()
	
func update_imposter_options():
	var count = LobbyManager.lobby_members.size()

	imposter1.disabled = count < 3
	imposter2.disabled = count < 3
	imposter3.disabled = count < 7

	# Force valid selection if current one becomes invalid
	if imposter_count == 3 and count < 7:
		imposter2.button_pressed = true
	elif imposter_count == 2 and count < 3:
		imposter1.button_pressed = true

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

# ============ CREDITS ============

func _on_credits_pressed():
	credits_panel.visible = true

func _on_close_credits_pressed():
	credits_panel.visible = false

func _on_credits_link_clicked(meta):
	OS.shell_open(str(meta))
