extends Node

## Network Manager
##
## Handles Steam P2P networking for player state synchronization.
## Based on official GodotSteam networking tutorial.

signal player_state_received(steam_id: int, state: Dictionary)
signal game_started()
signal voice_data_received(steam_id: int, audio_data: PackedByteArray)
signal health_update_received(steam_id: int, health: int)
signal role_assigned(is_impostor: bool)
signal item_picked_up(steam_id: int, item_id: String)
signal taser_shot_received(steam_id: int, origin: Vector3, direction: Vector3)
signal taser_hit_received(damage: int)
signal progress_update_received(progress: float, speed: float)
signal game_over_received(impostor_won: bool)
signal play_again_received()
signal elevator_used(action: String, floor_name: String)
signal emergency_meeting_called()
signal timer_sync_received(arrival_time: float, speed: float)
signal ship_integrity_update_received(sender_steam_id: int, integrity: float)

const PACKET_READ_LIMIT: int = 32

# Packet types
enum PacketType {
	PLAYER_STATE,
	GAME_START,
	HANDSHAKE,
	VOICE_DATA,
	HEALTH_UPDATE,
	ROLE_ASSIGNMENT,
	ITEM_PICKUP,
	TASER_SHOT,
	TASER_HIT,
	PROGRESS_UPDATE,
	GAME_OVER,
	PLAY_AGAIN,
	ELEVATOR_USE,
	EMERGENCY_MEETING,
	TIMER_SYNC,
	SHIP_INTEGRITY
}

var players_in_game: Dictionary = {}  # steam_id -> player node

# Buffered role assignment (in case packet arrives before player scene loads)
var pending_role_received: bool = false
var pending_role_impostor: bool = false

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

func send_role_assignment(target_steam_id: int, is_impostor: bool):
	send_p2p_packet(target_steam_id, {"type": PacketType.ROLE_ASSIGNMENT, "impostor": is_impostor}, Steam.P2P_SEND_RELIABLE, 0)

func send_health_update(health: int):
	send_p2p_packet(0, {"type": PacketType.HEALTH_UPDATE, "hp": health}, Steam.P2P_SEND_RELIABLE, 0)

func send_voice_data(compressed_audio: PackedByteArray):
	send_p2p_packet(0, {"type": PacketType.VOICE_DATA, "audio": compressed_audio}, Steam.P2P_SEND_UNRELIABLE, 0)

func send_taser_hit(target_steam_id: int, damage: int):
	send_p2p_packet(target_steam_id, {"type": PacketType.TASER_HIT, "dmg": damage}, Steam.P2P_SEND_RELIABLE, 0)

func send_taser_shot(origin: Vector3, direction: Vector3):
	var data = {
		"type": PacketType.TASER_SHOT,
		"ox": origin.x, "oy": origin.y, "oz": origin.z,
		"dx": direction.x, "dy": direction.y, "dz": direction.z
	}
	send_p2p_packet(0, data, Steam.P2P_SEND_RELIABLE, 0)
	taser_shot_received.emit(Steam.getSteamID(), origin, direction)

func send_item_pickup(item_id: String):
	send_p2p_packet(0, {"type": PacketType.ITEM_PICKUP, "item_id": item_id, "picker": Steam.getSteamID()}, Steam.P2P_SEND_RELIABLE, 0)
	item_picked_up.emit(Steam.getSteamID(), item_id)

func send_progress_update(progress: float, speed: float):
	send_p2p_packet(0, {"type": PacketType.PROGRESS_UPDATE, "prog": progress, "spd": speed}, Steam.P2P_SEND_RELIABLE, 0)

func send_game_start():
	send_p2p_packet(0, {"type": PacketType.GAME_START}, Steam.P2P_SEND_RELIABLE, 0)
	game_started.emit()

func send_game_over(impostor_won: bool):
	send_p2p_packet(0, {"type": PacketType.GAME_OVER, "impostor_won": impostor_won}, Steam.P2P_SEND_RELIABLE, 0)
	game_over_received.emit(impostor_won)

func send_play_again():
	send_p2p_packet(0, {"type": PacketType.PLAY_AGAIN}, Steam.P2P_SEND_RELIABLE, 0)
	play_again_received.emit()

func send_elevator_use(action: String, floor_name: String):
	send_p2p_packet(0, {"type": PacketType.ELEVATOR_USE, "action": action, "floor": floor_name}, Steam.P2P_SEND_RELIABLE, 0)

func send_emergency_meeting():
	send_p2p_packet(0, {"type": PacketType.EMERGENCY_MEETING}, Steam.P2P_SEND_RELIABLE, 0)
	emergency_meeting_called.emit()

func send_timer_sync(arrival: float, speed: float):
	send_p2p_packet(0, {"type": PacketType.TIMER_SYNC, "arrival": arrival, "spd": speed}, Steam.P2P_SEND_RELIABLE, 0)

func send_ship_integrity_update(integrity: float):
	send_p2p_packet(0, {"type": PacketType.SHIP_INTEGRITY, "integrity": integrity}, Steam.P2P_SEND_RELIABLE, 0)
	ship_integrity_update_received.emit(Steam.getSteamID(), integrity)

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

		PacketType.VOICE_DATA:
			voice_data_received.emit(sender_steam_id, data.get("audio", PackedByteArray()))

		PacketType.HEALTH_UPDATE:
			health_update_received.emit(sender_steam_id, data.get("hp", 0))

		PacketType.ROLE_ASSIGNMENT:
			var is_imp = data.get("impostor", false)
			pending_role_received = true
			pending_role_impostor = is_imp
			role_assigned.emit(is_imp)

		PacketType.ITEM_PICKUP:
			var picker_id = data.get("picker", 0)
			var item_id = data.get("item_id", "")
			item_picked_up.emit(picker_id, item_id)

		PacketType.TASER_SHOT:
			var origin = Vector3(data.get("ox", 0), data.get("oy", 0), data.get("oz", 0))
			var direction = Vector3(data.get("dx", 0), data.get("dy", 0), data.get("dz", 0))
			taser_shot_received.emit(sender_steam_id, origin, direction)

		PacketType.TASER_HIT:
			taser_hit_received.emit(data.get("dmg", 0))

		PacketType.PROGRESS_UPDATE:
			progress_update_received.emit(data.get("prog", 0.0), data.get("spd", 1.0))

		PacketType.GAME_OVER:
			game_over_received.emit(data.get("impostor_won", false))

		PacketType.PLAY_AGAIN:
			play_again_received.emit()

		PacketType.ELEVATOR_USE:
			elevator_used.emit(data.get("action", ""), data.get("floor", ""))

		PacketType.EMERGENCY_MEETING:
			emergency_meeting_called.emit()

		PacketType.TIMER_SYNC:
			timer_sync_received.emit(data.get("arrival", 0.0), data.get("spd", 1.0))

		PacketType.SHIP_INTEGRITY:
			ship_integrity_update_received.emit(sender_steam_id, data.get("integrity", 100.0))
	
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
	pending_role_received = false
	pending_role_impostor = false
