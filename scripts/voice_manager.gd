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

# Voice scramble state
var voice_scrambled: bool = false
const SCRAMBLE_PITCH: float = 1.6  # pitch up to make voices indiscernible

func _ready():
	NetworkManager.voice_data_received.connect(_on_voice_data_received)
	UIState.sabotage_triggered.connect(_on_sabotage_triggered)
	UIState.sabotage_ended.connect(_on_sabotage_ended)

func _on_sabotage_triggered(sabotage_type: String) -> void:
	if sabotage_type == "scramble_voices":
		voice_scrambled = true

func _on_sabotage_ended(sabotage_type: String) -> void:
	if sabotage_type == "scramble_voices":
		voice_scrambled = false

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

	var decompressed = Steam.decompressVoice(compressed_audio, sample_rate)
	if decompressed["result"] != 0:
		return

	var pcm_data: PackedByteArray = decompressed["uncompressed"]
	# "size" is the actual byte count of real audio — the rest of the buffer is empty
	var actual_byte_size: int = decompressed["size"]
	var num_samples: int = actual_byte_size / 2
	var playback: AudioStreamGeneratorPlayback = voice_playbacks[sender_steam_id]

	# Convert 16-bit signed PCM samples to float frames and push to audio stream
	if voice_scrambled:
		# Pitch shift by resampling — read samples at a different rate
		var out_samples = int(num_samples / SCRAMBLE_PITCH)
		for i in range(out_samples):
			if playback.can_push_buffer(1):
				var src_idx = int(i * SCRAMBLE_PITCH)
				if src_idx >= num_samples:
					break
				var sample_value = pcm_data.decode_s16(src_idx * 2) / 32768.0
				playback.push_frame(Vector2(sample_value, sample_value))
	else:
		for i in range(num_samples):
			if playback.can_push_buffer(1):
				var sample_value = pcm_data.decode_s16(i * 2) / 32768.0
				playback.push_frame(Vector2(sample_value, sample_value))

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

func cleanup():
	for steam_id in voice_players.keys():
		if voice_players[steam_id] != null and is_instance_valid(voice_players[steam_id]):
			voice_players[steam_id].queue_free()
	voice_playbacks.clear()
	voice_players.clear()
