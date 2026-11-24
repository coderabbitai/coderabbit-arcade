## The Approve Shield's visual: a translucent pixel bubble drawn around Hoppy.
##
## The player owns one of these as a child in front of its sprite. It shows when the shield
## is gained, breathes gently while the shield holds, and pops (a quick swell and fade) when
## the shield absorbs a hit or is otherwise lost. It is presentation only; the gameplay flag
## stays on the player.
extends Node2D
const RADIUS := Vector2(36.0, 48.0)
const CENTER := Vector2(0.0, -38.0)
const SEGMENTS := 20
const FILL := Color(0.45, 0.85, 1.0, 0.22)
const RIM := Color(0.6, 0.95, 1.0, 0.85)
const SHINE := Color(1.0, 1.0, 1.0, 0.75)
const POP_TIME := 0.22
## True while the shield holds; false once it is popping or hidden.
var active := false
var _pulse := 0.0
var _tween: Tween


func _ready() -> void:
	z_index = 1
	visible = false


func _process(dt: float) -> void:
	if not active: return
	_pulse += dt
	scale = Vector2.ONE * (1.0 + 0.03 * sin(_pulse * 4.0))
	queue_redraw()


## Show the bubble; a shield gained while the bubble was still popping reopens it cleanly.
func raise() -> void:
	_kill_tween()
	active = true
	_pulse = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	visible = true
	queue_redraw()


## Swell and fade out, then hide. Safe to call when already hidden.
func pop() -> void:
	if not active: return
	active = false
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE * 1.35, POP_TIME).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, POP_TIME)
	_tween.chain().tween_callback(_finish_pop)


## Hide at once with no animation (death, scene reset).
func clear() -> void:
	_kill_tween()
	active = false
	visible = false
	modulate = Color.WHITE
	scale = Vector2.ONE


func _finish_pop() -> void:
	_tween = null
	visible = false
	modulate = Color.WHITE
	scale = Vector2.ONE


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = null


func _draw() -> void:
	var points := PackedVector2Array()
	for i in SEGMENTS:
		var angle := TAU * i / SEGMENTS
		points.append(CENTER + Vector2(cos(angle) * RADIUS.x, sin(angle) * RADIUS.y))
	draw_colored_polygon(points, FILL)
	points.append(points[0])
	draw_polyline(points, RIM, 3.0)
	# A chunky highlight on the upper-left, like a soap bubble catching the light.
	var shine := CENTER + Vector2(-RADIUS.x * 0.55, -RADIUS.y * 0.6)
	draw_rect(Rect2(shine, Vector2(8, 4)), SHINE)
	draw_rect(Rect2(shine + Vector2(-4, 4), Vector2(4, 8)), SHINE)
