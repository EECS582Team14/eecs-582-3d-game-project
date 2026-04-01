extends Node3D

# Initialize child nodes
@onready var east_door = $EastDoor
@onready var west_door = $WestDoor

# Internal state variables
var _is_open: bool = false
var _is_animating: bool = false

# Door slide distance (slides sideways into the elevator shaft)
const SLIDE_DISTANCE: float = 1.25
const SLIDE_DURATION: float = 0.6

# Closed position (set in _ready based on initial transform)
var _east_closed_position: Vector3
var _west_closed_position: Vector3
var _east_open_position: Vector3
var _west_open_position: Vector3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_east_closed_position = east_door.position
	_west_closed_position = west_door.position
	_east_open_position = _east_closed_position + Vector3(0, 0, SLIDE_DISTANCE)
	_west_open_position = _west_closed_position - Vector3(0, 0, SLIDE_DISTANCE)
	NetworkManager.elevator_door_opened.connect(_on_door_opened)
	NetworkManager.elevator_door_closed.connect(_on_door_closed)

func _open_doors() -> void:
	if _is_open or _is_animating:
		return
	NetworkManager.send_elevator_door_state_change(str(get_path()), "open")

func _close_doors() -> void:
	if not _is_open or _is_animating:
		return
	NetworkManager.send_elevator_door_state_change(str(get_path()), "close")

# Open doors
func _open_doors_animation() -> void:
	_is_open = true
	_is_animating = true

	var tween = create_tween()
	tween.tween_property(east_door, "position", _east_open_position, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(west_door, "position", _west_open_position, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func(): _is_animating = false)

# Close doors
func _close_doors_animation() -> void:
	_is_open = false
	_is_animating = true

	var tween = create_tween()
	tween.tween_property(east_door, "position", _east_closed_position, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(west_door, "position", _west_closed_position, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func(): _is_animating = false)

func _on_door_opened(door_id: String) -> void:
	if door_id == str(get_path()):
		_open_doors_animation()

func _on_door_closed(door_id: String) -> void:
	if door_id == str(get_path()):
		_close_doors_animation()
