extends Control

signal minigame_completed
signal minigame_cancelled

var grid_size = 4
var path_indices = [] 
var current_step = 0
var buttons = []
var game_panel: Panel

func start_game():
	create_ui()
	generate_random_path()

func _input(event):
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		emit_signal("minigame_cancelled")
		queue_free()

func create_ui():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 0.95)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	game_panel = Panel.new()
	game_panel.custom_minimum_size = Vector2(400, 450)
	add_child(game_panel)
	game_panel.set_anchors_preset(Control.PRESET_CENTER)
	game_panel.set_anchor_and_offset(SIDE_LEFT, 0.5, -200)
	game_panel.set_anchor_and_offset(SIDE_TOP, 0.5, -225)

	var title = Label.new()
	title.text = "ENCRYPTED BRIDGE LINK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.custom_minimum_size = Vector2(400, 30)
	game_panel.add_child(title)

	var grid = GridContainer.new()
	grid.columns = grid_size
	grid.add_theme_constant_override("h_separation", 15)
	grid.add_theme_constant_override("v_separation", 15)
	grid.position = Vector2(55, 80)
	game_panel.add_child(grid)

	for i in range(grid_size * grid_size):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(65, 65)
		btn.text = "?"
		btn.pressed.connect(_on_node_clicked.bind(i))
		grid.add_child(btn)
		buttons.append(btn)

func generate_random_path():
	path_indices.clear()
	var current = 0 # Start at Top-Left
	path_indices.append(current)
	
	var end_node = (grid_size * grid_size) - 1
	var max_attempts = 50
	var attempts = 0
	
	# Random Walk Algorithm
	while current != end_node and attempts < max_attempts:
		attempts += 1
		var neighbors = get_neighbors(current)
		neighbors.shuffle()
		
		var moved = false
		for n in neighbors:
			if n not in path_indices:
				current = n
				path_indices.append(current)
				moved = true
				break
		
		# If stuck, reset and try again
		if not moved:
			path_indices = [0]
			current = 0
			
	# UI Polish for Start/End
	buttons[path_indices[0]].modulate = Color.GREEN
	buttons[path_indices[0]].text = "START"
	buttons[path_indices[-1]].modulate = Color.YELLOW
	buttons[path_indices[-1]].text = "END"

func get_neighbors(index):
	var n = []
	var x = index % grid_size
	var y = index / grid_size
	
	if x > 0: n.append(index - 1) # Left
	if x < grid_size - 1: n.append(index + 1) # Right
	if y > 0: n.append(index - grid_size) # Up
	if y < grid_size - 1: n.append(index + grid_size) # Down
	return n

func _on_node_clicked(index):
	# If correct next step
	if index == path_indices[current_step]:
		buttons[index].modulate = Color.CYAN
		buttons[index].text = "OK"
		current_step += 1
		
		if current_step == path_indices.size():
			finish_game()
	else:
		# Wrong step! Reset with a penalty flash
		reset_game_state()

func reset_game_state():
	current_step = 0
	for i in range(buttons.size()):
		buttons[i].modulate = Color.WHITE
		buttons[i].text = "?"
	
	buttons[path_indices[0]].modulate = Color.GREEN
	buttons[path_indices[0]].text = "START"
	buttons[path_indices[-1]].modulate = Color.YELLOW
	
	# Visual "Error" flash
	var t = create_tween()
	t.tween_property(game_panel, "modulate", Color(1, 0, 0), 0.1)
	t.tween_property(game_panel, "modulate", Color(1, 1, 1), 0.1)

func finish_game():
	for b in buttons: b.disabled = true
	
	var l = Label.new()
	l.text = "BRIDGE ACTIVE"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 400)
	l.custom_minimum_size = Vector2(400, 30)
	game_panel.add_child(l)
	
	await get_tree().create_timer(1.0).timeout
	emit_signal("minigame_completed")
	queue_free()
