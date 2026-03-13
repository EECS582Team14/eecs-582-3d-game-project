extends StaticBody3D

@export var button_id: String = "button_left"
@export var door_controller: NodePath

var _is_pressed: bool = false
var _other_pressed: bool = false

@onready var _mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	NetworkManager.armory_button_changed.connect(_on_armory_button_changed)

func activate() -> void:
	_is_pressed = true
	_set_color(Color.GREEN)
	NetworkManager.send_armory_button(button_id, true)
	_check_unlock()

func deactivate() -> void:
	_is_pressed = false
	_set_color(Color.RED)
	NetworkManager.send_armory_button(button_id, false)
	_check_unlock()

func _on_armory_button_changed(changed_button_id: String, pressed: bool) -> void:
	if changed_button_id == button_id:
		# Our own button state from network (already handled locally)
		return
	_other_pressed = pressed
	_check_unlock()

func _check_unlock() -> void:
	if door_controller.is_empty():
		return
	var door = get_node_or_null(door_controller)
	if door == null:
		return
	door.is_locked = not (_is_pressed and _other_pressed)

func _set_color(color: Color) -> void:
	if _mesh == null:
		return
	var mat = _mesh.get_active_material(0)
	if mat:
		mat.albedo_color = color
