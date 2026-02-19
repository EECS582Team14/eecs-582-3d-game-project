extends Control

@onready var bar: ProgressBar = $ProgressBar

var max_health: float = 100.0
var current_health: float = 100.0

func _ready():
	# Connect to UIState
	UIState.health_changed.connect(_on_health_changed)
	_update_display()

func _on_health_changed(value: float):
	current_health = clamp(value, 0.0, max_health)
	_update_display()

func _update_display():
	bar.value = current_health / max_health * 100.0
