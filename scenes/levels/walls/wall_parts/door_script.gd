@tool
extends StaticBody3D
## This script controls the opening and closing mechanism of the door.

# Initialize child nodes
@onready var collider: CollisionShape3D = $DoorCollision
@onready var door_mesh: MeshInstance3D = $DoorMesh

# Internal state variables
var is_locked: bool = false

# Materials to swap for locked and unlocked states
@export var locked_mesh: Material
@export var unlocked_mesh: Material

func _ready() -> void:
	NetworkManager.door_opened.connect(_on_door_opened)
	NetworkManager.door_closed.connect(_on_door_closed)

func _process(_delta: float) -> void:
	# Update the door's mesh based on its locked state
	if is_locked:
		door_mesh.material_override = locked_mesh
	else:
		door_mesh.material_override = unlocked_mesh

## FUNCTION TO OPEN THE DOOR
func _open_door() -> void:
	#Set the collider to be disabled and make the door invisible to simulate opening
	collider.disabled = true
	self.visible = false

## FUNCTION TO CLOSE THE DOOR
func _close_door() -> void:
	#Set the collider to be enabled and make the door visible to simulate closing
	collider.disabled = false
	self.visible = true

## SIGNAL CALLBACK FOR WHEN A BODY ENTERS THE DOOR'S DETECTION RANGE
func _on_door_detection_range_body_entered(_body: Node3D) -> void:
	if not is_locked:
		_open_door()

## SIGNAL CALLBACK FOR WHEN A BODY EXITS THE DOOR'S DETECTION RANGE
func _on_door_detection_range_body_exited(_body: Node3D) -> void:
	_close_door()

func _on_door_opened(door_id: String) -> void:
	if door_id == self.name:
		_open_door()

func _on_door_closed(door_id: String) -> void:
	if door_id == self.name:
		_close_door()
