extends Node2D
signal preview_changed(index: int)
const Preview = preload("res://scenes/main_menu/preview.gd")
const GROUPS = [[0, 1, 2], [3, 4, 5, 6], [7, 8, 9, 10, 11, 12]]
const COUNT := 13
var idle_index := 0
var idle_remaining := 9.0
var focus_group := -1
var focus_cursor := 0
var focus_remaining := 3.0
var resume_remaining := 0.0
var suspended := false
var active_index := -1
var active: Node2D
var outgoing: Node2D
var fade: Tween
var pending := -1
var pending_duration := 0.6

func _ready() -> void:
	Preview.warm()
	transition_to(0, 0.0)

func select_group(group: int) -> void:
	if focus_group == group:
		return
	focus_group = group
	if group < 0:
		resume_remaining = 2.0
		return
	resume_remaining = 0.0
	focus_cursor = 0
	focus_remaining = 3.0
	transition_to(GROUPS[group][0], 0.6)

func _process(delta: float) -> void:
	if suspended:
		return
	if focus_group >= 0:
		focus_remaining -= delta
		if focus_remaining <= 0:
			focus_remaining += 3.0
			focus_cursor = (focus_cursor + 1) % GROUPS[focus_group].size()
			transition_to(GROUPS[focus_group][focus_cursor], 0.6)
	elif resume_remaining > 0:
		resume_remaining -= delta
		if resume_remaining <= 0:
			transition_to(idle_index, 1.2)
	else:
		idle_remaining -= delta
		if idle_remaining <= 0:
			idle_remaining += 9.0
			idle_index = (idle_index + 1) % COUNT
			transition_to(idle_index, 1.2)

func transition_to(index: int, duration: float) -> void:
	if fade and fade.is_running():
		pending = index
		pending_duration = duration
		return
	if active_index == index:
		return
	outgoing = active
	active = Preview.new()
	active.setup(index)
	add_child(active)
	active_index = index
	preview_changed.emit(index)
	if not outgoing or duration <= 0:
		if is_instance_valid(outgoing):
			outgoing.free()
		outgoing = null
		return
	active.modulate.a = 0.0
	fade = create_tween().set_parallel(true)
	fade.tween_property(active, "modulate:a", 1.0, duration)
	fade.tween_property(outgoing, "modulate:a", 0.0, duration)
	fade.chain().tween_callback(_finish_transition)

func _finish_transition() -> void:
	outgoing.free()
	outgoing = null
	fade = null
	if pending >= 0:
		var next := pending
		pending = -1
		transition_to(next, pending_duration)
