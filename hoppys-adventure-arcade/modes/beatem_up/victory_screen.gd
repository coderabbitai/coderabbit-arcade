extends Control
## The final-boss results screen shared by both beat'em ups, shown once the victory epilogue has
## played. A celebratory title and line sit over the run's final score, which counts up from zero,
## and the time taken; one button returns to the menu.
##
## Clock-driven, no Tweens: the host calls advance(dt) from its _physics_process while the screen
## is up, so a paused tree freezes it and headless tests can step it.
##
## Input: for the first ARM seconds every confirm, click and touch is swallowed, so a press carried
## over from the cinematic can't skip anything. After that a confirm during the count-up lands it at
## once (skip()). The button only becomes pressable, and takes focus, once the score has landed.

const Style = preload("res://scenes/main_menu/menu_style.gd")
## Seconds the score takes to count up from zero; it eases out so the last digits settle slowly.
const COUNT := 1.8
## Seconds after the screen appears before any confirm, click or touch is honoured.
const ARM := .5
const BACKDROP := Color(.018,.03,.05,1)

## Extra actions (beyond ui_accept) that confirm here, e.g. HvV's popup-advance on the pad's View.
var confirm_actions: Array[String] = []
var final_score := 0
var seconds_taken := 0.0
## Seconds since show_result(); the count-up runs on it until it lands.
var clock := 0.0
var landed := false
## Whether advance() has reported the landing yet: a skip() lands the count between ticks, and
## the next advance() still owes the host its cue.
var cued := false
var accent := Style.MINT
var backdrop: ColorRect
var glow: ColorRect
var title: Label
var subtitle: Label
var score_caption: Label
var score_label: Label
var time_label: Label
var action: Button

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	backdrop = ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(backdrop)
	# A soft band of the mode's accent behind the score.
	glow = ColorRect.new()
	glow.mouse_filter = MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(PRESET_HCENTER_WIDE)
	glow.offset_top = -70
	glow.offset_bottom = 90
	add_child(glow)
	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.mouse_filter = MOUSE_FILTER_IGNORE
	column.custom_minimum_size = Vector2(720,0)
	column.add_theme_constant_override("separation",10)
	center.add_child(column)
	title = _label(column,40)
	subtitle = _label(column,20)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0,36)
	gap.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(gap)
	score_caption = _label(column,18,Color(Style.CREAM,.72))
	score_caption.text = "FINAL SCORE"
	score_label = _label(column,72)
	time_label = _label(column,18,Color(Style.CREAM,.72))
	var gap_after := Control.new()
	gap_after.custom_minimum_size = Vector2(0,40)
	gap_after.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(gap_after)
	action = Style.button("",58)
	column.add_child(action)
	_paint(accent)
	hide()

func _label(parent: Control, font_size: int, color := Style.CREAM) -> Label:
	var label := Style.label("",font_size,color)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

func _paint(color: Color) -> void:
	accent = color
	glow.color = Color(color,.12)
	title.add_theme_color_override("font_color",color)
	score_label.add_theme_color_override("font_color",color)

## Opens the screen with the count at zero. The button is disabled until the score lands.
func show_result(heading: String, line: String, score: int, seconds: float, color: Color, label: String, callback: Callable) -> void:
	_paint(color)
	title.text = "★  %s  ★" % heading
	subtitle.text = line
	final_score = maxi(score,0)
	seconds_taken = maxf(seconds,0)
	time_label.text = "TIME  %d:%02d" % [int(seconds_taken)/60,int(seconds_taken)%60]
	action.text = label
	for connection in action.pressed.get_connections(): action.pressed.disconnect(connection.callable)
	action.pressed.connect(callback)
	clock = 0
	landed = false
	cued = false
	action.disabled = true
	show()
	_render()

## Steps the count-up. True on the one call where the score lands, by itself or by a skip() since
## the last call (the host plays its cue then).
func advance(dt: float) -> bool:
	if not visible: return false
	clock += dt
	if clock >= COUNT: landed = true
	_render()
	if not landed or cued: return false
	cued = true
	return true

## Lands the count at the final score now.
func skip() -> void:
	clock = maxf(clock,COUNT)
	landed = true
	_render()

## The score on screen now: eased out from zero to the final score over COUNT.
func shown_score() -> int:
	if landed: return final_score
	var t := clampf(clock/COUNT,0,1)
	return roundi(final_score*(1.0-pow(1.0-t,3)))

## The button presses once the score has landed and the arming time is over.
func armed() -> bool:
	return landed and clock >= ARM

func _render() -> void:
	score_label.text = _grouped(shown_score())
	if armed() and action.disabled:
		action.disabled = false
		if action.is_inside_tree(): action.grab_focus()

## 12480 → "012,480": six digits, thousands grouped.
static func _grouped(value: int) -> String:
	var digits := "%06d" % value
	var out := ""
	for i in digits.length():
		if i>0 and (digits.length()-i)%3==0: out += ","
		out += digits[i]
	return out

func _is_confirm(event: InputEvent) -> bool:
	if event.is_action("ui_accept"): return true
	for name in confirm_actions:
		if event.is_action(name): return true
	return false

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	var pointer := event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag
	if not pointer and not _is_confirm(event): return
	if clock < ARM:
		get_viewport().set_input_as_handled()
		return
	if not landed:
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo(): skip()
		return
	# Landed and armed: ui_accept and clicks reach the focused button the usual way; the extra
	# confirm actions aren't ui_accept, so they press it here.
	for name in confirm_actions:
		if event.is_action(name):
			get_viewport().set_input_as_handled()
			if event.is_pressed() and not event.is_echo() and not action.disabled: action.pressed.emit()
			return
