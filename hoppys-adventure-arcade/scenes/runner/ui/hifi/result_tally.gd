extends Node2D
## The canonical result text stays intact for accessibility and contract consumers.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var _label: Label
var clock := 0.0
var delay := 0.0
var pattern := RegEx.new()
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	pattern.compile("[0-9]+")
	_label = get_parent() as Label
	_label.visible_characters = 0
func _process(delta: float) -> void:
	clock += delta
	if clock >= delay + 0.65:
		get_parent().visible_characters = -1
		queue_free()
	queue_redraw()
func _draw() -> void:
	var label := get_parent() as Label
	var progress := clampf((clock-delay) / 0.65, 0, 1)
	var text := label.text
	var matches := pattern.search_all(text)
	matches.reverse()
	for found in matches:
		var digits: String = found.get_string()
		var value := str(roundi(int(digits) * (1.0-pow(1.0-progress,3)))).pad_zeros(digits.length())
		text = text.substr(0,found.get_start()) + value + text.substr(found.get_end())
	var font := label.get_theme_font("font")
	var units := label.get_theme_font_size("font_size")
	var at := Vector2(0, (label.size.y-font.get_height(units))*0.5+font.get_ascent(units))
	draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,units,label.get_theme_constant("outline_size"),Palette.NAVY_BG)
	draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,units,label.get_theme_color("font_color"))

func _exit_tree() -> void:
	if is_instance_valid(_label): _label.visible_characters = -1
