extends Control

## Simon Says minigame for the Nexus task.
## Shows a sequence of colored button flashes; player must repeat the pattern.

signal minigame_completed
signal minigame_cancelled

const TOTAL_ROUNDS: int = 3
const FLASH_DURATION: float = 0.4
const PAUSE_BETWEEN: float = 0.25
const DIM_ALPHA: float = 0.35

var _sequence: Array[int] = []
var _player_index: int = 0
var _current_round: int = 0
var _accepting_input: bool = false

var _buttons: Array[Button] = []
var _round_label: Label
var _status_label: Label

# Base colors (dimmed) and flash colors (bright)
var _base_colors: Array[Color] = [
	Color(0.6, 0.1, 0.1),   # red
	Color(0.1, 0.2, 0.6),   # blue
	Color(0.1, 0.5, 0.1),   # green
	Color(0.6, 0.5, 0.05),  # yellow
]

var _flash_colors: Array[Color] = [
	Color(1.0, 0.2, 0.2),   # red bright
	Color(0.3, 0.5, 1.0),   # blue bright
	Color(0.2, 1.0, 0.3),   # green bright
	Color(1.0, 0.9, 0.2),   # yellow bright
]

# Sound effects
@onready var complete_sound: AudioStreamPlayer = $SelectGranted
@onready var denied_sound: AudioStreamPlayer = $AccessDenied

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# Full-screen semi-transparent background
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "NEXUS CALIBRATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	vbox.add_child(title)

	# Round label
	_round_label = Label.new()
	_round_label.text = "Round 1 / %d" % TOTAL_ROUNDS
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_round_label)

	# Status label
	_status_label = Label.new()
	_status_label.text = "Watch the sequence..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_status_label)

	# Grid of 4 buttons (2x2)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(grid)

	var names = ["RED", "BLUE", "GREEN", "YELLOW"]
	for i in range(4):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(160, 160)
		btn.text = names[i]
		btn.add_theme_font_size_override("font_size", 16)
		# Style the button with its base color
		var style = StyleBoxFlat.new()
		style.bg_color = _base_colors[i]
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.3, 0.3, 0.3)
		btn.add_theme_stylebox_override("normal", style)
		# Hover style - slightly brighter
		var hover_style = style.duplicate()
		hover_style.bg_color = _base_colors[i].lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover_style)
		# Pressed style
		var pressed_style = style.duplicate()
		pressed_style.bg_color = _flash_colors[i]
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.pressed.connect(_on_button_pressed.bind(i))
		grid.add_child(btn)
		_buttons.append(btn)

	# Escape hint
	var hint = Label.new()
	hint.text = "Press Escape to cancel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

func start_game() -> void:
	_sequence.clear()
	_current_round = 0
	_accepting_input = false
	_next_round()

func _next_round() -> void:
	_current_round += 1
	_round_label.text = "Round %d / %d" % [_current_round, TOTAL_ROUNDS]
	_status_label.text = "Watch the sequence..."
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_accepting_input = false
	# Add a random step
	_sequence.append(randi_range(0, 3))
	# Small delay before playback
	await get_tree().create_timer(0.6).timeout
	await _play_sequence()
	_player_index = 0
	_accepting_input = true
	_status_label.text = "Your turn! Repeat the pattern."
	_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))

func _play_sequence() -> void:
	for i in range(_sequence.size()):
		await _flash_button(_sequence[i])
		if i < _sequence.size() - 1:
			await get_tree().create_timer(PAUSE_BETWEEN).timeout

func _flash_button(index: int) -> void:
	var btn = _buttons[index]
	var style = StyleBoxFlat.new()
	style.bg_color = _flash_colors[index]
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(1, 1, 1, 0.8)
	btn.add_theme_stylebox_override("normal", style)
	await get_tree().create_timer(FLASH_DURATION).timeout
	# Restore dim color
	var dim_style = StyleBoxFlat.new()
	dim_style.bg_color = _base_colors[index]
	dim_style.corner_radius_top_left = 12
	dim_style.corner_radius_top_right = 12
	dim_style.corner_radius_bottom_left = 12
	dim_style.corner_radius_bottom_right = 12
	dim_style.border_width_left = 2
	dim_style.border_width_right = 2
	dim_style.border_width_top = 2
	dim_style.border_width_bottom = 2
	dim_style.border_color = Color(0.3, 0.3, 0.3)
	btn.add_theme_stylebox_override("normal", dim_style)

func _on_button_pressed(index: int) -> void:
	if not _accepting_input:
		return
	if _sequence[_player_index] == index:
		# Correct
		_player_index += 1
		if _player_index >= _sequence.size():
			# Round complete
			_accepting_input = false
			if _current_round >= TOTAL_ROUNDS:
				complete_sound.play()
				_status_label.text = "Calibration complete!"
				_status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
				await get_tree().create_timer(0.8).timeout
				minigame_completed.emit()
			else:
				_status_label.text = "Correct!"
				_status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
				await get_tree().create_timer(0.8).timeout
				_next_round()
	else:
		# Wrong - replay current round
		_accepting_input = false
		denied_sound.play()
		_status_label.text = "Wrong! Watch again..."
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		await get_tree().create_timer(1.0).timeout
		_player_index = 0
		_status_label.text = "Watch the sequence..."
		_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		await get_tree().create_timer(0.4).timeout
		await _play_sequence()
		_player_index = 0
		_accepting_input = true
		_status_label.text = "Your turn! Repeat the pattern."
		_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		minigame_cancelled.emit()
		get_viewport().set_input_as_handled()
