extends StaticBody3D

@export var item_id: String = self.name
@export var current_uses: int = 3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	NetworkManager.item_picked_up.connect(_on_item_picked_up)
	
func activate(picker_steam_id: int) -> void:
	NetworkManager.send_item_pickup(item_id)
	var player = NetworkManager.get_player(picker_steam_id)
	if player and player.has_method("give_baton"):
		player.give_baton(current_uses)
	queue_free()

func _on_item_picked_up(_steam_id: int, picked_item_id: String) -> void:
	if picked_item_id == item_id:
		queue_free()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
