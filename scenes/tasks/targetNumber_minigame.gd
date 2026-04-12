extends Control

signal minigame_completed
signal minigame_cancelled

var target_load = 0
var current_load = 0
var switches = []

# UI References
var target_label : Label
var current_label : Label

# Sound effects
@onready var complete_sound: AudioStreamPlayer = $SelectGranted

func start_game():
	create_ui()
	spawn_switches()

func _input(event):
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		emit_signal("minigame_cancelled")
		queue_free()

func create_ui():
	# Root spans the full screen
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Semi-transparent background
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Master Vertical Layout
	var main_vbox = VBoxContainer.new()
	main_vbox.name = "MainLayout"
	main_vbox.custom_minimum_size = Vector2(400, 0) # Width of the minigame
	main_vbox.add_theme_constant_override("separation", 25)
	
	add_child(main_vbox)

	# --- THE MAGIC CENTERING CODE ---
	# We center the anchors, then tell Godot to pull the box back by 50% of its own size
	main_vbox.set_anchors_preset(Control.PRESET_CENTER)
	main_vbox.set_anchor_and_offset(SIDE_LEFT, 0.5, -200) # Half of custom_minimum_size width
	main_vbox.set_anchor_and_offset(SIDE_RIGHT, 0.5, 200)
	# --------------------------------

	# --- TOP SECTION: Labels ---
	var title = Label.new()
	title.text = "POWER GRID STABILIZER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	main_vbox.add_child(title)

	target_label = Label.new()
	target_label.text = "TARGET: " + str(target_load) + " MW"
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.add_theme_font_size_override("font_size", 20)
	main_vbox.add_child(target_label)

	current_label = Label.new()
	current_label.text = "CURRENT: 0 MW"
	current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_label.add_theme_font_size_override("font_size", 20)
	main_vbox.add_child(current_label)

	# --- BOTTOM SECTION: Buttons ---
	var grid = GridContainer.new()
	grid.columns = 3
	grid.name = "SwitchGrid"
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER 
	grid.add_theme_constant_override("h_separation", 15)
	grid.add_theme_constant_override("v_separation", 15)
	main_vbox.add_child(grid)

func spawn_switches():
	var grid = get_node("MainLayout/SwitchGrid")
	
	# 1. Define a pool of possible button values
	var pool = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50]
	pool.shuffle()
	
	# 2. Pick 6 values for our buttons
	var current_values = []
	for i in range(6):
		current_values.append(pool[i])
	
	# 3. CRITICAL: Pick a random subset of these buttons to form the target
	# This ensures the target is mathematically possible.
	var target_sum = 0
	var buttons_to_include = randi_range(2, 4) # Pick 2 to 4 buttons to be the 'solution'
	
	var temp_values = current_values.duplicate()
	temp_values.shuffle()
	
	for i in range(buttons_to_include):
		target_sum += temp_values[i]
	
	# 4. Set the global target_load and update the label
	target_load = target_sum
	target_label.text = "TARGET: " + str(target_load) + " MW"
	
	# 5. Actually create the button nodes
	for val in current_values:
		var btn = Button.new()
		btn.text = str(val)
		btn.custom_minimum_size = Vector2(80, 80)
		btn.toggle_mode = true
		
		var data = {"button": btn, "value": val, "active": false}
		btn.toggled.connect(_on_switch_toggled.bind(data))
		grid.add_child(btn)
		switches.append(data)

func _on_switch_toggled(is_on, data):
	data.active = is_on
	
	if is_on:
		data.button.modulate = Color(1, 0.8, 0) # Amber when active
	else:
		data.button.modulate = Color(1, 1, 1)

	calculate_total()

func calculate_total():
	current_load = 0
	for s in switches:
		if s.active:
			current_load += s.value
	
	current_label.text = "CURRENT: " + str(current_load) + " MW"
	
	# Visual feedback for the text
	if current_load == target_load:
		current_label.modulate = Color(0, 1, 0)
		finish_game()
	elif current_load > target_load:
		current_label.modulate = Color(1, 0, 0)
	else:
		current_label.modulate = Color(1, 1, 1)

func finish_game():
	for s in switches:
		s.button.disabled = true
	complete_sound.play()
	var win_msg = Label.new()
	win_msg.text = "SYSTEM NOMINAL"
	win_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	get_node("MainLayout").add_child(win_msg)
	
	await get_tree().create_timer(1.5).timeout
	emit_signal("minigame_completed")
	queue_free()
