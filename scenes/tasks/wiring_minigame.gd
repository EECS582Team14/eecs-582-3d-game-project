extends Control

## Wiring minigame for the Nav task.
## Players must drag colored wires from the left side to matching colored ports on the right.

signal minigame_completed
signal minigame_cancelled

const WIRE_COUNT: int = 4
const WIRE_THICKNESS: float = 6.0

var _wire_colors: Array[Color] = [
	Color(1.0, 0.2, 0.2),   # red
	Color(0.2, 0.5, 1.0),   # blue
	Color(0.2, 0.9, 0.3),   # green
	Color(1.0, 0.8, 0.1),   # yellow
]

var _color_names: Array[String] = ["RED", "BLUE", "GREEN", "YELLOW"]

# Left connectors (sources) and right connectors (targets)
var _left_connectors: Array[Button] = []
var _right_connectors: Array[Button] = []

# Shuffled order of right-side connectors
var _right_order: Array[int] = []

# Which wires have been connected: key = left index, value = right index
var _connections: Dictionary = {}

# Drag state
var _dragging: bool = false
var _drag_from_index: int = -1
var _drag_mouse_pos: Vector2 = Vector2.ZERO

# Drawing layer
var _draw_layer: Control = null

# Panel for layout reference
var _panel: PanelContainer = null

# Sound effects
@onready var complete_sound: AudioStreamPlayer = $SelectGranted

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
	title.text = "NAVIGATION ARRAY ALIGNMENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	vbox.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Connect matching wires to align the navigation array"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(subtitle)

	# Main wiring panel
	_panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.3, 0.3, 0.4)
	panel_style.content_margin_left = 40
	panel_style.content_margin_right = 40
	panel_style.content_margin_top = 30
	panel_style.content_margin_bottom = 30
	_panel.add_theme_stylebox_override("panel", panel_style)
	vbox.add_child(_panel)

	# HBoxContainer for left connectors, spacer, right connectors
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	_panel.add_child(hbox)

	# Left side - connectors in order
	var left_vbox = VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 20)
	hbox.add_child(left_vbox)

	for i in range(WIRE_COUNT):
		var btn = _create_connector(i, true)
		left_vbox.add_child(btn)
		_left_connectors.append(btn)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(300, 0)
	hbox.add_child(spacer)

	# Right side - shuffled order
	_right_order = []
	for i in range(WIRE_COUNT):
		_right_order.append(i)
	# Shuffle until it's not the identity (so there's something to solve)
	while _is_identity(_right_order):
		_right_order.shuffle()

	var right_vbox = VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 20)
	hbox.add_child(right_vbox)

	for i in range(WIRE_COUNT):
		var color_idx = _right_order[i]
		var btn = _create_connector(color_idx, false)
		right_vbox.add_child(btn)
		_right_connectors.append(btn)

	# Drawing layer for wires (on top of the panel)
	_draw_layer = Control.new()
	_draw_layer.set_anchors_preset(PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_layer.connect("draw", _on_draw)
	add_child(_draw_layer)

	# Escape hint
	var hint = Label.new()
	hint.text = "Press Escape to cancel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

func _is_identity(arr: Array[int]) -> bool:
	for i in range(arr.size()):
		if arr[i] != i:
			return false
	return true

func _create_connector(color_idx: int, is_left: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(100, 50)
	btn.text = _color_names[color_idx]
	btn.add_theme_font_size_override("font_size", 14)

	var style = StyleBoxFlat.new()
	style.bg_color = _wire_colors[color_idx].darkened(0.3)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = _wire_colors[color_idx]
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = _wire_colors[color_idx].darkened(0.1)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = _wire_colors[color_idx]
	btn.add_theme_stylebox_override("pressed", pressed_style)

	if is_left:
		btn.pressed.connect(_on_left_pressed.bind(color_idx))
	else:
		btn.pressed.connect(_on_right_pressed.bind(color_idx))

	return btn

func start_game() -> void:
	_connections.clear()
	_dragging = false
	_drag_from_index = -1

func _on_left_pressed(color_idx: int) -> void:
	# Start dragging a wire from this left connector
	# If already connected, remove that connection
	if _connections.has(color_idx):
		_connections.erase(color_idx)
	_dragging = true
	_drag_from_index = color_idx
	_draw_layer.queue_redraw()

func _on_right_pressed(color_idx: int) -> void:
	if not _dragging:
		return
	# Complete the connection
	_dragging = false
	_connections[_drag_from_index] = color_idx
	_drag_from_index = -1
	_draw_layer.queue_redraw()
	_update_connector_styles()
	_check_complete()

func _check_complete() -> void:
	if _connections.size() < WIRE_COUNT:
		return
	# Check all connections match (left color == right color)
	for left_idx in _connections:
		if _connections[left_idx] != left_idx:
			return
	# All correct!
	complete_sound.play()
	await get_tree().create_timer(0.5).timeout
	minigame_completed.emit()

func _update_connector_styles() -> void:
	# Dim connected left connectors
	for i in range(WIRE_COUNT):
		var btn = _left_connectors[i]
		if _connections.has(i):
			btn.modulate = Color(1, 1, 1, 0.6)
		else:
			btn.modulate = Color(1, 1, 1, 1.0)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		minigame_cancelled.emit()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _dragging:
		_drag_mouse_pos = event.position
		_draw_layer.queue_redraw()

	# Cancel drag on right-click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _dragging:
			_dragging = false
			_drag_from_index = -1
			_draw_layer.queue_redraw()

func _get_connector_center(btn: Button) -> Vector2:
	return btn.global_position + btn.size / 2.0

func _find_right_button_for_color(color_idx: int) -> Button:
	# Find the right-side button that has this color
	for i in range(WIRE_COUNT):
		if _right_order[i] == color_idx:
			return _right_connectors[i]
	return null

func _on_draw() -> void:
	# Draw completed connections
	for left_idx in _connections:
		var right_idx = _connections[left_idx]
		var from_btn = _left_connectors[left_idx]
		var to_btn = _find_right_button_for_color(right_idx)
		if from_btn and to_btn:
			var from_pos = _get_connector_center(from_btn) - _draw_layer.global_position
			var to_pos = _get_connector_center(to_btn) - _draw_layer.global_position
			var color = _wire_colors[left_idx]
			if left_idx == right_idx:
				color = color.lightened(0.2)
			else:
				color = color.darkened(0.2)
			_draw_layer.draw_line(from_pos, to_pos, color, WIRE_THICKNESS, true)

	# Draw in-progress drag wire
	if _dragging and _drag_from_index >= 0:
		var from_btn = _left_connectors[_drag_from_index]
		var from_pos = _get_connector_center(from_btn) - _draw_layer.global_position
		var to_pos = _drag_mouse_pos - _draw_layer.global_position
		var color = _wire_colors[_drag_from_index]
		color.a = 0.7
		_draw_layer.draw_line(from_pos, to_pos, color, WIRE_THICKNESS, true)
