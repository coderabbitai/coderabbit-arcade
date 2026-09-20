extends Control
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Style = preload("res://scenes/runner/ui/hud_style.gd")
var seconds := 0.0:
	set(value):
		seconds = value
		if number != null:
			number.text = str(ceili(seconds))
		queue_redraw()
var number: Label
var ring := false
var filled := true
var fraction := 1.0

func _ready() -> void:
	if ring:
		number = Style.label(str(ceili(seconds)), 20)
		add_child(number)
		number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.43
	if ring:
		radius = 24.0
		draw_circle(center, radius + 3, Color(Palette.NAVY_BG, 0.85))
		draw_arc(center, radius, 0, TAU, 64, Palette.SLATE, 5, true)
		draw_arc(center, radius, -PI / 2, -PI / 2 + TAU * clampf(fraction, 0, 1), 64, Palette.CREAM, 6, true)
		draw_arc(center, radius - 5, -PI / 2, -PI / 2 + TAU * clampf(fraction, 0, 1), 64, Palette.DANGER, 3, true)
		return
	var points := PackedVector2Array()
	for i in 6:
		points.append(center + Vector2.from_angle(PI / 3 * i - PI / 2) * radius)
	if filled:
		draw_colored_polygon(points, Color(Palette.MINT, 0.2))
	points.append(points[0])
	draw_polyline(points, Palette.MINT if filled else Palette.SLATE, 3, true)
	if filled:
		draw_polyline(PackedVector2Array([center + Vector2(-8, 0), center + Vector2(-2, 6), center + Vector2(9, -7)]), Palette.MINT, 3, true)
