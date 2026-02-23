extends StaticBody3D

@export var health_restore: int = 25
@export var respawn_time: float = 10.0

@onready var model: Node3D = $Model
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var item_id: String = ""
var _picked_up: bool = false
var _spawn_position: Vector3

func _ready() -> void:
	_spawn_position = global_position
	# Use the node path as a unique ID so multiple healthpacks don't collide
	item_id = str(get_path())
	NetworkManager.item_picked_up.connect(_on_item_picked_up)

func _on_item_picked_up(picker_id: int, id: String) -> void:
	if id != item_id:
		return
	if _picked_up:
		return

	_picked_up = true
	_hide_healthpack()

	# Apply health to the picker (works for both local and remote paths)
	var player = NetworkManager.get_player(picker_id)
	if player:
		player.current_health = min(player.current_health + health_restore, player.max_health)
		player.health_changed.emit(player.current_health)
		# Only update UI and broadcast health if we are the picker
		if picker_id == Steam.getSteamID():
			UIState.health_changed.emit(player.current_health)
			NetworkManager.send_health_update(player.current_health)

	# All clients start the respawn timer so it stays in sync
	await get_tree().create_timer(respawn_time).timeout
	_respawn()

func activate(picker_steam_id: int) -> void:
	if _picked_up:
		return
	# Send the pickup to all peers; the local signal handler will do the rest
	NetworkManager.send_item_pickup(item_id)

func _hide_healthpack() -> void:
	model.visible = false
	collision_shape.disabled = true

func _respawn() -> void:
	_picked_up = false
	global_position = _spawn_position
	model.visible = true
	collision_shape.disabled = false
