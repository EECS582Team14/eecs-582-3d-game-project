extends AnimatableBody3D

enum State { IDLE, MOVING_DOWN, MOVING_UP }

const MOVE_AMOUNT: float = 2.43
const MOVE_SPEED: float = 2.0
const AUTOCLOSE_AMOUNT: float = 5.0

@export var elevator_doors: Node3D
@export var upper_doors: Node3D
@export var lower_doors: Node3D

var state: State = State.IDLE
var upper_y: float
var lower_y: float
var _autoclose_timer: SceneTreeTimer = null

func _ready() -> void:
	upper_y = global_position.y
	lower_y = global_position.y - MOVE_AMOUNT
	NetworkManager.elevator_used.connect(_on_elevator_used)

func activate() -> void:
	if state == State.IDLE:
		_autoclose_timer = null
		if global_position.y >= upper_y - 0.05:
			elevator_doors._close_doors()
			upper_doors._close_doors()
			state = State.MOVING_DOWN
			NetworkManager.send_elevator_use("activate", "down")
		else:
			elevator_doors._close_doors()
			lower_doors._close_doors()
			state = State.MOVING_UP
			NetworkManager.send_elevator_use("activate", "up")

# Called by a CallButton to bring the elevator to a specific floor.
# floor_name should be "upper" or "lower".
func call_to_floor(floor_name: String) -> void:
	if state != State.IDLE:
		return
	if is_at_floor(floor_name):
		elevator_doors._open_doors()
		if floor_name == "upper":
			upper_doors._open_doors()
		else:
			lower_doors._open_doors()
		start_autoclose_timer()
		return
	elif floor_name == "upper" and global_position.y < upper_y - 0.05:
		elevator_doors._close_doors()
		lower_doors._close_doors()
		state = State.MOVING_UP
		NetworkManager.send_elevator_use("call", floor_name)
	elif floor_name == "lower" and global_position.y > lower_y + 0.05:
		elevator_doors._close_doors()
		upper_doors._close_doors()
		state = State.MOVING_DOWN
		NetworkManager.send_elevator_use("call", floor_name)

func is_at_floor(floor_name: String) -> bool:
	if floor_name == "upper":
		return global_position.y >= upper_y - 0.05
	elif floor_name == "lower":
		return global_position.y <= lower_y + 0.05
	return false

func _physics_process(delta: float) -> void:
	if elevator_doors._is_animating or upper_doors._is_animating or lower_doors._is_animating:
		return
	if state == State.MOVING_DOWN:
		global_position.y = move_toward(global_position.y, lower_y, MOVE_SPEED * delta)
		if abs(global_position.y - lower_y) < 0.01:
			global_position.y = lower_y
			elevator_doors._open_doors()
			lower_doors._open_doors()
			start_autoclose_timer()
			state = State.IDLE

	elif state == State.MOVING_UP:
		global_position.y = move_toward(global_position.y, upper_y, MOVE_SPEED * delta)
		if abs(global_position.y - upper_y) < 0.01:
			global_position.y = upper_y
			elevator_doors._open_doors()
			upper_doors._open_doors()
			start_autoclose_timer()
			state = State.IDLE

func _on_elevator_used(action: String, floor_name: String):
	if action == "activate":
		if state == State.IDLE:
			if floor_name == "down":
				state = State.MOVING_DOWN
			elif floor_name == "up":
				state = State.MOVING_UP
	elif action == "call":
		if state == State.IDLE:
			if floor_name == "upper":
				state = State.MOVING_UP
			elif floor_name == "lower":
				state = State.MOVING_DOWN

func open_doors_manually() -> void:
	if state == State.IDLE:
		elevator_doors._open_doors()
		if is_at_floor("upper"):
			upper_doors._open_doors()
		else:
			lower_doors._open_doors()
		start_autoclose_timer()

func start_autoclose_timer() -> void:
	var current_timer = get_tree().create_timer(AUTOCLOSE_AMOUNT)
	_autoclose_timer = current_timer
	await current_timer.timeout
	if _autoclose_timer == current_timer:
		elevator_doors._close_doors()
		upper_doors._close_doors()
		lower_doors._close_doors()
