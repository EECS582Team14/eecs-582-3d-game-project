@tool
extends StaticBody3D
## This script controls the opening and closing mechanism of the door.

# Initialize child nodes
@onready var collider: CollisionShape3D = $DoorCollision
@onready var door_mesh: MeshInstance3D = $DoorMesh
@onready var lock_icon: MeshInstance3D = $LockIcon
@onready var sound_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

# Internal state variables
var is_locked: bool = false:
	set(value):
		is_locked = value
		_apply_locked_visuals()
var _is_open: bool = false
var _is_animating: bool = false
var _bodies_in_range: int = 0

# Door slide distance (slides sideways into the wall frame)
const SLIDE_DISTANCE: float = 1.5
const SLIDE_DURATION: float = 0.6

# Closed position (set in _ready based on initial transform)
var _closed_position: Vector3
var _open_position: Vector3
var _lock_closed_position: Vector3

# Materials to swap for locked and unlocked states
@export var locked_mesh: Material
@export var unlocked_mesh: Material

func _ready() -> void:
	_closed_position = door_mesh.position
	_open_position = _closed_position + Vector3(SLIDE_DISTANCE, 0, 0)
	_lock_closed_position = lock_icon.position
	NetworkManager.door_opened.connect(_on_door_opened)
	NetworkManager.door_closed.connect(_on_door_closed)
	NetworkManager.door_lock_received.connect(_on_door_lock_received)
	# Apply once at startup since the setter ran before @onready vars existed.
	_apply_locked_visuals()

func _apply_locked_visuals() -> void:
	if not door_mesh or not lock_icon:
		return
	if is_locked:
		door_mesh.material_override = locked_mesh
		lock_icon.visible = true
	else:
		door_mesh.material_override = unlocked_mesh
		lock_icon.visible = false

## FUNCTION TO OPEN THE DOOR
func _open_door() -> void:
	if _is_open or _is_animating:
		return
	_is_open = true
	_is_animating = true
	collider.disabled = true

	var tween = create_tween()
	tween.tween_property(door_mesh, "position", _open_position, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(lock_icon, "position:x", _lock_closed_position.x + SLIDE_DISTANCE, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func(): _is_animating = false)

## FUNCTION TO CLOSE THE DOOR
func _close_door() -> void:
	if not _is_open or _is_animating:
		return
	_is_open = false
	_is_animating = true

	var tween = create_tween()
	tween.tween_property(door_mesh, "position", _closed_position, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(lock_icon, "position:x", _lock_closed_position.x, SLIDE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		_is_animating = false
		collider.disabled = false
	)

## SIGNAL CALLBACK FOR WHEN A BODY ENTERS THE DOOR'S DETECTION RANGE
func _on_door_detection_range_body_entered(_body: Node3D) -> void:
	_bodies_in_range += 1
	if not is_locked and _bodies_in_range == 1:
		_open_door()
		sound_player.play()
		NetworkManager.send_door_state_change(str(get_path()), "open")

## SIGNAL CALLBACK FOR WHEN A BODY EXITS THE DOOR'S DETECTION RANGE
func _on_door_detection_range_body_exited(_body: Node3D) -> void:
	_bodies_in_range = max(_bodies_in_range - 1, 0)
	if _bodies_in_range == 0:
		_close_door()
		sound_player.play()
		NetworkManager.send_door_state_change(str(get_path()), "close")

func _on_door_opened(door_id: String) -> void:
	if door_id == str(get_path()):
		_open_door()
		sound_player.play()

func _on_door_closed(door_id: String) -> void:
	if door_id == str(get_path()):
		_close_door()
		sound_player.play()

func _on_door_lock_received(door_id: String, locked: bool) -> void:
	var my_path = str(get_path())
	if door_id == my_path or door_id == str(get_parent().get_path()):
		is_locked = locked
		# Also set on the parent controller so it doesn't overwrite us
		if get_parent() and "is_locked" in get_parent():
			get_parent().is_locked = locked
		if locked and _is_open:
			_close_door()
