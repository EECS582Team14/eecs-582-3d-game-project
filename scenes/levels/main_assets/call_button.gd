extends StaticBody3D

# Drag the elevator's AnimatableBody3D node into this slot in the Inspector.
@export var elevator: AnimatableBody3D
@export var button_mesh: Node3D
# Check this box if this button is on the UPPER floor. Leave unchecked for the lower floor.
@export var is_upper_floor: bool = false

var _waiting: bool = false
var _anim_player: AnimationPlayer

func activate() -> void:
	print("CallButton activate() called!")

	if elevator == null:
		push_warning("CallButton: elevator reference not set!")
		return

	var floor_name = "upper" if is_upper_floor else "lower"

	_play_button_animation()
	_waiting = true
	# call_to_floor handles the network broadcast
	elevator.call_to_floor(floor_name)

func _ready() -> void:
	NetworkManager.elevator_used.connect(_on_elevator_used)
	# Find AnimationPlayer in the button model
	if button_mesh:
		_anim_player = _find_animation_player(button_mesh)

func _find_animation_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var result = _find_animation_player(child)
		if result:
			return result
	return null

func _play_button_animation() -> void:
	if _anim_player == null:
		return
	var anims = _anim_player.get_animation_list()
	if anims.size() > 0:
		_anim_player.stop()
		_anim_player.play(anims[0])

func _process(_delta: float) -> void:
	if not _waiting or elevator == null:
		return
	var floor_name = "upper" if is_upper_floor else "lower"
	if elevator.is_at_floor(floor_name):
		_waiting = false

func _on_elevator_used(_action: String, floor_name: String):
	# Update call button color when elevator is called remotely
	var my_floor = "upper" if is_upper_floor else "lower"
	if floor_name == my_floor:
		_play_button_animation()
		_waiting = true
