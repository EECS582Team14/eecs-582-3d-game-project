extends Control

@onready var task_text = $DirectivesPanel/MarginContainer/MainText
@onready var panel = $DirectivesPanel

const REAL_TASK: String = "Calibrate reactor temperature. (Lower Deck - Reactor)"
var flavor_tasks = [
	"Calibrate navigation array.",
	"Prime the hyperjump reactor.",
	"Stabilize cryo-chambers.",
	"Re-route auxiliary power.",
	"Inspect hull integrity sensors."
]

var typing_speed = 0.02
var typing = true
var full_text = ""
var chosen_tasks: Array[String] = []

var is_impostor: bool = false

func _ready():
	panel.visible = false
	randomize()
	# Always include the real task first, pick one random flavor task for second slot
	var shuffled_flavor = flavor_tasks.duplicate()
	shuffled_flavor.shuffle()
	chosen_tasks = [REAL_TASK, shuffled_flavor[0]]
	for t in chosen_tasks:
		full_text += t + "\n"

	# Enable BBCode in case you want styling later
	task_text.bbcode_enabled = true
	task_text.text = ""

	# Check if role was already assigned
	if NetworkManager.pending_role_received:
		_on_role_assigned(NetworkManager.pending_role_impostor)
	NetworkManager.role_assigned.connect(_on_role_assigned)

	type_text()

func _on_role_assigned(impostor: bool) -> void:
	is_impostor = impostor
	if is_impostor:
		# Wait for the role reveal delay before changing the panel color
		var local_player = NetworkManager.get_player(Steam.getSteamID())
		var delay = local_player.ROLE_REVEAL_DELAY if local_player else 30.0
		await get_tree().create_timer(delay).timeout
		var style = panel.get_theme_stylebox("panel").duplicate()
		style.bg_color = Color(0.84, 0, 0, 0.5)
		style.border_color = Color(0.78, 0.3, 0.3, 1)
		panel.add_theme_stylebox_override("panel", style)

func type_text() -> void:
	typing = true
	var index = 0
	while index < full_text.length():
		if not typing:
			# Skipped typing → print full text instantly
			task_text.text = full_text
			return
		task_text.text += full_text[index]
		index += 1
		await get_tree().create_timer(typing_speed).timeout
	typing = false

func mark_task_completed(task_name: String) -> void:
	# Skip typing animation if still going
	typing = false
	# Rebuild text with the completed task struck through
	var lines = ""
	for t in chosen_tasks:
		if t == task_name:
			lines += "[s]" + t + "[/s] [color=green]✓[/color]\n"
		else:
			lines += t + "\n"
	task_text.text = lines

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if typing:
			typing = false
	if event is InputEventKey:
		if event.keycode == KEY_Z and event.pressed:
			panel.visible = !panel.visible
