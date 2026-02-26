extends Control

@onready var bar: ProgressBar = $ProgressBar
@onready var label: Label = $Label

var max_integrity: float = 100.0
var current_integrity: float = 100.0

func _ready():
	# Initialize from GameManager if available
	if Engine.has_singleton("GameManager"):
		max_integrity = GameManager.max_ship_integrity if "max_ship_integrity" in GameManager else max_integrity
		current_integrity = GameManager.ship_integrity if "ship_integrity" in GameManager else current_integrity

	UIState.ship_durability_changed.connect(_on_ship_durability_changed)
	_on_ship_durability_changed(current_integrity)

func _on_ship_durability_changed(value: float) -> void:
	current_integrity = clamp(value, 0.0, max_integrity)
	var percent := 0.0
	if max_integrity > 0:
		percent = current_integrity / max_integrity * 100.0
	bar.value = percent
	label.text = "Ship Integrity: %d%%" % int(percent)
