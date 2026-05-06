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
signal elevator_door_opened(door_id: String)
signal elevator_door_closed(door_id: String)
signal emergency_meeting_called()
signal timer_sync_received(arrival_time: float, speed: float)
signal door_opened(door_id: String)
signal door_closed(door_id: String)
signal ship_integrity_update_received(sender_steam_id: int, integrity: float)
signal taser_hide_received(steam_id: int, hidden: bool)
signal armory_button_changed(button_id: String, pressed: bool)
signal punch_received(steam_id: int)
signal baton_swing_received(steam_id: int)
signal item_dropped_received(item_id: String, tranform: Transform3D, uses: int)
signal taser_dead(steam_id: int)
signal sabotage_received(sabotage_type: String)
signal possess_start_received(impostor_steam_id: int, target_steam_id: int)
signal possess_move_received(target_steam_id: int, move_dir: Vector3, rotation_y: float, cam_rotation_x: float)
signal possess_end_received(target_steam_id: int)
signal possess_action_received(target_steam_id: int, action: String)
signal door_lock_received(door_id: String, locked: bool)
signal hide_update_recieved(locker_id: String, io: bool, steam_id: int)
signal emote_received(steam_id: int, emote_name: String)
signal body_reported(victim_name: String, reporter_name: String)
# Dedicated death broadcast — fires when any player has entered dead state.
# Redundant with HEALTH_UPDATE so a single-packet drop can't leave a dead
# player appearing alive on remote clients.
signal player_died_received(dead_steam_id: int)
# Dedicated visual-equip broadcast. ITEM_PICKUP already kicks remote clients
# into give_baton/give_taser, but field reports show the weapon model
# sometimes not appearing on the picker's remote model. This is a redundant
# explicit "attach this weapon to this player" message that other clients
# act on idempotently.
signal weapon_equipped_received(equipper_steam_id: int, weapon_type: String, uses: int)

const PACKET_READ_LIMIT: int = 32

# Marker byte for the manually-serialized PLAYER_STATE packet. var_to_bytes
# encodes a Dictionary with type=27 (TYPE_DICTIONARY) in the first byte, so
# 0xFF is unambiguously our binary format. Cuts ~75% off PLAYER_STATE
# bandwidth and dodges the var_to_bytes / bytes_to_var path on the hot loop.
const _PACKET_MAGIC_PLAYER_STATE: int = 0xFF
const _PLAYER_STATE_PACKET_SIZE: int = 22

# Packet types
enum PacketType {
	PLAYER_STATE,
	GAME_START,
	HANDSHAKE,
	VOICE_DATA,
	HEALTH_UPDATE,
	ROLE_ASSIGNMENT,
	ITEM_PICKUP,
	ITEM_DROP,
	TASER_SHOT,
	TASER_HIT,
	PROGRESS_UPDATE,
	GAME_OVER,
	PLAY_AGAIN,
	ELEVATOR_USE,
	ELEVATOR_DOOR_STATE_CHANGE,
	EMERGENCY_MEETING,
	TIMER_SYNC,
	DOOR_STATE_CHANGE,
	SHIP_INTEGRITY,
	TASER_HIDE,
	ARMORY_BUTTON,
	PUNCH,
	BATON_SWING,
	TASER_DEAD,
	SABOTAGE,
	POSSESS_START,
	POSSESS_MOVE,
	POSSESS_END,
	POSSESS_ACTION,
	DOOR_LOCK,
	HIDE_UPDATE,
	EMOTE,
	BODY_REPORTED,
	PLAYER_DIED,
	WEAPON_EQUIPPED
}

var players_in_game: Dictionary = {}  # steam_id -> player node
var possessed_players: Dictionary = {}  # target_steam_id -> impostor_steam_id

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

	var packet_type_id = packet_data.get("type", -1)
	# Diagnostic: print broadcasts of any "important" one-shot packet so we
	# can correlate host send vs client receive in the console. Not for
	# PLAYER_STATE / VOICE_DATA — too noisy.
	var noisy_types: Array = [
		PacketType.PLAYER_STATE,
		PacketType.VOICE_DATA,
		PacketType.POSSESS_MOVE,
	]

	# target == 0 means broadcast to all lobby members
	if target == 0:
		var my_steam_id = Steam.getSteamID()
		var member_count := LobbyManager.lobby_members.size()
		var sent_to: Array = []
		if member_count > 1:
			for member in LobbyManager.lobby_members:
				if member['steam_id'] != my_steam_id:
					var ok = Steam.sendP2PPacket(member['steam_id'], this_data, send_type, channel)
					sent_to.append({"id": member['steam_id'], "ok": ok})
		if not noisy_types.has(packet_type_id):
			print("[SEND] type=%d host=%s lobby_members=%d sent_to=%s" % [
				packet_type_id, str(LobbyManager.is_host()), member_count, str(sent_to)
			])
	else:
		var ok = Steam.sendP2PPacket(target, this_data, send_type, channel)
		if not noisy_types.has(packet_type_id):
			print("[SEND] type=%d host=%s direct_target=%d ok=%s" % [
				packet_type_id, str(LobbyManager.is_host()), target, str(ok)
			])

func send_player_state(position: Vector3, rotation_y: float, camera_rotation_x: float, is_moving: bool = false, is_moving_backward: bool = false):
	# Reverted from manual binary encoding back to Dictionary serialization.
	# The binary path was suspected of breaking host->client P2P delivery
	# (asymmetric packet loss). Idle-suppression in the player_controller
	# already cuts most of the traffic; the per-packet CPU win from binary
	# encoding wasn't worth the reliability risk.
	var data = {
		"type": PacketType.PLAYER_STATE,
		"px": position.x,
		"py": position.y,
		"pz": position.z,
		"ry": rotation_y,
		"cx": camera_rotation_x,
		"mv": is_moving,
		"mb": is_moving_backward
	}
	send_p2p_packet(0, data, Steam.P2P_SEND_UNRELIABLE, 0)

func _send_raw_p2p(target: int, data: PackedByteArray, send_type: int, channel: int) -> void:
	# Same fan-out logic as send_p2p_packet but without re-serializing the
	# already-encoded byte array.
	if target == 0:
		var my_steam_id = Steam.getSteamID()
		if LobbyManager.lobby_members.size() > 1:
			for member in LobbyManager.lobby_members:
				if member['steam_id'] != my_steam_id:
					Steam.sendP2PPacket(member['steam_id'], data, send_type, channel)
	else:
		Steam.sendP2PPacket(target, data, send_type, channel)

func send_role_assignment(target_steam_id: int, is_impostor: bool, impostor_ids: Array = [], anon_impostors: bool = false):
	var data = {"type": PacketType.ROLE_ASSIGNMENT, "impostor": is_impostor, "impostor_ids": impostor_ids, "anon_imp": anon_impostors}
	send_p2p_packet(target_steam_id, data, Steam.P2P_SEND_RELIABLE, 0)
	# Retransmit at +0.5s and +2s so VPN/flaky-network players still get
	# their role even if the first packet drops. Receiver gates on
	# _role_received so duplicates are no-ops.
	_retransmit_packet(target_steam_id, data, [0.5, 2.0])

func send_health_update(health: int):
	send_p2p_packet(0, {"type": PacketType.HEALTH_UPDATE, "hp": health}, Steam.P2P_SEND_RELIABLE, 0)

func send_player_died(dead_steam_id: int):
	# Broadcast even though the dead player's steam_id is implicitly the
	# sender — explicit field lets recipients handle relayed death (e.g.,
	# host announcing a player's death) and stay forwards-compatible.
	var data = {"type": PacketType.PLAYER_DIED, "dead_id": dead_steam_id}
	send_p2p_packet(0, data, Steam.P2P_SEND_RELIABLE, 0)
	# Retransmits — _enter_dead_state is idempotent on is_dead, so safe.
	_retransmit_packet(0, data, [0.5, 2.0])

func send_weapon_equipped(weapon_type: String, uses: int = 0):
	# Broadcast that the local player now visibly holds this weapon. Receivers
	# attach the model to their copy of this player. Independent of
	# ITEM_PICKUP so the model attaches reliably even if the pickup-handler
	# path fails for any reason.
	var data = {"type": PacketType.WEAPON_EQUIPPED, "weapon": weapon_type, "uses": uses}
	send_p2p_packet(0, data, Steam.P2P_SEND_RELIABLE, 0)
	# Retransmits — receiver drops + reattaches each time, which is a no-op
	# if the model is already correct.
	_retransmit_packet(0, data, [0.5, 2.0])

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

func send_item_dropped(item_id: String, transform: Transform3D, uses: int = 0) -> void:
	var pos = transform.origin
	var rot = transform.basis.get_euler()
	
	var data = {
		"type": PacketType.ITEM_DROP,
		"item_id": item_id,
		"position": { "x": pos.x, "y": pos.y, "z": pos.z},
		"rotation": {"x": rot.x, "y": rot.y, "z": rot.z},
		"uses": uses
	}
	send_p2p_packet(0, data, Steam.P2P_SEND_RELIABLE)

func send_taser_hide(hidden: bool):
	send_p2p_packet(0, {"type": PacketType.TASER_HIDE, "hidden": hidden}, Steam.P2P_SEND_RELIABLE, 0)

func send_progress_update(progress: float, speed: float):
	send_p2p_packet(0, {"type": PacketType.PROGRESS_UPDATE, "prog": progress, "spd": speed}, Steam.P2P_SEND_RELIABLE, 0)

func send_game_start():
	send_p2p_packet(0, {"type": PacketType.GAME_START}, Steam.P2P_SEND_RELIABLE, 0)
	game_started.emit()

func send_game_over(impostor_won: bool):
	send_p2p_packet(0, {"type": PacketType.GAME_OVER, "impostor_won": impostor_won}, Steam.P2P_SEND_RELIABLE, 0)
	game_over_received.emit(impostor_won)

# Broadcast-only variant for retransmits — does NOT emit locally, since the
# host already showed their end screen on the first send_game_over call.
func resend_game_over(impostor_won: bool):
	send_p2p_packet(0, {"type": PacketType.GAME_OVER, "impostor_won": impostor_won}, Steam.P2P_SEND_RELIABLE, 0)

# Schedule N retransmits of the same packet at the given delays. Useful for
# important reliable packets that must reach players on flaky networks
# (e.g., VPNs that disrupt Steam P2P) — duplicates are absorbed by
# idempotent receive handlers, so this is safe.
func _retransmit_packet(target: int, packet_data: Dictionary, delays: Array) -> void:
	for d in delays:
		await get_tree().create_timer(d).timeout
		# Bail if the lobby has been left in the meantime.
		if LobbyManager.lobby_id == 0:
			return
		send_p2p_packet(target, packet_data, Steam.P2P_SEND_RELIABLE, 0)

func send_play_again():
	send_p2p_packet(0, {"type": PacketType.PLAY_AGAIN}, Steam.P2P_SEND_RELIABLE, 0)
	play_again_received.emit()

func send_elevator_use(action: String, floor_name: String):
	send_p2p_packet(0, {"type": PacketType.ELEVATOR_USE, "action": action, "floor": floor_name}, Steam.P2P_SEND_RELIABLE, 0)
	elevator_used.emit(action, floor_name)

func send_elevator_door_state_change(door_id: String, action: String):
	send_p2p_packet(0, {"type": PacketType.ELEVATOR_DOOR_STATE_CHANGE, "door_id": door_id, "action": action}, Steam.P2P_SEND_RELIABLE, 0)
	if action == "open":
		elevator_door_opened.emit(door_id)
	else:
		elevator_door_closed.emit(door_id)

func send_emergency_meeting():
	send_p2p_packet(0, {"type": PacketType.EMERGENCY_MEETING}, Steam.P2P_SEND_RELIABLE, 0)
	emergency_meeting_called.emit()

func send_body_reported(victim_name: String):
	var reporter_name = Steam.getPersonaName()
	send_p2p_packet(0, {"type": PacketType.BODY_REPORTED, "victim": victim_name, "reporter": reporter_name}, Steam.P2P_SEND_RELIABLE, 0)
	body_reported.emit(victim_name, reporter_name)

func send_timer_sync(arrival: float, speed: float):
	send_p2p_packet(0, {"type": PacketType.TIMER_SYNC, "arrival": arrival, "spd": speed}, Steam.P2P_SEND_RELIABLE, 0)

func send_ship_integrity_update(integrity: float):
	send_p2p_packet(0, {"type": PacketType.SHIP_INTEGRITY, "integrity": integrity}, Steam.P2P_SEND_RELIABLE, 0)
	ship_integrity_update_received.emit(Steam.getSteamID(), integrity)

func send_door_state_change(door_id: String, action: String):
	send_p2p_packet(0, {"type": PacketType.DOOR_STATE_CHANGE, "door_id": door_id, "action": action}, Steam.P2P_SEND_RELIABLE, 0)

func send_punch():
	send_p2p_packet(0, {"type": PacketType.PUNCH}, Steam.P2P_SEND_RELIABLE, 0)

func send_baton_swing():
	send_p2p_packet(0, {"type": PacketType.BATON_SWING}, Steam.P2P_SEND_RELIABLE, 0)

func send_armory_button(button_id: String, pressed: bool):
	send_p2p_packet(0, {"type": PacketType.ARMORY_BUTTON, "button_id": button_id, "pressed": pressed}, Steam.P2P_SEND_RELIABLE, 0)
	armory_button_changed.emit(button_id, pressed)

func send_taser_dead(target_id: int):
	send_p2p_packet(0, {"type": PacketType.TASER_DEAD, "steam_id": target_id }, Steam.P2P_SEND_RELIABLE, 0)
	taser_dead.emit(target_id)

func send_sabotage(sabotage_type: String):
	send_p2p_packet(0, {"type": PacketType.SABOTAGE, "sabotage_type": sabotage_type}, Steam.P2P_SEND_RELIABLE, 0)
	sabotage_received.emit(sabotage_type)

func send_possess_start(target_steam_id: int):
	possessed_players[target_steam_id] = Steam.getSteamID()
	send_p2p_packet(0, {"type": PacketType.POSSESS_START, "impostor_id": Steam.getSteamID(), "target": target_steam_id}, Steam.P2P_SEND_RELIABLE, 0)

func send_possess_move(target_steam_id: int, move_dir: Vector3, rot_y: float, cam_rot_x: float):
	var data = {
		"type": PacketType.POSSESS_MOVE,
		"target": target_steam_id,
		"mx": move_dir.x, "my": move_dir.y, "mz": move_dir.z,
		"ry": rot_y, "cx": cam_rot_x
	}
	send_p2p_packet(target_steam_id, data, Steam.P2P_SEND_UNRELIABLE, 0)

func send_possess_end(target_steam_id: int):
	possessed_players.erase(target_steam_id)
	send_p2p_packet(0, {"type": PacketType.POSSESS_END, "target": target_steam_id}, Steam.P2P_SEND_RELIABLE, 0)

func send_possess_action(target_steam_id: int, action: String):
	send_p2p_packet(target_steam_id, {"type": PacketType.POSSESS_ACTION, "target": target_steam_id, "action": action}, Steam.P2P_SEND_RELIABLE, 0)

func send_door_lock(door_id: String, locked: bool):
	send_p2p_packet(0, {"type": PacketType.DOOR_LOCK, "door_id": door_id, "locked": locked}, Steam.P2P_SEND_RELIABLE, 0)
	door_lock_received.emit(door_id, locked)
	
func send_emote(emote_name: String):
	send_p2p_packet(0, {"type": PacketType.EMOTE, "emote_name": emote_name}, Steam.P2P_SEND_RELIABLE, 0)

func send_hide_update(cabinet_id: String, io: bool, steam_id: int):
	send_p2p_packet(0, {"type": PacketType.HIDE_UPDATE, "cabinet_id": cabinet_id, "io": io, "target": steam_id})
	hide_update_recieved.emit(cabinet_id,io,steam_id)
# ============ READ PACKETS ============

func _read_all_p2p_packets(read_count: int = 0):
	# Reverted to original recursive form. The iterative loop was suspected
	# of contributing to a host->client P2P regression; reverting to the
	# baseline behavior to isolate.
	if read_count >= PACKET_READ_LIMIT:
		return
	if Steam.getAvailableP2PPacketSize(0) > 0:
		_read_p2p_packet()
		_read_all_p2p_packets(read_count + 1)

# Discard any queued P2P packets without dispatching their signals. Called
# at the start of a new round so stale damage/death/state packets from the
# previous round can't immediately re-kill or desync a freshly-spawned player.
func flush_packet_queue() -> void:
	var dropped := 0
	# No PACKET_READ_LIMIT here — we want to fully drain whatever's queued.
	while Steam.getAvailableP2PPacketSize(0) > 0:
		var size: int = Steam.getAvailableP2PPacketSize(0)
		Steam.readP2PPacket(size, 0)
		dropped += 1
		if dropped > 1024:
			# Safety cap so a malicious sender can't wedge us in this loop.
			break
	if dropped > 0:
		print("flush_packet_queue: discarded %d stale packets" % dropped)

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
	# Diagnostic: log non-noisy packet receives so we can see whether broadcasts
	# from the host (or anyone) are landing on this client.
	if packet_type != PacketType.PLAYER_STATE and packet_type != PacketType.VOICE_DATA and packet_type != PacketType.POSSESS_MOVE:
		print("[RECV] type=%d from=%d host=%s" % [
			packet_type, sender_steam_id, str(LobbyManager.is_host())
		])

	match packet_type:
		PacketType.HANDSHAKE:
			print("Handshake from: %s" % Steam.getFriendPersonaName(sender_steam_id))

		PacketType.PLAYER_STATE:
			var state = {
				"position": Vector3(data.px, data.py, data.pz),
				"rotation_y": data.ry,
				"camera_rotation_x": data.cx,
				"is_moving": data.get("mv", false),
				"is_moving_backward": data.get("mb", false)
			}
			player_state_received.emit(sender_steam_id, state)

		PacketType.GAME_START:
			print("Received GAME_START from host!")
			game_started.emit()

		PacketType.VOICE_DATA:
			voice_data_received.emit(sender_steam_id, data.get("audio", PackedByteArray()))

		PacketType.HEALTH_UPDATE:
			health_update_received.emit(sender_steam_id, data.get("hp", 0))

		PacketType.PLAYER_DIED:
			player_died_received.emit(data.get("dead_id", sender_steam_id))

		PacketType.WEAPON_EQUIPPED:
			weapon_equipped_received.emit(sender_steam_id, data.get("weapon", ""), data.get("uses", 0))

		PacketType.ROLE_ASSIGNMENT:
			var is_imp = data.get("impostor", false)
			var imp_ids = data.get("impostor_ids", [])
			pending_role_received = true
			pending_role_impostor = is_imp
			# Sync anonymous impostors setting from host
			GameManager.anonymous_impostors = data.get("anon_imp", false)
			# Mark impostor flags on player nodes so clients know who is who
			for imp_id in imp_ids:
				var p = get_player(imp_id)
				if p and "is_impostor" in p:
					p.is_impostor = true
			role_assigned.emit(is_imp)

		PacketType.ITEM_PICKUP:
			var picker_id = data.get("picker", 0)
			var item_id = data.get("item_id", "")
			item_picked_up.emit(picker_id, item_id)
			
		PacketType.ITEM_DROP:
			var id = data.item_id
			var pos = Vector3(data.position.x, data.position.y, data.position.z)
			var rot = Vector3(data.rotation.x, data.rotation.y, data.rotation.z)
			var transform = Transform3D(Basis.from_euler(rot), pos)
			var uses = data.get("uses", 0)
			item_dropped_received.emit(id, transform, uses)

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

		PacketType.ELEVATOR_DOOR_STATE_CHANGE:
			if data.get("action") == "open":
				elevator_door_opened.emit(data.get("door_id"))
			elif data.get("action") == "close":
				elevator_door_closed.emit(data.get("door_id"))

		PacketType.EMERGENCY_MEETING:
			emergency_meeting_called.emit()

		PacketType.BODY_REPORTED:
			body_reported.emit(data.get("victim", ""), data.get("reporter", ""))

		PacketType.TIMER_SYNC:
			timer_sync_received.emit(data.get("arrival", 0.0), data.get("spd", 1.0))

		PacketType.SHIP_INTEGRITY:
			ship_integrity_update_received.emit(sender_steam_id, data.get("integrity", 100.0))
	
		PacketType.DOOR_STATE_CHANGE:
			if data.get("action", "") == "open":
				door_opened.emit(data.get("door_id", ""))
			elif data.get("action", "") == "close":
				door_closed.emit(data.get("door_id", ""))

		PacketType.TASER_HIDE:
			taser_hide_received.emit(sender_steam_id, data.get("hidden", false))

		PacketType.ARMORY_BUTTON:
			armory_button_changed.emit(data.get("button_id", ""), data.get("pressed", false))

		PacketType.PUNCH:
			punch_received.emit(sender_steam_id)

		PacketType.BATON_SWING:
			baton_swing_received.emit(sender_steam_id)

		PacketType.TASER_DEAD:
			taser_dead.emit(sender_steam_id)
		PacketType.SABOTAGE:
			sabotage_received.emit(data.get("sabotage_type", ""))
		PacketType.POSSESS_START:
			var target_id = data.get("target", 0)
			possessed_players[target_id] = data.get("impostor_id", 0)
			possess_start_received.emit(data.get("impostor_id", 0), target_id)
		PacketType.POSSESS_MOVE:
			var dir = Vector3(data.get("mx", 0), data.get("my", 0), data.get("mz", 0))
			possess_move_received.emit(data.get("target", 0), dir, data.get("ry", 0.0), data.get("cx", 0.0))
		PacketType.POSSESS_END:
			var end_target_id = data.get("target", 0)
			possessed_players.erase(end_target_id)
			possess_end_received.emit(end_target_id)
		PacketType.POSSESS_ACTION:
			possess_action_received.emit(data.get("target", 0), data.get("action", ""))
		PacketType.DOOR_LOCK:
			door_lock_received.emit(data.get("door_id", ""), data.get("locked", false))
		PacketType.HIDE_UPDATE:
			hide_update_recieved.emit(data.get("locker_id", ""), data.get("io", false), data.get("target", 0))
		PacketType.EMOTE:
			emote_received.emit(sender_steam_id, data.get("emote_name", ""))
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
	possessed_players.clear()
	pending_role_received = false
	pending_role_impostor = false
