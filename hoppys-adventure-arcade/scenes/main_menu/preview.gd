extends CanvasGroup
## Scene-local artwork only, flattened so crossfades do not ghost through individual layers.
const TITLES = ["BAY AREA BLITZ", "ORBITAL OPS", "ENCHANTED REPO",
	"THE CODEBASE CORRIDOR", "GRAB THE POWER-UPS", "JUMP, ROLL, DODGE", "BOSS FIGHTS",
	"CLI / IDE DISTRICT", "SECURITY SECTOR", "GIT REPOSITORY HQ",
	"THE GENERATION FLOOR", "THE REVIEW GAUNTLET", "THE AGENTIC CORE"]
const COLORS = [Color("65dec9"), Color("a99bff"), Color("b6dc87"),
	Color("63f9b2"), Color("79e0c4"), Color("71d9f3"), Color("ff9f6b"),
	Color("71d9f3"), Color("ff7185"), Color("e9bc70"),
	Color("ffb366"), Color("79e0c4"), Color("a99bff")]
## Actual stage plates. These are finite panoramas, not seamless tiles.
const LAYERS := {
	0: ["res://Assets/bay-area-blitz-assets-only/bay_area/backdrop.png"],
	1: ["res://Assets/orbital-ops-assets-only/orbital_ops/starfield.png",
		"res://Assets/orbital-ops-assets-only/orbital_ops/station_hull.png"],
	2: ["res://Assets/enchanted-repo-assets-only/enchanted_repo/sky.png",
		"res://Assets/enchanted-repo-assets-only/enchanted_repo/treeline.png"],
	7: ["res://Assets/code-city-brawl-assets-only/code_city/district_background.png"],
	8: ["res://Assets/code-city-brawl-assets-only/code_city/security_background.png"],
	9: ["res://Assets/code-city-brawl-assets-only/code_city/hq_background.png"],
	10: ["res://Assets/heroes-vs-villains-assets-only/heroes_villains/generation_floor.png"],
	11: ["res://Assets/heroes-vs-villains-assets-only/heroes_villains/review_gauntlet.png"],
	12: ["res://Assets/heroes-vs-villains-assets-only/heroes_villains/agentic_core.png"]
}
## Endless Runner stills captured from real play (tests/capture_runner_menu_previews.gd).
const STILLS := {
	3: "res://Assets/runner/menu_previews/runner_gameplay.png",
	4: "res://Assets/runner/menu_previews/runner_powerup.png",
	5: "res://Assets/runner/menu_previews/runner_dodge.png",
	6: "res://Assets/runner/menu_previews/runner_boss.png"
}
const STILL_DRIFT := 0.035
## Keep strong references so revisiting a preview does not reload its textures from disk.
static var _textures := {}
var index := 0
var elapsed := 0.0
var plates: Array[Sprite2D] = []
var canvas: Node2D

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

static func collection(id: int) -> String:
	if id < 3:
		return "PLATFORMER"
	if id < 7:
		return "ENDLESS RUNNER"
	return "CODE CITY BRAWL" if id < 10 else "HEROES VS. VILLAINS"

func setup(id: int) -> void:
	index = id

func _ready() -> void:
	canvas = Node2D.new()
	canvas.draw.connect(_draw_scene)
	add_child(canvas)
	var paths: Array = LAYERS.get(index, [STILLS.get(index, "")])
	for path in paths:
		var tex := _texture(path)
		if tex == null:
			push_error("Missing menu preview: " + path)
			continue
		var plate := Sprite2D.new()
		plate.texture = tex
		plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if STILLS.has(index) else CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(plate)
		plates.append(plate)
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	canvas.queue_redraw()
	_place_plates()

func _process(delta: float) -> void:
	elapsed += delta
	_place_plates()

func _place_plates() -> void:
	var visible := get_viewport_rect().size
	var progress := minf(elapsed / 9.0, 1.0)
	for i in plates.size():
		var plate := plates[i]
		var tex_size := plate.texture.get_size()
		var cover := maxf(visible.x / tex_size.x, visible.y / tex_size.y)
		# Overscan leaves safe room for bounded movement, including ultrawide/tall windows.
		# Independent depth factors retain subtle parallax on multi-layer stage art.
		var depth := 0.3 if i == 0 and plates.size() > 1 else 1.0
		plate.scale = Vector2.ONE * cover * (1.04 + STILL_DRIFT * progress * depth)
		plate.position = visible * 0.5 - visible * Vector2(0.012, 0.006) * progress * depth

func _draw_scene() -> void:
	canvas.draw_rect(get_viewport_rect(), Color("10182b"))
