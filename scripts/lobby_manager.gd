extends Node

signal lobby_created(lobby_id)
signal lobby_joined(lobby_id)
signal lobby_join_failed(reason)
signal player_joined(steam_id)
signal player_left(steam_id)
signal lobby_list_received(lobbies)
signal lobby_closed
signal member_names_updated

const GAME_TAG: String = "outliar"

var lobby_id: int = 0
var lobby_members: Array = []
var current_host_id: int = 0
signal host_changed(new_host_id)
var _pending_password: String = ""

func _ready():
	print("LobbyManager starting...")
	var result = Steam.steamInitEx()
	print("Steam init result: ", result)
	if result.status != 0:
		print("Steam failed: ", result.verbal)
		return
	
	print("Steam initialized: ", Steam.getPersonaName())
	
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.persona_state_change.connect(_on_persona_state_change)

func _process(_delta):
	Steam.run_callbacks()
	_check_host_change()
	_check_lobby_closing()
	
func _check_host_change():
	if lobby_id == 0:
		return

	var new_host = Steam.getLobbyOwner(lobby_id)

	if new_host != current_host_id:
		print("Host migrated to:", new_host)
		current_host_id = new_host
		host_changed.emit(new_host)
		
func is_in_lobby() -> bool:
	return lobby_id != 0

# ============ CREATE ============

func create_lobby(max_players: int = 4, password: String = ""):
	print("Creating lobby...")
	_pending_password = password
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, max_players)

func _on_lobby_created(result: int, new_lobby_id: int):
	if result == 1:
		lobby_id = new_lobby_id
		print("Lobby created: ", lobby_id)
		Steam.setLobbyJoinable(lobby_id, true)
		Steam.setLobbyData(lobby_id, "name", Steam.getPersonaName() + "'s Game")
		Steam.setLobbyData(lobby_id, "game_tag", GAME_TAG)
		Steam.setLobbyData(lobby_id, "original_host", str(Steam.getSteamID()))
		#set password
		if _pending_password != "":
			Steam.setLobbyData(lobby_id, "has_password", "1")
			Steam.setLobbyData(lobby_id, "password", _pending_password)
		else:
			Steam.setLobbyData(lobby_id, "has_password", "0")
		_pending_password = ""
		# Allow Steam relay as fallback for P2P
		Steam.allowP2PPacketRelay(true)
		_refresh_lobby_members()
		lobby_created.emit(lobby_id)
	else:
		print("Failed to create lobby: ", result)

func get_my_steam_id() -> int:
	return Steam.getSteamID()

# ============ FIND ============

func find_lobbies():
	print("Searching for lobbies...")
	Steam.addRequestLobbyListStringFilter("game_tag", GAME_TAG, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array):
	print("Found ", lobbies.size(), " lobbies")
	var lobby_data: Array = []
	for lob_id in lobbies:
		var player_count = Steam.getNumLobbyMembers(lob_id)
		# Skip empty/orphaned lobbies
		if player_count <= 0:
			continue
		lobby_data.append({
			"id": lob_id,
			"name": Steam.getLobbyData(lob_id, "name"),
			"player_count": player_count,
			"max_players": Steam.getLobbyMemberLimit(lob_id),
			"has_password": Steam.getLobbyData(lob_id, "has_password") == "1"
		})
	lobby_list_received.emit(lobby_data)

# ============ JOIN ============

func join_lobby(target_lobby_id: int):
	var has_password = Steam.getLobbyData(target_lobby_id, "has_password") == "1"

	if has_password:
		print("Blocked: password required")
		lobby_join_failed.emit("Password required")
		return
		
	print("Joining lobby: ", target_lobby_id)
	Steam.joinLobby(target_lobby_id)
	
func join_lobby_with_password(target_lobby_id: int, entered_password: String):
	var actual_password = Steam.getLobbyData(target_lobby_id, "password")
	var has_password = Steam.getLobbyData(target_lobby_id, "has_password") == "1"

	if has_password and entered_password != actual_password:
		print("Incorrect password")
		lobby_join_failed.emit("Incorrect password")
		return

	print("Joining lobby: ", target_lobby_id)
	Steam.joinLobby(target_lobby_id)

func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, result: int):
	if result == 1:
		lobby_id = joined_lobby_id
		print("Joined lobby: ", lobby_id)
		_refresh_lobby_members()
		# Establish P2P connections with existing members
		NetworkManager.establish_p2p_with_lobby()
		lobby_joined.emit(lobby_id)
	else:
		print("Failed to join: ", result)
		lobby_join_failed.emit(result)

# ============ MEMBERS ============
		
func _on_lobby_chat_update(changed_lobby_id: int, changed_user_id: int, _making_change_id: int, chat_state: int):
	if changed_lobby_id != lobby_id:
		return

	_refresh_lobby_members()

	if chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
		player_joined.emit(changed_user_id)

		_check_original_host_returned(changed_user_id)

	elif chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_LEFT \
	or chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED:
		player_left.emit(changed_user_id)
		
func _check_original_host_returned(joined_id: int):
	var original_host = get_original_host_id()

	# Only the current host can transfer ownership
	if not is_host():
		return

	if joined_id == original_host:
		print("Original host returned — transferring ownership back")
		Steam.setLobbyOwner(lobby_id, original_host)
		# Update our stored host immediately
		current_host_id = original_host
		# Emit signal so UI updates instantly
		host_changed.emit(original_host)

func _refresh_lobby_members():
	lobby_members.clear()
	var count = Steam.getNumLobbyMembers(lobby_id)
	for i in range(count):
		var member_id = Steam.getLobbyMemberByIndex(lobby_id, i)
		var member_name = Steam.getFriendPersonaName(member_id)
		# If Steam hasn't cached this player's name yet, request it
		if member_name == "":
			Steam.requestUserInformation(member_id, true)
		lobby_members.append({
			"steam_id": member_id,
			"name": member_name
		})
	print("Members: ", lobby_members)
	# Whenever membership changes (someone joined, someone left, or initial
	# population), proactively accept P2P sessions with everyone. This is
	# load-bearing for host->client reliable packet delivery — see
	# NetworkManager.accept_all_p2p_sessions for the why.
	if NetworkManager and NetworkManager.has_method("accept_all_p2p_sessions"):
		NetworkManager.accept_all_p2p_sessions()

func _on_persona_state_change(steam_id: int, _flags: int):
	if lobby_id == 0:
		return
	# Update the name in our member list if this player is in our lobby
	var updated = false
	for member in lobby_members:
		if member.steam_id == steam_id and member.name == "":
			member.name = Steam.getFriendPersonaName(steam_id)
			if member.name != "":
				updated = true
	if updated:
		member_names_updated.emit()

# ============ LEAVE ============

func leave_lobby():
	if lobby_id != 0:
		print("Leaving lobby: ", lobby_id)
		NetworkManager.close_all_sessions()
		Steam.leaveLobby(lobby_id)
		lobby_id = 0
		lobby_members.clear()

func _notification(what):
	# Auto-cleanup when the game is closing
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave_lobby()
		
func close_lobby():
	if !is_host():
		return

	print("Host closing lobby")

	# Tell everyone the lobby is closing
	Steam.setLobbyData(lobby_id, "lobby_closing", "1")

	# Host leaves
	leave_lobby()

	lobby_closed.emit()
	
func _check_lobby_closing():
	if lobby_id == 0:
		return

	var closing = Steam.getLobbyData(lobby_id, "lobby_closing")

	if closing == "1" and !is_host():
		print("Lobby closed by host")
		leave_lobby()
		lobby_closed.emit()

# ============ HELPERS ============
func get_original_host_id() -> int:
	var id_str = Steam.getLobbyData(lobby_id, "original_host")
	return int(id_str) if id_str != "" else 0
	
func is_host() -> bool:
	return Steam.getLobbyOwner(lobby_id) == Steam.getSteamID()

func get_host_steam_id() -> int:
	return Steam.getLobbyOwner(lobby_id)
