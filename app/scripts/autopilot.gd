extends Node
## For screenshots and checks without a person at the controls: ARMADA_PORTS_AUTOPILOT holds
## steps separated by commas, run in order: wait:SECONDS, shot:FILE.png, or an input action
## (right, left, up, down, accept, back, x, y). The app quits after the last step.

var steps: PackedStringArray


func _ready() -> void:
	steps = OS.get_environment("ARMADA_PORTS_AUTOPILOT").split(",", false)
	_run.call_deferred()


func _run() -> void:
	const NAMES := {"right": "ui_right", "left": "ui_left", "up": "ui_up", "down": "ui_down",
			"accept": "ui_accept", "back": "ui_cancel", "x": "act_x", "y": "act_y"}
	for step in steps:
		step = step.strip_edges()
		if step.begins_with("wait:"):
			await get_tree().create_timer(float(step.substr(5))).timeout
		elif step.begins_with("shot:"):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(step.substr(5))
			print("autopilot: saved ", step.substr(5))
		elif NAMES.has(step):
			for pressed in [true, false]:
				var ev := InputEventAction.new()
				ev.action = NAMES[step]
				ev.pressed = pressed
				Input.parse_input_event(ev)
				await get_tree().process_frame
			await get_tree().create_timer(0.35).timeout
	get_tree().quit()
