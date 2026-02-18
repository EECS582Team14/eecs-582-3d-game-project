extends AnimatableBody3D

enum State { IDLE, MOVING_DOWN, MOVING_UP }

const UPPER_Y: float = 0.0
const LOWER_Y: float = -2.5325365
const MOVE_SPEED: float = 2.0

@export var button_mesh: MeshInstance3D

var state: State = State.IDLE

func _ready() -> void:
	_set_button_color(Color.RED)

func activate() -> void:
	if state == State.IDLE:
		_set_button_color(Color.GREEN)
		if global_position.y >= UPPER_Y - 0.05:
			state = State.MOVING_DOWN
		else:
			state = State.MOVING_UP

func _set_button_color(color: Color) -> void:
	if button_mesh == null:
		return
	var mat = button_mesh.get_active_material(0)
	if mat:
		mat.albedo_color = color

func _physics_process(delta: float) -> void:
	if state == State.MOVING_DOWN:
		global_position.y = move_toward(global_position.y, LOWER_Y, MOVE_SPEED * delta)
		if abs(global_position.y - LOWER_Y) < 0.01:
			global_position.y = LOWER_Y
			state = State.IDLE
			_set_button_color(Color.RED)
	elif state == State.MOVING_UP:
		global_position.y = move_toward(global_position.y, UPPER_Y, MOVE_SPEED * delta)
		if abs(global_position.y - UPPER_Y) < 0.01:
			global_position.y = UPPER_Y
			state = State.IDLE
			_set_button_color(Color.RED)
