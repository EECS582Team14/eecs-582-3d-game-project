extends Control

## Breaker sequence minigame for the Electrical task.
## A row of breakers must be flipped ON in the correct order.
## The correct order is briefly shown, then the player must recall it.
## Flip one wrong and they all reset.

signal minigame_completed
signal minigame_cancelled

const BREAKER_COUNT: int = 5
const HINT_FLASH_DURATION: float = 0.5
const HINT_PAUSE: float = 0.3
const RESET_DELAY: float = 0.6

var _correct_order: Array[int] = []
var _player_index: int = 0
var _accepting_input: bool = false
var _completed: bool = false

var _breakers: Array[Button] = []
var _status_label: Label = null
var _hint_label: Label = null

# Style references
var _off_style: StyleBoxFlat
var _on_style: StyleBoxFlat
var _hint_style: StyleBoxFlat
var _wrong_style: StyleBoxFlat

func _ready() -> void:
	_create_styles()
	_build_ui()

func _create_styles() -> void:
	# OFF state - dark
	_off_style = StyleBoxFlat.new()
	_off_style.bg_color = Color(0.15, 0.15, 0.2)
	_off_style.corner_radius_top_left = 6
	_off_style.corner_radius_top_right = 6
	_off_style.corner_radius_bottom_left = 6
	_off_style.corner_radius_bottom_right = 6
	_off_style.border_width_left = 2
	_off_style.border_width_right = 2
	_off_style.border_width_top = 2
	_off_style.border_width_bottom = 2
	_off_style.border_color = Color(0.3, 0.3, 0.35)

	# ON state - bright green
	_on_style = StyleBoxFlat.new()
	_on_style.bg_color = Color(0.1, 0.5, 0.2)
	_on_style.corner_radius_top_left = 6
	_on_style.corner_radius_top_right = 6
	_on_style.corner_radius_bottom_left = 6
	_on_style.corner_radius_bottom_right = 6
	_on_style.border_width_left = 2
	_on_style.border_width_right = 2
	_on_style.border_width_top = 2
	_on_style.border_width_bottom = 2
	_on_style.border_color = Color(0.2, 0.9, 0.4)

	# HINT flash - yellow glow
	_hint_style = StyleBoxFlat.new()
	_hint_style.bg_color = Color(0.6, 0.5, 0.05)
	_hint_style.corner_radius_top_left = 6
	_hint_style.corner_radius_top_right = 6
	_hint_style.corner_radius_bottom_left = 6
	_hint_style.corner_radius_bottom_right = 6
	_hint_style.border_width_left = 3
	_hint_style.border_width_right = 3
	_hint_style.border_width_top = 3
	_hint_style.border_width_bottom = 3
	_hint_style.border_color = Color(1.0, 0.9, 0.3)

	# WRONG flash - red
	_wrong_style = StyleBoxFlat.new()
	_wrong_style.bg_color = Color(0.6, 0.1, 0.1)
	_wrong_style.corner_radius_top_left = 6
	_wrong_style.corner_radius_top_right = 6
	_wrong_style.corner_radius_bottom_left = 6
	_wrong_style.corner_radius_bottom_right = 6
	_wrong_style.border_width_left = 3
	_wrong_style.border_width_right = 3
	_wrong_style.border_width_top = 3
	_wrong_style.border_width_bottom = 3
	_wrong_style.border_color = Color(1.0, 0.2, 0.2)

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
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "CIRCUIT BREAKER RESET"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	vbox.add_child(title)

	# Status label
	_status_label = Label.new()
	_status_label.text = "Watch the sequence..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_status_label)

	# Breaker panel
	var panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.1)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.3, 0.3, 0.35)
	panel_style.content_margin_left = 30
	panel_style.content_margin_right = 30
	panel_style.content_margin_top = 30
	panel_style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", panel_style)
	vbox.add_child(panel)

	var panel_vbox = VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 16)
	panel_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(panel_vbox)

	# Breaker row
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_vbox.add_child(hbox)

	for i in range(BREAKER_COUNT):
		var breaker_vbox = VBoxContainer.new()
		breaker_vbox.add_theme_constant_override("separation", 8)
		breaker_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_child(breaker_vbox)

		var label = Label.new()
		label.text = str(i + 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		breaker_vbox.add_child(label)

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(80, 120)
		btn.text = "OFF"
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_stylebox_override("normal", _off_style.duplicate())
		btn.add_theme_stylebox_override("hover", _off_style.duplicate())
		btn.pressed.connect(_on_breaker_pressed.bind(i))
		breaker_vbox.add_child(btn)
		_breakers.append(btn)

	# Hint reminder
	_hint_label = Label.new()
	_hint_label.text = ""
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	panel_vbox.add_child(_hint_label)

	# Escape hint
	var hint = Label.new()
	hint.text = "Press Escape to cancel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

func start_game() -> void:
	_completed = false
	_accepting_input = false
	_player_index = 0

	# Generate random order
	_correct_order.clear()
	var indices: Array[int] = []
	for i in range(BREAKER_COUNT):
		indices.append(i)
	indices.shuffle()
	_correct_order = indices

	# Reset all breakers to OFF
	_reset_all_breakers()

	# Show the sequence
	_status_label.text = "Watch the order..."
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	await get_tree().create_timer(0.8).timeout
	await _show_hint_sequence()
	_accepting_input = true
	_player_index = 0
	_status_label.text = "Flip the breakers in the correct order!"
	_status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	_hint_label.text = "Flip breaker %d of %d" % [1, BREAKER_COUNT]

func _show_hint_sequence() -> void:
	for i in range(_correct_order.size()):
		var idx = _correct_order[i]
		var btn = _breakers[idx]
		# Flash the breaker
		btn.add_theme_stylebox_override("normal", _hint_style.duplicate())
		btn.add_theme_stylebox_override("hover", _hint_style.duplicate())
		btn.text = str(i + 1)
		await get_tree().create_timer(HINT_FLASH_DURATION).timeout
		btn.add_theme_stylebox_override("normal", _off_style.duplicate())
		btn.add_theme_stylebox_override("hover", _off_style.duplicate())
		btn.text = "OFF"
		if i < _correct_order.size() - 1:
			await get_tree().create_timer(HINT_PAUSE).timeout

func _reset_all_breakers() -> void:
	for btn in _breakers:
		btn.add_theme_stylebox_override("normal", _off_style.duplicate())
		btn.add_theme_stylebox_override("hover", _off_style.duplicate())
		btn.text = "OFF"

func _on_breaker_pressed(index: int) -> void:
	if not _accepting_input or _completed:
		return

	if index == _correct_order[_player_index]:
		# Correct!
		var btn = _breakers[index]
		btn.add_theme_stylebox_override("normal", _on_style.duplicate())
		btn.add_theme_stylebox_override("hover", _on_style.duplicate())
		btn.text = "ON"
		_player_index += 1
		_hint_label.text = "Flip breaker %d of %d" % [mini(_player_index + 1, BREAKER_COUNT), BREAKER_COUNT]

		if _player_index >= BREAKER_COUNT:
			# All done!
			_completed = true
			_accepting_input = false
			_status_label.text = "Breakers reset! Power restored!"
			_status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
			_hint_label.text = ""
			await get_tree().create_timer(0.8).timeout
			minigame_completed.emit()
	else:
		# Wrong! Flash all red and reset
		_accepting_input = false
		_status_label.text = "Wrong breaker! Resetting..."
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		_hint_label.text = ""

		# Flash everything red
		for btn in _breakers:
			btn.add_theme_stylebox_override("normal", _wrong_style.duplicate())
			btn.add_theme_stylebox_override("hover", _wrong_style.duplicate())
			btn.text = "X"

		await get_tree().create_timer(RESET_DELAY).timeout

		# Reset and replay hint
		_reset_all_breakers()
		_player_index = 0
		_status_label.text = "Watch the order again..."
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		await get_tree().create_timer(0.5).timeout
		await _show_hint_sequence()
		_accepting_input = true
		_status_label.text = "Flip the breakers in the correct order!"
		_status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
		_hint_label.text = "Flip breaker 1 of %d" % BREAKER_COUNT

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		minigame_cancelled.emit()
		get_viewport().set_input_as_handled()
