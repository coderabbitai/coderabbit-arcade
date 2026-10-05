extends Node2D
## Boss-local cue, driven by the same timer that permits damage.
var remaining := 1.0
var elapsed := 0.0

func _ready() -> void:
	var caption := Label.new()
	caption.text = "CORE EXPOSED · FINISHER"
	caption.position = Vector2(-140,-80)
	caption.size = Vector2(280,30)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",16)
	caption.add_theme_color_override("font_color",Color("b8ffe2"))
	caption.add_theme_color_override("font_outline_color",Color("071720"))
	caption.add_theme_constant_override("outline_size",6)
	add_child(caption)

func update_window(seconds_left: float, duration: float) -> void:
	remaining = clampf(seconds_left/duration,0,1)
	elapsed = duration-seconds_left
	queue_redraw()

func _draw() -> void:
	var pulse := .5+.5*sin(elapsed*TAU*1.7)
	var radius := 43.0+pulse*4.0
	draw_circle(Vector2.ZERO,radius,Color(.3,1,.75,.08+pulse*.06))
	draw_arc(Vector2.ZERO,radius,0,TAU,64,Color(.05,.15,.18,.9),7,true)
	draw_arc(Vector2.ZERO,radius,-PI*.5,-PI*.5+TAU*remaining,64,Color("a4ffda"),4,true)
	# Four inward ticks identify the core even when the countdown is almost empty.
	for i in 4:
		var direction := Vector2.from_angle(PI*.25+i*PI*.5)
		draw_line(direction*31,direction*37,Color("fff0b0"),3,true)
