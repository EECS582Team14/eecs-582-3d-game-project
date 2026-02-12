extends Control

@onready var task_text = $DirectivesPanel/MarginContainer/MainText

var tasks = [
	"Calibrate navigation array.",
	"Prime the hyperjump reactor.",
	"Stabilize cryo-chambers.",
	"Re-route auxiliary power.",
    "Inspect hull integrity sensors."
]

var typing_speed = 0.02
var typing = true
var full_text = ""

func _ready():
	randomize()
	# Shuffle tasks and pick the first two
	var shuffled_tasks = tasks.duplicate()
	shuffled_tasks.shuffle()
	var chosen_tasks = shuffled_tasks.slice(0, 2) # first two tasks
	for i in chosen_tasks:
		full_text += i + "\n"

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

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if typing:
			typing = false
		else:
			# Already typed → maybe do nothing or hide panel if needed
			pass
