@static_unload
extends RefCounted
const BASE := "res://Assets/heroes-vs-villains-assets-only/heroes_villains/"
const PRESENTATION := "res://Assets/heroes-vs-villains-assets-only/presentation/"
const Shared = preload("res://modes/beatem_up/art.gd")
static var resources: Dictionary = {}
static var manifest: Dictionary = {}

static func frames(key: String) -> SpriteFrames:
	if not resources.has(key): resources[key] = load(BASE+key+".tres")
	return resources[key]

static func sprite(key: String, pose: String, magnify := 1.0, foot := true) -> AnimatedSprite2D:
	if manifest.is_empty(): manifest = JSON.parse_string(FileAccess.get_file_as_string(BASE+"manifest.json"))
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames(key)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2.ONE*magnify
	if foot:
		var spec: Dictionary = manifest.atlases[key]
		s.offset = Vector2(spec.cell[0]*.5-spec.pivot[0],spec.cell[1]*.5-spec.pivot[1])
	s.play(pose)
	return s

static func shadow(radius := 27.0) -> Polygon2D:
	return Shared.shadow(radius)
