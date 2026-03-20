extends Control

## Reactor temperature balancing minigame.
## A fluctuating temperature gauge that the player must keep in the green zone
## by clicking UP/DOWN buttons. Hold it stable for a few seconds to complete.

signal minigame_completed
signal minigame_cancelled

# Temperature range
const TEMP_MIN: float = 0.0
const TEMP_MAX: float = 100.0
const TEMP_TARGET: float = 50.0
const GREEN_ZONE_HALF: float = 15.0  # +/- 15 from target = green zone

# Player control
const ADJUST_AMOUNT: float = 5.0  # per click

# Drift - the reactor fights you
var _drift_speed: float = 8.0  # degrees per second of random drift
var _drift_direction: float = 1.0
var _drift_change_timer: float = 0.0
const DRIFT_CHANGE_INTERVAL: float = 1.2  # how often drift changes direction

# Completion
const HOLD_DURATION: float = 3.0  # seconds in green zone to complete
var _in_zone_timer: float = 0.0
var _completed: bool = false

# Current state
var _temperature: float = 30.0  # start below target so player has to adjust

# UI references
var _gauge_bar: ProgressBar = null
var _green_zone_rect: ColorRect = null
var _needle_rect: ColorRect = null
var _temp_label: Label = null
var _status_label: Label = null
var _progress_label: Label = null
var _progress_bar: ProgressBar = null
var _gauge_container: Control = null

func _ready() -> void:
	_build_ui()
	# Randomize starting temp
	_temperature = randf_range(15.0, 35.0)
	_drift_direction = [-1.0, 1.0].pick_random()

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
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "REACTOR TEMPERATURE CONTROL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	vbox.add_child(title)

	# Status label
	_status_label = Label.new()
	_status_label.text = "Stabilize temperature in the green zone"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_status_label)

	# Gauge panel
	var panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12)
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
	panel.add_theme_stylebox_override("panel", panel_style)
	vbox.add_child(panel)

	var panel_vbox = VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 16)
	panel_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(panel_vbox)

	# Temperature readout
	_temp_label = Label.new()
	_temp_label.text = "TEMP: 30.0°"
	_temp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_temp_label.add_theme_font_size_override("font_size", 28)
	_temp_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	panel_vbox.add_child(_temp_label)

	# Gauge - a visual bar with green zone overlay
	_gauge_container = Control.new()
	_gauge_container.custom_minimum_size = Vector2(500, 50)
	panel_vbox.add_child(_gauge_container)

	# Background bar
	var gauge_bg = ColorRect.new()
	gauge_bg.color = Color(0.2, 0.2, 0.25)
	gauge_bg.set_anchors_preset(PRESET_FULL_RECT)
	_gauge_container.add_child(gauge_bg)

	# Danger zones (red on edges)
	var left_danger = ColorRect.new()
	left_danger.color = Color(0.6, 0.1, 0.1, 0.5)
	left_danger.position = Vector2.ZERO
	left_danger.size = Vector2(500.0 * (TEMP_TARGET - GREEN_ZONE_HALF) / TEMP_MAX, 50)
	_gauge_container.add_child(left_danger)

	var right_danger_x = 500.0 * (TEMP_TARGET + GREEN_ZONE_HALF) / TEMP_MAX
	var right_danger = ColorRect.new()
	right_danger.color = Color(0.6, 0.1, 0.1, 0.5)
	right_danger.position = Vector2(right_danger_x, 0)
	right_danger.size = Vector2(500.0 - right_danger_x, 50)
	_gauge_container.add_child(right_danger)

	# Green zone
	_green_zone_rect = ColorRect.new()
	_green_zone_rect.color = Color(0.1, 0.5, 0.1, 0.5)
	var green_start = 500.0 * (TEMP_TARGET - GREEN_ZONE_HALF) / TEMP_MAX
	var green_width = 500.0 * (GREEN_ZONE_HALF * 2.0) / TEMP_MAX
	_green_zone_rect.position = Vector2(green_start, 0)
	_green_zone_rect.size = Vector2(green_width, 50)
	_gauge_container.add_child(_green_zone_rect)

	# Needle indicator
	_needle_rect = ColorRect.new()
	_needle_rect.color = Color(1, 1, 1)
	_needle_rect.size = Vector2(4, 50)
	_gauge_container.add_child(_needle_rect)

	# Gauge border labels
	var labels_hbox = HBoxContainer.new()
	labels_hbox.custom_minimum_size = Vector2(500, 0)
	panel_vbox.add_child(labels_hbox)

	var cold_label = Label.new()
	cold_label.text = "COLD"
	cold_label.add_theme_font_size_override("font_size", 12)
	cold_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	labels_hbox.add_child(cold_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels_hbox.add_child(spacer)

	var optimal_label = Label.new()
	optimal_label.text = "OPTIMAL"
	optimal_label.add_theme_font_size_override("font_size", 12)
	optimal_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	labels_hbox.add_child(optimal_label)

	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels_hbox.add_child(spacer2)

	var hot_label = Label.new()
	hot_label.text = "HOT"
	hot_label.add_theme_font_size_override("font_size", 12)
	hot_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	labels_hbox.add_child(hot_label)

	# UP / DOWN buttons
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 30)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_vbox.add_child(btn_hbox)

	var cool_btn = Button.new()
	cool_btn.text = "COOL DOWN"
	cool_btn.custom_minimum_size = Vector2(150, 50)
	cool_btn.add_theme_font_size_override("font_size", 18)
	var cool_style = StyleBoxFlat.new()
	cool_style.bg_color = Color(0.15, 0.25, 0.5)
	cool_style.corner_radius_top_left = 8
	cool_style.corner_radius_top_right = 8
	cool_style.corner_radius_bottom_left = 8
	cool_style.corner_radius_bottom_right = 8
	cool_style.border_width_left = 2
	cool_style.border_width_right = 2
	cool_style.border_width_top = 2
	cool_style.border_width_bottom = 2
	cool_style.border_color = Color(0.3, 0.5, 1.0)
	cool_btn.add_theme_stylebox_override("normal", cool_style)
	var cool_hover = cool_style.duplicate()
	cool_hover.bg_color = Color(0.2, 0.35, 0.65)
	cool_btn.add_theme_stylebox_override("hover", cool_hover)
	var cool_pressed = cool_style.duplicate()
	cool_pressed.bg_color = Color(0.3, 0.5, 0.9)
	cool_btn.add_theme_stylebox_override("pressed", cool_pressed)
	cool_btn.pressed.connect(_on_cool_pressed)
	btn_hbox.add_child(cool_btn)

	var heat_btn = Button.new()
	heat_btn.text = "HEAT UP"
	heat_btn.custom_minimum_size = Vector2(150, 50)
	heat_btn.add_theme_font_size_override("font_size", 18)
	var heat_style = StyleBoxFlat.new()
	heat_style.bg_color = Color(0.5, 0.15, 0.1)
	heat_style.corner_radius_top_left = 8
	heat_style.corner_radius_top_right = 8
	heat_style.corner_radius_bottom_left = 8
	heat_style.corner_radius_bottom_right = 8
	heat_style.border_width_left = 2
	heat_style.border_width_right = 2
	heat_style.border_width_top = 2
	heat_style.border_width_bottom = 2
	heat_style.border_color = Color(1.0, 0.4, 0.2)
	heat_btn.add_theme_stylebox_override("normal", heat_style)
	var heat_hover = heat_style.duplicate()
	heat_hover.bg_color = Color(0.65, 0.25, 0.15)
	heat_btn.add_theme_stylebox_override("hover", heat_hover)
	var heat_pressed = heat_style.duplicate()
	heat_pressed.bg_color = Color(0.9, 0.35, 0.2)
	heat_btn.add_theme_stylebox_override("pressed", heat_pressed)
	heat_btn.pressed.connect(_on_heat_pressed)
	btn_hbox.add_child(heat_btn)

	# Stability progress
	_progress_label = Label.new()
	_progress_label.text = "Stability: 0%"
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 18)
	panel_vbox.add_child(_progress_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(500, 20)
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = HOLD_DURATION
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	# Style the progress bar green
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.8, 0.3)
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_bottom_right = 4
	_progress_bar.add_theme_stylebox_override("fill", fill_style)
	var bar_bg_style = StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(0.15, 0.15, 0.2)
	bar_bg_style.corner_radius_top_left = 4
	bar_bg_style.corner_radius_top_right = 4
	bar_bg_style.corner_radius_bottom_left = 4
	bar_bg_style.corner_radius_bottom_right = 4
	_progress_bar.add_theme_stylebox_override("background", bar_bg_style)
	panel_vbox.add_child(_progress_bar)

	# Escape hint
	var hint = Label.new()
	hint.text = "Press Escape to cancel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

func start_game() -> void:
	_in_zone_timer = 0.0
	_completed = false
	set_process(true)

func _process(delta: float) -> void:
	if _completed:
		return

	# Apply drift
	_drift_change_timer -= delta
	if _drift_change_timer <= 0.0:
		_drift_change_timer = DRIFT_CHANGE_INTERVAL * randf_range(0.6, 1.4)
		# Slight bias away from center
		if _temperature > TEMP_TARGET:
			_drift_direction = 1.0 if randf() < 0.55 else -1.0
		else:
			_drift_direction = -1.0 if randf() < 0.55 else 1.0

	_temperature += _drift_direction * _drift_speed * delta
	_temperature = clampf(_temperature, TEMP_MIN, TEMP_MAX)

	# Check if in green zone
	var in_zone = absf(_temperature - TEMP_TARGET) <= GREEN_ZONE_HALF
	if in_zone:
		_in_zone_timer += delta
		_progress_label.text = "Stability: %d%%" % int((_in_zone_timer / HOLD_DURATION) * 100.0)
		_progress_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		_status_label.text = "Holding steady... keep it stable!"
		_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	else:
		_in_zone_timer = maxf(0.0, _in_zone_timer - delta)  # drains at same rate it fills
		_progress_label.text = "Stability: %d%%" % int((_in_zone_timer / HOLD_DURATION) * 100.0)
		_progress_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		if _temperature > TEMP_TARGET + GREEN_ZONE_HALF:
			_status_label.text = "TOO HOT! Cool it down!"
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		else:
			_status_label.text = "TOO COLD! Heat it up!"
			_status_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))

	_progress_bar.value = _in_zone_timer

	# Update gauge needle
	var needle_x = (500.0 - 4.0) * (_temperature / TEMP_MAX)
	_needle_rect.position = Vector2(needle_x, 0)

	# Update needle color based on zone
	if in_zone:
		_needle_rect.color = Color(0.3, 1.0, 0.4)
	else:
		_needle_rect.color = Color(1.0, 0.3, 0.2)

	# Update temp readout
	_temp_label.text = "TEMP: %.1f°" % _temperature
	if in_zone:
		_temp_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	elif _temperature > TEMP_TARGET:
		_temp_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	else:
		_temp_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))

	# Check completion
	if _in_zone_timer >= HOLD_DURATION:
		_completed = true
		_status_label.text = "Reactor stabilized!"
		_status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		_progress_label.text = "Stability: 100%"
		await get_tree().create_timer(0.8).timeout
		minigame_completed.emit()

func _on_cool_pressed() -> void:
	if not _completed:
		_temperature -= ADJUST_AMOUNT
		_temperature = clampf(_temperature, TEMP_MIN, TEMP_MAX)

func _on_heat_pressed() -> void:
	if not _completed:
		_temperature += ADJUST_AMOUNT
		_temperature = clampf(_temperature, TEMP_MIN, TEMP_MAX)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		minigame_cancelled.emit()
		get_viewport().set_input_as_handled()
