extends Node3D

var player_inside = null


@onready var door = $DoorPivot
@onready var hide_point = $HidePoint

func activate(player) -> void:
	if player_inside == null:
		hide_player(player)
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
	
func exit_player(player):
	player_inside.visible = true
	player.can_move = true
	player._hiding_in = null
	player_inside.global_transform.origin = global_transform.origin + Vector3(1, 0, 0)
	player.set_collision_layer_value(1, true)
	player.set_collision_mask_value(1, true)
	player_inside = null
