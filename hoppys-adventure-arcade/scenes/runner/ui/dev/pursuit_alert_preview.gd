extends "res://scenes/runner/ui/dev/mock_runner_game.gd"
const Audio = preload("res://scenes/runner/audio/runner_audio.tscn")
var preview_clock := 0.0
var preview_step := -1

func _ready() -> void:
	autoplay = false
	super._ready()
	var audio := Audio.instantiate()
	add_child(audio)
	audio.bind(self)
	start_run()

func _process(delta: float) -> void:
	if paused:
		return
	preview_clock += delta
	var cycle := fposmod(preview_clock, 28.0)
	var step := int(cycle)
	if step != preview_step:
		preview_step = step
		match step:
			0, 21:
				state = &"running"
				state_changed.emit(state)
				pursuit_started.emit(18.0)
				pursuit_alert.emit(&"warn", 18.0)
			5:
				damage_blocked.emit(&"pr_backlog_low", &"shield")
			12:
				pursuit_alert.emit(&"critical", 6.0)
			18:
				pursuit_recovered.emit(&"timer")
				pursuit_alert.emit(&"clear", 0.0)
			24:
				state = &"caught"
				state_changed.emit(state)
				caught.emit()
				pursuit_alert.emit(&"clear", 0.0)
	if cycle < 18:
		pursuit_progress.emit(18.0 - cycle, 18.0)
	elif cycle >= 21 and cycle < 24:
		pursuit_progress.emit(24.0 - cycle, 18.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		if paused:
			resume()
		else:
			pause()
		get_viewport().set_input_as_handled()
	else:
		super._unhandled_input(event)
