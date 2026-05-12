extends Node3D

const MAX_HIDE_TIME := 30.0

var player_inside = null
var _hide_remaining: float = 0.0
var _timer_label: Label = null

@onready var door = $DoorPivot
@onready var hide_point = $HidePoint

func _ready() -> void:
	NetworkManager.hide_update_recieved.connect(_on_hide_update)
	set_process(false)

func _process(delta: float) -> void:
	if player_inside == null:
		set_process(false)
		return
	_hide_remaining -= delta
	if _timer_label and is_instance_valid(_timer_label):
		_timer_label.text = "Hiding: %0.1fs" % max(_hide_remaining, 0.0)
	if _hide_remaining <= 0.0:
		exit_player(player_inside)

func activate(player) -> void:
	if player_inside == null:
		hide_player(player)
	elif player_inside != player:
		exit_player(player_inside)
	else:
		exit_player(player)

func hide_player(player):
	player_inside = player
	print(player)
	player.global_transform.origin = hide_point.global_transform.origin
	player.visible = false
	player.can_move = false
	player._hiding_in = self
	player.set_collision_layer_value(1, false)
	player.set_collision_mask_value(1, false)
	print(player, " is hiding in ", self.name)
	NetworkManager.send_hide_update(self.name, true, player.steam_id)
	_hide_remaining = MAX_HIDE_TIME
	if player.is_local_player:
		_show_timer_label(player)
	set_process(true)

func exit_player(player):
	player_inside.visible = true
	player.can_move = true
	player._hiding_in = null
	player_inside.global_transform.origin = global_transform.origin + Vector3(1, 0, 0)
	player.set_collision_layer_value(1, true)
	player.set_collision_mask_value(1, true)
	player_inside = null
	_hide_remaining = 0.0
	_hide_timer_label_clear()
	set_process(false)
	NetworkManager.send_hide_update(self.name, false, player.steam_id)

func _show_timer_label(player) -> void:
	_hide_timer_label_clear()
	var hud: Node = player.get_node_or_null("HUD")
	if hud == null:
		return
	_timer_label = Label.new()
	_timer_label.name = "LockerHideTimer"
	_timer_label.text = "Hiding: %0.1fs" % MAX_HIDE_TIME
	_timer_label.add_theme_font_size_override("font_size", 28)
	_timer_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_timer_label.add_theme_constant_override("outline_size", 6)
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.position = Vector2(-80, 80)
	_timer_label.size = Vector2(160, 40)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(_timer_label)

func _hide_timer_label_clear() -> void:
	if _timer_label and is_instance_valid(_timer_label):
		_timer_label.queue_free()
	_timer_label = null

func _on_hide_update(locker_id: String, io: bool, target_id: int):
	var player = NetworkManager.get_player(target_id)
	if io:
		player.visible = false
		print("hidden")
	else:
		player.visible = true
