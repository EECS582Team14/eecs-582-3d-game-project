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

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# Open doors
func _open_doors() -> void:
	if _is_open or _is_animating:
		return
	_is_open = true
	_is_animating = true

	var tween = create_tween()
	tween.tween_property(east_door, "position", _east_open_position, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(west_door, "position", _west_open_position, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func(): _is_animating = false)

# Close doors
func _close_doors() -> void:
	if not _is_open or _is_animating:
		return
	_is_open = false
	_is_animating = true

	var tween = create_tween()
	tween.tween_property(east_door, "position", _east_closed_position, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(west_door, "position", _west_closed_position, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func(): _is_animating = false)
