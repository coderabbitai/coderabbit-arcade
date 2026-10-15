extends Control
## Screen-space cutaway: independent of world position, camera limits and pit depth.
## The level freezes play; this node alone advances the presentation through that pause.
signal completed
const Style = preload("res://scenes/main_menu/menu_style.gd")
const DURATION := 3.5
const RABBIT_Y := 0.56
var elapsed := 0.0
var active := false
var rabbit: AnimatedSprite2D
var callout: Label
var flash: ColorRect
var direction := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rabbit = AnimatedSprite2D.new()
	rabbit.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(rabbit)
	callout = Style.label("K.O.", 88, Color("ffd36b"))
	callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(callout)
	flash = ColorRect.new()
	flash.color = Color.WHITE
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash)
	hide()
	set_process(false)
	resized.connect(_apply)

func play(frames: SpriteFrames, facing: float) -> void:
	elapsed = 0.0
	direction = -signf(facing) if facing != 0 else -1.0
	rabbit.sprite_frames = frames
	rabbit.flip_h = facing < 0
	active = true
	callout.show()
	show()
	set_process(true)
	_apply()

func cancel() -> void:
	active = false
	set_process(false)
	hide()

func _process(dt: float) -> void:
	tick(dt)

## A single clock also lets regression tests step coarse frames without skipping completion.
func tick(dt: float) -> void:
	if not active: return
	elapsed = minf(DURATION, elapsed + maxf(0.0, dt))
	_apply()
	if elapsed >= DURATION:
		active = false
		set_process(false)
		completed.emit()

func _apply() -> void:
	if rabbit.sprite_frames == null: return
	var unit := minf(size.x / 1280.0, size.y / 720.0)
	var animation_progress := clampf((elapsed - 0.12) / 1.4, 0.0, 1.0)
	rabbit.position = Vector2(size.x * 0.5, size.y * RABBIT_Y)
	rabbit.scale = Vector2.ONE * 4.4 * unit
	rabbit.rotation = 0.0
	rabbit.animation = &"hurt" if elapsed < 0.12 else &"death"
	rabbit.pause()
	var count := rabbit.sprite_frames.get_frame_count(rabbit.animation)
	rabbit.frame = mini(count - 1, int(animation_progress * count))
	var pop := clampf((elapsed - 1.82) / 0.2, 0.0, 1.0)
	callout.position = Vector2(0, size.y * 0.24)
	callout.size = Vector2(size.x, 110 * unit)
	callout.add_theme_font_size_override("font_size", int(88 * unit))
	callout.pivot_offset = callout.size * 0.5
	callout.scale = Vector2.ONE * lerpf(1.3, 1.0, pop)
	callout.modulate.a = pop
	flash.modulate.a = 0.5 * (1.0 - clampf(elapsed / 0.22, 0.0, 1.0))
	queue_redraw()

func _draw() -> void:
	var unit := minf(size.x / 1280.0, size.y / 720.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.025, 0.06, 0.82))
	var center := Vector2(size.x * 0.5, size.y * 0.55)
	# Soft concentric glow and an oval shadow anchor the cutaway without new art assets.
	for i in range(12, 0, -1):
		draw_circle(center, (85 + i * 12) * unit, Color(0.9, 0.35, 0.08, 0.012))
	draw_set_transform(Vector2(size.x * 0.5, size.y * RABBIT_Y + 166 * unit), 0, Vector2(1, 0.18))
	draw_circle(Vector2.ZERO, 130 * unit, Color(0, 0, 0, 0.4))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(0, 0, size.x, 90 * unit), Color.BLACK)
	draw_rect(Rect2(0, size.y - 90 * unit, size.x, 90 * unit), Color.BLACK)
	if elapsed < 1.82: return
	var head := rabbit.position + Vector2(-direction * 18, 26) * rabbit.scale
	for i in 3:
		var angle := elapsed * 3.2 + TAU * i / 3.0
		var at := head + Vector2(cos(angle) * 65, sin(angle) * 18 - 48) * unit
		var points := PackedVector2Array()
		for point in 10:
			var a := -PI / 2 + point * TAU / 10 + elapsed
			points.append(at + Vector2(cos(a), sin(a)) * (11.0 if point % 2 == 0 else 4.5) * unit)
		draw_colored_polygon(points, Color("ffe36e"))
