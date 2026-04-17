extends Node3D
## Physical lobby room where players walk around before the game starts.
## The host can configure settings and start the mission via interactive consoles.

const PlayerScene = preload("res://scenes/player/player.tscn")
const LobbyConsoleScript = preload("res://scenes/lobby/lobby_console.gd")
const LOBBY_UI_SCENE = "res://scenes/lobby/lobby_ui.tscn.tscn"

const PLAYER_COLORS: Array[Color] = [
	Color.GREEN,
	Color.DODGER_BLUE,
	Color.ORANGE_RED,
	Color.GOLD,
	Color.MEDIUM_PURPLE,
	Color.HOT_PINK,
	Color.CYAN,
	Color.YELLOW,
]

var lobby_spawn_points: Array[Vector3] = [
	Vector3(-3, 0, 1),
	Vector3(-1.5, 0, 1),
	Vector3(0, 0, 1),
	Vector3(1.5, 0, 1),
	Vector3(3, 0, 1),
	Vector3(-2.25, 0, 3),
	Vector3(0, 0, 3),
	Vector3(2.25, 0, 3),
]

var players_container: Node3D = null
var _settings_open: bool = false
var _settings_layer: CanvasLayer = null
var _player_list_layer: CanvasLayer = null
var _player_list_ui: ItemList = null
var _host_label: Label = null

var dot_purple = preload("res://scenes/lobby/lobby_assets/PurpleIcon.png")
var dot_host = preload("res://scenes/lobby/lobby_assets/HostIcon.png")

func _ready():
	_build_room()
	_build_consoles()
	_build_player_list_ui()
	_spawn_all_players()

	LobbyManager.player_joined.connect(_on_player_joined)
	LobbyManager.player_left.connect(_on_player_left)
	LobbyManager.host_changed.connect(_on_host_changed)
	LobbyManager.lobby_closed.connect(_on_lobby_closed)
	LobbyManager.member_names_updated.connect(_on_member_names_updated)
	NetworkManager.game_started.connect(_on_game_started)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Enable voice chat in lobby
	VoiceManager.start()

# ============ ROOM GEOMETRY ============

func _build_room():
	# World environment
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.45, 0.6)
	env.ambient_light_energy = 0.7
	world_env.environment = env
	add_child(world_env)

	# Floor
	_create_surface(Vector3(0, -0.25, 0), Vector3(16, 0.5, 16), Color(0.12, 0.12, 0.16))
	# Ceiling
	_create_surface(Vector3(0, 4.0, 0), Vector3(16, 0.5, 16), Color(0.06, 0.06, 0.08))
	# Walls
	_create_surface(Vector3(0, 2, -8), Vector3(16, 4.5, 0.3), Color(0.08, 0.08, 0.12))   # Back
	_create_surface(Vector3(0, 2, 8), Vector3(16, 4.5, 0.3), Color(0.08, 0.08, 0.12))    # Front
	_create_surface(Vector3(-8, 2, 0), Vector3(0.3, 4.5, 16), Color(0.08, 0.08, 0.12))   # Left
	_create_surface(Vector3(8, 2, 0), Vector3(0.3, 4.5, 16), Color(0.08, 0.08, 0.12))    # Right

	# Directional light
	var dir_light = DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-50, 25, 0)
	dir_light.light_energy = 1.2
	dir_light.light_color = Color(0.9, 0.9, 1.0)
	dir_light.shadow_enabled = true
	add_child(dir_light)

	# Central overhead light
	_create_point_light(Vector3(0, 3.5, 0), Color(0.7, 0.8, 1.0), 4.0, 14.0)
	# Console accent lights
	_create_point_light(Vector3(-2.5, 2.5, -6.5), Color(0.3, 0.6, 1.0), 2.5, 6.0)
	_create_point_light(Vector3(2.5, 2.5, -6.5), Color(0.3, 1.0, 0.5), 2.5, 6.0)
	# Corner fill lights
	_create_point_light(Vector3(-6, 3.0, -6), Color(0.5, 0.5, 0.7), 1.5, 8.0)
	_create_point_light(Vector3(6, 3.0, -6), Color(0.5, 0.5, 0.7), 1.5, 8.0)
	_create_point_light(Vector3(-6, 3.0, 6), Color(0.5, 0.5, 0.7), 1.5, 8.0)
	_create_point_light(Vector3(6, 3.0, 6), Color(0.5, 0.5, 0.7), 1.5, 8.0)
	# Leave console light
	_create_point_light(Vector3(7, 2.5, -3), Color(1.0, 0.3, 0.2), 1.5, 5.0)

	# Floor guide stripes (mesh only, no collision)
	_create_decal(Vector3(0, 0.01, -5.5), Vector3(14, 0.02, 0.05), Color(0.2, 0.4, 0.8))
	_create_decal(Vector3(0, 0.01, -3), Vector3(14, 0.02, 0.05), Color(0.15, 0.25, 0.5))

	# Room title
	var title = Label3D.new()
	title.text = "MISSION BRIEFING ROOM"
	title.position = Vector3(0, 3.3, -7.8)
	title.font_size = 64
	title.modulate = Color(0.4, 0.7, 1.0, 0.9)
	title.outline_size = 4
	title.outline_modulate = Color(0.1, 0.2, 0.4)
	add_child(title)

func _create_surface(pos: Vector3, size: Vector3, color: Color) -> void:
	var body = StaticBody3D.new()
	body.position = pos

	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.3
	mat.roughness = 0.7
	mesh_inst.material_override = mat

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape

	body.add_child(mesh_inst)
	body.add_child(col)
	add_child(body)

func _create_decal(pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.position = pos
	var box = BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mesh_inst.material_override = mat
	add_child(mesh_inst)

func _create_point_light(pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	var light = OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	add_child(light)

# ============ CONSOLES ============

func _build_consoles():
	var settings_console = _create_console(Vector3(-2.5, 0, -7), "SETTINGS", "settings")
	settings_console.console_activated.connect(_on_console_activated)

	var start_console = _create_console(Vector3(2.5, 0, -7), "START MISSION", "start")
	start_console.console_activated.connect(_on_console_activated)

	var leave_console = _create_console(Vector3(7, 0, -3), "LEAVE LOBBY", "leave")
	leave_console.console_activated.connect(_on_console_activated)

func _create_console(pos: Vector3, label_text: String, type: String) -> StaticBody3D:
	var console = LobbyConsoleScript.new()
	console.position = pos
	console.console_type = type
	console.add_to_group("lobby_console")

	# Console body
	var body_mesh = MeshInstance3D.new()
	var body_box = BoxMesh.new()
	body_box.size = Vector3(1.4, 1.0, 0.7)
	body_mesh.mesh = body_box
	body_mesh.position = Vector3(0, 0.5, 0)
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.15, 0.18, 0.25)
	body_mat.metallic = 0.6
	body_mat.roughness = 0.4
	body_mesh.material_override = body_mat
	console.add_child(body_mesh)

	# Console screen
	var screen = MeshInstance3D.new()
	var screen_box = BoxMesh.new()
	screen_box.size = Vector3(1.0, 0.5, 0.05)
	screen.mesh = screen_box
	screen.position = Vector3(0, 0.85, -0.33)
	var screen_mat = StandardMaterial3D.new()
	var screen_color: Color
	match type:
		"settings":
			screen_color = Color(0.05, 0.15, 0.4)
		"start":
			screen_color = Color(0.05, 0.35, 0.15)
		"leave":
			screen_color = Color(0.4, 0.1, 0.05)
		_:
			screen_color = Color(0.05, 0.2, 0.4)
	screen_mat.albedo_color = screen_color
	screen_mat.emission_enabled = true
	screen_mat.emission = screen_color
	screen_mat.emission_energy_multiplier = 3.0
	screen.material_override = screen_mat
	console.add_child(screen)

	# Collision
	var col = CollisionShape3D.new()
	var col_shape = BoxShape3D.new()
	col_shape.size = Vector3(1.4, 1.0, 0.7)
	col.shape = col_shape
	col.position = Vector3(0, 0.5, 0)
	console.add_child(col)

	# Label above console
	var label = Label3D.new()
	label.text = label_text
	label.position = Vector3(0, 1.4, -0.2)
	label.font_size = 36
	match type:
		"settings":
			label.modulate = Color(0.4, 0.6, 1.0)
		"start":
			label.modulate = Color(0.3, 1.0, 0.4)
		"leave":
			label.modulate = Color(1.0, 0.4, 0.3)
	label.outline_size = 3
	label.outline_modulate = Color(0, 0, 0, 0.5)
	console.add_child(label)

	add_child(console)
	return console

func _on_console_activated(type: String):
	match type:
		"settings":
			if LobbyManager.is_host():
				_open_settings_ui()
			else:
				_show_notification("Only the host can change settings")
		"start":
			if LobbyManager.is_host():
				GameManager.start_game()
			else:
				_show_notification("Waiting for the host to start")
		"leave":
			_cleanup_players()
			if LobbyManager.is_host():
				LobbyManager.close_lobby()
				# lobby_closed signal handler will transition to UI
			else:
				LobbyManager.leave_lobby()
				_go_to_lobby_ui()

# ============ PLAYER LIST UI ============

func _build_player_list_ui():
	_player_list_layer = CanvasLayer.new()
	_player_list_layer.layer = 10
	add_child(_player_list_layer)

	var panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -280
	panel.offset_right = -20
	panel.offset_top = 20
	panel.offset_bottom = 320

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.8)
	style.border_color = Color(0.2, 0.4, 0.8, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	_player_list_layer.add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "CREW MEMBERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	vbox.add_child(title)

	_player_list_ui = ItemList.new()
	_player_list_ui.custom_minimum_size = Vector2(240, 200)
	_player_list_ui.fixed_icon_size = Vector2i(15, 15)
	_player_list_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var list_style = StyleBoxFlat.new()
	list_style.bg_color = Color(0, 0, 0, 0)
	_player_list_ui.add_theme_stylebox_override("panel", list_style)
	vbox.add_child(_player_list_ui)

	_host_label = Label.new()
	_host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_label.add_theme_font_size_override("font_size", 14)
	_host_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_host_label)

	_refresh_player_list()

func _refresh_player_list():
	if not _player_list_ui:
		return
	_player_list_ui.clear()
	for member in LobbyManager.lobby_members:
		var icon = dot_purple
		if member["steam_id"] == LobbyManager.get_host_steam_id():
			icon = dot_host
		_player_list_ui.add_item(member["name"], icon)

	if LobbyManager.is_host():
		_host_label.text = "You are the host"
	else:
		var host_name = ""
		for member in LobbyManager.lobby_members:
			if member["steam_id"] == LobbyManager.get_host_steam_id():
				host_name = member["name"]
				break
		_host_label.text = "Host: " + host_name

# ============ SETTINGS UI ============

func _get_local_player():
	if not players_container:
		return null
	for player in players_container.get_children():
		if player.is_local_player:
			return player
	return null

func _open_settings_ui():
	if _settings_open:
		return
	_settings_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Tell the local player to stop processing mouse/input
	var local_player = _get_local_player()
	if local_player:
		local_player._is_mouse_captured = false

	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 50
	add_child(_settings_layer)

	# Dim background — clicking it closes the menu
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_settings_bg_clicked)
	_settings_layer.add_child(bg)

	# Settings panel
	var panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = -240
	panel.offset_bottom = 240

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.15, 0.95)
	style.border_color = Color(0.3, 0.5, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	_settings_layer.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "MISSION SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	vbox.add_child(title)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Imposter count
	var imp_label = Label.new()
	imp_label.text = "Number of Imposters"
	imp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	imp_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(imp_label)

	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_container)

	var button_group = ButtonGroup.new()
	var player_count = LobbyManager.lobby_members.size()

	for i in range(1, 4):
		var btn = Button.new()
		btn.text = str(i)
		btn.toggle_mode = true
		btn.button_group = button_group
		btn.custom_minimum_size = Vector2(60, 40)
		btn.add_theme_font_size_override("font_size", 22)

		# Need at least 2*imposters + 1 players
		if player_count < (i * 2 + 1):
			btn.disabled = true

		if i == GameManager.imposter_count:
			btn.button_pressed = true

		btn.pressed.connect(_on_imposter_count_changed.bind(i))
		btn_container.add_child(btn)

	# Info label
	var info = Label.new()
	info.text = "Players in lobby: %d" % player_count
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	vbox.add_child(info)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# Anonymous impostors toggle
	var anon_container = HBoxContainer.new()
	anon_container.alignment = BoxContainer.ALIGNMENT_CENTER
	anon_container.add_theme_constant_override("separation", 10)
	vbox.add_child(anon_container)

	var anon_label = Label.new()
	anon_label.text = "Anonymous Impostors"
	anon_label.add_theme_font_size_override("font_size", 20)
	anon_container.add_child(anon_label)

	var anon_toggle = CheckButton.new()
	anon_toggle.button_pressed = GameManager.anonymous_impostors
	anon_toggle.toggled.connect(_on_anonymous_impostors_toggled)
	anon_container.add_child(anon_toggle)

	var sep3 = HSeparator.new()
	vbox.add_child(sep3)

	# Baton spawn rate
	var baton_label = Label.new()
	baton_label.text = "Baton Spawn Rate"
	baton_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	baton_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(baton_label)

	var baton_row = HBoxContainer.new()
	baton_row.alignment = BoxContainer.ALIGNMENT_CENTER
	baton_row.add_theme_constant_override("separation", 10)
	vbox.add_child(baton_row)

	var baton_slider = HSlider.new()
	baton_slider.min_value = 0.0
	baton_slider.max_value = 1.0
	baton_slider.step = 0.05
	baton_slider.value = GameManager.baton_spawn_chance
	baton_slider.custom_minimum_size = Vector2(200, 20)
	baton_row.add_child(baton_slider)

	var baton_value_label = Label.new()
	baton_value_label.text = "%d%%" % int(GameManager.baton_spawn_chance * 100)
	baton_value_label.add_theme_font_size_override("font_size", 18)
	baton_value_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	baton_value_label.custom_minimum_size = Vector2(50, 0)
	baton_row.add_child(baton_value_label)

	baton_slider.value_changed.connect(_on_baton_spawn_changed.bind(baton_value_label))

	var sep4 = HSeparator.new()
	vbox.add_child(sep4)

	# Close button
	var close_container = HBoxContainer.new()
	close_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(close_container)

	var close_btn = Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(120, 40)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(_close_settings_ui)
	close_container.add_child(close_btn)

func _close_settings_ui():
	_settings_open = false
	if _settings_layer:
		_settings_layer.queue_free()
		_settings_layer = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Restore player input
	var local_player = _get_local_player()
	if local_player:
		local_player._is_mouse_captured = true

func _on_settings_bg_clicked(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_settings_ui()

func _on_imposter_count_changed(count: int):
	GameManager.imposter_count = count

func _on_anonymous_impostors_toggled(enabled: bool):
	GameManager.anonymous_impostors = enabled

func _on_baton_spawn_changed(value: float, value_label: Label):
	GameManager.baton_spawn_chance = value
	value_label.text = "%d%%" % int(value * 100)

# ============ NOTIFICATIONS ============

var _notification_layer: CanvasLayer = null

func _show_notification(text: String):
	if _notification_layer:
		_notification_layer.queue_free()

	_notification_layer = CanvasLayer.new()
	_notification_layer.layer = 60
	add_child(_notification_layer)

	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.7
	label.anchor_bottom = 0.7
	label.offset_left = -300
	label.offset_right = 300
	label.offset_top = -20
	label.offset_bottom = 20
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_notification_layer.add_child(label)

	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(_notification_layer):
			_notification_layer.queue_free()
			_notification_layer = null
	)

# ============ PLAYER SPAWNING ============

func _spawn_all_players():
	players_container = Node3D.new()
	players_container.name = "Players"
	add_child(players_container)

	var spawn_index = 0
	for member in LobbyManager.lobby_members:
		_spawn_player(member, spawn_index)
		spawn_index += 1

func _spawn_player(member: Dictionary, spawn_index: int = -1):
	if spawn_index < 0:
		spawn_index = players_container.get_child_count()

	var steam_id = member.steam_id
	var is_local = (steam_id == Steam.getSteamID())

	var player = PlayerScene.instantiate()
	player.steam_id = steam_id
	player.is_local_player = is_local
	player.name = "Player_" + str(steam_id)

	var pos = lobby_spawn_points[spawn_index % lobby_spawn_points.size()]
	player.position = pos

	players_container.add_child(player)

	# Assign color
	var color = PLAYER_COLORS[spawn_index % PLAYER_COLORS.size()]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	var model = player.get_node("PlayerModel")
	for child in model.get_children():
		if child is MeshInstance3D:
			child.material_override = mat
			break

	NetworkManager.register_player(steam_id, player)

	if not is_local:
		VoiceManager.setup_player_voice(steam_id, player)

func _cleanup_players():
	if players_container:
		for player in players_container.get_children():
			player.queue_free()
		players_container.queue_free()
		players_container = null
	NetworkManager.players_in_game.clear()

# ============ SIGNAL HANDLERS ============

func _on_player_joined(steam_id: int):
	var member = null
	for m in LobbyManager.lobby_members:
		if m.steam_id == steam_id:
			member = m
			break
	if member:
		_spawn_player(member)
	_refresh_player_list()

func _on_player_left(steam_id: int):
	VoiceManager.remove_player_voice(steam_id)
	var player = NetworkManager.get_player(steam_id)
	if player:
		NetworkManager.unregister_player(steam_id)
		player.queue_free()
	_refresh_player_list()

func _on_member_names_updated():
	_refresh_player_list()

func _on_host_changed(_new_host_id: int):
	_refresh_player_list()

func _on_lobby_closed():
	_cleanup_players()
	_go_to_lobby_ui()

func _go_to_lobby_ui():
	if is_inside_tree() and get_tree() != null:
		get_tree().call_deferred("change_scene_to_file", LOBBY_UI_SCENE)

func _on_game_started():
	# Clean up lobby players - GameManager will spawn game players in the new scene
	_cleanup_players()

func _input(event):
	if _settings_open and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			_close_settings_ui()
			get_viewport().set_input_as_handled()
