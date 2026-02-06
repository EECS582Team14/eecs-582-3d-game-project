extends Node

## Network Manager
##
## Handles Steam P2P networking for player state synchronization.
## Add this as an autoload singleton.

signal player_state_received(steam_id: int, state: Dictionary)
signal game_started()

const CHANNEL_PLAYER_STATE: int = 0
const CHANNEL_GAME_EVENTS: int = 1

# Packet types
enum PacketType {
	PLAYER_STATE,
	GAME_START,
	PLAYER_SPAWN
}

var players_in_game: Dictionary = {}  # steam_id -> player node

func _ready():
	# Connect to Steam P2P signals
	Steam.p2p_session_request.connect(_on_p2p_session_request)
	Steam.p2p_session_connect_fail.connect(_on_p2p_session_connect_fail)

func _process(_delta):
	_read_p2p_packets()

# ============ P2P SESSION MANAGEMENT ============

func _on_p2p_session_request(remote_steam_id: int):
	# Accept P2P sessions from lobby members
	var is_lobby_member = false
	for member in LobbyManager.lobby_members:
		if member.steam_id == remote_steam_id:
			is_lobby_member = true
			break

	if is_lobby_member:
		Steam.acceptP2PSessionWithUser(remote_steam_id)
		print("Accepted P2P session with: ", remote_steam_id)
	else:
		# Accept anyway if we're in a lobby - they might have just joined
		if LobbyManager.lobby_id != 0:
			Steam.acceptP2PSessionWithUser(remote_steam_id)
			print("Accepted P2P session (lobby active): ", remote_steam_id)
		else:
			print("Rejected P2P session from non-lobby member: ", remote_steam_id)

# Call this when joining a lobby to pre-establish P2P with all members
func establish_p2p_with_lobby():
	var my_steam_id = Steam.getSteamID()
	for member in LobbyManager.lobby_members:
		if member.steam_id != my_steam_id:
			# Send a ping packet to establish the P2P session
			var ping = {"type": -1}  # Ping packet
			Steam.sendP2PPacket(member.steam_id, var_to_bytes(ping), Steam.P2P_SEND_RELIABLE, CHANNEL_GAME_EVENTS)
			print("Establishing P2P with: ", member.steam_id)

func _on_p2p_session_connect_fail(steam_id: int, reason: int):
	print("P2P connection failed with ", steam_id, " reason: ", reason)

# ============ SEND PACKETS ============

func send_player_state(position: Vector3, rotation: float, camera_rotation: float):
	var data = {
		"type": PacketType.PLAYER_STATE,
		"pos_x": position.x,
		"pos_y": position.y,
		"pos_z": position.z,
		"rot_y": rotation,
		"cam_x": camera_rotation
	}
	_broadcast_to_lobby(data, CHANNEL_PLAYER_STATE, Steam.P2P_SEND_UNRELIABLE)

func send_game_start():
	var data = {
		"type": PacketType.GAME_START
	}
	_broadcast_to_lobby(data, CHANNEL_GAME_EVENTS, Steam.P2P_SEND_RELIABLE)
	game_started.emit()

func _broadcast_to_lobby(data: Dictionary, channel: int, send_type: int):
	var my_steam_id = Steam.getSteamID()
	var packed = var_to_bytes(data)

	for member in LobbyManager.lobby_members:
		if member.steam_id != my_steam_id:
			Steam.sendP2PPacket(member.steam_id, packed, send_type, channel)

# ============ READ PACKETS ============

func _read_p2p_packets():
	# Read from all channels
	for channel in [CHANNEL_PLAYER_STATE, CHANNEL_GAME_EVENTS]:
		var packet_size = Steam.getAvailableP2PPacketSize(channel)
		while packet_size > 0:
			var packet = Steam.readP2PPacket(packet_size, channel)
			if packet.is_empty():
				break

			var sender_steam_id: int = packet["steam_id_remote"]
			var data = bytes_to_var(packet["data"])

			_handle_packet(sender_steam_id, data)

			packet_size = Steam.getAvailableP2PPacketSize(channel)

func _handle_packet(sender_steam_id: int, data: Dictionary):
	var packet_type = data.get("type", -999)

	match packet_type:
		-1:
			# Ping packet for establishing P2P - just ignore
			print("P2P ping received from: ", sender_steam_id)

		PacketType.PLAYER_STATE:
			var state = {
				"position": Vector3(data.pos_x, data.pos_y, data.pos_z),
				"rotation_y": data.rot_y,
				"camera_rotation_x": data.cam_x
			}
			player_state_received.emit(sender_steam_id, state)

		PacketType.GAME_START:
			print("Received GAME_START from host!")
			game_started.emit()

		_:
			print("Unknown packet type: ", packet_type)

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
		Steam.closeP2PSessionWithUser(member.steam_id)
	players_in_game.clear()
