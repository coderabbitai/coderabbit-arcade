extends CanvasGroup
## Lightweight menu scenery only; never instantiates gameplay.
## A CanvasGroup so fades apply to the flattened preview instead of each layer (no see-through ghosting).
const TITLES = ["BAY AREA BLITZ", "ORBITAL OPS", "ENCHANTED REPO",
	"THE CODEBASE CORRIDOR", "GRAB THE POWER-UPS", "SHARP TURNS AHEAD", "BOSS FIGHTS",
	"CLI / IDE DISTRICT", "SECURITY SECTOR", "GIT REPOSITORY HQ"]
const COLORS = [Color("65dec9"), Color("a99bff"), Color("b6dc87"),
	Color("63f9b2"), Color("79e0c4"), Color("71d9f3"), Color("ff9f6b"),
	Color("71d9f3"), Color("ff7185"), Color("e9bc70")]
## Pixel-art parallax stacks, scrolled and nearest-filtered.
const LAYERS := {
	0: ["res://Assets/Backgrounds/CityBackground/sCitySky.png", "res://Assets/Backgrounds/CityBackground/sCityFar.png",
		"res://Assets/Backgrounds/CityBackground/sCityMid.png", "res://Assets/Backgrounds/CityBackground/sCityClose.png"],
	1: ["res://Assets/Backgrounds/space_background_pack/layers/parallax-space-backgound.png",
		"res://Assets/Backgrounds/space_background_pack/layers/parallax-space-stars.png",
		"res://Assets/Backgrounds/space_background_pack/layers/parallax-space-far-planets.png"],
	2: ["res://Assets/Backgrounds/parallax_forest_pack/layers/parallax-forest-back-trees.png",
		"res://Assets/Backgrounds/parallax_forest_pack/layers/parallax-forest-lights.png",
		"res://Assets/Backgrounds/parallax_forest_pack/layers/parallax-forest-middle-trees.png",
		"res://Assets/Backgrounds/parallax_forest_pack/layers/parallax-forest-front-trees.png"],
	7: ["res://Assets/Backgrounds/cyberpunk-street-files/Assets/Version 2/Layers/back.png",
		"res://Assets/Backgrounds/cyberpunk-street-files/Assets/Version 2/Layers/middle.png",
		"res://Assets/Backgrounds/cyberpunk-street-files/Assets/Version 2/Layers/foreground.png"]
}
## Endless Runner stills captured from real play (tests/capture_runner_menu_previews.gd).
const STILLS := {
	3: "res://Assets/runner/menu_previews/runner_gameplay.png",
	4: "res://Assets/runner/menu_previews/runner_powerup.png",
	5: "res://Assets/runner/menu_previews/runner_turn.png",
	6: "res://Assets/runner/menu_previews/runner_boss.png"
}
const PROCEDURAL := [8, 9]
const STILL_DRIFT := 0.035
## Strong references: previews are recreated on every transition and would otherwise reload from disk.
static var _textures := {}
var index := 0
var elapsed := 0.0
var canvas: Node2D
var still: Sprite2D

static func warm() -> void:
	for paths in LAYERS.values():
		for path in paths:
			_texture(path)
	for path in STILLS.values():
		_texture(path)

static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]

func setup(id: int) -> void:
	index = id

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas = Node2D.new()
	canvas.draw.connect(_draw_scene)
	add_child(canvas)
	var paths: Array = LAYERS.get(index, [])
	for i in paths.size():
		var tex := _texture(paths[i])
		if tex == null:
			continue
		var factor := 720.0 / tex.get_height()
		var layer := Parallax2D.new()
		layer.repeat_size = Vector2(tex.get_width() * factor, 0)
		layer.repeat_times = 4
		layer.autoscroll = Vector2([1.2, 3.6, 7.2, 7.2][i], 0)
		add_child(layer)
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.scale = Vector2.ONE * factor
		layer.add_child(sprite)
	if STILLS.has(index) and _texture(STILLS[index]) != null:
		still = Sprite2D.new()
		still.texture = _texture(STILLS[index])
		# 3D renders are not pixel art: filter them smoothly while they drift.
		still.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(still)
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var viewport := get_viewport_rect().size
	scale = Vector2.ONE * maxf(1.0, viewport.y / 720.0)
	canvas.queue_redraw()
	_place_still()

func _process(delta: float) -> void:
	elapsed += delta
	if index in PROCEDURAL:
		canvas.queue_redraw()
	if still:
		_place_still()

# Cover the visible area and drift in slowly so the still reads as footage, not a slide.
func _place_still() -> void:
	if not still:
		return
	var visible := get_viewport_rect().size / scale
	var tex_size := still.texture.get_size()
	var cover := maxf(visible.x / tex_size.x, visible.y / tex_size.y)
	var drift := 1.0 + STILL_DRIFT * minf(elapsed / 9.0, 1.0)
	still.scale = Vector2.ONE * cover * drift
	still.position = visible * 0.5 + Vector2(-18.0, -6.0) * minf(elapsed / 9.0, 1.0)

func _draw_scene() -> void:
	var accent: Color = COLORS[index]
	canvas.draw_rect(Rect2(0, 0, 2600, 1500), Color("10182b"))
	# Procedural stand-ins for themes whose dedicated art is not supplied yet.
	if index not in PROCEDURAL:
		return
	var center := Vector2(900, 330)
	for i in range(12):
		var depth := fmod(float(i) / 12.0 + elapsed * 0.025, 1.0)
		var extent := Vector2(1100, 650) * depth * depth
		canvas.draw_rect(Rect2(center - extent, extent * 2), Color(accent, depth * 0.32), false, 2)
	for x in range(0, 2000, 110):
		canvas.draw_line(center, Vector2(x, 780), Color(accent, 0.18), 1)
	if index == 8:
		for x in range(660, 1700, 145):
			canvas.draw_rect(Rect2(x, 140, 95, 390), Color("141d2b"))
			for y in range(165, 510, 25):
				canvas.draw_rect(Rect2(x + 12, y, 70, 5), Color(accent, 0.45))
		canvas.draw_line(Vector2(600, 220 + sin(elapsed) * 140), Vector2(1600, 220 + sin(elapsed) * 140), accent, 2)
	else:
		for i in range(6):
			var p := Vector2(720 + i % 3 * 190, 180 + i / 3 * 170)
			canvas.draw_line(Vector2(900, 600), p, Color(accent, 0.4), 3)
			canvas.draw_circle(p, 14, accent, false, 3)
