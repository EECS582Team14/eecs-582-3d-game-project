extends Control

signal minigame_completed
signal minigame_cancelled

var game_panel: Panel
var items = []
var completed_count = 0
var total_items = 6

# Sound effects
@onready var complete_sound: AudioStreamPlayer = $SelectGranted

func start_game():
	create_ui()
	spawn_items()

func _input(event):
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		emit_signal("minigame_cancelled")
		queue_free()

func create_ui():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	game_panel = Panel.new()
	game_panel.custom_minimum_size = Vector2(500, 350)
	add_child(game_panel)
	game_panel.set_anchors_preset(Control.PRESET_CENTER)
	game_panel.set_anchor_and_offset(SIDE_LEFT, 0.5, -250)
	game_panel.set_anchor_and_offset(SIDE_TOP, 0.5, -175)

	var title = Label.new()
	title.text = "SORT RADIOACTIVE ISOTOPES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.custom_minimum_size = Vector2(500, 30)
	game_panel.add_child(title)

	# --- DROP ZONES (Targets) ---
	var zone_colors = [Color.RED, Color.BLUE, Color.YELLOW]
	for i in range(3):
		var zone = ColorRect.new()
		zone.color = zone_colors[i]
		zone.color.a = 0.2 # Faint background
		zone.size = Vector2(100, 100)
		zone.position = Vector2(50 + (i * 150), 200)
		zone.name = "Zone_" + str(i)
		# Add a border to make it look like a bin
		var border = ReferenceRect.new()
		border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		border.border_color = zone_colors[i]
		border.editor_only = false
		zone.add_child(border)
		
		game_panel.add_child(zone)

func spawn_items():
	var colors = [Color.RED, Color.BLUE, Color.YELLOW]
	
	for i in range(total_items):
		var target_idx = i % 3
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(50, 50)
		btn.modulate = colors[target_idx]
		btn.text = "O" # Represents the isotope
		
		# Random start position in the top half
		btn.position = Vector2(randf_range(50, 400), randf_range(60, 120))
		
		var data = {
			"node": btn,
			"target_color": colors[target_idx],
			"target_id": target_idx,
			"locked": false
		}
		
		btn.gui_input.connect(_on_item_drag.bind(data))
		game_panel.add_child(btn)
		items.append(data)

func _on_item_drag(event, data):
	if data.locked: return
	
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		data.node.global_position += event.relative
	
	if event is InputEventMouseButton and not event.pressed:
		# Check if dropped in correct zone
		check_drop(data)

func check_drop(data):
	var zone_name = "Zone_" + str(data.target_id)
	var target_zone = game_panel.get_node(zone_name)
	
	# Check if center of item is inside target zone
	var item_center = data.node.position + data.node.size / 2
	if target_zone.get_rect().has_point(item_center):
		# SUCCESSFUL DROP
		data.locked = true
		data.node.disabled = true
		data.node.modulate.a = 0.5 # Dim it
		completed_count += 1
		
		if completed_count >= total_items:
			finish_game()
	else:
		# Wrong zone or missed - bounce back slightly
		var tween = create_tween()
		tween.tween_property(data.node, "position", Vector2(randf_range(50, 400), 80), 0.3)

func finish_game():
	complete_sound.play()
	var l = Label.new()
	l.text = "MATERIALS SECURED"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 310)
	l.custom_minimum_size = Vector2(500, 30)
	game_panel.add_child(l)
	
	await get_tree().create_timer(1.0).timeout
	emit_signal("minigame_completed")
	queue_free()
