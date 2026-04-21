extends Node

## Voice Manager
##
## Handles always-on proximity voice chat using Steam Voice API.
## Records from the local mic, sends compressed audio over P2P,
## and plays received audio through AudioStreamPlayer3D on remote
## players so volume attenuates with distance.

# Optimal sample rate from Steam
var sample_rate: int = 0

# Whether voice recording is active
var is_active: bool = false

# Playback streams per remote player: steam_id -> AudioStreamGeneratorPlayback
var voice_playbacks: Dictionary = {}

# AudioStreamPlayer3D nodes per remote player: steam_id -> AudioStreamPlayer3D
var voice_players: Dictionary = {}

# Non-proximity "dead chat" playback per dead remote: steam_id -> AudioStreamGeneratorPlayback
var dead_voice_playbacks: Dictionary = {}

# Non-proximity "dead chat" players per dead remote: steam_id -> AudioStreamPlayer
var dead_voice_players: Dictionary = {}

# When true, dead senders are filtered: living listeners drop their audio and
# dead listeners route them through the non-proximity dead-chat stream.
var dead_chat_enabled: bool = true

# Voice scramble — uses a dedicated audio bus with AudioEffectPitchShift
var voice_scrambled: bool = false
const SCRAMBLE_PITCH: float = 1.6
const VOICE_BUS_NAME: String = "VoiceChat"
var _voice_bus_idx: int = -1

func _ready():
	NetworkManager.voice_data_received.connect(_on_voice_data_received)
	UIState.sabotage_triggered.connect(_on_sabotage_triggered)
	UIState.sabotage_ended.connect(_on_sabotage_ended)
	_setup_voice_bus()

func _setup_voice_bus() -> void:
	# Create a dedicated audio bus for voice chat
	var bus_count = AudioServer.bus_count
	AudioServer.add_bus(bus_count)
	_voice_bus_idx = bus_count
	AudioServer.set_bus_name(_voice_bus_idx, VOICE_BUS_NAME)
	AudioServer.set_bus_send(_voice_bus_idx, "Master")

	# Add a pitch shift effect (disabled by default)
	var pitch_effect = AudioEffectPitchShift.new()
	pitch_effect.pitch_scale = SCRAMBLE_PITCH
	AudioServer.add_bus_effect(_voice_bus_idx, pitch_effect)
	AudioServer.set_bus_effect_enabled(_voice_bus_idx, 0, false)

func set_voice_scramble(enabled: bool) -> void:
	voice_scrambled = enabled
	if _voice_bus_idx >= 0:
		AudioServer.set_bus_effect_enabled(_voice_bus_idx, 0, enabled)

func _on_sabotage_triggered(sabotage_type: String) -> void:
	if sabotage_type == "anonymous":
		set_voice_scramble(true)

func _on_sabotage_ended(sabotage_type: String) -> void:
	if sabotage_type == "anonymous":
		set_voice_scramble(false)

func _process(_delta):
	if not is_active:
		return
	_poll_and_send_voice()

# ============ RECORDING CONTROL ============

func start():
	sample_rate = Steam.getVoiceOptimalSampleRate()
	Steam.startVoiceRecording()
	Steam.setInGameVoiceSpeaking(Steam.getSteamID(), true)
	is_active = true
	print("Voice chat started (sample rate: %d)" % sample_rate)

func stop():
	if not is_active:
		return
	Steam.stopVoiceRecording()
	Steam.setInGameVoiceSpeaking(Steam.getSteamID(), false)
	is_active = false
	cleanup()
	print("Voice chat stopped")

# ============ SEND VOICE ============

func _poll_and_send_voice():
	# getVoice() returns compressed mic data; result 0 = OK
	var voice = Steam.getVoice()
	if voice["result"] != 0 or voice["written"] == 0:
		return

	NetworkManager.send_voice_data(voice["buffer"])

# ============ RECEIVE & PLAY VOICE ============

func _on_voice_data_received(sender_steam_id: int, compressed_audio: PackedByteArray):
	if not voice_playbacks.has(sender_steam_id):
		return
	if compressed_audio.is_empty():
		return

	var playback: AudioStreamGeneratorPlayback = _route_voice_playback(sender_steam_id)
	if playback == null:
		return

	var decompressed = Steam.decompressVoice(compressed_audio, sample_rate)
	if decompressed["result"] != 0:
		return

	var pcm_data: PackedByteArray = decompressed["uncompressed"]
	# "size" is the actual byte count of real audio — the rest of the buffer is empty
	var actual_byte_size: int = decompressed["size"]
	var num_samples: int = actual_byte_size / 2

	# Convert 16-bit signed PCM samples to float frames and push to audio stream
	for i in range(num_samples):
		if playback.can_push_buffer(1):
			var sample_value = pcm_data.decode_s16(i * 2) / 32768.0
			playback.push_frame(Vector2(sample_value, sample_value))

func _route_voice_playback(sender_steam_id: int) -> AudioStreamGeneratorPlayback:
	if not dead_chat_enabled:
		return voice_playbacks.get(sender_steam_id, null)
	var sender = NetworkManager.get_player(sender_steam_id)
	var sender_dead: bool = sender != null and "is_dead" in sender and sender.is_dead
	if not sender_dead:
		return voice_playbacks.get(sender_steam_id, null)
	var local_player = NetworkManager.get_player(Steam.getSteamID())
	var local_dead: bool = local_player != null and "is_dead" in local_player and local_player.is_dead
	if not local_dead:
		return null
	return _ensure_dead_voice_playback(sender_steam_id)

func _ensure_dead_voice_playback(sender_steam_id: int) -> AudioStreamGeneratorPlayback:
	if dead_voice_playbacks.has(sender_steam_id):
		return dead_voice_playbacks[sender_steam_id]
	var dead_player = AudioStreamPlayer.new()
	dead_player.name = "DeadVoicePlayer_%d" % sender_steam_id
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = float(sample_rate)
	stream.buffer_length = 0.5
	dead_player.stream = stream
	dead_player.bus = VOICE_BUS_NAME
	get_tree().root.add_child(dead_player)
	dead_player.play()
	dead_voice_players[sender_steam_id] = dead_player
	dead_voice_playbacks[sender_steam_id] = dead_player.get_stream_playback()
	return dead_voice_playbacks[sender_steam_id]

# ============ PLAYER SETUP ============

func setup_player_voice(steam_id: int, player_node: Node):
	if sample_rate == 0:
		sample_rate = Steam.getVoiceOptimalSampleRate()

	var voice_player = AudioStreamPlayer3D.new()
	voice_player.name = "VoicePlayer"

	var stream = AudioStreamGenerator.new()
	stream.mix_rate = float(sample_rate)
	stream.buffer_length = 0.5  # 500ms buffer to absorb network jitter

	voice_player.stream = stream
	voice_player.bus = VOICE_BUS_NAME

	# Proximity settings — voices fade with distance
	voice_player.max_distance = 20.0
	voice_player.unit_size = 5.0
	voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

	player_node.add_child(voice_player)
	voice_player.play()

	voice_playbacks[steam_id] = voice_player.get_stream_playback()
	voice_players[steam_id] = voice_player
	print("Voice setup for player: %s" % Steam.getFriendPersonaName(steam_id))

func disable_proximity():
	# Replace each 3D voice player with a non-positional AudioStreamPlayer
	# so audio plays at full volume regardless of distance
	for steam_id in voice_players.keys():
		var old_vp = voice_players[steam_id]
		if not is_instance_valid(old_vp):
			continue

		var new_vp = AudioStreamPlayer.new()
		new_vp.name = "VoicePlayerGlobal"
		var stream = AudioStreamGenerator.new()
		stream.mix_rate = float(sample_rate)
		stream.buffer_length = 0.5
		new_vp.stream = stream
		new_vp.bus = VOICE_BUS_NAME

		# Add to scene root so it's not tied to any player node
		old_vp.get_tree().root.add_child(new_vp)
		new_vp.play()

		# Swap references
		voice_playbacks[steam_id] = new_vp.get_stream_playback()
		voice_players[steam_id] = new_vp

		# Remove old 3D player
		old_vp.queue_free()

func remove_player_voice(steam_id: int):
	if voice_players.has(steam_id):
		voice_players[steam_id].queue_free()
		voice_players.erase(steam_id)
	voice_playbacks.erase(steam_id)
	if dead_voice_players.has(steam_id):
		if is_instance_valid(dead_voice_players[steam_id]):
			dead_voice_players[steam_id].queue_free()
		dead_voice_players.erase(steam_id)
	dead_voice_playbacks.erase(steam_id)

func disable_dead_chat():
	dead_chat_enabled = false
	for steam_id in dead_voice_players.keys():
		if dead_voice_players[steam_id] != null and is_instance_valid(dead_voice_players[steam_id]):
			dead_voice_players[steam_id].queue_free()
	dead_voice_playbacks.clear()
	dead_voice_players.clear()

func cleanup():
	for steam_id in voice_players.keys():
		if voice_players[steam_id] != null and is_instance_valid(voice_players[steam_id]):
			voice_players[steam_id].queue_free()
	voice_playbacks.clear()
	voice_players.clear()
	for steam_id in dead_voice_players.keys():
		if dead_voice_players[steam_id] != null and is_instance_valid(dead_voice_players[steam_id]):
			dead_voice_players[steam_id].queue_free()
	dead_voice_playbacks.clear()
	dead_voice_players.clear()
	dead_chat_enabled = true
