extends Control

signal minigame_completed
signal minigame_cancelled

var goal_freq = 0.0
var goal_amp = 0.0
var current_freq = 1.0
var current_amp = 10.0

var wave_line: Line2D
var goal_line: Line2D
var game_panel: Panel

# Sound effects
@onready var complete_sound: AudioStreamPlayer = $SelectGranted

func start_game():
	# Randomize the target wave
	goal_freq = randf_range(2.0, 5.0)
	goal_amp = randf_range(20.0, 50.0)
	create_ui()

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
	game_panel.custom_minimum_size = Vector2(500, 400)
	add_child(game_panel)
	game_panel.set_anchors_preset(Control.PRESET_CENTER)
	game_panel.set_anchor_and_offset(SIDE_LEFT, 0.5, -250)
	game_panel.set_anchor_and_offset(SIDE_TOP, 0.5, -200)

	var title = Label.new()
	title.text = "MATCH SIGNAL FREQUENCY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.custom_minimum_size = Vector2(500, 30)
	game_panel.add_child(title)

	# --- Wave Display (The "Oscilloscope") ---
	var screen = ColorRect.new()
	screen.color = Color(0, 0.1, 0, 1) # Dark green CRT look
	screen.size = Vector2(400, 200)
	screen.position = Vector2(50, 60)
	game_panel.add_child(screen)

	# The Goal Wave (Static Ghost)
	goal_line = Line2D.new()
	goal_line.width = 2.0
	goal_line.default_color = Color(0, 1, 0, 0.3) # Faint Green
	screen.add_child(goal_line)

	# The Player Wave (Active)
	wave_line = Line2D.new()
	wave_line.width = 3.0
	wave_line.default_color = Color(0, 1, 0.2) # Bright Green
	screen.add_child(wave_line)

	# --- Controls ---
	var controls = VBoxContainer.new()
	controls.position = Vector2(50, 280)
	controls.custom_minimum_size = Vector2(400, 100)
	game_panel.add_child(controls)

	# Frequency Slider
	var freq_slider = HSlider.new()
	freq_slider.min_value = 1.0
	freq_slider.max_value = 6.0
	freq_slider.step = 0.1
	freq_slider.value_changed.connect(func(v): current_freq = v)
	controls.add_child(Label.new().duplicate()) # Spacer
	var f_label = Label.new()
	f_label.text = "Frequency"
	controls.add_child(f_label)
	controls.add_child(freq_slider)

	# Amplitude Slider
	var amp_slider = HSlider.new()
	amp_slider.min_value = 5.0
	amp_slider.max_value = 60.0
	amp_slider.step = 1.0
	amp_slider.value_changed.connect(func(v): current_amp = v)
	var a_label = Label.new()
	a_label.text = "Amplitude"
	controls.add_child(a_label)
	controls.add_child(amp_slider)

	# Draw the initial goal wave
	draw_wave(goal_line, goal_freq, goal_amp)

func _process(_delta):
	# Redraw the player's wave every frame to reflect slider changes
	draw_wave(wave_line, current_freq, current_amp)
	
	# Check for match (with a small margin of error)
	if abs(current_freq - goal_freq) < 0.2 and abs(current_amp - goal_amp) < 3.0:
		finish_game()

func draw_wave(line: Line2D, freq: float, amp: float):
	line.clear_points()
	for i in range(401): # 400 pixels wide
		var x = i
		# Sine wave formula: y = sin(x * frequency) * amplitude
		var y = 100 + sin(i * 0.1 * freq) * amp 
		line.add_point(Vector2(x, y))

func finish_game():
	set_process(false)
	wave_line.default_color = Color.WHITE
	complete_sound.play()
	var l = Label.new()
	l.text = "SIGNAL LOCKED"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 150)
	l.custom_minimum_size = Vector2(500, 30)
	game_panel.add_child(l)
	
	await get_tree().create_timer(1.2).timeout
	emit_signal("minigame_completed")
	queue_free()
