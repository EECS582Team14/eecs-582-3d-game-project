extends Control

@onready var task_text = $DirectivesPanel/MarginContainer/MainText

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

func _ready():
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

	type_text()

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
		else:
			# Already typed → maybe do nothing or hide panel if needed
			pass
