extends Control

@onready var label: Label = $PanelContainer/Label

var arrival_time: float = 0.0
var active := false

func _ready():
	label.text = "--:--"
	UIState.timer_synced.connect(_on_timer_synced)
	print("here")

func _on_timer_synced(server_arrival_time: float, _scale: float):
	arrival_time = server_arrival_time
	active = true
	print("active")

func _process(_delta):
	if not active:
		return
	var remaining: float = max(0.0, arrival_time - float(Time.get_unix_time_from_system()))
	label.text = _format_time(remaining)

	if remaining <= 0.0:
		active = false

func _format_time(seconds: float) -> String:
	var total := int(seconds)
	var mins := total / 60
	var secs := total % 60
	return "%02d:%02d" % [mins, secs]
