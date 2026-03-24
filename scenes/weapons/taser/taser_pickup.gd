extends StaticBody3D

@export var item_id: String = self.name

func _ready() -> void:
	NetworkManager.item_picked_up.connect(_on_item_picked_up)

func activate(picker_steam_id: int) -> void:
	var player = NetworkManager.get_player(picker_steam_id)
	if player and player.has_method("give_taser"):
		player.give_taser()
	NetworkManager.send_item_pickup(item_id)
	queue_free()

func _on_item_picked_up(_steam_id: int, picked_item_id: String) -> void:
	if picked_item_id == item_id:
		queue_free()
