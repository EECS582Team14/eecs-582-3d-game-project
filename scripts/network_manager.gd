extends Node

## Network Manager
##
## Handles Steam P2P networking for player state synchronization.
## Based on official GodotSteam networking tutorial.

signal player_state_received(steam_id: int, state: Dictionary)
signal game_started()

const PACKET_READ_LIMIT: int = 32

# Packet types
enum PacketType {
	PLAYER_STATE,
	GAME_START,
	HANDSHAKE
}

var players_in_game: Dictionary = {}  # steam_id -> player node

func _ready():
	Steam.p2p_session_request.connect(_on_p2p_session_request)
	Steam.p2p_session_connect_fail.connect(_on_p2p_session_connect_fail)

func _process(_delta):
	if LobbyManager.lobby_id > 0:
		_read_all_p2p_packets()

# ============ P2P SESSION MANAGEMENT ============

func _on_p2p_session_request(remote_id: int) -> void:
	var requester: String = Steam.getFriendPersonaName(remote_id)
	print("P2P session request from: %s" % requester)

	# Accept if we're in a lobby
	if LobbyManager.lobby_id != 0:
		Steam.acceptP2PSessionWithUser(remote_id)
		print("Accepted P2P session with: %s" % requester)
		make_p2p_handshake()

func _on_p2p_session_connect_fail(this_steam_id: int, session_error: int) -> void:
	match session_error:
		0: print("P2P failure with %s: no error given" % this_steam_id)
		1: print("P2P failure with %s: target not running same game" % this_steam_id)
		2: print("P2P failure with %s: local user doesn't own app" % this_steam_id)
		3: print("P2P failure with %s: target not connected to Steam" % this_steam_id)
		4: print("P2P failure with %s: connection timed out" % this_steam_id)
		_: print("P2P failure with %s: unknown error %s" % [this_steam_id, session_error])

func make_p2p_handshake() -> void:
	print("Sending P2P handshake to lobby")
	send_p2p_packet(0, {"type": PacketType.HANDSHAKE, "from": Steam.getSteamID()})

# Call this when joining a lobby to pre-establish P2P with all members
func establish_p2p_with_lobby():
	Steam.allowP2PPacketRelay(true)
	make_p2p_handshake()

# ============ SEND PACKETS ============

func send_p2p_packet(target: int, packet_data: Dictionary, send_type: int = Steam.P2P_SEND_RELIABLE, channel: int = 0) -> void:
	var this_data: PackedByteArray
	this_data.append_array(var_to_bytes(packet_data))

	# target == 0 means broadcast to all lobby members
	if target == 0:
		var my_steam_id = Steam.getSteamID()
		if LobbyManager.lobby_members.size() > 1:
			for member in LobbyManager.lobby_members:
				if member['steam_id'] != my_steam_id:
					Steam.sendP2PPacket(member['steam_id'], this_data, send_type, channel)
	else:
		Steam.sendP2PPacket(target, this_data, send_type, channel)

func send_player_state(position: Vector3, rotation_y: float, camera_rotation_x: float):
	var data = {
		"type": PacketType.PLAYER_STATE,
		"px": position.x,
		"py": position.y,
		"pz": position.z,
		"ry": rotation_y,
		"cx": camera_rotation_x
	}
	send_p2p_packet(0, data, Steam.P2P_SEND_UNRELIABLE, 0)

func send_game_start():
	send_p2p_packet(0, {"type": PacketType.GAME_START}, Steam.P2P_SEND_RELIABLE, 0)
	game_started.emit()

# ============ READ PACKETS ============

func _read_all_p2p_packets(read_count: int = 0):
	if read_count >= PACKET_READ_LIMIT:
		return
	if Steam.getAvailableP2PPacketSize(0) > 0:
		_read_p2p_packet()
		_read_all_p2p_packets(read_count + 1)

func _read_p2p_packet() -> void:
	var packet_size: int = Steam.getAvailableP2PPacketSize(0)
	if packet_size > 0:
		var packet: Dictionary = Steam.readP2PPacket(packet_size, 0)
		if packet.is_empty():
			print("WARNING: read an empty packet with non-zero size!")
			return

		var packet_sender: int = packet['remote_steam_id']
		var packet_data: PackedByteArray = packet['data']
		var readable: Dictionary = bytes_to_var(packet_data)

		_handle_packet(packet_sender, readable)

func _handle_packet(sender_steam_id: int, data: Dictionary):
	var packet_type = data.get("type", -999)

	match packet_type:
		PacketType.HANDSHAKE:
			print("Handshake from: %s" % Steam.getFriendPersonaName(sender_steam_id))

		PacketType.PLAYER_STATE:
			var state = {
				"position": Vector3(data.px, data.py, data.pz),
				"rotation_y": data.ry,
				"camera_rotation_x": data.cx
			}
			player_state_received.emit(sender_steam_id, state)

		PacketType.GAME_START:
			print("Received GAME_START from host!")
			game_started.emit()

		_:
			print("Unknown packet type: %s" % packet_type)

# ============ PLAYER TRACKING ============

func register_player(steam_id: int, player_node: Node):
	players_in_game[steam_id] = player_node

func unregister_player(steam_id: int):
	players_in_game.erase(steam_id)

func get_player(steam_id: int) -> Node:
	return players_in_game.get(steam_id, null)

# ============ CLEANUP ============

func close_all_sessions():
	for member in LobbyManager.lobby_members:
		if member['steam_id'] != Steam.getSteamID():
			Steam.closeP2PSessionWithUser(member['steam_id'])
	players_in_game.clear()
