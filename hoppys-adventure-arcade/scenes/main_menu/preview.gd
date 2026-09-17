extends Node2D
## Lightweight menu scenery only; never instantiates gameplay.
const TITLES = ["BAY AREA BLITZ", "ORBITAL OPS", "ENCHANTED REPO", "THE CODEBASE CORRIDOR", "CLI / IDE DISTRICT", "SECURITY SECTOR", "GIT REPOSITORY HQ"]
const COLORS = [Color("65dec9"), Color("a99bff"), Color("b6dc87"), Color("63f9b2"), Color("71d9f3"), Color("ff7185"), Color("e9bc70")]
var index := 0
var elapsed := 0.0

func setup(id: int) -> void:
	index = id

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var paths: Array[String] = []
	match index:
		0:
			for layer in ["sCitySky", "sCityFar", "sCityMid", "sCityClose"]:
				paths.append("res://Assets/CityBackground/" + layer + ".png")
		1:
			for layer in ["backgound", "stars", "far-planets"]:
				paths.append("res://Assets/space_background_pack/layers/parallax-space-" + layer + ".png")
		2:
			for layer in ["back-trees", "lights", "middle-trees", "front-trees"]:
				paths.append("res://Assets/parallax_forest_pack/layers/parallax-forest-" + layer + ".png")
		4:
			for layer in ["back", "middle", "foreground"]:
				paths.append("res://Assets/cyberpunk-street-files/Assets/Version 2/Layers/" + layer + ".png")
	for i in paths.size():
		var tex := load(paths[i]) as Texture2D
		var factor := 720.0 / tex.get_height()
		var width := tex.get_width() * factor
		var layer := Parallax2D.new()
		layer.repeat_size = Vector2(width, 0)
		layer.repeat_times = 4
		layer.autoscroll = Vector2([1.2, 3.6, 7.2, 7.2][i], 0)
		add_child(layer)
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.scale = Vector2.ONE * factor
		layer.add_child(sprite)

func _process(delta: float) -> void:
	elapsed += delta
	scale = Vector2.ONE * maxf(1.0, get_viewport_rect().size.y / 720.0)
	queue_redraw()

func _draw() -> void:
	var accent: Color = COLORS[index]
	draw_rect(Rect2(0, 0, 2600, 1500), Color("10182b"))
	# Procedural stand-ins for themes whose dedicated art is not supplied yet.
	if index in [3, 5, 6]:
		var center := Vector2(900, 330)
		for i in range(12):
			var depth := fmod(float(i) / 12.0 + elapsed * 0.025, 1.0)
			var extent := Vector2(1100, 650) * depth * depth
			draw_rect(Rect2(center - extent, extent * 2), Color(accent, depth * 0.32), false, 2)
		for x in range(0, 2000, 110):
			draw_line(center, Vector2(x, 780), Color(accent, 0.18), 1)
		if index == 3:
			for i in range(38):
				var x := float(i * 57)
				for j in range(8):
					var y := fmod(i * 61.0 + j * 27 + elapsed * (18 + i % 5 * 7), 750.0)
					draw_rect(Rect2(x, y, 3 + (i + j) % 4 * 3, 12), Color(accent, 0.12 + j * 0.025))
		elif index == 5:
			for x in range(660, 1700, 145):
				draw_rect(Rect2(x, 140, 95, 390), Color("141d2b"))
				for y in range(165, 510, 25):
					draw_rect(Rect2(x + 12, y, 70, 5), Color(accent, 0.45))
			draw_line(Vector2(600, 220 + sin(elapsed) * 140), Vector2(1600, 220 + sin(elapsed) * 140), accent, 2)
		else:
			for i in range(6):
				var p := Vector2(720 + i % 3 * 190, 180 + i / 3 * 170)
				draw_line(Vector2(900, 600), p, Color(accent, 0.4), 3)
				draw_circle(p, 14, accent, false, 3)
