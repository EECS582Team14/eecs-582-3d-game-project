extends StaticBody3D

@export var health_restore: int = 25
@export var respawn_time: float = 10.0

@onready var model: Node3D = $Model
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var item_id: String = "healthpack_01"
var _picked_up: bool = false
var _spawn_position: Vector3

func _ready() -> void:
	_spawn_position = global_position
	NetworkManager.item_picked_up.connect(_on_item_picked_up)
	set_process(true)

#func _process(delta: float) -> void:
#	if not _picked_up:
#		rotation.y += 1.5 * delta

func _on_item_picked_up(_picker_id: int, id: String) -> void:
	if id == item_id:
		_picked_up = true
		_hide_healthpack()

func activate(picker_steam_id: int) -> void:
	if _picked_up:
		return
	
	_picked_up = true
	NetworkManager.send_item_pickup(item_id)
	
	var player = NetworkManager.get_player(picker_steam_id)
	if player:
		player.current_health = min(player.current_health + health_restore, player.max_health)
		player.health_changed.emit(player.current_health)
		UIState.health_changed.emit(player.current_health)
		NetworkManager.send_health_update(player.current_health)
	
	_hide_healthpack()
	await get_tree().create_timer(respawn_time).timeout
	_respawn()

func _hide_healthpack() -> void:
	model.visible = false
	collision_shape.disabled = true
	'''for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
		elif child is CollisionShape3D:
			child.disabled = true'''

func _respawn() -> void:
	_picked_up = false
	global_position = _spawn_position
	
	model.visible = true
	collision_shape.disabled = false
	
	'''for child in get_children():
		if child is MeshInstance3D:
			child.visible = true
		elif child is CollisionShape3D:
			child.disabled = false'''
