extends StaticBody3D

# Drag the elevator's AnimatableBody3D node into this slot in the Inspector.
@export var elevator: AnimatableBody3D
@export var button_mesh: MeshInstance3D
# Check this box if this button is on the UPPER floor. Leave unchecked for the lower floor.
@export var is_upper_floor: bool = false

func activate() -> void:
	print("CallButton activate() called!")
	_set_color(Color.GREEN)

	if elevator == null:
		push_warning("CallButton: elevator reference not set!")
		return

	var floor_name = "upper" if is_upper_floor else "lower"
	print("CallButton floor: ", floor_name, " | elevator at y: ", elevator.global_position.y)
	print("is_at_floor: ", elevator.is_at_floor(floor_name))

	if elevator.is_at_floor(floor_name):
		_set_color(Color.RED)
		return
	elevator.call_to_floor(floor_name)

func _set_color(color: Color) -> void:
	if button_mesh == null:
		return
	var mat = button_mesh.get_active_material(0)
	if mat:
		mat.albedo_color = color
