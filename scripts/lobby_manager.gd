extends Node

signal lobby_created(lobby_id)
signal lobby_joined(lobby_id)
signal lobby_join_failed(reason)
signal player_joined(steam_id)
signal player_left(steam_id)
signal lobby_list_received(lobbies)

var lobby_id: int = 0
var lobby_members: Array = []

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

func _process(_delta):
	Steam.run_callbacks()

# ============ CREATE ============

func create_lobby(max_players: int = 4):
	print("Creating lobby...")
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, max_players)

func _on_lobby_created(result: int, new_lobby_id: int):
	if result == 1:
		lobby_id = new_lobby_id
		print("Lobby created: ", lobby_id)
		Steam.setLobbyJoinable(lobby_id, true)
		Steam.setLobbyData(lobby_id, "name", Steam.getPersonaName() + "'s Game")
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
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array):
	print("Found ", lobbies.size(), " lobbies")
	var lobby_data: Array = []
	for lob_id in lobbies:
		lobby_data.append({
			"id": lob_id,
			"name": Steam.getLobbyData(lob_id, "name"),
			"player_count": Steam.getNumLobbyMembers(lob_id),
			"max_players": Steam.getLobbyMemberLimit(lob_id)
		})
	lobby_list_received.emit(lobby_data)

# ============ JOIN ============

func join_lobby(target_lobby_id: int):
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

	if chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
		player_joined.emit(changed_user_id)
		# Establish P2P with the new player
		_refresh_lobby_members()
		NetworkManager.establish_p2p_with_lobby()
	elif chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_LEFT or chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED:
		player_left.emit(changed_user_id)
		_refresh_lobby_members()
	else:
		_refresh_lobby_members()

func _refresh_lobby_members():
	lobby_members.clear()
	var count = Steam.getNumLobbyMembers(lobby_id)
	for i in range(count):
		var member_id = Steam.getLobbyMemberByIndex(lobby_id, i)
		lobby_members.append({
			"steam_id": member_id,
			"name": Steam.getFriendPersonaName(member_id)
		})
	print("Members: ", lobby_members)

# ============ LEAVE ============

func leave_lobby():
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		lobby_id = 0
		lobby_members.clear()

# ============ HELPERS ============

func is_host() -> bool:
	return Steam.getLobbyOwner(lobby_id) == Steam.getSteamID()

func get_host_steam_id() -> int:
	return Steam.getLobbyOwner(lobby_id)
