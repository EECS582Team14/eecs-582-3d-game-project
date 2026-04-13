extends StaticBody3D
## Interactive console for the lobby room.
## Players walk up and press E to interact.

@export var console_type: String = ""
@export var prompt_text: String = "Press E to interact"

signal console_activated(type: String)

func activate():
	console_activated.emit(console_type)

func get_prompt_text() -> String:
	match console_type:
		"settings":
			if LobbyManager.is_host():
				return "Press E to open settings"
			else:
				return "Only the host can change settings"
		"start":
			if LobbyManager.is_host():
				return "Press E to launch mission"
			else:
				return "Waiting for host to start..."
		"leave":
			if LobbyManager.is_host():
				return "Press E to close lobby"
			else:
				return "Press E to leave lobby"
	return prompt_text
