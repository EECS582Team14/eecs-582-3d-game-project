extends Control

@onready var text_label = $Panel/MarginContainer/MainText
@onready var panel = $Panel
var full_text = "You are an autonomous maintenance unit. Prepare the ship for hyperjump. \nCurrent directive displayed above."
var typing_speed = 0.02
var current_index = 0
var typing = true

func _ready():
	text_label.text = ""
	type_text()
	UIState.system_alert.connect(_new_message)

func reset(text):
	text_label.text = ""
	current_index = 0
	full_text = text
	typing = true
	panel.visible = true

func _new_message(text):
	reset(text)
	type_text()
	
func type_text():
	while current_index < full_text.length():
		if !typing:
			return
		text_label.text += full_text[current_index]
		current_index += 1
		await get_tree().create_timer(typing_speed).timeout

	typing = false

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if typing:
			typing = false
			text_label.text = full_text
		else:
			panel.visible = false # removes textbox after finished
