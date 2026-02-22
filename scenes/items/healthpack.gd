extends StaticBody3D

@export var health_restore: int = 25
@export var respawn_time: float = 10.0
var item_id: String = "healthpack_01"
var _picked_up: bool = false
var _spawn_position: Vector3

func _ready() -> void:
	_spawn_position = global_position
	set_process(true)

#func _process(delta: float) -> void:
#	if not _picked_up:
#		rotation.y += 1.5 * delta

func activate(picker_steam_id: int) -> void:
	if _picked_up:
		return
	
	_picked_up = true
	
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
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
		elif child is CollisionShape3D:
			child.disabled = true

func _respawn() -> void:
	#if is_node_orphaned():
	#	return
	
	_picked_up = false
	global_position = _spawn_position
	
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = true
		elif child is CollisionShape3D:
			child.disabled = false
