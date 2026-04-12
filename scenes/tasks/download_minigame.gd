extends Control

signal minigame_completed
signal minigame_cancelled

var download_progress = 0.0
var packet_pos = 0.0
var packet_dir = 1
var packet_speed = 300.0

var progress_bar: ProgressBar
var packet_node: ColorRect
var signal_zone: ColorRect
var game_panel: Panel

var is_downloading = false
var game_active = false

# Sound effects
@onready var complete_sound: AudioStreamPlayer = $SelectGranted

func start_game():
	create_ui()
	game_active = true

func _input(event):
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		emit_signal("minigame_cancelled")
		queue_free()

func create_ui():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	game_panel = Panel.new()
	game_panel.custom_minimum_size = Vector2(500, 300)
	add_child(game_panel)
	game_panel.set_anchors_preset(Control.PRESET_CENTER)
	game_panel.set_anchor_and_offset(SIDE_LEFT, 0.5, -250)
	game_panel.set_anchor_and_offset(SIDE_TOP, 0.5, -150)

	var title = Label.new()
	title.text = "INTERCEPT DATA STREAM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.custom_minimum_size = Vector2(500, 30)
	game_panel.add_child(title)

	# --- The Rail ---
	var rail = ColorRect.new()
	rail.color = Color(0.2, 0.2, 0.2)
	rail.size = Vector2(400, 10)
	rail.position = Vector2(50, 100)
	game_panel.add_child(rail)

	# The Signal Zone (Target area in middle of rail)
	signal_zone = ColorRect.new()
	signal_zone.color = Color(0, 0.8, 0.8, 0.3) # Cyan translucent
	signal_zone.size = Vector2(100, 40)
	signal_zone.position = Vector2(200, 85)
	game_panel.add_child(signal_zone)

	# The Moving Packet
	packet_node = ColorRect.new()
	packet_node.color = Color(1, 1, 1)
	packet_node.size = Vector2(20, 20)
	packet_node.position = Vector2(50, 95)
	game_panel.add_child(packet_node)

	# --- Progress Bar ---
	progress_bar = ProgressBar.new()
	progress_bar.size = Vector2(400, 20)
	progress_bar.position = Vector2(50, 180)
	progress_bar.max_value = 100
	game_panel.add_child(progress_bar)

	# --- Interaction ---
	var btn = Button.new()
	btn.text = "HOLD TO DOWNLOAD"
	btn.custom_minimum_size = Vector2(200, 50)
	btn.position = Vector2(150, 230)
	btn.button_down.connect(func(): is_downloading = true)
	btn.button_up.connect(func(): is_downloading = false)
	game_panel.add_child(btn)

func _process(delta):
	if not game_active: return

	# 1. Move the packet back and forth
	packet_pos += packet_speed * packet_dir * delta
	if packet_pos > 380: # Right edge
		packet_pos = 380
		packet_dir = -1
	elif packet_pos < 0: # Left edge
		packet_pos = 0
		packet_dir = 1
	
	packet_node.position.x = 50 + packet_pos

	# 2. Check if downloading while in zone
	var in_zone = packet_node.get_rect().intersects(signal_zone.get_rect())
	
	if is_downloading:
		if in_zone:
			download_progress += 40 * delta # Progress gain
			packet_node.modulate = Color.CYAN
		else:
			download_progress -= 15 * delta # Penalty for missing
			packet_node.modulate = Color.RED
	else:
		packet_node.modulate = Color.WHITE

	download_progress = clamp(download_progress, 0, 100)
	progress_bar.value = download_progress

	if download_progress >= 100:
		finish_game()

func finish_game():
	game_active = false
	complete_sound.play()
	var l = Label.new()
	l.text = "DECRYPTION COMPLETE"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 145)
	l.custom_minimum_size = Vector2(500, 30)
	game_panel.add_child(l)
	
	await get_tree().create_timer(1.2).timeout
	emit_signal("minigame_completed")
	queue_free()
