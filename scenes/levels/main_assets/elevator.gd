extends AnimatableBody3D

enum State { IDLE, MOVING_DOWN, MOVING_UP }

const MOVE_AMOUNT: float = 2.6
const MOVE_SPEED: float = 2.0

@export var button_mesh: MeshInstance3D

var state: State = State.IDLE
var upper_y: float
var lower_y: float

func _ready() -> void:
	upper_y = global_position.y
	lower_y = global_position.y - MOVE_AMOUNT
	_set_button_color(Color.RED)

func activate() -> void:
	if state == State.IDLE:
		_set_button_color(Color.GREEN)
		if global_position.y >= upper_y - 0.05:
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
		global_position.y = move_toward(global_position.y, lower_y, MOVE_SPEED * delta)
		if abs(global_position.y - lower_y) < 0.01:
			global_position.y = lower_y
			state = State.IDLE
			_set_button_color(Color.RED)
	elif state == State.MOVING_UP:
		global_position.y = move_toward(global_position.y, upper_y, MOVE_SPEED * delta)
		if abs(global_position.y - upper_y) < 0.01:
			global_position.y = upper_y
			state = State.IDLE
			_set_button_color(Color.RED)
