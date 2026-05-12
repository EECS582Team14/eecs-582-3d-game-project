extends Control

@onready var task_text = $DirectivesPanel/MarginContainer/MainText
@onready var panel = $DirectivesPanel

var TASK_DESCRIPTIONS := {
	"Colonial_task": "Log preservation status. (Lower - Colonial)",
	"Crew_task": "Verify ID badge scans. (Upper - Crew Quarters)",
	"Electrical_task": "Reroute power flow. (Lower - Electrical)",
	"Fab_task": "Fabricate replacement components. (Lower - Fabrication Lab)",
	"Human_Resources_task": "File crew reports. (Upper - Human Resources)",
	"Life_task": "Balance oxygen levels. (Upper - Life Support)",
	"Lower_Reactor_task": "Calibrate reactor temperature. (Lower - Reactor)",
	"Nav_task": "Align navigation array. (Upper - Nav)",
	"Nexus_task": "Stabilize data uplinks. (Upper - Nexus)",
	"Personal_task": "Sort storage items. (Lower - Personal Items)",
	"Shielding_task": "Reinforce hull shielding. (Upper - Shielding)",
	"Supply_task": "Sort supply inventory. (Lower - Ship Supplies)",
	"Supply_Closet_task": "Restock supplies. (Upper - Supply Closet)",
	"Trash_task": "Empty waste bins. (Lower - Trash)",
}

var typing = true
var all_task_ids: Array[String] = []
var active_task_ids: Array[String] = []
var active_task_texts: Array[String] = []
var completed_tasks: Array[String] = []

var is_impostor: bool = false

var _comms_disabled: bool = false
var _saved_text: String = ""

func _ready():
	panel.visible = true
	randomize()
	all_task_ids = []
	for key in TASK_DESCRIPTIONS.keys():
		all_task_ids.append(key)
	all_task_ids.shuffle()

	active_task_ids.clear()
	active_task_texts.clear()
	completed_tasks.clear()
	rebuild_ui()

	for i in range(3):
		_add_new_task()

	# Enable BBCode in case you want styling later
	task_text.bbcode_enabled = true
	task_text.text = ""

	# Check if role was already assigned
	if NetworkManager.pending_role_received:
		_on_role_assigned(NetworkManager.pending_role_impostor)
	NetworkManager.role_assigned.connect(_on_role_assigned)

	# Connect sabotage signals for comms disable
	UIState.sabotage_triggered.connect(_on_sabotage_triggered)
	UIState.sabotage_ended.connect(_on_sabotage_ended)

	rebuild_ui()
	
func _add_new_task():
	if all_task_ids.is_empty():
		return
	var next_id = all_task_ids.pop_front()

	active_task_ids.append(next_id)
	active_task_texts.append(TASK_DESCRIPTIONS[next_id])

	rebuild_ui()

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
	
func show_message(text: String, duration: float = 1.5) -> void:
	var original_text = task_text.text
	var original_scale = task_text.scale
	var original_modulate = task_text.modulate

	# Make message loud and obvious
	task_text.text = text
	task_text.modulate = Color.WHITE 
	task_text.scale = original_scale * 2

	# quick punch-in animation
	var t = create_tween()
	t.tween_property(task_text, "scale", Vector2(1.5, 1.5), 0.08)
	t.tween_property(task_text, "scale", Vector2(1.35, 1.35), 0.12)

	await get_tree().create_timer(duration).timeout

	# fade back smoothly
	var fade = create_tween()
	fade.tween_property(task_text, "modulate", original_modulate, 0.15)
	fade.parallel().tween_property(task_text, "scale", original_scale, 0.15)
	fade.tween_callback(func():
		rebuild_ui()
	)

func mark_task_completed(task_id: String) -> void:
	if task_id not in active_task_ids:
		return

	typing = false

	var index = active_task_ids.find(task_id)
	if index == -1:
		return

	active_task_ids.remove_at(index)
	active_task_texts.remove_at(index)

	completed_tasks.append(task_id)

	rebuild_ui()

	_add_new_task()
	
func rebuild_ui():
	var lines = ""

	for i in range(active_task_ids.size()):
		var text = active_task_texts[i]
		lines += text + "\n"

	task_text.text = lines
	
func can_complete_task(task_id: String) -> bool:
	return task_id in active_task_ids

func _on_sabotage_triggered(sabotage_type: String) -> void:
	if sabotage_type == "disable_comms":
		_comms_disabled = true
		_saved_text = task_text.text
		task_text.text = "[color=red]== COMMS OFFLINE ==[/color]\n[color=gray]Directives unavailable...[/color]"
		panel.visible = true

func _on_sabotage_ended(sabotage_type: String) -> void:
	if sabotage_type == "disable_comms" and _comms_disabled:
		_comms_disabled = false
		task_text.text = _saved_text

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if typing:
			typing = false
	if event is InputEventKey:
		if event.keycode == KEY_Z and event.pressed:
			panel.visible = !panel.visible
