extends Node2D
## Temporary code-drawn mascot. Replace this node with final AnimatedSprite2D art.
var elapsed := 0.0
var reaction := -1
const PIXELS = [
"      WW      WW     ",
"     WWWW    WWWW    ",
"     WPPW    WPPW    ",
"     WPPW    WPPW    ",
"     WPPW   WWPPW    ",
"     WPPW   WPPWW    ",
"     WWWWWWWWWWW     ",
"    WWWWWWWWWWWWW    ",
"   WWWWWWWWWWWWWWW   ",
"   WWWWDDWWWDDWWWW   ",
"   WWWWDDWWWDDWWWW   ",
"   WPWWWWPPWWWWPW   ",
"    WWWWWDDWWWWW    ",
"     WWWWWWWWWW     ",
"    OOOOOOOOOOOO    ",
"   WWOOOOTTOOOOWW   ",
"  WWWOOOOTTOOOOWWW  ",
"  WWWOOOOOOOOOOWWW  ",
"   WWOOOOOOOOOOWW   ",
"     DDDDDDDDDD     ",
"    WWWWW  WWWWW    ",
"   WWWWWW  WWWWWW   "]
func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
func _draw() -> void:
	var hop := sin(elapsed * 2.5) * 3.0
	if reaction == 0:
		hop -= maxf(0, sin(elapsed * 3)) * 24
	elif reaction == 1:
		hop = sin(elapsed * 16) * 5
	draw_ellipse_shadow()
	var colors := {"W": Color("fff1d5"), "P": Color("ecaca0"), "D": Color("202b40"), "O": Color("f78949"), "T": Color("ffe4a3")}
	for y in PIXELS.size():
		for x in PIXELS[y].length():
			var key: String = PIXELS[y][x]
			if colors.has(key):
				var c: Color = colors[key]
				if key == "D" and y in [9, 10] and fmod(elapsed, 4.8) > 4.6:
					c = colors.W
				draw_rect(Rect2(x * 9 - 99, y * 9 - 198 + hop, 9, 9), c)
	if reaction == 2:
		draw_rect(Rect2(84 + maxf(0, sin(elapsed * 10)) * 18, -66, 28, 25), colors.W)
func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(0, 8), 0, Vector2(1, 0.16))
	draw_circle(Vector2.ZERO, 95, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
