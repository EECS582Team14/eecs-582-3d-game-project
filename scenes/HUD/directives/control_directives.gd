extends Control

@onready var task_text = $DirectivesPanel/MarginContainer/MainText
@onready var panel = $DirectivesPanel

#const REAL_TASK: String = "Calibrate reactor temperature. (Lower Deck - Reactor)"
#var flavor_tasks = [
	#"Calibrate navigation array.",
	#"Prime the hyperjump reactor.",
	#"Stabilize cryo-chambers.",
	#"Re-route auxiliary power.",
	#"Inspect hull integrity sensors."
#]
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

var typing_speed = 0.02
var typing = true
var full_text = ""
var chosen_tasks: Array[String] = []
var completed: Array[String] = []

var is_impostor: bool = false

var _comms_disabled: bool = false
var _saved_text: String = ""

func _ready():
	panel.visible = false
	randomize()
	# Always include the real task first, pick one random flavor task for second slot
	var task_ids = TASK_DESCRIPTIONS.keys()
	var shuffled = task_ids.duplicate()
	shuffled.shuffle()

	chosen_tasks.clear()
	full_text = ""

	var count := 0
	for id in shuffled:
		var desc = TASK_DESCRIPTIONS[id]
		if desc != "":
			chosen_tasks.append(desc)
			full_text += desc + "\n"
			count += 1
			if count == 3:
				break

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
	if task_name not in completed:
		completed.append(task_name)
	# Rebuild text with the completed task struck through
	var lines = ""
	for t in chosen_tasks:
		if t in completed:
			lines += "[s]" + t + "[/s] [color=green]✓[/color]\n"
		else:
			lines += t + "\n"
	task_text.text = lines

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
