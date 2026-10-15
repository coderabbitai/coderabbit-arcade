extends Control
## The booth's game-over card. AppRouter lays it over a finished game when the booth player has
## used their retries: GAME OVER, the game's score line, a thank-you, and a countdown to the next
## player. It takes no input; the router opens the attract route when the countdown ends.
const Style = preload("res://scenes/main_menu/menu_style.gd")
var summary: Label
var countdown: Label

func _init() -> void:
	name = "NextPlayerCard"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Stop clicks reaching the game underneath.
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Style.theme()
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	var title := Style.label("GAME OVER", 48)
	summary = Style.label("", 24, Style.MINT)
	var thanks := Style.label("Thanks for playing!", 26)
	countdown = Style.label("", 18, Color("afbdc9"))
	for label in [title, summary, thanks, countdown]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	hide()

## Show the card with the game's score line ("" for none) and the seconds left.
func present(score_line: String, seconds: float) -> void:
	summary.text = score_line
	summary.visible = score_line != ""
	set_seconds(seconds)
	show()

func set_seconds(seconds: float) -> void:
	countdown.text = "Next player in %d" % ceili(maxf(seconds, 0.0))
